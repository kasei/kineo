//
//  SPARQLXML.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 5/1/18.
//

import Foundation
import SPARQLSyntax

public struct SPARQLXMLParser : SPARQLParsable {
    let mediaTypes = Set(["application/sparql-results+xml"])
    
    public init() {
        
    }
    class Delegate: NSObject, XMLParserDelegate {
        enum QueryType {
            case bindings
            case boolean(Bool)
        }
        var traceParsing: Bool
        var depth: Int
        var results: [TermResult]
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
        
        var queryResult: QueryResult<[TermResult], [Triple]>? {
            guard let t = type else { return nil }
            switch t {
            case .bindings:
                return QueryResult<[TermResult], [Triple]>.bindings(projection, results)
            case .boolean(let b):
                return QueryResult<[TermResult], [Triple]>.boolean(b)
            }
        }
        
        private func trace(_ message: String) {
            if traceParsing {
                print("\(indent)\(message)")
            }
        }
        
        func parserDidStartDocument(_ parser: XMLParser) {
            trace("parserDidStartDocument")
            chars = ""
        }
        
        func parserDidEndDocument(_ parser: XMLParser) {
            trace("parserDidEndDocument")
        }
        
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
            trace("didStartElement \(elementName)")
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
                trace("  [name=\(v)]")
                bindingName = v
            case "literal":
                allowCharacterData = true
                if let dt = attributeDict["datatype"] {
                    trace("  [datatype=\(dt)]")
                    termType = .datatype(dt)
                } else if let lang = attributeDict["xml:lang"] {
                    trace("  [xml:lang=\(lang)]")
                    termType = .language(lang)
                } else {
                    termType = .datatype("http://www.w3.org/2001/XMLSchema#string")
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
            trace("didEndElement \(elementName)")
            depth -= 1
            switch elementName {
            case "result":
                let r = TermResult(bindings: bindings)
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
                trace("foundCharacters: '\(string.replacingOccurrences(of: "\n", with: " "))'")
                chars += string
            }
        }
    }
    
    public func parse(_ data: Data) throws -> QueryResult<[TermResult], [Triple]> {
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
