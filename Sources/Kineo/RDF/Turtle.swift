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
    
    var turtleIRIEscaped: String {
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

extension Term {
    func turtleData() -> Data? {
        switch self.type {
        case .iri:
            return "<\(self.value.turtleIRIEscaped)>".data(using: .utf8)
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
    var canonicalMediaType = "application/turtle"
    
    public init() {
        
    }
    
    public func serialize(_ triple: Triple, to data: inout Data) throws {
        for t in triple {
            guard let termData = t.turtleData() else {
                throw SerializationError.encodingError("Failed to encode term as utf-8: \(t)")
            }
            data.append(termData)
            data.append(0x20)
        }
        data.append(contentsOf: [0x2e, 0x0a]) // dot newline
    }
    
    public func serialize<S: Sequence>(_ triples: S, forPredicate predicate: Term, to data: inout Data) throws where S.Element == Triple {
        guard let termData = predicate.turtleData() else {
            throw SerializationError.encodingError("Failed to encode term as utf-8: \(predicate)")
        }
        data.append(termData)
        data.append(0x20)

        let objects = triples.map { $0.object }
        for (i, o) in objects.sorted().enumerated() {
            guard let termData = o.turtleData() else {
                throw SerializationError.encodingError("Failed to encode term as utf-8: \(o)")
            }
            if i > 0 {
                data.append(0x2c)
                data.append(0x20)
            }
            data.append(termData)
        }
    }
    
    public func serialize<S: Sequence>(_ triples: S, forSubject subject: Term, to data: inout Data) throws where S.Element == Triple {
        let preds = Dictionary(grouping: triples) { $0.predicate }
        guard let termData = subject.turtleData() else {
            throw SerializationError.encodingError("Failed to encode term as utf-8: \(subject)")
        }
        data.append(termData)
        data.append(0x20)
        for (i, p) in preds.keys.sorted().enumerated() {
            let t = preds[p]!
            if i > 0 {
                data.append(0x3b)
                data.append(0x20)
            }
            try serialize(t, forPredicate: p, to: &data)
        }
        data.append(0x20)
        data.append(contentsOf: [0x2e, 0x0a]) // dot newline
    }
    
    public func serialize<S: Sequence>(_ triples: S) throws -> Data where S.Element == Triple {
        let subjects = Dictionary(grouping: triples) { $0.subject }
        var d = Data()
        for s in subjects.keys.sorted() {
            let t = subjects[s]!
            try serialize(t, forSubject: s, to: &d)
        }
        return d
    }
}
