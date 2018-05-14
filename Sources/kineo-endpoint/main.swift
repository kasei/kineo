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
 Evaluate the supplied Query against the database's QuadStore and print the results.
 If a graph argument is given, use it as the initial active graph.
 
 - parameter query: The query to evaluate.
 - parameter graph: The graph name to use as the initial active graph.
 - parameter verbose: A flag indicating whether verbose debugging should be emitted during query evaluation.
 */
func query<D : PageDatabase>(_ query: Query, with database: D, graph: Term? = nil, verbose: Bool) throws -> HTTPResponse { // QueryResult<[TermResult], [Triple]> {
    let store = try PageQuadStore(database: database)
    var defaultGraph: Term
    if let g = graph {
        defaultGraph = g
    } else {
        // if there are no graphs in the database, it doesn't matter what the default graph is.
        defaultGraph = store.graphs().next() ?? Term(iri: "tag:kasei.us,2018:default-graph")
        // "Using default graph \(defaultGraph)"
    }
    
    var resp = HTTPResponse(status: .ok)
    let e           = SimpleQueryEvaluator(store: store, defaultGraph: defaultGraph, verbose: verbose)
    if let mtime = try e.effectiveVersion(matching: query, activeGraph: defaultGraph) {
        let date = getDateString(seconds: mtime)
        if verbose {
            resp.headers.add(name: "Last-Modified", value: "\(date)")
        }
    }
    let results = try e.evaluate(query: query, activeGraph: defaultGraph)
    let ser = SPARQLJSONSerializer<TermResult>()
    resp.headers.replaceOrAdd(name: "Content-Type", value: ser.canonicalMediaType)
    let data = try ser.serialize(results)
    let body = HTTPBody(data: data)
    resp.body = body
    return resp
}

var verbose = true
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
//        guard let sparql = "SELECT * WHERE { ?s <http://www.w3.org/2003/01/geo/wgs84_pos#long> ?o }".data(using: .utf8) else { fatalError("Failed to interpret SPARQL as utf-8") }
        guard var p = SPARQLParser(data: sparqlData) else { throw EndpointError(status: .internalServerError, message: "Failed to construct SPARQL parser") }
        let q = try p.parseQuery()
        return try query(q, with: database, graph: nil, verbose: verbose)
    } catch let e {
        if let err = e as? EndpointError {
            return HTTPResponse(status: err.status, body: err.message)
        }
        let output = "*** Failed to evaluate query:\n*** - \(e)"
        return HTTPResponse(status: .internalServerError, body: output)
    }
}

try app.run()
