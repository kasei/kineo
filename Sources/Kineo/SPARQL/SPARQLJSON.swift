//
//  SPARQLJSON.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 4/24/18.
//

import Foundation
import SPARQLSyntax

public struct SPARQLJSONSerializer<T: ResultProtocol> : SPARQLSerializable where T.TermType == Term {
    typealias ResultType = T
    let canonicalMediaType = "application/sparql-results+json"

    public var encoder: JSONEncoder
    public init() {
        encoder = JSONEncoder()
    }
    enum ResultValue: Encodable {
        case bindings([String], [[String:Term]])
        case boolean(Bool)

        enum CodingKeys: CodingKey {
            case head
            case vars
            case boolean
            case results
            case bindings
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            var head = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .head)
            switch self {
            case let .bindings(vars, bindings):
                var results = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .results)
                try head.encode(vars, forKey: .vars)
                try results.encode(bindings, forKey: .bindings)
            case let .boolean(value):
                let lex = value ? "true" : "false"
                try container.encode(lex, forKey: .boolean)
            }
        }
    }
    
    public func serialize(_ results: QueryResult<T>) throws -> Data {
        var r : ResultValue
        switch results {
        case .boolean(let value):
            r = ResultValue.boolean(value)
        case let .bindings(vars, iter):
            var results = [[String:Term]]()
            while let result = iter.next() {
                var d = [String:Term]()
                for k in result.keys {
                    d[k] = result[k]
                }
                results.append(d)
            }
            r = ResultValue.bindings(vars, results)
        case .triples(_):
            throw SerializationError.encodingError("RDF triples cannot be serialized in SPARQL-JSON")
        }
        return try encoder.encode(r)
    }
}
