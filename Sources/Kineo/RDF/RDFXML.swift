//
//  RDFXML.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 5/6/18.
//

import Foundation
import SPARQLSyntax

public struct RDFXMLParser {
    enum ParserError: Error {
        case parsingError(String)
    }
    
    let mediaTypes = Set(["application/rdf+xml"])
    let fileExtensions = Set(["rdf", "xml"])
    var bnode_prefix: String
    var base: String
    
    init(base: String? = nil) {
        self.base = base ?? "http://base.example.org/"
        self.bnode_prefix = "b"
    }
    
    class RDFXMLParserDelegate: NSObject, XMLParserDelegate {
        enum ExpectedData {
            case none
            case subject
            case predicate
            case object
            case literal
            case collection
        }
        
        var traceParsing: Bool
        var expectedState: [ExpectedData]
        var base: [String]
        var depth: Int
        var characters: String
        var prefix: String
        var counter: Int
        var nodes: [Term]
        var chars_ok: Bool
        var error: SerializationError?
        var tripleHandler: TripleHandler
        var named_bnodes: [String:Term]
        var collection_last: [Term?]
        var collection_head: [Term?]
        var seqs: [Int]
        var reify_id: [String?]
        var datatype: String?
        var language: [String]
        var literal_depth: Int
        var rdf_resource: Term?
        var errors: [ParserError]
        var namespaces: [String:[String]]

        init(base baseURI: String, tripleHandler handler: @escaping TripleHandler) {
            expectedState = [.subject, .none]
            seqs = [0]
            base = [baseURI]
            depth = 0
            characters = ""
            prefix = ""
            counter = 0
            nodes = []
            chars_ok = false
            error = nil
            named_bnodes = [:]
            collection_last = []
            collection_head = []
            datatype = nil
            language = []
            literal_depth = 0
            rdf_resource = nil
            reify_id = [nil]
            errors = []
            tripleHandler = handler
            namespaces = [:]

            traceParsing = false
            super.init()
        }
        
        func expect(_ e : ExpectedData) {
            expectedState.insert(e, at: 0)
        }
        
        func expecting(_ e : ExpectedData) -> Bool {
            if let expected = self.expectedState.first {
                return expected == e
            }
            return false
        }

        @discardableResult
        func pop_expect() -> ExpectedData {
            let e = expectedState[0]
            expectedState.removeFirst()
            return e
        }
        
        func get_language() -> String? {
            return language.last
        }
        
        func push_language(_ l: String) {
            language.append(l)
        }
        
        func pop_language() {
            if language.count > 0 {
                language.removeLast()
            }
        }

        func pop_base() {
            if base.count > 0 {
                base.removeLast()
            }
        }

        var indent: String {
            return String(repeating: " ", count: depth*4)
        }
        
        private func trace(_ message: String) {
            if traceParsing {
                print("\(indent)\(message)")
            }
        }
        
        func parserDidStartDocument(_ parser: XMLParser) {
            trace("parserDidStartDocument")
            characters = ""
        }
        
        func parserDidEndDocument(_ parser: XMLParser) {
            trace("parserDidEndDocument")
        }
        
        private func handleScopedValues(_ elementName: String, attributes attributeDict: [String : String]) {
            let b = attributeDict["xml:base"] ?? self.base.last ?? ""
            base.append(b)
            language.append(attributeDict["xml:lang"] ?? "")
        }
        
        func new_iri(_ value: String) -> Term {
            var iri = value
            if let b = base.first {
                if iri == "" {
                    return Term(iri: b)
                }
                if let u = SPARQLSyntax.IRI(string: iri, relativeTo: SPARQLSyntax.IRI(string: b)) {
                    iri = u.absoluteString
                }
            }
            return Term(iri: iri)
        }
        
