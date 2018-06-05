//
//  main.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 6/24/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import SPARQLSyntax
import Kineo
import Vapor


struct EndpointError : Error {
    var status: HTTPResponseStatus
    var message: String
}


/**
 Evaluate the supplied Query against the database's QuadStore and return an HTTP response.
 If a graph argument is given, use it as the initial active graph.
 
 - parameter query: The query to evaluate.
 */
func evaluate<Q : QuadStoreProtocol>(_ query: Query, using store: Q, dataset: Dataset, serializedWith serializer: SPARQLSerializable) throws -> HTTPResponse {
    let verbose = false
//    let store = try PageQuadStore(database: database)

    let e = SimpleQueryEvaluator(store: store, dataset: dataset, verbose: verbose)

    var resp = HTTPResponse(status: .ok)
    resp.headers.replaceOrAdd(name: "Content-Type", value: serializer.canonicalMediaType)

    if let mtime = try e.effectiveVersion(matching: query) {
        let date = getDateString(seconds: mtime)
        resp.headers.add(name: "Last-Modified", value: "\(date)")
    }

    let results = try e.evaluate(query: query)

    let data = try serializer.serialize(results)
    resp.body = HTTPBody(data: data)
    return resp
}

func dataset<Q : QuadStoreProtocol>(from components: URLComponents, for store: Q) throws -> Dataset {
    let queryItems = components.queryItems ?? []
    let defaultGraphs = queryItems.filter { $0.name == "default-graph-uri" }.compactMap { $0.value }.map { Term(iri: $0) }
    let namedGraphs = queryItems.filter { $0.name == "named-graph-uri" }.compactMap { $0.value }.map { Term(iri: $0) }
    let dataset = Dataset(defaultGraphs: defaultGraphs, namedGraphs: namedGraphs)
    if dataset.isEmpty {
        let defaultGraph = store.graphs().next() ?? Term(iri: "tag:kasei.us,2018:default-graph")
        return Dataset(defaultGraphs: [defaultGraph])
    } else {
        return dataset
    }
}

var pageSize = 8192

guard CommandLine.arguments.count > 1 else { warn("No database filename given."); exit(1) }
var filename : String = ""
var language : Bool = false

while true {
    filename = CommandLine.arguments.removeLast()
    if filename == "-l" {
        language = true
        guard CommandLine.arguments.count > 1 else { warn("No database filename given."); exit(1) }
        continue
    }
    break
}

guard let database = FilePageDatabase(filename, size: pageSize) else { warn("Failed to open \(filename)"); exit(1) }

struct ProtocolRequest : Codable {
    var query: String
    var defaultGraphs: [String]?
    var namedGraphs: [String]?
    
    var dataset: Dataset? {
        let dg = defaultGraphs ?? []
        let ng = namedGraphs ?? []
        let ds = Dataset(defaultGraphs: dg.map { Term(iri: $0) }, namedGraphs: ng.map { Term(iri: $0) })
        return ds.isEmpty ? nil : ds
    }
}

func parseAcceptLanguages(_ value: String) -> [(String, Double)] {
    var accept = [(String, Double)]()
    let items = value.split(separator: ",")
    for i in items {
        let pair = i.split(separator: ";")
        if pair.count == 1 {
            accept.append((String(pair[0]), 1.0))
        } else if pair.count == 2 {
            if let d = Double(pair[1]) {
                accept.append((String(pair[0]), d))
            } else {
                accept.append((String(pair[0]), 1.0))
            }
        }
    }
    return accept
}

