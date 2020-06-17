//
//  SerdParser.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 10/7/18.
//

import serd
import Foundation
import SPARQLSyntax

private class ParserContext {
    var count: Int
    var errors: [Error]
    var handler: QuadHandler
    var env: OpaquePointer!
    var defaultGraph: Term
    
    init(env: OpaquePointer, handler: @escaping QuadHandler, defaultGraph: Term, produceUniqueBlankIdentifiers: Bool = true) {
        var blankNodes = [String:Term]()
        self.defaultGraph = defaultGraph
        self.count = 0
        self.env = env
        self.handler = { (s,p,o,g) in
            var subj = s
            let pred = p
            var obj = o
            let graph = g
            
            if case .blank = subj.type {
                if let t = blankNodes[subj.value] {
                    subj = t
                } else if produceUniqueBlankIdentifiers {
                    let id = NSUUID().uuidString
                    let b = Term(value: id, type: .blank)
                    blankNodes[subj.value] = b
                    subj = b
                } else {
                    subj = Term(value: subj.value, type: .blank)
                }
            }
            if case .blank = obj.type {
                if let t = blankNodes[obj.value] {
                    obj = t
                } else if produceUniqueBlankIdentifiers {
                    let id = NSUUID().uuidString
                    let b = Term(value: id, type: .blank)
                    blankNodes[obj.value] = b
                    obj = b
                } else {
                    obj = Term(value: obj.value, type: .blank)
                }
            }
            
            handler(subj, pred, obj, graph)
        }
        self.errors = []
    }
}



let serd_base_sink : @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<SerdNode>?) -> SerdStatus = { (handle, node) -> SerdStatus in
    guard let handle = handle, let node = node else { return SERD_FAILURE }
    let ptr = handle.assumingMemoryBound(to: ParserContext.self)
    let ctx = ptr.pointee
    let env = ctx.env
    return serd_env_set_base_uri(env, node)
}

let serd_prefix_sink : @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<SerdNode>?, UnsafePointer<SerdNode>?) -> SerdStatus = { (handle, name, uri) -> SerdStatus in
    guard let handle = handle, let name = name, let uri = uri else { return SERD_FAILURE }
    let ptr = handle.assumingMemoryBound(to: ParserContext.self)
    let ctx = ptr.pointee
    let env = ctx.env
    return serd_env_set_prefix(env, name, uri)
}

let serd_free_handle : @convention(c) (UnsafeMutableRawPointer?) -> Void = { (ptr) -> Void in }

let sentinel_graph = Term(iri: "tag:kasei.us,2018:sentinel-graph")
let serd_statement_sink : @convention(c) (UnsafeMutableRawPointer?, SerdStatementFlags, UnsafePointer<SerdNode>?, UnsafePointer<SerdNode>?, UnsafePointer<SerdNode>?, UnsafePointer<SerdNode>?, UnsafePointer<SerdNode>?, UnsafePointer<SerdNode>?) -> SerdStatus = { (handle, flags, graph, subject, predicate, object, datatype, language) -> SerdStatus in
    guard let handle = handle, let subject = subject, let predicate = predicate, let object = object else { return SERD_FAILURE }
    let ptr = handle.assumingMemoryBound(to: ParserContext.self)
    let ctx = ptr.pointee
    let env = ctx.env
    let handler = ctx.handler
    
    do {
        var dt: String? = nil
        if let dtTerm = datatype?.pointee {
            if let term = try? serd_node_as_term(env: env, node: dtTerm, datatype: nil, language: nil) {
                dt = term.value
            }
        }
        
        let s = try serd_node_as_term(env: env, node: subject.pointee, datatype: nil, language: nil)
        let p = try serd_node_as_term(env: env, node: predicate.pointee, datatype: nil, language: nil)
        let o = try serd_node_as_term(env: env, node: object.pointee, datatype: dt, language: language?.pointee.value)
        let g: Term
        if let graph = graph {
            g = try serd_node_as_term(env: env, node: graph.pointee, datatype: nil, language: nil)
        } else {
            g = sentinel_graph
        }

        ctx.count += 1
        handler(s, p, o, g)
    } catch let e {
        print("*** \(e)")
        return SERD_FAILURE
    }
    return SERD_SUCCESS
}

let serd_end_sink : @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<SerdNode>?) -> SerdStatus = { (handle, node) -> SerdStatus in return SERD_SUCCESS }

let serd_error_sink : @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<SerdError>?) -> SerdStatus = { (handle, error) in
    if let error = error {
        let e = error.pointee
        let filename = String(cString: e.filename)
        let fmt = String(cString: e.fmt)
        let msg = "serd error while parsing \(filename): \(fmt))"
        Logger.shared.error(msg)
        if let ptr = handle?.assumingMemoryBound(to: ParserContext.self) {
            let ctx = ptr.pointee
            ctx.errors.append(RDFParserCombined.RDFParserError.parseError(msg))
        }
    } else {
        Logger.shared.error("serd error during parsing")
    }
    return SERD_FAILURE
}

