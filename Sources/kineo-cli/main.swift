//
//  main.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 6/24/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import Kineo

/**
 If necessary, create a new quadstore in the supplied database.
 */
func setup<D : Database>(_ database: D, startTime: UInt64) throws {
    try database.update(version: Version(startTime)) { (m) in
        do {
            _ = try QuadStore.create(mediator: m)
        } catch let e {
            warn("*** \(e)")
            throw DatabaseUpdateError.rollback
        }
    }
}

/**
 Parse the supplied RDF files and assign each unique RDF term an integer ID such that the
 ordering of IDs corresponds to the terms' ordering according to the sorting rules of SPARQL.
 
 - parameter files: Filenames of Turtle or N-Triples files to parse.
 - parameter graph: An optional graph name to be included in the list of terms.
 */
func sortParse(files: [String], graph defaultGraphTerm: Term? = nil) throws -> (Int, [Int:Term]) {
    var count   = 0
    var blanks = Set<Term>()
    var iris = Set<Term>()
    var literals = Set<Term>()
    for filename in files {
        #if os (OSX)
            guard let path = NSURL(fileURLWithPath: filename).absoluteString else { throw DatabaseError.DataError("Not a valid graph path: \(filename)") }
        #else
            let path = NSURL(fileURLWithPath: filename).absoluteString
        #endif
        let graph   = defaultGraphTerm ?? Term(value: path, type: .iri)

        iris.insert(graph)
        
        let parser = RDFParser()
        count = try parser.parse(file: filename, base: graph.value) { (s, p, o) in
            for term in [s, p, o] {
                switch term.type {
                case .iri:
                    iris.insert(term)
                case .blank:
                    blanks.insert(term)
                default:
                    literals.insert(term)
                }
            }
        }
        warn("\r\(count) triples parsed")
    }
    
    let blanksCount = blanks.count
    let irisAndBlanksCount = iris.count + blanksCount

    var mapping = [Int:Term]()
    for (i, term) in blanks.enumerated() { // blanks don't have inherent ordering amongst themselves
        mapping[i] = term
    }
    for (i, term) in iris.sorted().enumerated() {
        mapping[i + blanksCount] = term
    }
    for (i, term) in literals.sorted().enumerated() {
        mapping[i + irisAndBlanksCount] = term
    }
    return (count, mapping)
}

/**
 Parse the supplied RDF files and load the resulting RDF triples into the database's
 QuadStore in the supplied named graph (or into a graph named with the corresponding
 filename, if no graph name is given).
 
 - parameter files: Filenames of Turtle or N-Triples files to parse.
 - parameter startTime: The timestamp to use as the database transaction version number.
 - parameter graph: The graph into which parsed triples should be load.
 */
