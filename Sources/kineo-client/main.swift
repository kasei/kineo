//
//  main.swift
//  kineo-client
//
//  Created by Gregory Todd Williams on 6/24/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import SPARQLSyntax
import Kineo

/**
 Evaluate the supplied Query against the database's QuadStore and print the results.
 If a graph argument is given, use it as the initial active graph.

 - parameter query: The query to evaluate.
 - parameter graph: The graph name to use as the initial active graph.
 - parameter verbose: A flag indicating whether verbose debugging should be emitted during query evaluation.
 */
func query<Q : QuadStoreProtocol>(_ store: Q, query: Query, graph: Term? = nil, verbose: Bool) throws -> Int {
    var count       = 0
    let startTime = getCurrentTime()
    var defaultGraph: Term
    if let g = graph {
        defaultGraph = g
    } else {
        // if there are no graphs in the database, it doesn't matter what the default graph is.
        defaultGraph = store.graphs().next() ?? Term(iri: "tag:kasei.us,2018:default-graph")
        warn("Using default graph \(defaultGraph)")
    }
    let dataset = store.dataset(withDefault: defaultGraph)
    let e           = SimpleQueryEvaluator(store: store, dataset: dataset, verbose: verbose)
    if let mtime = try e.effectiveVersion(matching: query) {
        let date = getDateString(seconds: mtime)
        if verbose {
            print("# Last-Modified: \(date)")
        }
    }
    let results = try e.evaluate(query: query)
    switch results {
    case .bindings(_, let iter):
        for result in iter {
            count += 1
            print("\(count)\t\(result.description)")
        }
    case .boolean(let v):
        print("\(v)")
    case .triples(let iter):
        for triple in iter {
            count += 1
            print("\(count)\t\(triple.description)")
        }
    }

    if verbose {
        let endTime = getCurrentTime()
        let elapsed = endTime - startTime
        warn("query time: \(elapsed)s")
    }
    return count
}

func data(fromFileOrString qfile: String) throws -> Data {
    let url = URL(fileURLWithPath: qfile)
    let data: Data
    if case .some(true) = try? url.checkResourceIsReachable() {
        data = try Data(contentsOf: url)
    } else {
        guard let s = qfile.data(using: .utf8) else {
            fatalError("Could not interpret SPARQL query string as UTF-8")
        }
        data = s
    }
    return data
}

var verbose = true
let argscount = CommandLine.arguments.count
var args = PeekableIterator(generator: CommandLine.arguments.makeIterator())
guard let pname = args.next() else { fatalError("Missing command name") }
guard argscount >= 1 else {
    print("Usage: \(pname) [-v] ENDPOINT QUERY")
    print("")
    exit(1)
}

if let next = args.peek(), next == "-v" {
    _ = args.next()
    verbose = true
}

guard let endpoint = args.next(), let url = URL(string: endpoint) else { fatalError("Missing endpoint") }
guard let qfile = args.next() else { fatalError("No query file given") }
let graph = Term(iri: "http://example.org/")


let startTime = getCurrentTime()
let startSecond = getCurrentDateSeconds()
var count = 0


let store = SPARQLClientQuadStore(endpoint: url, defaultGraph: graph)
do {
    let sparql = try data(fromFileOrString: qfile)
    guard var p = SPARQLParser(data: sparql) else { fatalError("Failed to construct SPARQL parser") }
    let q = try p.parseQuery()
    count = try query(store, query: q, graph: graph, verbose: verbose)
} catch let e {
    warn("*** Failed to evaluate query:")
    warn("*** - \(e)")
}

let endTime = getCurrentTime()
let elapsed = Double(endTime - startTime)
let tps = Double(count) / elapsed
if verbose {
//    Logger.shared.printSummary()
    warn("elapsed time: \(elapsed)s (\(tps)/s)")
}
