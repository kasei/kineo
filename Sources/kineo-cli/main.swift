//
//  main.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 6/24/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import Kineo

func setup(_ database : FilePageDatabase, startTime : UInt64) throws {
    try database.update(version: startTime) { (m) in
        do {
            _ = try QuadStore.create(mediator: m)
        } catch let e {
            warn("*** \(e)")
            throw DatabaseUpdateError.Rollback
        }
    }
}

func parse(_ database : FilePageDatabase, files : [String], startTime : UInt64, graph defaultGraphTerm: Term? = nil) throws -> Int {
    var count   = 0
    let version = startTime
    try database.update(version: version) { (m) in
        do {
            for filename in files {
                #if os (OSX)
                    guard let path = NSURL(fileURLWithPath: filename).absoluteString else { throw DatabaseError.DataError("Not a valid graph path: \(filename)") }
                #else
                    let path = NSURL(fileURLWithPath: filename).absoluteString
                #endif
                let graph   = defaultGraphTerm ?? Term(value: path, type: .iri)
                
                let reader  = FileReader(filename: filename)
                let parser  = NTriplesParser(reader: reader)
                let quads = AnySequence { () -> AnyIterator<Quad> in
                    let i = parser.makeIterator()
                    return AnyIterator {
                        guard let triple = i.next() else { return nil }
                        count += 1
                        return Quad(subject: triple.subject, predicate: triple.predicate, object: triple.object, graph: graph)
                    }
                    //    warn("\r\(quads.count) triples parsed")
                }
                
                let store = try QuadStore.create(mediator: m)
                try store.load(quads: quads)
            }
        } catch let e {
            warn("*** Failed during load of RDF (\(count) triples handled); \(e)")
            throw DatabaseUpdateError.Rollback
        }
    }
    return count
}

func parseQuery(_ database : FilePageDatabase, filename : String) throws -> Algebra? {
    let reader      = FileReader(filename: filename)
    let qp          = QueryParser(reader: reader)
    return qp.parse()
}

func query(_ database : FilePageDatabase, algebra query: Algebra) throws -> Int {
    var count       = 0
    try database.read { (m) in
        do {
            let store       = try QuadStore(mediator: m)
            guard let defaultGraph = store.graphs().next() else { return }
            warn("Using default graph \(defaultGraph)")
            let e           = SimpleQueryEvaluator(store: store, defaultGraph: defaultGraph)
            for result in try e.evaluate(algebra: query, activeGraph: defaultGraph) {
                count += 1
                print("\(count)\t\(result.description)")
            }
        } catch let e {
            warn("*** \(e)")
        }
    }
    return count
}

func serialize(_ database : FilePageDatabase) throws -> Int {
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

func graphs(_ database : FilePageDatabase) throws -> Int {
    var count = 0
    try database.read { (m) in
        guard let store = try? QuadStore(mediator: m) else { return }
        for graph in store.graphs() {
            count += 1
            print("\(graph)")
        }
    }
    return count
}

func indexes(_ database : FilePageDatabase) throws -> Int {
    var count = 0
    try database.read { (m) in
        guard let store = try? QuadStore(mediator: m) else { return }
        for idx in store.availableQuadIndexes {
            count += 1
            print("\(idx)")
        }
    }
    return count
}

func output(_ database : FilePageDatabase) throws -> Int {
    try database.read { (m) in
        guard let store = try? QuadStore(mediator: m) else { return }
        for (k,v) in store.id {
            print("\(k) -> \(v)")
        }
    }
    return try serialize(database)
}

func match(_ database : FilePageDatabase) throws -> Int {
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
let args = CommandLine.arguments
let pname = args[0]
var pageSize = 16384
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
    try setup(database, startTime: startTime)
    let op = args[2]
    if op == "load" {
        var graph : Term? = nil
        var parseArgs = Array(args.suffix(from: 3))
        if parseArgs.count > 0 {
            if parseArgs[0] == "-g" {
                guard parseArgs.count >= 2 else {
                    warn("No graph IRI present after '-g'")
                    exit(1)
                }
                graph = Term(value: parseArgs[1], type: .iri)
                parseArgs = Array(parseArgs.suffix(from: 2))
            }
            count = try parse(database, files: parseArgs, startTime: startTime, graph: graph)
        }
    } else if op == "graphs" {
        count = try graphs(database)
    } else if op == "indexes" {
        count = try indexes(database)
    } else if op == "query" {
        let qfile = args[3]
        guard let algebra = try parseQuery(database, filename: qfile) else { fatalError("Failed to parse query") }
        count = try query(database, algebra: algebra)
    } else if op == "qparse" {
        let qfile = args[3]
        guard let algebra = try parseQuery(database, filename: qfile) else { fatalError("Failed to parse query") }
        let s = algebra.serialize()
        count = 1
        print(s)
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
    } else if op == "test" {
        let lat : Node      = .bound(Term(value: "http://www.w3.org/2003/01/geo/wgs84_pos#lat", type: .iri))
        let long : Node     = .bound(Term(value: "http://www.w3.org/2003/01/geo/wgs84_pos#long", type: .iri))
        let vs : Node       = .variable("s", binding: true)
        let vlat : Node     = .variable("lat", binding: true)
        let vlong : Node    = .variable("long", binding: true)
        let tlat : TriplePattern = TriplePattern(
            subject: vs,
            predicate: lat,
            object: vlat
        )
        let tlong : TriplePattern = TriplePattern(
            subject: vs,
            predicate: long,
            object: vlong
        )
        let join : Algebra  = .innerJoin(.triple(tlat), .triple(tlong))
        let e1 : Expression = .gt(.node(vlat), .node(.bound(Term(integer: 31))))
        let e2 : Expression = .lt(.node(vlat), .node(.bound(Term(integer: 33))))
        let f1 : Algebra    = .filter(join, e1)
        let f2 : Algebra    = .filter(f1, e2)

        let e3 : Expression = .lt(.node(vlong), .node(.bound(Term(integer: -117))))
        let f3 : Algebra    = .filter(f2, e3)

        let e4 : Expression = .add(.node(vlat), .node(vlong))
        let bind : Algebra  = .extend(f3, e4, "sum")
        
        let result = TermResult(bindings: ["lat": Term(integer: 32), "long": Term(integer: -118)])
        print("-----")
        print(e4.description)
        print(result.description)

        let term1 = try? e4.evaluate(result: result)
        print("==> term eval result: \(term1?.description)")

        let term2 = try? e4.numericEvaluate(result: result)
        print("==> numeric eval result: \(term2?.description)")
        
        let algebra = bind
        print("Query algebra:\n\(algebra.serialize())")
        count = try query(database, algebra: algebra)
    } else {
        warn("Unrecognized operation: '\(op)'")
        exit(1)
    }
} else {
//    count = try output(database: database)
    count = try serialize(database)
}

let endTime = getCurrentDateSeconds()
let elapsed = endTime - startTime
let tps = Double(count) / Double(elapsed)
if verbose {
    warn("elapsed time: \(elapsed)s (\(tps)/s)")
}


