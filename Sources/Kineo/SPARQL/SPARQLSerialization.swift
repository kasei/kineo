//
//  File.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 4/27/18.
//

import Foundation
import SPARQLSyntax

enum SerializationError: Error {
    case encodingError(String)
    case parsingError(String)
}

protocol SPARQLParsable {
    var mediaTypes: Set<String> { get }
    func parse(_ data: Data) throws -> QueryResult<[TermResult], [Triple]>
}

protocol SPARQLSerializable {
    var canonicalMediaType: String { get }
    func serialize(_ results: QueryResult<[TermResult], [Triple]>) throws -> Data
}
