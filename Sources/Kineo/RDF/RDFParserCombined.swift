//
//  RDFParser.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 1/21/17.
//  Copyright © 2017 Gregory Todd Williams. All rights reserved.
//

import serd
import Foundation
import SPARQLSyntax

public typealias TripleHandler = (Term, Term, Term) -> Void
public protocol RDFParser {
    init()
    var mediaTypes: Set<String> { get }
    func parse(string: String, mediaType: String, base: String?, handleTriple: @escaping TripleHandler) throws -> Int
    func parseFile(_ filename: String, mediaType: String, base: String?, handleTriple: @escaping TripleHandler) throws -> Int
}

public class RDFParserCombined : RDFParser {
    public var mediaTypes: Set<String> = [
    
    ]
    
    public enum RDFParserError : Error {
        case parseError(String)
        case internalError(String)
    }
    
    public enum RDFSyntax {
        case ntriples
        case turtle
        case rdfxml
        
        var serdSyntax : SerdSyntax? {
            switch self {
            case .ntriples:
                return SERD_NTRIPLES
            case .turtle:
                return SERD_TURTLE
            default:
                return nil
            }
        }
    }

    public static func guessSyntax(filename: String) -> RDFSyntax {
        if filename.hasSuffix("ttl") {
            return .turtle
        } else if filename.hasSuffix("nt") {
            return .ntriples
        } else if filename.hasSuffix("rdf") {
            return .rdfxml
        } else {
            return .turtle
        }
    }
    
    public static func guessSyntax(mediaType: String) -> RDFSyntax {
        if mediaType.hasPrefix("text/turtle") {
            return .turtle
        } else if mediaType.hasPrefix("text/plain") {
            return .turtle
        } else if mediaType.hasPrefix("application/rdf+xml") {
            return .rdfxml
        } else if mediaType.hasPrefix("application/xml") {
            return .rdfxml
        } else if mediaType.hasSuffix("application/n-triples") {
            return .ntriples
        } else {
            return .turtle
        }
    }
    
    var defaultBase: String
    var produceUniqueBlankIdentifiers: Bool
    
    required public init() {
        self.defaultBase = "http://base.example.org/"
        self.produceUniqueBlankIdentifiers = true
    }
    
    public init(base defaultBase: String = "http://base.example.org/", produceUniqueBlankIdentifiers: Bool = true) {
        self.defaultBase = defaultBase
        self.produceUniqueBlankIdentifiers = produceUniqueBlankIdentifiers
    }

    @discardableResult
    public func parse(string: String, mediaType type: String, base: String? = nil, handleTriple: @escaping TripleHandler) throws -> Int {
        
        let inputSyntax = RDFParserCombined.guessSyntax(mediaType: type)
        return try parse(string: string, syntax: inputSyntax, base: base, handleTriple: handleTriple)
    }
    
    @discardableResult
    public func parse(string: String, syntax inputSyntax: RDFSyntax, base: String? = nil, handleTriple: @escaping TripleHandler) throws -> Int {
        let base = base ?? defaultBase
        switch inputSyntax {
        case .ntriples, .turtle:
            let p = SerdParser(syntax: inputSyntax, base: base, produceUniqueBlankIdentifiers: produceUniqueBlankIdentifiers)
            return try p.serd_parse(string: string, handleTriple: handleTriple)
        default:
            let p = RDFXMLParser()
            try p.parse(string: string, tripleHandler: handleTriple)
            return 0
        }
    }

    @discardableResult
    public func parse(file filename: String, base: String? = nil, handleTriple: @escaping TripleHandler) throws -> Int {
        let inputSyntax = RDFParserCombined.guessSyntax(filename: filename)
        return try parse(file: filename, syntax: inputSyntax, base: base, handleTriple: handleTriple)
    }
    
    @discardableResult
    public func parseFile(_ filename: String, mediaType type: String, base: String? = nil, handleTriple: @escaping TripleHandler) throws -> Int {
        let inputSyntax = RDFParserCombined.guessSyntax(mediaType: type)
        return try parse(file: filename, syntax: inputSyntax, base: base, handleTriple: handleTriple)
    }
    
    @discardableResult
    public func parse(file filename: String, syntax inputSyntax: RDFSyntax, base: String? = nil, handleTriple: @escaping TripleHandler) throws -> Int {
        let base = base ?? defaultBase
        switch inputSyntax {
        case .ntriples, .turtle:
            let p = SerdParser(syntax: inputSyntax, base: base, produceUniqueBlankIdentifiers: produceUniqueBlankIdentifiers)
            return try p.serd_parse(file: filename, base: base, handleTriple: handleTriple)
        default:
            let fileURI = URL(fileURLWithPath: filename)
            let p = RDFXMLParser(base: fileURI.absoluteString)
            let data = try Data(contentsOf: fileURI)
            try p.parse(data: data, tripleHandler: handleTriple)
            return 0
        }
    }
}

