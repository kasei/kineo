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

public class RDFParserCombined : RDFPushParser {
    public var mediaTypes: Set<String> = [
    
    ]
    
    public enum RDFParserError : Error {
        case parseError(String)
        case unsupportedSyntax(String)
        case internalError(String)
    }
    
    public enum RDFSyntax {
        case nquads
        case ntriples
        case turtle
        case rdfxml
        
        var serdSyntax : SerdSyntax? {
            switch self {
            case .nquads:
                return SERD_NQUADS
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
        } else if filename.hasSuffix("nq") {
            return .nquads
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
        } else if mediaType.hasSuffix("application/n-quads") {
            return .nquads
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
        guard inputSyntax != .nquads else {
            throw RDFParserError.unsupportedSyntax("Cannot parse N-Quads data with a triple-based parsing API")
        }
        return try parse(string: string, syntax: inputSyntax, base: base, handleTriple: handleTriple)
    }
    
    @discardableResult
    public func parse(string: String, mediaType type: String, defaultGraph: Term, base: String? = nil, handleQuad: @escaping QuadHandler) throws -> Int {
        let inputSyntax = RDFParserCombined.guessSyntax(mediaType: type)
        if case .nquads = inputSyntax {
            return try parse(string: string, syntax: inputSyntax, defaultGraph: defaultGraph, base: base, handleQuad: handleQuad)
        } else {
            return try parse(string: string, syntax: inputSyntax, base: base) { (s, p, o) in
                handleQuad(s, p, o, defaultGraph)
            }
        }
    }
    
    
    @discardableResult
    public func parse(string: String, syntax inputSyntax: RDFSyntax, defaultGraph: Term, base: String? = nil, handleQuad: @escaping QuadHandler) throws -> Int {
        let base = base ?? defaultBase
        switch inputSyntax {
        case .nquads:
            let p = NQuadsParser(reader: string, defaultGraph: defaultGraph)
            var count = 0
            for q in p {
                count += 1
                handleQuad(q.subject, q.predicate, q.object, q.graph)
            }
            return count
        case .ntriples, .turtle:
            let p = SerdParser(syntax: inputSyntax, base: base, produceUniqueBlankIdentifiers: produceUniqueBlankIdentifiers)
            return try p.serd_parse(string: string) { (s,p,o) in
                handleQuad(s,p,o,defaultGraph)
            }
        default:
            let p = RDFXMLParser()
            var count = 0
            try p.parse(string: string) { (s,p,o) in
                count += 1
                handleQuad(s,p,o,defaultGraph)
            }
            return count
        }
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
    public func parse(file filename: String, defaultGraph: Term, base: String? = nil, handleQuad: @escaping QuadHandler) throws -> Int {
        let inputSyntax = RDFParserCombined.guessSyntax(filename: filename)
        return try parse(file: filename, syntax: inputSyntax, defaultGraph: defaultGraph, base: base, handleQuad: handleQuad)
    }
    
    @discardableResult
    public func parseFile(_ filename: String, mediaType type: String, base: String? = nil, handleTriple: @escaping TripleHandler) throws -> Int {
        let inputSyntax = RDFParserCombined.guessSyntax(mediaType: type)
        return try parse(file: filename, syntax: inputSyntax, base: base, handleTriple: handleTriple)
    }
    
    @discardableResult
    public func parseFile(_ filename: String, mediaType type: String, defaultGraph: Term, base: String?, handleQuad: @escaping QuadHandler) throws -> Int {
        let inputSyntax = RDFParserCombined.guessSyntax(mediaType: type)
        return try parse(file: filename, syntax: inputSyntax, defaultGraph: defaultGraph, base: base, handleQuad: handleQuad)
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
    
    @discardableResult
    public func parse(file filename: String, syntax inputSyntax: RDFSyntax, defaultGraph: Term, base: String? = nil, handleQuad: @escaping QuadHandler) throws -> Int {
        let base = base ?? defaultBase
        switch inputSyntax {
        case .nquads:
            let fileURI = URL(fileURLWithPath: filename)
            let reader = FileReader(filename: filename)
            let p = NQuadsParser(reader: reader, defaultGraph: defaultGraph)
            var count = 0
            for q in p {
                count += 1
                handleQuad(q.subject, q.predicate, q.object, q.graph)
            }
            return count
        case .ntriples, .turtle:
            let p = SerdParser(syntax: inputSyntax, base: base, produceUniqueBlankIdentifiers: produceUniqueBlankIdentifiers)
            var count = 0
            return try p.serd_parse(file: filename, defaultGraph: defaultGraph, base: base) { (s,p,o,g) in
                handleQuad(s,p,o,g)
                count += 1
            }
            return count
        default:
            let fileURI = URL(fileURLWithPath: filename)
            let p = RDFXMLParser(base: fileURI.absoluteString)
            let data = try Data(contentsOf: fileURI)
            var count = 0
            try p.parse(data: data) { (s,p,o) in
                handleQuad(s,p,o,defaultGraph)
                count += 1
            }
            return count
        }
    }
}

