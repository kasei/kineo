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
            print("*** \(e)")
            throw DatabaseUpdateError.Rollback
        }
    }
}

func parse(database : FilePageDatabase, filename : String, startTime : UInt64) throws -> Int {
    let graph = Term(value: filename, type: .iri)
    let reader = FileReader(filename: filename)
    let parser = NTriplesParser(reader: reader)
    
    var count = 0
    let quads = parser.makeIterator().map { (triple) -> Quad in
        count += 1
        return Quad(subject: triple.subject, predicate: triple.predicate, object: triple.object, graph: graph)
    }
    print("\r\(quads.count) triples parsed")
    
    let version = startTime
    try database.update(version: version) { (m) in
        do {
            let store = try QuadStore.create(mediator: m)
            try store.load(quads: quads)
        } catch let e {
            print("*** \(e)")
            throw DatabaseUpdateError.Rollback
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
            print("*** \(e)")
        }
    }
    return count
}

let args = Process.arguments
var pageSize = 4096
guard args.count >= 2 else { print("Usage: kineo database.db rdf.nt"); exit(1) }
let filename = args[1]
guard let database = FilePageDatabase(filename, size: pageSize) else { print("Failed to open \(filename)"); exit(1) }
let startTime = getCurrentDateSeconds()
var count = 0

if args.count > 2 {
    try setup(database: database, startTime: startTime)
    for rdf in args.suffix(from: 2) {
        print("parsing \(rdf)")
        count = try parse(database: database, filename: rdf, startTime: startTime)
    }
} else {
    count = try serialize(database: database)
}

let endTime = getCurrentDateSeconds()
let elapsed = endTime - startTime
let tps = Double(count) / Double(elapsed)
print("elapsed time: \(elapsed)s (\(tps)/s)")
