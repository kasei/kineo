//
//  SPARQLClient.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 5/30/18.
//

import Foundation
import SPARQLSyntax

public struct SPARQLClient {
    var endpoint: URL
    public var timeout: DispatchTimeInterval
    public var silent: Bool

    public init(endpoint: URL, silent: Bool = false, timeout: DispatchTimeInterval = .seconds(5)) {
        self.endpoint = endpoint
        self.timeout = timeout
        self.silent = silent
    }
    
    public func execute(_ query: String) throws -> QueryResult<[TermResult], [Triple]> {
        let n = SPARQLContentNegotiator.shared
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
            
            var urlRequest = URLRequest(url: u)
            urlRequest.addValue("application/json, application/sparql-results+json, application/sparql-results+xml, */*;q=0.1", forHTTPHeaderField: "Accept") // TODO: update this to use media types available in SPARQLContentNegotiator

            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.allowsCellularAccess = true
            var userAgent : String = ""
            let headers = sessionConfig.httpAdditionalHeaders ?? [:]
            let spkUserAgent = "Kineo/1.0"
            if let ua = headers["User-Agent"] as? String {
                userAgent = "\(spkUserAgent) \(ua)"
            } else {
                userAgent = spkUserAgent
            }
            sessionConfig.httpAdditionalHeaders?["User-Agent"] = userAgent
            sessionConfig.httpAdditionalHeaders?["Accept-Language"] = "*"
            sessionConfig.timeoutIntervalForRequest = 60.0
            sessionConfig.timeoutIntervalForResource = 60.0
            sessionConfig.httpMaximumConnectionsPerHost = 1
            sessionConfig.requestCachePolicy = .useProtocolCachePolicy
            let session = URLSession(configuration: sessionConfig)

//            let session = URLSession.shared
            let semaphore = DispatchSemaphore(value: 0)
            let task = session.dataTask(with: urlRequest) {
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
            
            let parser = n.negotiateParser(for: resp)
            do {
                return try parser.parse(data)
            } catch let e {
                throw QueryError.evaluationError("SPARQL Results parsing error [\(parser)]: \(e)")
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

public struct SPARQLContentNegotiator {
    public static var shared = SPARQLContentNegotiator()
    
    public var supportedSerializations : [ResultFormat]
    private var serializers: [SPARQLSerializable]
    
    public init() {
        // TODO: The `#if os(Linux)` conditions in this variable is temporarily
        //       required because XML serialization is broken on linux.
        #if os(Linux)
        supportedSerializations = [.sparqlJSON, .sparqlTSV, .ntriples, .turtle]
        #else
        supportedSerializations = [.sparqlXML, .sparqlJSON, .sparqlTSV, .ntriples, .turtle]
        #endif
        
        serializers = [
            SPARQLJSONSerializer<TermResult>(),
            SPARQLXMLSerializer<TermResult>(),
            SPARQLTSVSerializer<TermResult>(),
            TurtleSerializer(),
            NTriplesSerializer()
        ]
    }
    
    public mutating func addSerializer(_ s: SPARQLSerializable) {
        serializers.append(s)
    }
    
    public enum ResultFormat : String {
        case rdfxml = "http://www.w3.org/ns/formats/RDF_XML"
        case turtle = "http://www.w3.org/ns/formats/Turtle"
        case ntriples = "http://www.w3.org/ns/formats/N-Triples"
        case sparqlXML = "http://www.w3.org/ns/formats/SPARQL_Results_XML"
        case sparqlJSON = "http://www.w3.org/ns/formats/SPARQL_Results_JSON"
        case sparqlCSV = "http://www.w3.org/ns/formats/SPARQL_Results_CSV"
        case sparqlTSV = "http://www.w3.org/ns/formats/SPARQL_Results_TSV"
        
    }
    
    public func negotiateSerializer<S : Sequence, B, T>(for result: QueryResult<B, T>, accept: S) -> SPARQLSerializable? where S.Element == String {
        let json = SPARQLJSONSerializer<TermResult>()
        let valid : [SPARQLSerializable]
        switch result {
        case .boolean(_):
            valid = serializers.filter { $0.serializesBoolean }
        case .bindings(_):
            valid = serializers.filter { $0.serializesBindings }
        case .triples(_):
            valid = serializers.filter { $0.serializesTriples }
        }
        
        if valid.isEmpty {
            return nil
        }
        
        for a in accept {
            if a == "*/*" {
                return valid.first!
            }
            
            for s in valid {
                for mt in s.acceptableMediaTypes {
                    print(">>> \(mt)")
                    if a.hasPrefix(mt) {
                        return s
                    } else {
                        print("skipping \(mt) while looking for \(a)")
                    }
                }
            }
            
            if a.hasPrefix("text/plain") {
                return json
            }
        }
        return nil
    }
    
    public func negotiateParser(for response: URLResponse) -> SPARQLParsable {
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