        func new_literal(_ value: String) -> Term {
            if let dt = datatype {
                if dt == "http://www.w3.org/1999/02/22-rdf-syntax-ns#XMLLiteral" {
                    fatalError()
                } else {
                    return Term(value: value, type: .datatype(dt))
                }
            } else if let lang = get_language() {
                if lang.count > 0 {
                    return Term(value: value, type: .language(lang))
                } else {
                    return Term(string: value)
                }
            } else {
                return Term(string: value)
            }
        }
        
        func new_bnode() -> Term {
            let id = NSUUID().uuidString
            return Term(value: id, type: .blank)
        }
        
        private func get_named_bnode(name: String) -> Term {
            if let t = named_bnodes[name] {
                return t
            } else {
                return new_bnode()
            }
        }
        
        @discardableResult
        private func parse_literal_property_attributes(elementName: String, attributes attributeDict: [String : String] = [:], term: Term? = nil) throws -> Term? {
            let node_id = term ?? new_bnode()
            var asserted = false
            reify_id.insert(nil, at: 0)
            let ignore = Set([
                "xmlns",
                "about",
                "xml:lang",
                "xml:base",
                "rdf:resource",
                "rdf:about",
                "rdf:ID",
                "rdf:datatype",
                "rdf:nodeID",
                ])
            for (k, data) in attributeDict.filter({ (k,_) -> Bool in !ignore.contains(k) }) {
                let pair = k.components(separatedBy: ":")
                guard pair.count == 2 else { continue }
                let u = try uri(for: pair[0], local: pair[1])
                let pred = Term(iri: u)
                let obj = new_literal(data)
                if let subj = nodes.last {
                    tripleHandler(subj, pred, obj)
                    asserted = true
                }
            }
            reify_id.removeFirst()
            return asserted ? node_id : nil
        }
        
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
            depth += 1
            
            let iri = "\(namespaceURI ?? "")\(elementName)"
            trace("didStartElement \(elementName) <\(iri)>")
            if !expecting(.literal) {
                handleScopedValues(elementName, attributes: attributeDict)
            }
            
            if depth == 1 && iri == "http://www.w3.org/1999/02/22-rdf-syntax-ns#RDF" {
                // ignore the wrapping of rdf:RDF element
                return
            }
            
            let e = expectedState.first!
            if e == .none {
                expect(.subject)
            }
            
