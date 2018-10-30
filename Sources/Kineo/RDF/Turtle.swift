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
    var turtleStringEscaped: String {
        let needsEscaping = self.unicodeScalars.contains { String.unicodeScalarsNeedingLiteralEscaping.contains($0) }
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
                case Character(UnicodeScalar(0x5d)):
                    escaped += "\\r"
                default:
                    escaped.append(c)
                }
            }
            return escaped
        }
    }
    
    var turtleIRIEscaped: String {
        let needsEscaping = self.unicodeScalars.contains { String.unicodeScalarsNeedingIRIEscaping.contains($0) }
        if !needsEscaping {
            return self
        } else {
            var escaped = ""
            for c in self {
                switch c {
                case Character(UnicodeScalar(0x00))...Character(UnicodeScalar(0x20)),
                     Character(UnicodeScalar(0x3c)),
                     Character(UnicodeScalar(0x3e)),
                     Character(UnicodeScalar(0x22)),
                     Character(UnicodeScalar(0x5c)),
                     Character(UnicodeScalar(0x5e)),
                     Character(UnicodeScalar(0x60)),
                     Character(UnicodeScalar(0x7b)),
                     Character(UnicodeScalar(0x7c)),
                     Character(UnicodeScalar(0x7d)):
                    for s in c.unicodeScalars {
                        escaped += String(format: "\\U%08X", s.value)
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
    func turtleData(usingPrefixes prefixes: [String:Term]? = nil) -> Data? {
        switch self.type {
        case .iri:
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
                                return prefixname.data(using: .utf8)
                            }
                        }
                    }
                }
            }
            return "<\(v.turtleIRIEscaped)>".data(using: .utf8)
        case .blank:
            return "_:\(self.value)".data(using: .utf8)
        case .language(let l):
            return "\"\(value.turtleStringEscaped)\"@\(l)".data(using: .utf8)
        case .datatype(.integer):
            return "\(Int(self.numericValue))".data(using: .utf8)
        case .datatype(.string):
            return "\"\(value.turtleStringEscaped)\"".data(using: .utf8)
        case .datatype(let dt):
            return "\"\(value.turtleStringEscaped)\"^^<\(dt.value)>".data(using: .utf8)
        }
    }
}

open class TurtleSerializer : RDFSerializer {
    public var canonicalMediaType = "application/turtle"
    var prefixes: [String:Term]
    
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
    
    public func serialize<T: TextOutputStream, S: Sequence>(_ triples: S, to stream: inout T) throws where S.Element == Triple {
        let data = try serialize(triples)
        if let string = String(data: data, encoding: .utf8) {
            stream.write(string)
        } else {
            throw SerializationError.encodingError("Failed to encode triples as utf-8")
        }
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
            let t = preds[p]!
            if i > 0 {
                data.append(contentsOf: [0x20, 0x3b, 0x0a, 0x09]) // space semicolon newline tab
            }
            try serialize(t, forPredicate: p, to: &data)
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
