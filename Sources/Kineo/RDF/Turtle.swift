//
//  Turtle.swift
//  PageDatabase
//
//  Created by Gregory Todd Williams on 6/4/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import SPARQLSyntax

extension String {
    static let unicodeScalarsNeedingTurtleIRIEscaping : Set<UnicodeScalar> = {
        var charactersNeedingEscaping = Set<UnicodeScalar>()
        for i in 0x00...0x20 {
            charactersNeedingEscaping.insert(UnicodeScalar(i)!)
        }
        charactersNeedingEscaping.insert(UnicodeScalar(0x3c))
        charactersNeedingEscaping.insert(UnicodeScalar(0x3e))
        charactersNeedingEscaping.insert(UnicodeScalar(0x22))
        charactersNeedingEscaping.insert(UnicodeScalar(0x5c))
        charactersNeedingEscaping.insert(UnicodeScalar(0x5e))
        charactersNeedingEscaping.insert(UnicodeScalar(0x60))
        charactersNeedingEscaping.insert(UnicodeScalar(0x7b))
        charactersNeedingEscaping.insert(UnicodeScalar(0x7c))
        charactersNeedingEscaping.insert(UnicodeScalar(0x7d))
        return charactersNeedingEscaping
    }()
    
    static let unicodeScalarsNeedingTurtleLiteralEscaping = Set<UnicodeScalar>([
        UnicodeScalar(0x22),
        UnicodeScalar(0x5c),
        UnicodeScalar(0x0a),
        UnicodeScalar(0x0d)
        ])

    var turtleStringEscaped: String {
        let needsEscaping = self.unicodeScalars.contains { String.unicodeScalarsNeedingTurtleLiteralEscaping.contains($0) }
        if !needsEscaping {
            return self
        } else {
            var escaped = ""
            for c in self {
                switch c {
                case Character(UnicodeScalar(0x22)):
                    escaped += "\\\""
                case Character(UnicodeScalar(0x5c)):
                    escaped += "\\\\"
                case Character(UnicodeScalar(0x0a)):
                    escaped += "\\n"
                case Character(UnicodeScalar(0x0d)):
                    escaped += "\\r"
                default:
                    escaped.append(c)
                }
            }
            return escaped
        }
    }
    
    var turtleIRIEscaped: String {
        let needsEscaping = self.unicodeScalars.contains {
            $0.value <= 0x20 || String.unicodeScalarsNeedingTurtleIRIEscaping.contains($0)
        }
        if !needsEscaping {
            return self
        } else {
            var escaped = ""
            for c in self {
                switch c {
                case _ where String.unicodeScalarsNeedingNTriplesIRIEscaping.contains(c.unicodeScalars.first!):
                    for s in c.unicodeScalars {
                        let value = s.value
                        if value <= 0xFFFF {
                            escaped += String(format: "\\u%04X", value)
                        } else {
                            escaped += String(format: "\\U%08X", value)
                        }
                    }
                default:
                    escaped.append(c)
                }
            }
            return escaped
        }
    }
}

extension Term {
    func turtleString(usingPrefixes prefixes: [String:Term]? = nil, for position: RDFTriplePosition = .object) -> String {
        switch self.type {
        case .iri:
            if position == .predicate && self.value == Namespace.rdf.type {
                return "a"
            }
            let v = self.value
            if let prefixes = prefixes {
                for (k, ns) in prefixes {
                    if v.hasPrefix(ns.value) {
                        let index = v.index(v.startIndex, offsetBy: ns.value.count)
                        let rest = v[index...]
                        let prefixname = "\(k):\(rest)"
                        guard let pndata = prefixname.data(using: .utf8) else {
                            continue
                        }
                        let istream = InputStream(data: pndata)
                        istream.open()
                        let lexer = SPARQLLexer(source: istream)
                        if let token = lexer.next() {
                            if lexer.hasRemainingContent {
                                continue
                            }
                            if case .prefixname(_) = token {
                                return prefixname
                            }
                        }
                    }
                }
            }
            return "<\(v.turtleIRIEscaped)>"
        case .blank:
            return "_:\(self.value)"
        case .language(let l):
            return "\"\(value.turtleStringEscaped)\"@\(l)"
        case .datatype(.integer):
            return "\(Int(self.numericValue))"
        case .datatype(.string):
            return "\"\(value.turtleStringEscaped)\""
        case .datatype(let dt):
            return "\"\(value.turtleStringEscaped)\"^^<\(dt.value)>"
        }
    }
    
    func printTurtleString<T: TextOutputStream>(to stream: inout T, usingPrefixes prefixes: [String:Term]? = nil, for position: RDFTriplePosition = .object) {
        let s = turtleString(usingPrefixes: prefixes, for: position)
        stream.write(s)
    }
    
    func turtleData(usingPrefixes prefixes: [String:Term]? = nil, for position: RDFTriplePosition = .object) -> Data? {
        let s = turtleString(usingPrefixes: prefixes, for: position)
        return s.data(using: .utf8)
    }
}

open class TurtleSerializer : RDFSerializer {
    public var canonicalMediaType = "application/turtle"
    public var prefixes: [String:Term]
    
    required public init() {
        self.prefixes = [:]
    }
    
    public init(prefixes: [String:Term]? = nil) {
        self.prefixes = prefixes ?? [:] // TODO: implement prefix use
    }
    
    public func add(name: String, for namespace: String) {
        prefixes[name] = Term(iri: namespace)
    }
    
