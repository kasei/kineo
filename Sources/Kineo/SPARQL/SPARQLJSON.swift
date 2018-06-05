//
//  SPARQLJSON.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 4/24/18.
//

import Foundation
import SPARQLSyntax

enum ResultValue: Codable {
    case bindings([String], [[String:Term]])
    case boolean(Bool)
    
    enum CodingKeys: CodingKey {
        case head
        case vars
        case boolean
        case results
        case bindings
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let head = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .head)
        if head.contains(.results) {
            let results = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .results)
            let vars = try results.decode([String].self, forKey: .vars)
            let bindings = try results.decode([[String:Term]].self, forKey: .bindings)
            self = .bindings(vars, bindings)
        } else {
            let value = try container.decode(String.self, forKey: .boolean)
            self = .boolean(value == "true")
        }
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

public struct SPARQLJSONSerializer<T: ResultProtocol> : SPARQLSerializable where T.TermType == Term {
    typealias ResultType = T
    public let canonicalMediaType = "application/sparql-results+json"

    public var encoder: JSONEncoder
    public init() {
        encoder = JSONEncoder()
    }
    public func serialize(_ results: QueryResult<[TermResult], [Triple]>) throws -> Data {
        var r : ResultValue
        switch results {
        case .boolean(let value):
            r = ResultValue.boolean(value)
        case let .bindings(vars, seq):
            var results = [[String:Term]]()
            for result in seq {
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

public struct SPARQLJSONParser : SPARQLParsable {
    public let mediaTypes = Set(["application/sparql-results+json", "application/json"])

    public var decoder: JSONDecoder
    public init() {
        decoder = JSONDecoder()
    }

    public func parse(_ data: Data) throws -> QueryResult<[TermResult], [Triple]> {
        let resultValue = try decoder.decode(ResultValue.self, from: data)
        switch resultValue {
        case .boolean(let v):
            return QueryResult.boolean(v)
        case let .bindings(vars, rows):
            let bindings = rows.map { TermResult(bindings: $0) }
            return QueryResult.bindings(vars, bindings)
        }
    }
}