            do {
                if expecting(.subject) || expecting(.object) {
                    let node = new_iri(iri)
                    if expecting(.object) {
                        characters = ""
                    }
                    
                    let node_id: Term
                    if let about = attributeDict["rdf:about"] {
                        node_id = new_iri(about)
                    } else if let id = attributeDict["rdf:ID"] {
                        node_id = new_iri("#\(id)")
                    } else if let nodeID = attributeDict["rdf:nodeID"] {
                        node_id = get_named_bnode(name: nodeID)
                    } else {
                        node_id = new_bnode()
                    }

                    if let peekIndex = expectedState.index(0, offsetBy: 1, limitedBy: expectedState.endIndex), expectedState[peekIndex] == .collection {
                        let list = new_bnode()
                        if let l = collection_last.first, let last = l {
                            tripleHandler(last, Term.rdf("rest"), list)
                        }
                        
                        if collection_last.count == 0 {
                            collection_last.append(list)
                        } else {
                            collection_last[0] = list
                        }
                        tripleHandler(list, Term.rdf("first"), node_id)
                        if collection_head.count == 0 {
                            collection_head.append(list)
                        } else if collection_head.first! == nil {
                            collection_head[0] = list
                        }
                    } else if expecting(.object) {
                        let pair = nodes.suffix(2)
                        if pair.count == 2 {
                            let i = pair.startIndex
                            let s = pair[i]
                            let p = pair[i+1]
                            tripleHandler(s, p, node_id)
                        }
                    }
                    
                    if iri != "http://www.w3.org/1999/02/22-rdf-syntax-ns#Description" {
                        tripleHandler(node_id, Term.rdf("type"), node)
                    }
                    nodes.append(node_id)
                    try parse_literal_property_attributes(elementName: elementName, attributes: attributeDict, term: node)
                    expect(.predicate)
                    seqs.insert(0, at: 0)
                } else if expecting(.collection) {
                } else if expecting(.predicate) {
                    var node = new_iri(iri)
                    if iri == "http://www.w3.org/1999/02/22-rdf-syntax-ns#li" {
                        seqs[0] += 1
                        let id = seqs[0]
                        node = Term.rdf("_\(id)")
                    }
                    nodes.append(node)
                    if let dt = attributeDict["rdf:datatype"] {
                        datatype = dt
                    }
                    
                    if let id = attributeDict["rdf:ID"] {
                        reify_id.insert(id, at: 0)
                    } else {
                        reify_id.insert(nil, at: 0)
                    }
                    
                    if let pt = attributeDict["rdf:parseType"] {
                        switch pt {
                        case "Resource":
                            // fake an enclosing object scope
                            let node = new_bnode()
                            nodes.append(node)
                            let triple = nodes.suffix(3)
                            let i = triple.startIndex
                            tripleHandler(triple[i], triple[i+1], triple[i+2])
                            expect(.predicate)
                        case "Literal":
                            datatype = "http://www.w3.org/1999/02/22-rdf-syntax-ns#XMLLiteral"
                            literal_depth = depth - 1
                            expect(.literal)
                        case "Collection":
                            collection_head.insert(nil, at: 0)
                            collection_last.insert(nil, at: 0)
                            expect(.collection)
                            expect(.object)
                        default:
                            errors.append(ParserError.parsingError("Unrecognized rdf:parseType"))
                            return
                        }
                    } else if let data = attributeDict["rdf:resource"] {
                        // stash the uri away so that we can use it when we get the end_element call for this predicate
                        let uri = new_iri(data)
                        try parse_literal_property_attributes(elementName: elementName, attributes: attributeDict, term: uri)
                        rdf_resource = uri
                        expect(.object)
                        chars_ok = true
                    } else if let node_name = attributeDict["rdf:nodeID"] {
                        // stash the bnode away so that we can use it when we get the end_element call for this predicate
                        let bnode = get_named_bnode(name: node_name)
                        try parse_literal_property_attributes(elementName: elementName, attributes: attributeDict, term: new_iri(iri))
                        rdf_resource = bnode // the key 'rdf:resource' is a bit misused here, but both rdf:resource and rdf:nodeID use it for the same purpose, so...
                        expect(.object)
                        chars_ok = true
                    } else if let node = try parse_literal_property_attributes(elementName: elementName, attributes: attributeDict) {
                        // fake an enclosing object scope
                        nodes.append(node)
                        let triple = nodes.suffix(3)
                        let i = triple.startIndex
                        tripleHandler(triple[i], triple[i+1], triple[i+2])
                        expect(.predicate)
                    } else {
                        expect(.object)
                        chars_ok = true
                    }
                } else if expecting(.literal) {
                    let tag = qName ?? elementName
                    characters += "<\(tag)"
                    /**
                my $attr	= $el->{Attributes};
                if (my $ns = $el->{NamespaceURI}) {
                    my $abbr = $el->{Prefix};
                    unless ($self->{defined_literal_namespaces}{$abbr}{$ns}) {
                        $self->{characters}	.= ' xmlns';
                        if (length($abbr)) {
                            $self->{characters}	.= ':' . $abbr;
                        }
                        $self->{characters}	.= '="' . $ns . '"';
                        $self->{defined_literal_namespaces}{$abbr}{$ns}++;
                    }
                }
                     **/
                    
                    for (k, value) in attributeDict {
                        characters += " \(k)=\"\(value)\""
                    }
                    characters += ">"
                } else {
                    errors.append(ParserError.parsingError("not sure what type of token is expected"))
                    return
                }
            } catch let e {
                errors.append(e as! ParserError)
                return
            }
        }
        
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            depth -= 1
            trace("didEndElement \(elementName)")
            
