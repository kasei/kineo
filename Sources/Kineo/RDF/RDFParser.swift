//
//  RDFParser.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 1/21/17.
//  Copyright © 2017 Gregory Todd Williams. All rights reserved.
//

import serd
import Foundation
import SPARQLParser

public class RDFParser {
    public enum RDFParserError : Error {
        case parseError(String)
        case internalError(String)
    }
    
    public enum RDFSyntax {
        case ntriples
        case turtle
        
        var serdSyntax : SerdSyntax {
            switch self {
            case .ntriples:
                return SERD_NTRIPLES
            case .turtle:
                return SERD_TURTLE
            }
        }
    }

    public typealias TripleHandler = (Term, Term, Term) -> Void
    private class ParserContext {
        var count: Int
        var handler: TripleHandler
        var env: OpaquePointer!
        
        init(env: OpaquePointer, handler: @escaping TripleHandler) {
            self.count = 0
            self.env = env
            self.handler = handler
        }
    }
    
    let base_sink : @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<SerdNode>?) -> SerdStatus = { (handle, node) -> SerdStatus in
        guard let handle = handle, let node = node else { return SERD_FAILURE }
        let ptr = handle.assumingMemoryBound(to: ParserContext.self)
        let ctx = ptr.pointee
        let env = ctx.env
        return serd_env_set_base_uri(env, node)
    }
    
    let prefix_sink : @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<SerdNode>?, UnsafePointer<SerdNode>?) -> SerdStatus = { (handle, name, uri) -> SerdStatus in
        guard let handle = handle, let name = name, let uri = uri else { return SERD_FAILURE }
        let ptr = handle.assumingMemoryBound(to: ParserContext.self)
        let ctx = ptr.pointee
        let env = ctx.env
        return serd_env_set_prefix(env, name, uri)
    }
    
    let free_handle : @convention(c) (UnsafeMutableRawPointer?) -> Void = { (ptr) -> Void in }
    
    let statement_sink : @convention(c) (UnsafeMutableRawPointer?, SerdStatementFlags, UnsafePointer<SerdNode>?, UnsafePointer<SerdNode>?, UnsafePointer<SerdNode>?, UnsafePointer<SerdNode>?, UnsafePointer<SerdNode>?, UnsafePointer<SerdNode>?) -> SerdStatus = { (handle, flags, graph, subject, predicate, object, datatype, language) -> SerdStatus in
        guard let handle = handle, let subject = subject, let predicate = predicate, let object = object else { return SERD_FAILURE }
        let ptr = handle.assumingMemoryBound(to: ParserContext.self)
        let ctx = ptr.pointee
        let env = ctx.env
        let handler = ctx.handler
        
        do {
            let s = try RDFParser.node_as_term(env: env, node: subject.pointee, datatype: nil, language: nil)
            let p = try RDFParser.node_as_term(env: env, node: predicate.pointee, datatype: nil, language: nil)
            let o = try RDFParser.node_as_term(env: env, node: object.pointee, datatype: datatype?.pointee.value, language: language?.pointee.value)
            
            ctx.count += 1
            handler(s, p, o)
        } catch let e {
            print("*** \(e)")
            return SERD_FAILURE
        }
        return SERD_SUCCESS
    }
    
    let end_sink : @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<SerdNode>?) -> SerdStatus = { (handle, node) -> SerdStatus in return SERD_SUCCESS }
    
    let error_sink : @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<SerdError>?) -> SerdStatus = { (reader, error) in
        print("error: \(String(describing: error))")
        return SERD_SUCCESS
    }
    
    var inputSyntax: RDFSyntax
    var defaultBase: String
    public init(syntax: RDFSyntax = .turtle, base defaultBase: String = "http://base.example.org/") {
        self.inputSyntax = syntax
        self.defaultBase = defaultBase
    }
    
    private static func node_as_term(env: OpaquePointer?, node: SerdNode, datatype: String?, language: String?) throws -> Term {
        switch node.type {
        case SERD_URI:
            var base_uri = SERD_URI_NULL
            var uri = SERD_URI_NULL
            var abs_uri = SERD_URI_NULL
            serd_env_get_base_uri(env, &base_uri)
            serd_uri_parse(node.buf, &uri)
            serd_uri_resolve(&uri, &base_uri, &abs_uri)
            return Term(value: abs_uri.value, type: .iri)
        case SERD_BLANK:
            return Term(value: node.value, type: .blank)
        case SERD_LITERAL:
            if let lang = language {
                return Term(value: node.value, type: .language(lang))
            } else {
                return Term(value:node.value, type: .datatype(datatype ?? "http://www.w3.org/2001/XMLSchema#string"))
            }
        case SERD_CURIE:
            var n = node
            let t = withUnsafePointer(to: &n) { (n) -> Term? in
                var uri_prefix = SerdChunk()
                var suffix = SerdChunk()
                let status = serd_env_expand(env, n, &uri_prefix, &suffix)
                guard status == SERD_SUCCESS else {
                    return nil
                }
                return Term(value: "\(uri_prefix.value)\(suffix.value)", type: .iri)
            }
            
            guard let term = t else {
                throw RDFParserError.parseError("Undefined namespace prefix \(node.value)")
            }
            return term
        default:
            // We assume the data being parsed is N-Triples, so we should never see a CURIE
            fatalError("Unexpected SerdNode type: \(node.type)")
        }
    }
    
    @discardableResult
    public func parse(string: String, handleTriple: @escaping (Term, Term, Term) -> Void) throws -> Int {
        var baseUri = SERD_URI_NULL
        var base = SERD_NODE_NULL
        
        guard let env = serd_env_new(&base) else { throw RDFParserError.internalError("Failed to construct parser context") }
        base = serd_node_new_uri_from_string(defaultBase, nil, &baseUri)
        
        var context = ParserContext(env: env, handler: handleTriple)
        withUnsafePointer(to: &context) { (ctx) -> Void in
            guard let reader = serd_reader_new(inputSyntax.serdSyntax, UnsafeMutableRawPointer(mutating: ctx), free_handle, base_sink, prefix_sink, statement_sink, end_sink) else { fatalError() }
            
            serd_reader_set_strict(reader, true)
            serd_reader_set_error_sink(reader, error_sink, nil)
            
            _ = serd_reader_read_string(reader, string)
            serd_reader_free(reader)
        }
        
        serd_env_free(env)
        serd_node_free(&base)
        return context.count
    }
    
    @discardableResult
    public func parse(file filename: String, base _base: String? = nil, handleTriple: @escaping TripleHandler) throws -> Int {
        guard let input = serd_uri_to_path(filename) else { throw RDFParserError.parseError("no such file") }
        
        var baseUri = SERD_URI_NULL
        var base = SERD_NODE_NULL
        if let b = _base {
            base = serd_node_new_uri_from_string(b, &baseUri, nil)
        } else {
            base = serd_node_new_file_uri(input, nil, &baseUri, false)
        }
        
        guard let env = serd_env_new(&base) else { throw RDFParserError.internalError("Failed to construct parser context") }

        var context = ParserContext(env: env, handler: handleTriple)
        try withUnsafePointer(to: &context) { (ctx) throws -> Void in
            guard let reader = serd_reader_new(inputSyntax.serdSyntax, UnsafeMutableRawPointer(mutating: ctx), free_handle, base_sink, prefix_sink, statement_sink, end_sink) else { fatalError() }
            
            serd_reader_set_strict(reader, true)
            serd_reader_set_error_sink(reader, error_sink, nil)
            
            guard let in_fd = fopen(filename, "r") else {
                let errptr = strerror(errno)
                let error = errptr == .none ? "(internal error)" : String(cString: errptr!)
                throw RDFParserError.parseError("\(error)")
            }
            
            var status = serd_reader_start_stream(reader, in_fd, filename, false)
            while status == SERD_SUCCESS {
                status = serd_reader_read_chunk(reader)
            }
            serd_reader_end_stream(reader)
            serd_reader_free(reader)
        }
        
        serd_env_free(env)
        serd_node_free(&base)
        return context.count
    }
}

fileprivate extension SerdURI {
    var value : String {
        var value = ""
        value += self.scheme.value
        value += "://"
        value += self.authority.value
        value += self.path_base.value
        value += self.path.value
        let query = self.query.value
        if query.count > 0 {
            value += "?"
            value += self.query.value
        }
        value += self.fragment.value
        return value
    }
}

fileprivate extension SerdChunk {
    var value : String {
        if let buf = self.buf {
            let len = self.len
            let value = String(cString: buf)
            if value.utf8.count != len {
                let bytes = value.utf8.prefix(len)
                if let string = String(bytes) {
                    return string
                } else {
                    fatalError()
                }
            } else {
                return value
            }
        } else {
            return ""
        }
    }
}

fileprivate extension SerdNode {
    var value : String {
        if let buf = self.buf {
            let len = self.n_bytes
            let value = String(cString: buf)
            if value.utf8.count != len {
                let bytes = value.utf8.prefix(len)
                if let string = String(bytes) {
                    return string
                } else {
                    fatalError()
                }
            } else {
                return value
            }
        } else {
            return ""
        }
    }
}