let app = try Application()
let router = try app.make(Router.self)
router.get("sparql") { (req) -> HTTPResponse in
    do {
        let u = req.http.url
        guard let components = URLComponents(string: u.absoluteString) else { throw EndpointError(status: .badRequest, message: "Failed to access URL components") }
        let queryItems = components.queryItems ?? []
        let queries = queryItems.filter { $0.name == "query" }.compactMap { $0.value }
        guard let sparql = queries.first else { throw EndpointError(status: .badRequest, message: "No query supplied") }
        guard let sparqlData = sparql.data(using: .utf8) else { throw EndpointError(status: .badRequest, message: "Failed to interpret SPARQL as utf-8") }
        guard var p = SPARQLParser(data: sparqlData) else { throw EndpointError(status: .internalServerError, message: "Failed to construct SPARQL parser") }
        let query = try p.parseQuery()
        let n = SPARQLContentNegotiator()
        let accept = req.http.headers["Accept"]
        let serializer = n.negotiateSerializer(for: accept)
        if language, let header = req.http.headers["Accept-Language"].first {
            let acceptLanguages = parseAcceptLanguages(header)
            let store = try LanguagePageQuadStore(database: database, acceptLanguages: acceptLanguages)
            let ds = try dataset(from: components, for: store)
            return try evaluate(query, using: store, dataset: ds, serializedWith: serializer)
        } else {
            let store = try PageQuadStore(database: database)
            let ds = try dataset(from: components, for: store)
            return try evaluate(query, using: store, dataset: ds, serializedWith: serializer)
        }
    } catch let e {
        if let err = e as? EndpointError {
            return HTTPResponse(status: err.status, body: err.message)
        }
        let output = "*** Failed to evaluate query:\n*** - \(e)"
        return HTTPResponse(status: .internalServerError, body: output)
    }
}

router.post("sparql") { (req) -> HTTPResponse in
    do {
        let u = req.http.url
        guard let components = URLComponents(string: u.absoluteString) else { throw EndpointError(status: .badRequest, message: "Failed to access URL components") }

        let ct = req.http.headers["Content-Type"].first
        let n = SPARQLContentNegotiator()
        let accept = req.http.headers["Accept"]
        let serializer = n.negotiateSerializer(for: accept)

        switch ct {
        case .none, .some("application/sparql-query"):
            guard let sparqlData = req.http.body.data else { throw EndpointError(status: .badRequest, message: "No query supplied") }
            guard var p = SPARQLParser(data: sparqlData) else { throw EndpointError(status: .internalServerError, message: "Failed to construct SPARQL parser") }
            let query = try p.parseQuery()
            if language, let header = req.http.headers["Accept-Language"].first {
                let acceptLanguages = parseAcceptLanguages(header)
                let store = try LanguagePageQuadStore(database: database, acceptLanguages: acceptLanguages)
                let ds = try dataset(from: components, for: store)
                return try evaluate(query, using: store, dataset: ds, serializedWith: serializer)
            } else {
                let store = try PageQuadStore(database: database)
                let ds = try dataset(from: components, for: store)
                return try evaluate(query, using: store, dataset: ds, serializedWith: serializer)
            }
        case .some("application/x-www-form-urlencoded"):
            guard let formData = req.http.body.data else { throw EndpointError(status: .badRequest, message: "No form data supplied") }
            let q = try URLEncodedFormDecoder().decode(ProtocolRequest.self, from: formData)
            guard let sparqlData = q.query.data(using: .utf8) else { throw EndpointError(status: .badRequest, message: "No query supplied") }
            guard var p = SPARQLParser(data: sparqlData) else { throw EndpointError(status: .internalServerError, message: "Failed to construct SPARQL parser") }
            let query = try p.parseQuery()
            if language, let header = req.http.headers["Accept-Language"].first {
                let acceptLanguages = parseAcceptLanguages(header)
                let store = try LanguagePageQuadStore(database: database, acceptLanguages: acceptLanguages)
                let ds = try q.dataset ?? dataset(from: components, for: store) // TOOD: access dataset IRIs from POST body
                return try evaluate(query, using: store, dataset: ds, serializedWith: serializer)
            } else {
                let store = try PageQuadStore(database: database)
                let ds = try q.dataset ?? dataset(from: components, for: store) // TOOD: access dataset IRIs from POST body
                return try evaluate(query, using: store, dataset: ds, serializedWith: serializer)
            }
        case .some(let c):
            throw EndpointError(status: .badRequest, message: "Unrecognized Content-Type: \(c)")
        }
        
    } catch let e {
        if let err = e as? EndpointError {
            return HTTPResponse(status: err.status, body: err.message)
        }
        let output = "*** Failed to evaluate query:\n*** - \(e)"
        return HTTPResponse(status: .internalServerError, body: output)
    }
}

try app.run()
