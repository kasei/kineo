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


/**
 Evaluate the supplied Query against the database's QuadStore and return an HTTP response.
 If a graph argument is given, use it as the initial active graph.
 
 - parameter query: The query to evaluate.
 */
func evaluate<Q : QuadStoreProtocol, S : SPARQLSerializable>(_ query: Query, using store: Q, defaultGraph: Term, serializedWith serializer: S) throws -> HTTPResponse {
    let verbose = false
//    let store = try PageQuadStore(database: database)
    let e = SimpleQueryEvaluator(store: store, defaultGraph: defaultGraph, verbose: verbose)

    var resp = HTTPResponse(status: .ok)
    resp.headers.replaceOrAdd(name: "Content-Type", value: serializer.canonicalMediaType)

    if let mtime = try e.effectiveVersion(matching: query, activeGraph: defaultGraph) {
        let date = getDateString(seconds: mtime)
        resp.headers.add(name: "Last-Modified", value: "\(date)")
    }

    let results = try e.evaluate(query: query, activeGraph: defaultGraph)

    let data = try serializer.serialize(results)
    resp.body = HTTPBody(data: data)
    return resp
}

var pageSize = 8192

let filename = CommandLine.arguments.removeLast()
guard let database = FilePageDatabase(filename, size: pageSize) else { warn("Failed to open \(filename)"); exit(1) }

struct EndpointError : Error {
    var status: HTTPResponseStatus
    var message: String
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
        let serializer = SPARQLJSONSerializer<TermResult>()
        let store = try PageQuadStore(database: database)
        let defaultGraph = store.graphs().next() ?? Term(iri: "tag:kasei.us,2018:default-graph")
        return try evaluate(query, using: store, defaultGraph: defaultGraph, serializedWith: serializer)
    } catch let e {
        if let err = e as? EndpointError {
            return HTTPResponse(status: err.status, body: err.message)
        }
        let output = "*** Failed to evaluate query:\n*** - \(e)"
        return HTTPResponse(status: .internalServerError, body: output)
    }
}

try app.run()
