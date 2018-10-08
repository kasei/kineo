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

public class RDFParser {
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
    
    var inputSyntax: RDFSyntax
    var defaultBase: String
    var produceUniqueBlankIdentifiers: Bool
    
    public init(syntax: RDFSyntax = .turtle, base defaultBase: String = "http://base.example.org/", produceUniqueBlankIdentifiers: Bool = true) {
        self.inputSyntax = syntax
        self.defaultBase = defaultBase
        self.produceUniqueBlankIdentifiers = produceUniqueBlankIdentifiers
    }

    @discardableResult
    public func parse(string: String, handleTriple: @escaping (Term, Term, Term) -> Void) throws -> Int {
        switch inputSyntax {
        case .ntriples, .turtle:
            let p = SerdParser(syntax: inputSyntax, base: defaultBase, produceUniqueBlankIdentifiers: produceUniqueBlankIdentifiers)
            return try p.serd_parse(string: string, handleTriple: handleTriple)
        default:
            let p = RDFXMLParser()
            try p.parse(string: string, tripleHandler: handleTriple)
            return 0
        }
    }
    
    @discardableResult
    public func parse(file filename: String, base: String? = nil, handleTriple: @escaping TripleHandler) throws -> Int {
        switch inputSyntax {
        case .ntriples, .turtle:
            let p = SerdParser(syntax: inputSyntax, base: base ?? defaultBase, produceUniqueBlankIdentifiers: produceUniqueBlankIdentifiers)
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

