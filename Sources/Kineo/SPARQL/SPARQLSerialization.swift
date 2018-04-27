//
//  File.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 4/27/18.
//

import Foundation

enum SerializationError: Error {
    case encodingError(String)
}

protocol SPARQLSerializable {
    var canonicalMediaType: String { get }
    associatedtype ResultType: ResultProtocol
    func serialize(_ results: QueryResult<ResultType>) throws -> Data
}