private func serd_node_as_term(env: OpaquePointer?, node: SerdNode, datatype: String?, language: String?) throws -> Term {
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
            let dt = TermDataType(stringLiteral: datatype ?? Namespace.xsd.string)
            return Term(value: node.value, type: .datatype(dt))
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
            throw RDFParserCombined.RDFParserError.parseError("Undefined namespace prefix \(node.value)")
        }
        return term
    default:
        throw RDFParserCombined.RDFParserError.parseError("Unexpected SerdNode type: \(node.type)")
    }
}

public struct SerdParser {
    var inputSyntax: RDFParserCombined.RDFSyntax
    var defaultBase: String
    var produceUniqueBlankIdentifiers: Bool
    
    public init(syntax: RDFParserCombined.RDFSyntax = .turtle, base defaultBase: String = "http://base.example.org/", produceUniqueBlankIdentifiers: Bool = true) {
        self.inputSyntax = syntax
        self.defaultBase = defaultBase
        self.produceUniqueBlankIdentifiers = produceUniqueBlankIdentifiers
    }

    public func serd_parse(string: String, handleTriple: @escaping (Term, Term, Term) -> Void) throws -> Int {
        var baseUri = SERD_URI_NULL
        var base = SERD_NODE_NULL
        
        guard let env = serd_env_new(&base) else { throw RDFParserCombined.RDFParserError.internalError("Failed to construct parser context") }
        base = serd_node_new_uri_from_string(defaultBase, nil, &baseUri)
        
        let handleQuad : QuadHandler = { (s,p,o,_) in handleTriple(s,p,o) }
        let defaultGraph = Term(iri: "tag:kasei.us,2018:default-graph")
        var context = ParserContext(env: env, handler: handleQuad, defaultGraph: defaultGraph, produceUniqueBlankIdentifiers: produceUniqueBlankIdentifiers)
        let status = try withUnsafePointer(to: &context) { (ctx) -> SerdStatus in
            guard let reader = serd_reader_new(inputSyntax.serdSyntax!, UnsafeMutableRawPointer(mutating: ctx), serd_free_handle, serd_base_sink, serd_prefix_sink, serd_statement_sink, serd_end_sink) else {
                throw RDFParserCombined.RDFParserError.parseError("Failed to construct Serd reader")
            }
            
            serd_reader_set_strict(reader, true)
            serd_reader_set_error_sink(reader, serd_error_sink, nil)
            
            let status = serd_reader_read_string(reader, string)
            serd_reader_free(reader)
            return status
        }
        
        serd_env_free(env)
        serd_node_free(&base)
        
        if status != SERD_SUCCESS {
            throw RDFParserCombined.RDFParserError.parseError("Failed to parse string using serd")
        }
        
        return context.count
    }
    
    public func serd_parse(string: String, defaultGraph: Term, handleQuad: @escaping (Term, Term, Term, Term) -> Void) throws -> Int {
        var baseUri = SERD_URI_NULL
        var base = SERD_NODE_NULL
        
        guard let env = serd_env_new(&base) else { throw RDFParserCombined.RDFParserError.internalError("Failed to construct parser context") }
        base = serd_node_new_uri_from_string(defaultBase, nil, &baseUri)
        
        var context = ParserContext(env: env, handler: handleQuad, defaultGraph: defaultGraph, produceUniqueBlankIdentifiers: produceUniqueBlankIdentifiers)
        let status = try withUnsafePointer(to: &context) { (ctx) -> SerdStatus in
            guard let reader = serd_reader_new(inputSyntax.serdSyntax!, UnsafeMutableRawPointer(mutating: ctx), serd_free_handle, serd_base_sink, serd_prefix_sink, serd_statement_sink, serd_end_sink) else {
                throw RDFParserCombined.RDFParserError.parseError("Failed to construct Serd reader")
            }
            
            serd_reader_set_strict(reader, true)
            serd_reader_set_error_sink(reader, serd_error_sink, nil)
            
            let status = serd_reader_read_string(reader, string)
            serd_reader_free(reader)
            return status
        }
        
        serd_env_free(env)
        serd_node_free(&base)
        
        if status != SERD_SUCCESS {
            throw RDFParserCombined.RDFParserError.parseError("Failed to parse string using serd")
        }
        
        return context.count
    }
    
