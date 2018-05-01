//
//  File.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 4/27/18.
//

import Foundation

enum SerializationError: Error {
    case encodingError(String)
    case parsingError(String)
}

protocol SPARQLParsable {
    var mediaTypes: Set<String> { get }
    associatedtype ResultType: ResultProtocol
    func parse(_ data: Data) throws -> QueryResult<ResultType>
}

protocol SPARQLSerializable {
    var canonicalMediaType: String { get }
    associatedtype ResultType: ResultProtocol
    func serialize(_ results: QueryResult<ResultType>) throws -> Data
}