    private func serialize(_ triple: Triple, to data: inout Data) throws {
        for t in triple {
            guard let termData = t.turtleData(usingPrefixes: prefixes) else {
                throw SerializationError.encodingError("Failed to encode term as utf-8: \(t)")
            }
            data.append(termData)
            data.append(0x20)
        }
        data.append(contentsOf: [0x2e, 0x0a]) // dot newline
    }
    
    public func serializeHeader<T: TextOutputStream>(to stream: inout T) {
        if prefixes.count > 0 {
            for (k, t) in prefixes {
                stream.write("@prefix \(k): ")
                t.printTurtleString(to: &stream)
                stream.write(" .\n")
            }
            stream.write("\n")
        }
    }

    public func serialize<T: TextOutputStream, S: Sequence>(_ triples: S, to stream: inout T) throws where S.Element == Triple {
        return try serialize(triples, to: &stream, emitHeader: true)
    }
    
    public func serialize<T: TextOutputStream, S: Sequence>(_ triples: S, to stream: inout T, emitHeader: Bool) throws where S.Element == Triple {
        if emitHeader {
            serializeHeader(to: &stream)
        }
        let subjects = Dictionary(grouping: triples) { $0.subject }
        for (i, s) in subjects.keys.sorted().enumerated() {
            if let triples = subjects[s] {
                if i > 0 {
                    stream.write("\n")
                }
                try serialize(triples, forSubject: s, toStream: &stream)
            }
        }
    }
    
    private func serialize<T: TextOutputStream, S: Sequence>(_ triples: S, forPredicate predicate: Term, toStream stream: inout T) throws where S.Element == Triple {
        let termString = predicate.turtleString(usingPrefixes: prefixes, for: .predicate)
        stream.write(termString)
        stream.write(" ")
        
        let objects = triples.map { $0.object }
        for (i, o) in objects.sorted().enumerated() {
            let termString = o.turtleString(usingPrefixes: prefixes, for: .object)
            if i > 0 {
                stream.write(", ")
            }
            stream.write(termString)
        }
    }
    
    private func serialize<T: TextOutputStream, S: Sequence>(_ triples: S, forSubject subject: Term, toStream stream: inout T) throws where S.Element == Triple {
        let preds = Dictionary(grouping: triples) { $0.predicate }
        let termString = subject.turtleString(usingPrefixes: prefixes, for: .subject)
        stream.write(termString)
        stream.write(" ")
        for (i, p) in preds.keys.sorted().enumerated() {
            let t = preds[p]!
            if i > 0 {
                stream.write(" ;\n\t")
            }
            try serialize(t, forPredicate: p, toStream: &stream)
        }
        stream.write(" .\n\n")
    }
    
    private func serialize<S: Sequence>(_ triples: S, forPredicate predicate: Term, to data: inout Data) throws where S.Element == Triple {
        guard let termData = predicate.turtleData(usingPrefixes: prefixes) else {
            throw SerializationError.encodingError("Failed to encode term as utf-8: \(predicate)")
        }
        data.append(termData)
        data.append(0x20)
        
        let objects = triples.map { $0.object }
        for (i, o) in objects.sorted().enumerated() {
            guard let termData = o.turtleData(usingPrefixes: prefixes) else {
                throw SerializationError.encodingError("Failed to encode term as utf-8: \(o)")
            }
            if i > 0 {
                data.append(contentsOf: [0x2c, 0x20]) // comma space
            }
            data.append(termData)
        }
    }
    
    private func serialize<S: Sequence>(_ triples: S, forSubject subject: Term, to data: inout Data) throws where S.Element == Triple {
        let preds = Dictionary(grouping: triples) { $0.predicate }
        guard let termData = subject.turtleData(usingPrefixes: prefixes) else {
            throw SerializationError.encodingError("Failed to encode term as utf-8: \(subject)")
        }
        data.append(termData)
        data.append(0x20)
        for (i, p) in preds.keys.sorted().enumerated() {
            if let t = preds[p] {
                if i > 0 {
                    data.append(contentsOf: [0x20, 0x3b, 0x0a, 0x09]) // space semicolon newline tab
                }
                try serialize(t, forPredicate: p, to: &data)
            }
        }
        data.append(contentsOf: [0x20, 0x2e, 0x0a]) // space dot newline newline
    }
    
    public func serialize<S: Sequence>(_ triples: S) throws -> Data where S.Element == Triple {
        var d = Data()
        if prefixes.count > 0 {
            for (k, t) in prefixes {
                d.append("@prefix \(k): ".data(using: .utf8)!)
                guard let termData = t.turtleData() else {
                    throw SerializationError.encodingError("Failed to encode prefix as utf-8: \(t)")
                }
                d.append(termData)
                d.append(" .\n".data(using: .utf8)!)
            }
            d.append(0x0a)
        }
        
        let subjects = Dictionary(grouping: triples) { $0.subject }
        for (i, s) in subjects.keys.sorted().enumerated() {
            let t = subjects[s]!
            if i > 0 {
                d.append(0x0a)
            }
            try serialize(t, forSubject: s, to: &d)
        }
        return d
    }
}

extension TurtleSerializer : SPARQLSerializable {
    public func serialize(_ results: QueryResult<[TermResult], [Triple]>) throws -> Data {
        switch results {
        case .triples(let triples):
            return try serialize(triples)
        default:
            throw SerializationError.encodingError("SPARQL results cannot be serialized as Turtle")
        }
    }
}
