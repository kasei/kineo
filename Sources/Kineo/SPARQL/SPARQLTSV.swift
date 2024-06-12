//
//  SPARQLTSV.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 4/24/18.
//

import Foundation
import SPARQLSyntax

public struct SPARQLTSVSerializer<T: ResultProtocol> : SPARQLSerializable where T.TermType == Term {
    typealias ResultType = T
    public let canonicalMediaType = "text/tab-separated-values"
    
    public var serializesTriples = false
    public var serializesBindings = true
    public var serializesBoolean = false
    public var acceptableMediaTypes: [String] { return [canonicalMediaType] }

    public init() {
    }
    
    public func serialize<R: Sequence, TT: Sequence>(_ results: QueryResult<R, TT>) throws -> Data where R.Element == SPARQLResultSolution<Term>, TT.Element == Triple {
        var d = Data()
        switch results {
        case .boolean(_):
            throw SerializationError.encodingError("Boolean results cannot be serialized in SPARQL-TSV")
        case let .bindings(vars, seq):
            let head = vars.map { "?\($0)" }.joined(separator: "\t")
            guard let headData = head.data(using: .utf8) else {
                throw SerializationError.encodingError("Failed to encode TSV header as utf-8")
            }
            d.append(headData)
            d.append(0x0a)
            
            for result in seq {
                let terms = vars.map { result[$0] }
                let strings = try terms.map { (t) -> String in
                    if let t = t {
                        guard let termString = t.tsvString else {
                            throw SerializationError.encodingError("Failed to encode term as utf-8: \(t)")
                        }
                        return termString
                    } else {
                        return ""
                    }
                }
                
                let line = strings.joined(separator: "\t")
                guard let lineData = line.data(using: .utf8) else {
                    throw SerializationError.encodingError("Failed to encode TSV line as utf-8")
                }
                d.append(lineData)
                d.append(0x0a)
            }
            return d
        case .triples(_):
            throw SerializationError.encodingError("RDF triples cannot be serialized in SPARQL-TSV")
        }
    }
}

private extension String {
    var tsvStringEscaped: String {
        var escaped = ""
        for c in self {
            switch c {
            case Character(UnicodeScalar(0x22)):
                escaped += "\\\""
            case Character(UnicodeScalar(0x5c)):
                escaped += "\\\\"
            case Character(UnicodeScalar(0x09)):
                escaped += "\\t"
            case Character(UnicodeScalar(0x0a)):
                escaped += "\\n"
            default:
                escaped.append(c)
            }
        }
        return escaped
    }
}

private extension Term {
    var tsvString: String? {
        switch self.type {
        case .iri:
            return "<\(value.turtleIRIEscaped)>"
        case .blank:
            return "_:\(self.value)"
        case .language(let l):
            return "\"\(value.tsvStringEscaped)\"@\(l)"
        case .datatype(.integer):
            return "\(Int(self.numericValue))"
        case .datatype(.string):
            return "\"\(value.tsvStringEscaped)\""
        case .datatype(let dt):
            return "\"\(value.tsvStringEscaped)\"^^<\(dt.value)>"
        }
    }
}

public struct SPARQLTSVParser : SPARQLParsable {
    public let mediaTypes = Set(["text/tab-separated-values"])
    var encoding: String.Encoding
    var parser: RDFParserCombined
    
    public init(encoding: String.Encoding = .utf8, produceUniqueBlankIdentifiers: Bool = true) {
        self.encoding = encoding
        self.parser = RDFParserCombined(base: "http://example.org/", produceUniqueBlankIdentifiers: produceUniqueBlankIdentifiers)
    }

    public func parse(_ data: Data) throws -> QueryResult<[SPARQLResultSolution<Term>], [Triple]> {
        guard let s = String(data: data, encoding: encoding) else {
            throw SerializationError.encodingError("Failed to decode SPARQL/TSV data as utf-8")
        }
        
        let lines = s.split(separator: "\n")
        guard let header = lines.first else {
            throw SerializationError.parsingError("SPARQL/TSV data missing header line")
        }
        
        let names = header.split(separator: "\t").map { String($0.dropFirst()) }
        var results = [SPARQLResultSolution<Term>]()
        for line in lines.dropFirst() {
            let values = line.split(separator: "\t", omittingEmptySubsequences: false)
            let terms = try values.map { try parseTerm(String($0)) }
            let pairs = zip(names, terms).compactMap { (name, term) -> (String, Term)? in
                guard let term = term else {
                    return nil
                }
                return (name, term)
            }
            let d = Dictionary(uniqueKeysWithValues: pairs)
            let r = SPARQLResultSolution<Term>(bindings: d)
            results.append(r)
        }
        
        return QueryResult.bindings(names, results)
    }

    private func parseTerm(_ string: String) throws -> Term? {
        guard !string.isEmpty else {
            return nil
        }
        var term : Term! = nil
        let ttl = "<> <> \(string) .\n"
        try parser.parse(string: ttl, syntax: .turtle) { (s,p,o) in
            term = o
        }
        return term
    }
}
