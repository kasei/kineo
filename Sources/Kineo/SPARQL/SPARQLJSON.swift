//
//  SPARQLJSON.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 4/24/18.
//

import Foundation
import SPARQLSyntax

enum SerializationError: Error {
    case encodingError(String)
}

//extension ResultProtocol: Encodable {
//    public func encode(to encoder: Encoder) throws {
//        var container = encoder.singleValueContainer
//        let d = Dictionary(self.makeIterator())
//        try container.encode(unid)
//    }
//
//}
public struct SPARQLJSONSerializer<T: ResultProtocol> where T.TermType == Term {
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
            var results = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .results)
            switch self {
            case let .bindings(vars, bindings):
                try head.encode(vars, forKey: .vars)
                try results.encode(bindings, forKey: .bindings)
            case let .boolean(value):
                let lex = value ? "true" : "false"
                try container.encode(lex, forKey: .boolean)
            }
        }
    }
    
    
    public func serialize<I: IteratorProtocol>(_ iter: inout I, for query: Query) throws -> Data where I.Element == T {
        var results = [[String:Term]]()
        while let result = iter.next() {
            var d = [String:Term]()
            for k in result.keys {
                d[k] = result[k]
            }
            results.append(d)
        }
        
        var r : ResultValue
        switch query.form {
        case .select(.variables(let vars)):
            r = ResultValue.bindings(vars, results)
        case .select(.star):
            r = ResultValue.bindings(query.algebra.inscope.sorted(), results)
        default:
            throw SerializationError.encodingError("Encoding non-bindings results not implemented")
        }
        return try encoder.encode(r)
    }
}
