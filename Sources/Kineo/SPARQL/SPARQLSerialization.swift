//
//  File.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 4/27/18.
//

import Foundation
import SPARQLSyntax

public enum SerializationError: Error {
    case encodingError(String)
    case parsingError(String)
}

public protocol SPARQLParsable {
    var mediaTypes: Set<String> { get }
    func parse(_ data: Data) throws -> QueryResult<[SPARQLResult<Term>], [Triple]>
}

public protocol SPARQLSerializable {
    var serializesTriples: Bool { get }
    var serializesBindings: Bool { get }
    var serializesBoolean: Bool { get }
    var canonicalMediaType: String { get }
    var acceptableMediaTypes: [String] { get }
    func serialize<R: Sequence, T: Sequence>(_ results: QueryResult<R, T>) throws -> Data where R.Element == SPARQLResult<Term>, T.Element == Triple
}
