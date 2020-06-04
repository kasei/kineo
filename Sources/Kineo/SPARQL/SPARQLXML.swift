//
//  SPARQLXML.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 5/1/18.
//

import Foundation
import SPARQLSyntax

public struct SPARQLXMLSerializer<T: ResultProtocol> : SPARQLSerializable where T.TermType == Term {
    typealias ResultType = T
    public let canonicalMediaType = "application/sparql-results+xml"

    public var serializesTriples = false
    public var serializesBindings = true
    public var serializesBoolean = true
    public var acceptableMediaTypes: [String] { return [canonicalMediaType, "application/xml"] }

    public init() {
    }
    
    func write(boolean: Bool, into root: XMLElement) {
        let b = XMLNode.element(withName: "boolean", stringValue: "\(boolean)") as! XMLNode
        root.addChild(b)
    }

    func write<S: Sequence>(variables: [String], rows: S, into root: XMLElement) where S.Element == SPARQLResult<Term> {
        write(head: variables, into: root)
        write(rows: rows, into: root)
    }

    func write(term: Term, into root: XMLElement) {
        switch term.type {
        case .blank:
            let e = XMLNode.element(withName: "bnode", stringValue: term.value) as! XMLElement
            root.addChild(e)
        case .iri:
            let e = XMLNode.element(withName: "uri", stringValue: term.value) as! XMLElement
            root.addChild(e)
        case .datatype(let dt):
            let e = XMLNode.element(withName: "literal", stringValue: term.value) as! XMLElement
            let attr = XMLNode.attribute(withName: "datatype", stringValue: dt.value) as! XMLNode
            e.addAttribute(attr)
            root.addChild(e)
        case .language(let lang):
            let e = XMLNode.element(withName: "literal", stringValue: term.value) as! XMLElement
            let attr = XMLNode.attribute(withName: "xml:lang", stringValue: lang) as! XMLNode
            e.addAttribute(attr)
            root.addChild(e)
        }
    }
    
    func write(result row: SPARQLResult<Term>, into root: XMLElement) {
        let result = XMLElement(name: "result")
        for (name, t) in row.sorted(by: { $0 < $1 }) {
            let binding = XMLElement(name: "binding")
            let attr = XMLNode.attribute(withName: "name", stringValue: name) as! XMLNode
            binding.addAttribute(attr)
            write(term: t, into: binding)
            result.addChild(binding)
        }
        root.addChild(result)
    }
    
    func write<S: Sequence>(rows: S, into root: XMLElement) where S.Element == SPARQLResult<Term> {
        let results = XMLElement(name: "results")
        for r in rows {
            write(result: r, into: results)
        }
        root.addChild(results)
    }
    
    func write(head variables: [String], into root: XMLElement) {
        let head = XMLElement(name: "head")
        for name in variables {
            let variable = XMLElement(name: "variable")
            let attr = XMLNode.attribute(withName: "name", stringValue: name) as! XMLNode
            variable.addAttribute(attr)
            head.addChild(variable)
        }
        root.addChild(head)
    }
    
    public func serialize<R: Sequence, T: Sequence>(_ results: QueryResult<R, T>) throws -> Data where R.Element == SPARQLResult<Term>, T.Element == Triple {
        let root = XMLElement(name: "sparql")
        let ns = XMLNode.namespace(withName: "", stringValue: "http://www.w3.org/2005/sparql-results#") as! XMLNode
        root.addNamespace(ns)

        switch results {
        case .boolean(let v):
            write(boolean: v, into: root)
        case .bindings(let variables, let rows):
            write(variables: variables, rows: rows, into: root)
        default:
            throw SerializationError.encodingError("RDF triples cannot be serialized using the SPARQL/XML format")
        }
        
        let xml = XMLDocument(rootElement: root)
        xml.isStandalone = true
        return xml.xmlData
    }

}

public struct SPARQLXMLParser : SPARQLParsable {
    public let mediaTypes = Set(["application/sparql-results+xml"])
    
