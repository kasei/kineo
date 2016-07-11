//
//  main.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 6/24/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import Kineo

func setup(database : FilePageDatabase, startTime : UInt64) throws {
    try database.update(version: startTime) { (m) in
        do {
            _ = try QuadStore.create(mediator: m)
        } catch let e {
            warn("*** \(e)")
            throw DatabaseUpdateError.Rollback
        }
    }
}

func parse(database : FilePageDatabase, filename : String, startTime : UInt64) throws -> Int {
    let reader  = FileReader(filename: filename)
    let parser  = NTriplesParser(reader: reader)
#if os (OSX)
    guard let path = NSURL(fileURLWithPath: filename).absoluteString else { throw DatabaseError.DataError("Not a valid graph path: \(filename)") }
#else
    let path = NSURL(fileURLWithPath: filename).absoluteString
#endif
    let graph   = Term(value: path, type: .iri)
    
    var count   = 0
    let quads = parser.makeIterator().map { (triple) -> Quad in
        count += 1
        return Quad(subject: triple.subject, predicate: triple.predicate, object: triple.object, graph: graph)
    }
//    warn("\r\(quads.count) triples parsed")
    
    let version = startTime
    try database.update(version: version) { (m) in
        do {
            let store = try QuadStore.create(mediator: m)
            try store.load(quads: quads)
        } catch let e {
            warn("*** \(e)")
            throw DatabaseUpdateError.Rollback
        }
    }
    return count
}

func parseQuery(database : FilePageDatabase, filename : String) throws -> Algebra? {
    let reader      = FileReader(filename: filename)
    let qp          = QueryParser(reader: reader)
    return qp.parse()
}

func query(database : FilePageDatabase, algebra query: Algebra) throws -> Int {
    var count       = 0
    try database.read { (m) in
        do {
            let store       = try QuadStore(mediator: m)
            guard let defaultGraph = store.graphs().next() else { return }
            warn("Using default graph \(defaultGraph)")
            let e           = SimpleQueryEvaluator(store: store, defaultGraph: defaultGraph)
            for result in try e.evaluate(algebra: query, activeGraph: defaultGraph) {
                count += 1
                print("\(count)\t\(result)")
            }
        } catch let e {
            warn("*** \(e)")
        }
    }
    return count
}

func serialize(database : FilePageDatabase) throws -> Int {
    var count = 0
    try database.read { (m) in
        do {
            let store = try QuadStore(mediator: m)
            var lastGraph : Term? = nil
            for quad in store {
                let s = quad.subject
                let p = quad.predicate
                let o = quad.object
                count += 1
                if quad.graph != lastGraph {
                    print("# GRAPH: \(quad.graph)")
                    lastGraph = quad.graph
                }
                print("\(s) \(p) \(o) .")
            }
        } catch let e {
            warn("*** \(e)")
        }
    }
    return count
}

func output(database : FilePageDatabase) throws -> Int {
    try database.read { (m) in
        guard let store = try? QuadStore(mediator: m) else { return }
        for (k,v) in store.id {
            warn("\(k) -> \(v)")
        }
    }
    return try serialize(database: database)
}

func match(database : FilePageDatabase) throws -> Int {
    var count = 0
    let parser = NTriplesPatternParser(reader: "")
    try database.read { (m) in
        guard let store = try? QuadStore(mediator: m) else { return }
        guard let pattern = parser.parseQuadPattern(line: "?s <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> ?name ?graph") else { return }
        guard let quads = try? store.quads(matching: pattern) else { return }
        for quad in quads {
            count += 1
            print("- \(quad)")
        }
    }
    return count
}

let verbose = true
let args = Process.arguments
let pname = args[0]
var pageSize = 4096
guard args.count >= 2 else {
    print("Usage: \(pname) database.db load rdf.nt")
    print("       \(pname) database.db query query.q")
    print("       \(pname) database.db")
    print("")
    exit(1)
}
let filename = args[1]
guard let database = FilePageDatabase(filename, size: pageSize) else { warn("Failed to open \(filename)"); exit(1) }
let startTime = getCurrentDateSeconds()
var count = 0

if args.count > 2 {
    try setup(database: database, startTime: startTime)
    let op = args[2]
    if op == "load" {
        for rdf in args.suffix(from: 3) {
//            warn("parsing \(rdf)")
            count = try parse(database: database, filename: rdf, startTime: startTime)
        }
    } else if op == "query" {
        let qfile = args[3]
        guard let algebra = try parseQuery(database: database, filename: qfile) else { fatalError() }
        count = try query(database: database, algebra: algebra)
    } else if op == "qparse" {
        let qfile = args[3]
        guard let algebra = try parseQuery(database: database, filename: qfile) else { fatalError() }
        print(algebra.serialize())
    } else if op == "index" {
        let index = args[3]
        try database.update(version: startTime) { (m) in
            do {
                let store = try QuadStore.create(mediator: m)
                try store.addQuadIndex(index)
            } catch let e {
                warn("*** \(e)")
                throw DatabaseUpdateError.Rollback
            }
        }
    } else {
        warn("Unrecognized operation: '\(op)'")
        exit(1)
    }
} else {
//    count = try output(database: database)
    count = try serialize(database: database)
}

let endTime = getCurrentDateSeconds()
let elapsed = endTime - startTime
let tps = Double(count) / Double(elapsed)
if verbose {
    warn("elapsed time: \(elapsed)s (\(tps)/s)")
}


