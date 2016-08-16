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
            throw DatabaseUpdateError.rollback
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
            throw DatabaseUpdateError.rollback
        }
    }
    return count
}

func parseQuery(_ database : FilePageDatabase, filename : String) throws -> Algebra? {
    let reader      = FileReader(filename: filename)
    let qp          = QueryParser(reader: reader)
    return try qp.parse()
}

func query(_ database : FilePageDatabase, algebra query: Algebra, graph: Term? = nil) throws -> Int {
    var count       = 0
    try database.read { (m) in
        do {
            let store       = try LanguageQuadStore(mediator: m, acceptLanguages: [("en", 1.0), ("", 0.5)])
//            let store       = try QuadStore(mediator: m)
            
            var defaultGraph : Term
            if let g = graph {
                defaultGraph = g
            } else {
                guard let g = store.graphs().next() else { return }
                defaultGraph = g
            }
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

private func printQuad(quad : Quad, lastGraph : Term?) {
    let s = quad.subject
    let p = quad.predicate
    let o = quad.object
    if quad.graph != lastGraph {
        print("# GRAPH: \(quad.graph)")
    }
    print("\(s) \(p) \(o) .")
}

func serialize(_ database : FilePageDatabase, index : String? = nil) throws -> Int {
    var count = 0
    try database.read { (m) in
        do {
            let store = try QuadStore(mediator: m)
            var lastGraph : Term? = nil
            if let index = index {
                let i = try store.iterator(usingIndex: index)
                for quad in i {
                    printQuad(quad: quad, lastGraph: lastGraph)
                    count += 1
                    lastGraph = quad.graph
                }
            } else {
                for quad in store {
                    printQuad(quad: quad, lastGraph: lastGraph)
                    count += 1
                    lastGraph = quad.graph
                }
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

func printPageInfo(mediator m : FilePageRMediator, name : String, page : PageId) {
    if let (type, date, previous) = m._pageInfo(page: page) {
        var prev : String
        switch previous {
        case .none, .some(0):
            prev = ""
        case .some(let value):
            prev = "Previous page: \(value)"
        }
        
        let name_padded = name.padding(toLength: 16, withPad: " ", startingAt: 0)
        let type_padded = type.padding(toLength: 24, withPad: " ", startingAt: 0)
        print("  \(page)\t\(date)\t\(name_padded)\t\(type_padded)\t\t\(prev)")
    }
}

let verbose = true
let _args = CommandLine.arguments
let argscount = _args.count
var args = PeekableIterator(generator: _args.makeIterator())
guard let pname = args.next() else { fatalError() }
var pageSize = 8192
guard argscount >= 2 else {
    print("Usage: \(pname) database.db load rdf.nt")
    print("       \(pname) database.db query query.q")
    print("       \(pname) database.db")
    print("")
    exit(1)
}

if let next = args.peek(), next == "-v" {
    _ = args.next()
    verbose = true
}

guard let filename = args.next() else { fatalError() }
guard let database = FilePageDatabase(filename, size: pageSize) else { warn("Failed to open \(filename)"); exit(1) }
let startTime = getCurrentTime()
let startSecond = getCurrentDateSeconds()
var count = 0

if let op = args.next() {
    try setup(database, startTime: startSecond)
    if op == "load" {
        var graph : Term? = nil
        if let next = args.peek(), next == "-g" {
            _ = args.next()
            guard let iri = args.next() else { fatalError("No IRI value given after -g") }
            graph = Term(value: iri, type: .iri)
        }
        
        count = try parse(database, files: args.elements(), startTime: startSecond, graph: graph)
    } else if op == "graphs" {
        count = try graphs(database)
    } else if op == "indexes" {
        count = try indexes(database)
    } else if op == "query" {
        var graph : Term? = nil
        if let next = args.peek(), next == "-g" {
            _ = args.next()
            guard let iri = args.next() else { fatalError("No IRI value given after -g") }
            graph = Term(value: iri, type: .iri)
        }
        guard let qfile = args.next() else { fatalError("No query file given") }
        guard let algebra = try parseQuery(database, filename: qfile) else { fatalError("Failed to parse query") }
        count = try query(database, algebra: algebra, graph: graph)
    } else if op == "qparse", let qfile = args.next() {
        guard let algebra = try parseQuery(database, filename: qfile) else { fatalError("Failed to parse query") }
        let s = algebra.serialize()
        count = 1
        print(s)
    } else if op == "index", let index = args.next() {
        try database.update(version: startSecond) { (m) in
            do {
                let store = try QuadStore.create(mediator: m)
                try store.addQuadIndex(index)
            } catch let e {
                warn("*** \(e)")
                throw DatabaseUpdateError.rollback
            }
        }
    } else if op == "roots" {
        try database.read { (m) in
            let roots = m.rootNames
            if roots.count > 0 {
                print("Roots:")
                for name in roots {
                    if let i = try? m.getRoot(named: name) {
                        printPageInfo(mediator: m, name : name, page : i)
                    }
                }
            }
        }
    } else if op == "pages" {
        print("Page size: \(database.pageSize)")
        try database.read { (m) in
            var roots = [Int:String]()
            for name in m.rootNames {
                if let i = try? m.getRoot(named: name) {
                    roots[Int(i)] = name
                }
            }
            
            var pages = Array(args.elements().flatMap { Int($0) })
            if pages.count == 0 {
                pages = Array(0..<m.pageCount)
            }
            for pid in pages {
                let name = roots[pid] ?? "_"
                printPageInfo(mediator: m, name : name, page : pid)
            }
        }
    } else if op == "testcreate" {
        if verbose {
            warn("\(getDateString(seconds: startSecond))")
            warn("Creating test tree...")
        }
        let name = "testvalues"
        try database.update(version: startSecond) { (m) in
            let pairs : [(UInt32, String)] = []
            _ = try m.create(tree: name, pairs: pairs)
        }
    } else if op == "testread" {
        let name = "testvalues"
        try database.read { (m) in
            guard let t : Tree<UInt32, String> = m.tree(name: name) else { fatalError("No such tree") }
            print("Tree: \(t)")
            for (k, v) in t {
                print("- \(k) -> \(v)")
            }
        }
    } else if op == "testadd" {
        let name = "testvalues"
        guard let key = UInt32(args.next() ?? "") else { fatalError("Cannot interpret key as an integer") }
        guard let value = args.next() else { fatalError("No value found") }
        if verbose {
            warn("\(getDateString(seconds: startSecond))")
            warn("Adding pair: \(key) => \(value)...")
        }
        try database.update(version: startSecond) { (m) in
            guard let t : Tree<UInt32, String> = m.tree(name: name) else { fatalError("No such tree") }
            try t.add(pair: (key, value))
        }
    } else if op == "testremove" {
        let name = "testvalues"
        guard let key = UInt32(args.next() ?? "") else { fatalError("Cannot interpret key as an integer") }
        if verbose {
            warn("\(getDateString(seconds: startSecond))")
            warn("Removing pair for key \(key)...")
        }
        try database.update(version: startSecond) { (m) in
            guard let t : Tree<UInt32, String> = m.tree(name: name) else { fatalError("No such tree") }
            try t.remove(key: key)
        }
    } else if op == "dump" {
        guard let index = args.next() else { fatalError("No index name given") }
        count = try serialize(database, index: index)
    } else {
        warn("Unrecognized operation: '\(op)'")
        exit(1)
    }
} else {
    count = try serialize(database)
}

let endTime = getCurrentTime()
let elapsed = Double(endTime - startTime)
let tps = Double(count) / elapsed
if verbose {
    warn("elapsed time: \(elapsed)s (\(tps)/s)")
}