    public init() {
        
    }
    class Delegate: NSObject, XMLParserDelegate {
        enum QueryType {
            case bindings
            case boolean(Bool)
        }
        var traceParsing: Bool
        var depth: Int
        var results: [SPARQLResult<Term>]
        var type: QueryType?
        var projection: [String]
        var allowCharacterData: Bool
        var bindings: [String:Term]
        var bindingName: String?
        var chars: String
        var termType: TermType?
        var error: SerializationError?
        override init() {
            allowCharacterData = false
            depth = 0
            type = nil
            projection = []
            termType = nil
            results = []
            bindings = [:]
            bindingName = nil
            chars = ""
            error = nil
            
            traceParsing = false
            super.init()
        }
        
        var indent: String {
            return String(repeating: " ", count: depth*4)
        }
        
        var queryResult: QueryResult<[SPARQLResult<Term>], [Triple]>? {
            guard let t = type else { return nil }
            switch t {
            case .bindings:
                return QueryResult<[SPARQLResult<Term>], [Triple]>.bindings(projection, results)
            case .boolean(let b):
                return QueryResult<[SPARQLResult<Term>], [Triple]>.boolean(b)
            }
        }
        
        private func trace(_ message: String) {
            if traceParsing {
                print("\(indent)\(message)")
            }
        }
        
        func parserDidStartDocument(_ parser: XMLParser) {
//            trace("parserDidStartDocument")
            chars = ""
        }
        
        func parserDidEndDocument(_ parser: XMLParser) {
//            trace("parserDidEndDocument")
        }
        
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
//            trace("didStartElement \(elementName)")
            depth += 1
            chars = ""
            switch elementName {
            case "results":
                type = .bindings
            case "variable":
                if let v = attributeDict["name"] {
                    projection.append(v)
                }
            case "boolean":
                allowCharacterData = true
            case "result":
                bindings = [:]
            case "binding":
                guard let v = attributeDict["name"] else {
                    error = SerializationError.parsingError("Found <binding> without associated binding name during SRX parsing")
                    return
                }
//                trace("  [name=\(v)]")
                bindingName = v
            case "literal":
                allowCharacterData = true
                if let dt = attributeDict["datatype"] {
//                    trace("  [datatype=\(dt)]")
                    termType = .datatype(TermDataType(stringLiteral: dt))
                } else if let lang = attributeDict["xml:lang"] {
//                    trace("  [xml:lang=\(lang)]")
                    termType = .language(lang)
                } else {
                    termType = .datatype(.string)
                }
            case "uri":
                allowCharacterData = true
                termType = .iri
            case "bnode":
                allowCharacterData = true
                termType = .blank
            default:
                break
            }
        }
        
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
//            trace("didEndElement \(elementName)")
            depth -= 1
            switch elementName {
            case "result":
                let r = SPARQLResult<Term>(bindings: bindings)
                results.append(r)
            case "boolean":
                allowCharacterData = false
                type = .boolean(chars == "true")
            case "literal", "uri", "bnode":
                allowCharacterData = false
            case "binding":
                guard let name = bindingName else {
                    error = SerializationError.parsingError("No binding name available while construcing result")
                    return
                }
                guard let type = termType else {
                    error = SerializationError.parsingError("No term type available in binding \(name)")
                    return
                }
                bindings[name] = Term(value: chars, type: type)
            default:
                break
            }
        }
        
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if allowCharacterData {
//                trace("foundCharacters: '\(string.replacingOccurrences(of: "\n", with: " "))'")
                chars += string
            }
        }
    }
    
    public func parse(_ data: Data) throws -> QueryResult<[SPARQLResult<Term>], [Triple]> {
        let parser = XMLParser(data: data)
        let delegate = Delegate()
        parser.delegate = delegate
        if !parser.parse() {
            if let e = parser.parserError {
                throw e
            }
        }
        
        if let e = delegate.error {
            throw e
        }
        
        guard let r = delegate.queryResult else {
            throw SerializationError.parsingError("No query result available at end of parsing")
        }
        return r
    }
}
