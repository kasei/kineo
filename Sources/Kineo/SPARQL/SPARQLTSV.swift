//
//  SPARQLTSV.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 4/24/18.
//

import Foundation
import SPARQLSyntax

public struct SPARQLTSVSerializer<T: ResultProtocol> : SPARQLSerializable where T.TermType == Term {
    typealias ResultType = T
    public let canonicalMediaType = "text/tab-separated-values"
    
    public init() {
    }
    
    public func serialize(_ results: QueryResult<[TermResult], [Triple]>) throws -> Data {
        var d = Data()
        switch results {
        case .boolean(_):
            throw SerializationError.encodingError("Boolean results cannot be serialized in SPARQL-TSV")
        case let .bindings(vars, seq):
            let head = vars.map { "?\($0)" }.joined(separator: "\t")
            guard let headData = head.data(using: .utf8) else {
                throw SerializationError.encodingError("Failed to encode TSV header as utf-8")
            }
            d.append(headData)
            d.append(0x0a)
            
            for result in seq {
                let terms = vars.map { result[$0] }
                let strings = try terms.map { (t) -> String in
                    if let t = t {
                        guard let termString = t.tsvString else {
                            throw SerializationError.encodingError("Failed to encode term as utf-8: \(t)")
                        }
                        return termString
                    } else {
                        return ""
                    }
                }
                
                let line = strings.joined(separator: "\t")
                guard let lineData = line.data(using: .utf8) else {
                    throw SerializationError.encodingError("Failed to encode TSV line as utf-8")
                }
                d.append(lineData)
                d.append(0x0a)
            }
            return d
        case .triples(_):
            throw SerializationError.encodingError("RDF triples cannot be serialized in SPARQL-TSV")
        }
    }
}

private extension String {
    var tsvStringEscaped: String {
        var escaped = ""
        for c in self {
            switch c {
            case Character(UnicodeScalar(0x22)):
                escaped += "\\\""
            case Character(UnicodeScalar(0x5c)):
                escaped += "\\\\"
            case Character(UnicodeScalar(0x09)):
                escaped += "\\t"
            case Character(UnicodeScalar(0x0a)):
                escaped += "\\n"
            default:
                escaped.append(c)
            }
        }
        return escaped
    }
}

private extension Term {
    var tsvString: String? {
        switch self.type {
        case .iri:
            return "<\(value.turtleIRIEscaped)>"
        case .blank:
            return "_:\(self.value)"
        case .language(let l):
            return "\"\(value.tsvStringEscaped)\"@\(l)"
        case .datatype(.integer):
            return "\(Int(self.numericValue))"
        case .datatype(.string):
            return "\"\(value.tsvStringEscaped)\""
        case .datatype(let dt):
            return "\"\(value.tsvStringEscaped)\"^^<\(dt.value)>"
        }
    }
}