            var cleanup = false
            if expecting(.subject) {
                pop_expect()
                cleanup = true
                chars_ok = false
                reify_id.removeFirst()
            } else if expecting(.predicate) {
                pop_expect()
                if expecting(.predicate) {
                    // we're closing a parseType=Resource block, so take off the extra implicit node.
                    nodes.removeLast()
                } else {
                    seqs.removeFirst()
                }
                cleanup = true
                chars_ok = false
            } else if expecting(.object) || (expecting(.literal) && literal_depth == depth) {
                if let uri = rdf_resource {
                    rdf_resource = nil
                    characters = ""
                    let pair = nodes.suffix(2)
                    if pair.count == 2 {
                        let i = pair.startIndex
                        tripleHandler(pair[i], pair[i+1], uri)
                    }
                }
                pop_expect()
                let string = characters
                if string.count > 0 {
                    let literal = new_literal(string)
                    let pair = nodes.suffix(2)
                    if pair.count == 2 {
                        let i = pair.startIndex
                        tripleHandler(pair[i], pair[i+1], literal)
                    }
                }
                characters = ""
                datatype = nil
                // TODO: defined_literal_namespaces = nil
                
                if expecting(.collection) {
                    // We were expecting an object, but got an end_element instead.
                    // after poping the OBJECT expectation, we see we were expecting objects in a COLLECTION.
                    // so we're ending the COLLECTION here:
                    pop_expect()
                    if let head = collection_head.first {
                        let headTerm = head ?? Term.rdf("nil")
                        let pair = nodes.suffix(2)
                        if pair.count == 2 {
                            let i = pair.startIndex
                            tripleHandler(pair[i], pair[i+1], headTerm)
                        }
                    }
                    
                    if let last = collection_last.first {
                        if let l = last {
                            tripleHandler(l, Term.rdf("rest"), Term.rdf("nil"))
                        }
                    }
                    
                    collection_last.removeFirst()
                    collection_head.removeFirst()
                }
                cleanup = true
                chars_ok = false
                reify_id.removeFirst()
            } else if expecting(.collection) {
                pop_expect()
            } else if expecting(.literal) {
                let tag = qName ?? elementName
                characters += "</\(tag)>"
                cleanup = false
            } else {
                fatalError()
            }
            
            if cleanup {
                if nodes.count > 0 {
                    nodes.removeLast()
                }
                pop_language()
                pop_base()
            }
        }
        
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if expecting(.literal) || (expecting(.object) && self.chars_ok) {
                self.characters.append(string)
            }
            trace("foundCharacters: '\(string.replacingOccurrences(of: "\n", with: " "))'")
        }
        
        func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
            trace("+ XMLNS \(prefix): \(namespaceURI)")
            namespaces[prefix, default: []].append(namespaceURI)
        }
        
        func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) {
            trace("- XMLNS \(prefix)")
            namespaces[prefix, default: []].removeLast()
        }
        
        func uri(for prefix: String, local: String) throws -> String {
            guard let ns = namespaces[prefix, default: []].last else {
                throw ParserError.parsingError("No mapping found for namespace prefix '\(prefix)'")
            }
            return "\(ns)\(local)"
        }
    }
    
    func parse(string: String, tripleHandler: @escaping TripleHandler) throws {
        guard let data = string.data(using: .utf8) else {
            throw ParserError.parsingError("RDF/XML data not in expected utf-8 encoding")
        }
        return try parse(data: data, tripleHandler: tripleHandler)
    }
    
    func parse(data: Data, tripleHandler: @escaping TripleHandler) throws {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        let delegate = RDFXMLParserDelegate(base: base, tripleHandler: tripleHandler)
        parser.delegate = delegate
        if !parser.parse() {
            if let e = parser.parserError {
                throw e
            }
        }
        
        if let e = delegate.error {
            throw e
        }
    }
}