    public func serd_parse(file filename: String, base _base: String? = nil , handleTriple: @escaping TripleHandler) throws -> Int {
        guard let input = serd_uri_to_path(filename) else { throw RDFParserCombined.RDFParserError.parseError("no such file") }
        
        var baseUri = SERD_URI_NULL
        var base = SERD_NODE_NULL
        if let b = _base {
            base = serd_node_new_uri_from_string(b, &baseUri, nil)
        } else {
            base = serd_node_new_file_uri(input, nil, &baseUri, false)
        }
        
        guard let env = serd_env_new(&base) else { throw RDFParserCombined.RDFParserError.internalError("Failed to construct parser context") }
        
        let handleQuad : QuadHandler = { (s,p,o,_) in handleTriple(s,p,o) }
        let defaultGraph = Term(iri: "tag:kasei.us,2018:default-graph")
        var context = ParserContext(env: env, handler: handleQuad, defaultGraph: defaultGraph, produceUniqueBlankIdentifiers: produceUniqueBlankIdentifiers)
        _ = try withUnsafePointer(to: &context) { (ctx) throws -> SerdStatus in
            guard let reader = serd_reader_new(inputSyntax.serdSyntax!, UnsafeMutableRawPointer(mutating: ctx), serd_free_handle, serd_base_sink, serd_prefix_sink, serd_statement_sink, serd_end_sink) else {
                throw RDFParserCombined.RDFParserError.parseError("Failed to construct Serd reader")
            }
            
            serd_reader_set_strict(reader, true)
            serd_reader_set_error_sink(reader, serd_error_sink, UnsafeMutableRawPointer(mutating: ctx))
            
            guard let in_fd = fopen(filename, "r") else {
                let errptr = strerror(errno)
                let error = errptr == .none ? "(internal error)" : String(cString: errptr!)
                throw RDFParserCombined.RDFParserError.parseError("Failed to open \(filename): \(error)")
            }
            
            var status = serd_reader_start_stream(reader, in_fd, filename, false)
            while status == SERD_SUCCESS {
                status = serd_reader_read_chunk(reader)
            }
            serd_reader_end_stream(reader)
            serd_reader_free(reader)
            return status
        }
        
        serd_env_free(env)
        serd_node_free(&base)
        
        if let e = context.errors.first {
            throw e
        }
        
        return context.count
    }
    
    public func serd_parse(file filename: String, defaultGraph: Term, base _base: String? = nil , handleQuad: @escaping QuadHandler) throws -> Int {
        guard let input = serd_uri_to_path(filename) else { throw RDFParserCombined.RDFParserError.parseError("no such file") }
        
        var baseUri = SERD_URI_NULL
        var base = SERD_NODE_NULL
        if let b = _base {
            base = serd_node_new_uri_from_string(b, &baseUri, nil)
        } else {
            base = serd_node_new_file_uri(input, nil, &baseUri, false)
        }
        
        guard let env = serd_env_new(&base) else { throw RDFParserCombined.RDFParserError.internalError("Failed to construct parser context") }
        
//        let defaultGraph = Term(iri: "tag:kasei.us,2018:default-graph")
        var context = ParserContext(env: env, handler: handleQuad, defaultGraph: defaultGraph, produceUniqueBlankIdentifiers: produceUniqueBlankIdentifiers)
        _ = try withUnsafePointer(to: &context) { (ctx) throws -> SerdStatus in
            guard let reader = serd_reader_new(inputSyntax.serdSyntax!, UnsafeMutableRawPointer(mutating: ctx), serd_free_handle, serd_base_sink, serd_prefix_sink, serd_statement_sink, serd_end_sink) else {
                throw RDFParserCombined.RDFParserError.parseError("Failed to construct Serd reader")
            }
            
            serd_reader_set_strict(reader, true)
            serd_reader_set_error_sink(reader, serd_error_sink, UnsafeMutableRawPointer(mutating: ctx))
            
            guard let in_fd = fopen(filename, "r") else {
                let errptr = strerror(errno)
                let error = errptr == .none ? "(internal error)" : String(cString: errptr!)
                throw RDFParserCombined.RDFParserError.parseError("Failed to open \(filename): \(error)")
            }
            
            var status = serd_reader_start_stream(reader, in_fd, filename, false)
            while status == SERD_SUCCESS {
                status = serd_reader_read_chunk(reader)
            }
            serd_reader_end_stream(reader)
            serd_reader_free(reader)
            return status
        }
        
        serd_env_free(env)
        serd_node_free(&base)
        
        if let e = context.errors.first {
            throw e
        }
        
        return context.count
    }
}

fileprivate extension SerdURI {
    var value : String {
        var value = ""
        value += self.scheme.value
        value += ":"
        if self.authority.defined {
            value += "//"
        }
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
    var defined : Bool {
        if let _ = self.buf {
            return true
        } else {
            return false
        }
    }
    
    var value : String {
        if let buf = self.buf {
            let len = self.len
            let value = String(cString: buf)
            if value.utf8.count != len {
                let bytes = value.utf8.prefix(len)
                if let string = String(bytes) {
                    return string
                } else {
                    fatalError("Internal error while transforming SerdChunk into a value string")
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
                    fatalError("Internal error while transforming SerdNode into a value string")
                }
            } else {
                return value
            }
        } else {
            return ""
        }
    }
}