func parse<D : Database>(_ database: D, files: [String], startTime: UInt64, graph defaultGraphTerm: Term? = nil) throws -> Int {
    var count   = 0
    let version = Version(startTime)
    try database.update(version: version) { (m) in
        do {
            for filename in files {
                #if os (OSX)
                    guard let path = NSURL(fileURLWithPath: filename).absoluteString else { throw DatabaseError.DataError("Not a valid graph path: \(filename)") }
                #else
                    let path = NSURL(fileURLWithPath: filename).absoluteString
                #endif
                let graph   = defaultGraphTerm ?? Term(value: path, type: .iri)

                let parser = RDFParser()
                var quads = [Quad]()
                print("Parsing RDF...")
                count = try parser.parse(file: filename, base: graph.value) { (s, p, o) in
                    let q = Quad(subject: s, predicate: p, object: o, graph: graph)
                    quads.append(q)
                }

                print("Loading RDF...")
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

func parseQuery<D : Database>(_ database: D, filename: String) throws -> Query? {
    let reader      = FileReader(filename: filename)
    let qp          = QueryParser(reader: reader)
    return try qp.parse()
}

/**
 Parse a SPARQL query from the supplied file, produce a query plan for it in the context
 of the database's QuadStore, and print a serialized form of the resulting query plan.
 
 - parameter query: The query to plan.
 - parameter graph: The graph name to use as the initial active graph.
 */
func explain<D : Database>(_ database: D, query: Query, graph: Term? = nil, verbose: Bool) throws {
    print("- explaining query")
    try database.read { (m) in
        print("- mediator: \(m)")
        let store       = try LanguageQuadStore(mediator: m, acceptLanguages: [("en", 1.0), ("", 0.5)])
        print("- store: \(store)")
        var defaultGraph: Term
        if let g = graph {
            defaultGraph = g
        } else {
            // if there are no graphs in the database, it doesn't matter what the default graph is.
            defaultGraph = store.graphs().next() ?? Term(iri: "tag:kasei.us,2018:default-graph")
            warn("Using default graph \(defaultGraph)")
        }
        let planner     = QuadStorePlanner(store: store, defaultGraph: defaultGraph)
        let plan        = try planner.plan(query)
        print("Query plan:")
        print(plan.serialize())
    }
}

/**
 Evaluate the supplied Query against the database's QuadStore and print the results.
 If a graph argument is given, use it as the initial active graph.

 - parameter query: The query to evaluate.
 - parameter graph: The graph name to use as the initial active graph.
 - parameter verbose: A flag indicating whether verbose debugging should be emitted during query evaluation.
 */
func query<D : Database>(_ database: D, query: Query, graph: Term? = nil, verbose: Bool) throws -> Int {
    var count       = 0
    let startTime = getCurrentTime()
    try database.read { (m) in
        let store       = try LanguageQuadStore(mediator: m, acceptLanguages: [("en", 1.0), ("", 0.5)])
        //            let store       = try QuadStore(mediator: m)
        
        var defaultGraph: Term
        if let g = graph {
            defaultGraph = g
        } else {
            // if there are no graphs in the database, it doesn't matter what the default graph is.
            defaultGraph = store.graphs().next() ?? Term(iri: "tag:kasei.us,2018:default-graph")
            warn("Using default graph \(defaultGraph)")
        }
        let e           = SimpleQueryEvaluator(store: store, defaultGraph: defaultGraph, verbose: verbose)
        if let mtime = try e.effectiveVersion(matching: query, activeGraph: defaultGraph) {
            let date = getDateString(seconds: mtime)
            if verbose {
                print("# Last-Modified: \(date)")
            }
        }
        
        for result in try e.evaluate(query: query, activeGraph: defaultGraph) {
            count += 1
            print("\(count)\t\(result.description)")
        }
    }
    if verbose {
        let endTime = getCurrentTime()
        let elapsed = endTime - startTime
        warn("query time: \(elapsed)s")
    }
    return count
}

private func print(quad: Quad, lastGraph: Term?) {
    let s = quad.subject
    let p = quad.predicate
    let o = quad.object
    if quad.graph != lastGraph {
        print("# GRAPH: \(quad.graph)")
    }
    print("\(s) \(p) \(o) .")
}

/**
 Print all the quads present in the database's QuadStore. If an index name is supplied,
 use it to print quads in its native order.

 - parameter index: The name of an index to use to sort the resulting output.
 */
func serialize<D : Database>(_ database: D, index: String? = nil) throws -> Int {
    var count = 0
    database.read { (m) in
        do {
            let store = try QuadStore(mediator: m)
            var lastGraph: Term? = nil
            if let index = index {
                let i = try store.iterator(usingIndex: index)
                for quad in i {
                    print(quad: quad, lastGraph: lastGraph)
                    count += 1
                    lastGraph = quad.graph
                }
            } else {
                for quad in store {
                    print(quad: quad, lastGraph: lastGraph)
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

/**
 Print basic information about the database's QuadStore including the last-modified time,
 the number of quads, the available indexes, and the count of triples in each graph.
 */
func printSummary<D : Database>(of database: D) throws {
    database.read { (m) in
        guard let store = try? QuadStore(mediator: m) else { return }
        print("Quad Store")
        if let v = try? store.effectiveVersion(), let version = v {
            let versionDate = getDateString(seconds: version)
            print("Version: \(versionDate)")
        }
        print("Quads: \(store.count)")

        let indexes = store.availableQuadIndexes.joined(separator: ", ")
        print("Indexes: \(indexes)")
        
        for graph in store.graphs() {
            let pattern = QuadPattern(
                subject: .variable("s", binding: true),
                predicate: .variable("p", binding: true),
                object: .variable("o", binding: true),
                graph: .bound(graph)
            )
            let count = store.count(matching: pattern)
            print("Graph: \(graph) (\(count) triples)")
        }
        
        print("")
    }
    
}

/**
 Print the RDF terms encoded in the database's QuadStore.
 
 Note that some RDF terms used in the QuadStore's indexes may not show up in this list
 if they are directly encoded in the internal IDs. This will be true for many common
 numeric and date types (integer, decimal, date, dateTime) as well as terms with small
 values (short strings, blank nodes, etc.).
 */
func printTerms<D : Database>(from database: D) throws -> Int {
    var count = 0
    database.read { (m) in
        let t2iMapTreeName = PersistentTermIdentityMap.t2iMapTreeName
        guard let t2i: Tree<Term, UInt64> = m.tree(name: t2iMapTreeName) else { print("*** no term map"); return }
        for (term, id) in t2i {
            count += 1
            print("\(id) \(term)")
        }
    }
    return count
}

func printGraphs<D : Database>(from database: D) throws -> Int {
    var count = 0
    database.read { (m) in
        guard let store = try? QuadStore(mediator: m) else { return }
        for graph in store.graphs() {
            count += 1
            print("\(graph)")
        }
    }
    return count
}

func printIndexes<D : Database>(from database: D) throws -> Int {
    var count = 0
    database.read { (m) in
        guard let store = try? QuadStore(mediator: m) else { return }
        for idx in store.availableQuadIndexes {
            count += 1
            print("\(idx)")
        }
    }
    return count
}

func printPageInfo(mediator: FilePageRMediator, name: String, page: PageId) {
    if let (type, date, previous) = mediator._pageInfo(page: page) {
        var prev: String
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
var pageSize = 8192
guard argscount >= 2 else {
    print("Usage: \(pname) [-v] database.db COMMAND [ARGUMENTS]")
    print("       \(pname) database.db load [-g GRAPH-IRI] rdf.nt ...")
    print("       \(pname) database.db sort [-g GRAPH-IRI] rdf.nt")
    print("       \(pname) database.db parse query.rq")
    print("       \(pname) database.db sparql query.rq")
    print("       \(pname) database.db terms")
    print("       \(pname) database.db graphs")
    print("       \(pname) database.db indexes")
    print("       \(pname) database.db index INDEXNAME")
    print("       \(pname) database.db dump [INDEXNAME]")
    print("")
    print("       \(pname) database.db roots")
    print("       \(pname) database.db pages")
    print("       \(pname) database.db dot")
    print("       \(pname) database.db")
    print("")
    exit(1)
}

if let next = args.peek(), next == "-v" {
    _ = args.next()
    verbose = true
}

guard let filename = args.next() else { fatalError("Missing filename") }
guard let database = FilePageDatabase(filename, size: pageSize) else { warn("Failed to open \(filename)"); exit(1) }
let startTime = getCurrentTime()
let startSecond = getCurrentDateSeconds()
var count = 0

if let op = args.next() {
    try setup(database, startTime: startSecond)
    if op == "load" {
        do {
            var graph: Term? = nil
            if let next = args.peek(), next == "-g" {
                _ = args.next()
                guard let iri = args.next() else { fatalError("No IRI value given after -g") }
                graph = Term(value: iri, type: .iri)
            }
            
            count = try parse(database, files: args.elements(), startTime: startSecond, graph: graph)
        } catch let e {
            warn("*** Failed to load data: \(e)")
        }
    } else if op == "sort" {
        do {
            var graph: Term? = nil
            if let next = args.peek(), next == "-g" {
                _ = args.next()
                guard let iri = args.next() else { fatalError("No IRI value given after -g") }
                graph = Term(value: iri, type: .iri)
            }
            
            let (c, terms) = try sortParse(files: args.elements(), graph: graph)
            for i in terms.keys.sorted() {
                if let term = terms[i] {
                    print("\(i)\t\(term)")
                }
            }
            count = c
        } catch let e {
            warn("*** Failed to sort data: \(e)")
        }
    } else if op == "terms" {
        count = try printTerms(from: database)
    } else if op == "graphs" {
        count = try printGraphs(from: database)
    } else if op == "indexes" {
        count = try printIndexes(from: database)
    } else if op == "parse", let qfile = args.next() {
        do {
            let sparql = try data(fromFileOrString: qfile)
            guard var p = SPARQLParser(data: sparql) else { fatalError("Failed to construct SPARQL parser") }
            let query = try p.parseQuery()
            let s = query.serialize()
            count = 1
            print(s)
        } catch let e {
            warn("*** Failed to parse query: \(e)")
        }
    } else if op == "explain" {
        var graph: Term? = nil
        if let next = args.peek(), next == "-g" {
            _ = args.next()
            guard let iri = args.next() else { fatalError("No IRI value given after -g") }
            graph = Term(value: iri, type: .iri)
        }
        guard let qfile = args.next() else { fatalError("No query file given") }
        let sparql = try data(fromFileOrString: qfile)
        guard var p = SPARQLParser(data: sparql) else { fatalError("Failed to construct SPARQL parser") }
        do {
            let q = try p.parseQuery()
            print("Parsed query:")
            print(q.serialize())
            try explain(database, query: q, graph: graph, verbose: verbose)
        } catch let e {
            warn("*** Failed to explain query: \(e)")
        }
    } else if op == "sparql" {
        var graph: Term? = nil
        if let next = args.peek(), next == "-g" {
            _ = args.next()
            guard let iri = args.next() else { fatalError("No IRI value given after -g") }
            graph = Term(value: iri, type: .iri)
        }
        guard let qfile = args.next() else { fatalError("No query file given") }
        let sparql = try data(fromFileOrString: qfile)
        guard var p = SPARQLParser(data: sparql) else { fatalError("Failed to construct SPARQL parser") }
        do {
            let q = try p.parseQuery()
            print(q.serialize())
            count = try query(database, query: q, graph: graph, verbose: verbose)
        } catch let e {
            warn("*** Failed to evaluate query:")
            warn("*** - \(e)")
        }
    } else if op == "query" {
        var graph: Term? = nil
        if let next = args.peek(), next == "-g" {
            _ = args.next()
            guard let iri = args.next() else { fatalError("No IRI value given after -g") }
            graph = Term(value: iri, type: .iri)
        }
        guard let qfile = args.next() else { fatalError("No query file given") }
        guard let q = try parseQuery(database, filename: qfile) else { fatalError("Failed to parse query") }
        count = try query(database, query: q, graph: graph, verbose: verbose)
    } else if op == "dump" {
        let index = args.next() ?? QuadStore.defaultIndex
        count = try serialize(database, index: index)
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
        database.read { (m) in
            let roots = m.rootNames
            if roots.count > 0 {
                print("Roots:")
                for name in roots {
                    if let i = try? m.getRoot(named: name) {
                        printPageInfo(mediator: m, name: name, page: i)
                    }
                }
            }
        }
    } else if op == "pages" {
        print("Page size: \(database.pageSize)")
        database.read { (m) in
            var roots = [Int:String]()
            for name in m.rootNames {
                if let i = try? m.getRoot(named: name) {
                    roots[Int(i)] = name
                }
            }

            var pages = Array(args.elements().compactMap { Int($0) })
            if pages.count == 0 {
                pages = Array(0..<m.pageCount)
            }
            for pid in pages {
                let name = roots[pid] ?? "_"
                printPageInfo(mediator: m, name: name, page: pid)
            }
        }
    } else if op == "dot" {
        database.read { (m) in
            let indexName = args.next() ?? QuadStore.defaultIndex
            m.printTreeDOT(name: indexName)
        }
    } else {
        warn("Unrecognized operation: '\(op)'")
        exit(1)
    }
} else {
    try printSummary(of: database)
}

let endTime = getCurrentTime()
let elapsed = Double(endTime - startTime)
let tps = Double(count) / elapsed
if verbose {
    warn("elapsed time: \(elapsed)s (\(tps)/s)")
}
