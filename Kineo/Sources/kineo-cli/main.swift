//
//  main.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 6/24/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation

private func generateIDQuadsAddingTerms<I : IdentityMap, R : protocol<Comparable, DefinedTestable, BufferSerializable>, S : Sequence where I.Result == R, I.Element == Term, S.Iterator.Element == Quad>(mediator : RWMediator, idGenerator: I, quads : S) throws -> AnyIterator<IDQuad<R>> {
    var termCount = 0
    var idquads = [IDQuad<R>]()
    var i2tpairs = [(R, Term)]()
    for quad in quads {
        var ids = [R]()
        for term in quad {
            if let id = idGenerator.id(for: term) {
                ids.append(id)
            } else {
                termCount += 1
                let id = try idGenerator.getOrSetID(for: term)
                ids.append(id)
                i2tpairs.append((id, term))
                termCount += 1
            }
            
        }
        idquads.append(IDQuad(ids[0], ids[1], ids[2], ids[3]))
    }
    return AnyIterator(idquads.makeIterator())
}

func setup(database : FilePageDatabase, filename : String, startTime : UInt64) throws {
    try database.update(version: startTime) { (m) in
        do {
            let i = try PersistentTermIdentityMap(mediator: m)
            _ = try generateIDQuadsAddingTerms(mediator: m, idGenerator: i, quads: [])
        } catch let e{
            print("*** \(e)")
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
//        if count % 256 == 0 {
//            print("\r\(count)", terminator: "")
//        }
        return Quad(subject: triple.subject, predicate: triple.predicate, object: triple.object, graph: graph)
    }
    print("\r\(quads.count) triples parsed")
    
    
    let version = startTime
    try database.update(version: version) { (m) in
        do {
            let i = try PersistentTermIdentityMap(mediator: m)
            print("Adding RDF terms to database...")
            let idquads = try generateIDQuadsAddingTerms(mediator: m, idGenerator: i, quads: quads)
            
            print("Adding RDF triples to database...")
            let empty = Empty()
            let spog = idquads.sorted().map { ($0, empty) }
            let tripleCount = spog.count
            print("creating table with \(tripleCount) quads")
            _ = try m.createTable(name: "quads", pairs: spog)
            
            try m.addQuadIndex("spog")
        } catch let e {
            print("*** \(e)")
        }
    }
    return count
}

func serialize(database : FilePageDatabase) throws -> Int {
    let rootname = "spog"
    var count = 0
    try database.read { (m) in
        do {
            let idmap = try PersistentTermIdentityMap(mediator: m)
            let mapping = try m.quadMapping(fromOrder: rootname)
            if let node : Tree<IDQuad<UInt64>,Empty> = m.tree(name: rootname) {
                var lastGraph : Term? = nil
                _ = try? node.walk { (pairs) in
                    for (indexOrder, _) in pairs {
                        let quad = mapping(quad: indexOrder)
                        if let s = idmap.term(for: quad[0]), p = idmap.term(for: quad[1]), o = idmap.term(for: quad[2]), g = idmap.term(for: quad[3]) {
                            count += 1
                            if g != lastGraph {
                                print("# GRAPH: \(g)")
                                lastGraph = g
                            }
                            print("\(s) \(p) \(o) .")
                        } else {
                            print("*** Failed to get terms for ids: \(quad)")
                        }
                    }
                }
            } else {
                print("No index named '\(rootname)' found")
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
    let rdf = args[2]
    try setup(database: database, filename: rdf, startTime: startTime)
    print("parsing \(rdf)")
    count = try parse(database: database, filename: rdf, startTime: startTime)
} else {
    print("dumping RDF")
    count = try serialize(database: database)
}

let endTime = getCurrentDateSeconds()
let elapsed = endTime - startTime
let tps = Double(count) / Double(elapsed)
print("elapsed time: \(elapsed)s (\(tps)/s)")
