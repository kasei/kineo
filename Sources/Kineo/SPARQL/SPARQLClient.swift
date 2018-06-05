//
//  SPARQLClient.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 5/30/18.
//

import Foundation
import SPARQLSyntax

struct SPARQLClient {
    var endpoint: URL
    var timeout: Double
    var silent: Bool
    
    init(endpoint: URL, silent: Bool = false, timeout: Double = 5.0) {
        self.endpoint = endpoint
        self.timeout = timeout
        self.silent = silent
    }
    
    public func execute(_ query: String) throws -> QueryResult<[TermResult], [Triple]> {
        var args : (Data?, URLResponse?, Error?) = (nil, nil, nil)
        do {
            guard var components = URLComponents(string: endpoint.absoluteString) else {
                throw QueryError.evaluationError("Invalid URL components for SERVICE evaluation: \(endpoint)")
            }
            var queryItems = components.queryItems ?? []
            queryItems.append(URLQueryItem(name: "query", value: query))
            components.queryItems = queryItems
            
            guard let u = components.url else {
                throw QueryError.evaluationError("Invalid URL for SERVICE evaluation: \(components)")
            }
            
            let semaphore = DispatchSemaphore(value: 0)
            let session = URLSession.shared
            let task = session.dataTask(with: u) {
                args = ($0, $1, $2)
                semaphore.signal()
            }
            task.resume()
            
            _ = semaphore.wait(timeout: DispatchTime.now() + timeout)
            
            if let error = args.2 {
                throw QueryError.evaluationError("URL request failed: \(error)")
            }
            
            guard let data = args.0 else {
                throw QueryError.evaluationError("URL request did not return data")
            }
            
            guard let resp = args.1 else {
                throw QueryError.evaluationError("URL request did not return a response object")
            }
            
            do {
                let n = SPARQLContentNegotiator()
                let parser = n.negotiateParser(for: resp)
                return try parser.parse(data)
            } catch let e {
                throw QueryError.evaluationError("SPARQL Results XML parsing error: \(e)")
            }
        } catch let e {
            if silent {
                let results = [TermResult(bindings: [:])]
                return QueryResult.bindings([], results)
            } else {
                throw QueryError.evaluationError("SERVICE error: \(e)")
            }
        }
    }
}

struct SPARQLContentNegotiator {
    func negotiateParser(for response: URLResponse) -> SPARQLParsable {
        if let resp = response as? HTTPURLResponse {
            let type = resp.allHeaderFields["Content-Type"] as? String
            switch type {
            case "application/json", "application/sparql-results+json":
                return SPARQLJSONParser()
            case "application/sparql-results+xml":
                return SPARQLXMLParser()
            default:
                break
            }
        }
        
        return SPARQLXMLParser()
    }
}
