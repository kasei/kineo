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

@discardableResult
func load<Q: MutableQuadStoreProtocol>(store: Q, configuration config: QuadStoreConfiguration, verbose: Bool = false) throws -> Int {
    var count = 0
    let startSecond = getCurrentDateSeconds()
    if case let .loadFiles(defaultGraphs, namedGraphs) = config.initialize {
        let defaultGraph = Term(iri: "tag:kasei.us,2018:default-graph")
        print("Loading RDF files into default graph (\(defaultGraph)): \(defaultGraphs)")
        count += try parse(into: store, files: defaultGraphs, version: startSecond, graph: defaultGraph, verbose: verbose)
        
        for (graph, file) in namedGraphs {
            print("Loading RDF file into named graph \(graph): \(file)")
            count = try parse(into: store, files: [file], version: startSecond, graph: graph, verbose: verbose)
        }
    }
    return count
}

/// Parse the supplied RDF files and assign each unique RDF term an integer ID such that the
/// ordering of IDs corresponds to the terms' ordering according to the sorting rules of SPARQL.
///
/// - parameter files: Filenames of Turtle or N-Triples files to parse.
/// - parameter graph: An optional graph name to be included in the list of terms.
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

        let parser = RDFParserCombined()
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
        if verbose {
            warn("\r\(count) triples parsed")
        }
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

/// Parse the supplied RDF files and load the resulting RDF triples into the database's
/// QuadStore in the supplied named graph (or into a graph named with the corresponding
/// filename, if no graph name is given).
///
/// - parameter files: Filenames of Turtle or N-Triples files to parse.
/// - parameter startTime: The timestamp to use as the database transaction version number.
/// - parameter graph: The graph into which parsed triples should be load.
func parse<Q: MutableQuadStoreProtocol>(into store: Q, files: [String], version: Version, graph defaultGraphTerm: Term? = nil, verbose: Bool = false) throws -> Int {
    var count = 0
    for filename in files {
        #if os (OSX)
        guard let path = NSURL(fileURLWithPath: filename).absoluteString else { throw DatabaseError.DataError("Not a valid graph path: \(filename)") }
        #else
        let path = NSURL(fileURLWithPath: filename).absoluteString
        #endif
        let graph   = defaultGraphTerm ?? Term(value: path, type: .iri)
        
        let parser = RDFParserCombined()
        var quads = [Quad]()
        if verbose {
            warn("Parsing RDF...")
        }
        count = try parser.parse(file: filename, base: graph.value) { (s, p, o) in
            let q = Quad(subject: s, predicate: p, object: o, graph: graph)
            quads.append(q)
        }
        
        if verbose {
            print("Loading RDF...")
        }
        try store.load(version: version, quads: quads)
    }
    return count
}

/// Parse a SPARQL query from the supplied file, produce a query plan for it in the context
/// of the database's QuadStore, and print a serialized form of the resulting query plan.
///
/// - parameter query: The query to plan.
/// - parameter graph: The graph name to use as the initial active graph.
func explain<Q : QuadStoreProtocol>(in store: Q, query: Query, graph: Term? = nil, verbose: Bool) throws {
    let dataset = datasetForStore(store, graph: graph, verbose: verbose)
    let planner     = queryPlanner(store: store, dataset: dataset)
    let plan        = try planner.plan(query: query)
    let ce = QueryPlanSimpleCostEstimator()
    let cost = try ce.cost(for: plan)
    print("Query plan [\(cost)]")
    print(plan.serialize())
}

func datasetForStore(_ store: QuadStoreProtocol, graph: Term?, verbose: Bool = false) -> Dataset {
    var defaultGraph: Term
    if let g = graph {
        defaultGraph = g
    } else {
        // if there are no graphs in the database, it doesn't matter what the default graph is.
        defaultGraph = store.graphs().next() ?? Term(iri: "tag:kasei.us,2018:default-graph")
        if verbose {
            warn("Using default graph \(defaultGraph)")
        }
    }
    let dataset = store.dataset(withDefault: defaultGraph)
    return dataset
}

func runQuery<Q: QuadStoreProtocol>(_ query: Query, in store: Q, graph: Term?, verbose: Bool) throws -> QueryResult<AnySequence<TermResult>, [Triple]> {
    let dataset = datasetForStore(store, graph: graph, verbose: verbose)
    let simpleEvaluator       = SimpleQueryEvaluator(store: store, dataset: dataset, verbose: verbose)
    if let mtime = try simpleEvaluator.effectiveVersion(matching: query) {
        let date = getDateString(seconds: mtime)
        if verbose {
            print("# Last-Modified: \(date)")
        }
    } else if verbose {
        print("# Last-Modified: (no version available)")
    }
    
    //    let e       = SimpleQueryEvaluator(store: store, dataset: dataset, verbose: verbose)
    let planner     = queryPlanner(store: store, dataset: dataset)
    let e       = QueryPlanEvaluator(planner: planner)
    let results = try e.evaluate(query: query)
    return results
}

func queryPlanner<Q : QuadStoreProtocol>(store: Q, dataset: Dataset) -> QueryPlanner<Q> {
    let planner = QueryPlanner(store: store, dataset: dataset)
    // Add extension functions here:
//    planner.addFunction("http://example.org/func") { (terms) -> Term in
//        return Term(string: "test")
//    }
    return planner
}

/// Evaluate the supplied Query against the database's QuadStore and print the results.
/// If a graph argument is given, use it as the initial active graph.
///
/// - parameter query: The query to evaluate.
/// - parameter graph: The graph name to use as the initial active graph.
/// - parameter verbose: A flag indicating whether verbose debugging should be emitted during query evaluation.
func query<Q: QuadStoreProtocol>(in store: Q, query: Query, graph: Term? = nil, verbose: Bool) throws -> Int {
    let startTime = getCurrentTime()
    let results = try runQuery(query, in: store, graph: graph, verbose: verbose)
    let count = printResult(results)
    if verbose {
        let endTime = getCurrentTime()
        let elapsed = endTime - startTime
        warn("query time: \(elapsed)s")
    }
    return count
}

func cliQuery<Q: QuadStoreProtocol>(in store: Q, query: Query, graph: Term? = nil, verbose: Bool = false) throws -> Int {
    let startTime = getCurrentTime()
    let results = try runQuery(query, in: store, graph: graph, verbose: verbose)
    let count = cliPrintResult(results)
    if verbose {
        let endTime = getCurrentTime()
        let elapsed = endTime - startTime
        warn("query time: \(elapsed)s")
    }
    return count
}

//func query<D : PageDatabase>(_ database: D, query q: Query, graph: Term? = nil, verbose: Bool) throws -> Int {
//    let store = try PageQuadStore(database: database)
//    return try query(in: store, query: q, graph: graph, verbose: verbose)
//}

private func cliPrintResult<R, T>(_ results: QueryResult<R, T>) -> Int {
    var count       = 0
    switch results {
    case let .bindings(columns, iter):
        let c = columns.joined(separator: "\t")
        print("\t\(c)")
        for result in iter {
            count += 1
            let values = columns.map { result[$0]?.description ?? "" }
            print("\(count)\t\(values.joined(separator: "\t"))")
        }
    case .boolean(let v):
        print("\(v)")
    case .triples(let iter):
        for triple in iter {
            count += 1
            print("\(count)\t\(triple.description)")
        }
    }
    return count
}

private func printResult<R, T>(_ results: QueryResult<R, T>) -> Int {
    var count       = 0
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

func printGraphs(in store: QuadStoreProtocol) throws -> Int {
    var count = 0
    for graph in store.graphs() {
        count += 1
        print("\(graph)")
    }
    return count
}

func printDataset(in store: QuadStoreProtocol, graph: Term? = nil) throws -> Int {
    let dataset = datasetForStore(store, graph: graph)
    print("Dataset:")
    if !dataset.defaultGraphs.isEmpty {
        print("\tDefault graphs:")
        for g in dataset.defaultGraphs {
            print("\t\t\(g)")
        }
    }
    if !dataset.namedGraphs.isEmpty {
        print("\tNamed graphs:")
        for g in dataset.namedGraphs {
            print("\t\t\(g)")
        }
    }
    return 0
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

func printSPARQL(_ qfile: String, pretty: Bool = false, silent: Bool = false, includeComments: Bool = false) throws {
    let url = URL(fileURLWithPath: qfile)
    let sparql = try Data(contentsOf: url)
    let stream = InputStream(data: sparql)
    stream.open()
    let lexer = SPARQLLexer(source: stream, includeComments: includeComments)
    let s = SPARQLSerializer(prettyPrint: true)
    let tokens: UnfoldSequence<SPARQLToken, Int> = sequence(state: 0) { (_) in return lexer.next() }
    if pretty {
        print(s.serialize(tokens))
    } else {
        print(s.serialize(tokens))
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

func usage(_ pname: String) {
    print("Usage: \(pname) [-v] database.db COMMAND [ARGUMENTS]")
    print("       \(pname) database.db load [-g GRAPH-IRI] rdf.nt ...")
    print("       \(pname) database.db query query.rq")
    print("       \(pname) database.db graphs")
    print("")
}

var verbose = false
let config = try QuadStoreConfiguration(arguments: &CommandLine.arguments)

let argscount = CommandLine.arguments.count
var args = PeekableIterator(generator: CommandLine.arguments.makeIterator())
guard let pname = args.next() else { fatalError("Missing command name") }
guard argscount >= 1 else {
    usage(pname)
    exit(1)
}

if let next = args.peek(), next == "-v" {
    _ = args.next()
    verbose = true
}

let startTime = getCurrentTime()
let startSecond = getCurrentDateSeconds()
var count = 0

func readLine(prompt: String) -> String? {
    print(prompt, terminator: "")
    return readLine()
}

func quadStore(_ config: QuadStoreConfiguration) throws -> QuadStoreProtocol {
    let qs = try config.store()
    if case let .loadFiles(defaultFiles, namedFiles) = config.initialize {
        if let mqs = qs as? SQLiteQuadStore {
            _ = try parse(into: mqs, files: defaultFiles, version: startSecond, graph: nil, verbose: verbose)
            try namedFiles.forEach { (graph, file) throws in
                _ = try parse(into: mqs, files: [file], version: startSecond, graph: graph, verbose: verbose)
            }
        } else if let mqs = qs as? SQLiteLanguageQuadStore {
            _ = try parse(into: mqs, files: defaultFiles, version: startSecond, graph: nil, verbose: verbose)
            try namedFiles.forEach { (graph, file) throws in
                _ = try parse(into: mqs, files: [file], version: startSecond, graph: graph, verbose: verbose)
            }
        } else if let mqs = qs as? MemoryQuadStore {
            _ = try parse(into: mqs, files: defaultFiles, version: startSecond, graph: nil, verbose: verbose)
            try namedFiles.forEach { (graph, file) throws in
                _ = try parse(into: mqs, files: [file], version: startSecond, graph: graph, verbose: verbose)
            }
        } else if let mqs = qs as? LanguageMemoryQuadStore {
            _ = try parse(into: mqs, files: defaultFiles, version: startSecond, graph: nil, verbose: verbose)
            try namedFiles.forEach { (graph, file) throws in
                _ = try parse(into: mqs, files: [file], version: startSecond, graph: graph, verbose: verbose)
            }
        }
    }
    return qs
}

do {
    let qs  = try quadStore(config)
    if let op = args.next() {
        if op == "load" {
        } else if op == "dataset" {
            var graph: Term? = nil
            if let next = args.peek(), next == "-g" {
                _ = args.next()
                guard let iri = args.next() else { fatalError("No IRI value given after -g") }
                graph = Term(value: iri, type: .iri)
            }
            count = try printDataset(in: qs, graph: graph)
        } else if op == "graphs" {
            count = try printGraphs(in: qs)
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
                switch (config.type, config.languageAware) {
                case (.memoryDatabase, false):
                    let s = qs as! MemoryQuadStore
                    try explain(in: s, query: q, graph: graph, verbose: verbose)
                case (.memoryDatabase, true):
                    let s = qs as! LanguageMemoryQuadStore
                    try explain(in: s, query: q, graph: graph, verbose: verbose)
                case (.sqliteFileDatabase(_), false), (.sqliteMemoryDatabase, false):
                    let s = qs as! SQLiteQuadStore
                    try explain(in: s, query: q, graph: graph, verbose: verbose)
                case (.sqliteFileDatabase(_), true), (.sqliteMemoryDatabase, true):
                    let s = qs as! SQLiteLanguageQuadStore
                    try explain(in: s, query: q, graph: graph, verbose: verbose)
                default:
                    fatalError("Unusable configuration type: \(config)")
                }
            } catch let e {
                warn("*** Failed to explain query: \(e)")
            }
        } else if op == "query" {
            var graph: Term? = nil
            if let next = args.peek(), next == "-g" {
                _ = args.next()
                guard let iri = args.next() else { fatalError("No IRI value given after -g") }
                graph = Term(value: iri, type: .iri)
            }
            guard let qfile = args.next() else { fatalError("No query file given") }
            do {
                let sparql = try data(fromFileOrString: qfile)
                guard var p = SPARQLParser(data: sparql) else { fatalError("Failed to construct SPARQL parser") }
                let q = try p.parseQuery()
                switch (config.type, config.languageAware) {
                case (.memoryDatabase, false):
                    let s = qs as! MemoryQuadStore
                    count = try query(in: s, query: q, graph: graph, verbose: verbose)
                case (.memoryDatabase, true):
                    let s = qs as! LanguageMemoryQuadStore
                    count = try query(in: s, query: q, graph: graph, verbose: verbose)
                case (.sqliteFileDatabase(_), false), (.sqliteMemoryDatabase, false):
                    let s = qs as! SQLiteQuadStore
                    count = try query(in: s, query: q, graph: graph, verbose: verbose)
                case (.sqliteFileDatabase(_), true), (.sqliteMemoryDatabase, true):
                    let s = qs as! SQLiteLanguageQuadStore
                    count = try query(in: s, query: q, graph: graph, verbose: verbose)
                default:
                    fatalError("Unusable configuration type: \(config)")
                }
            } catch let e {
                warn("*** Failed to evaluate query:")
                warn("*** - \(e)")
            }
        } else if op == "dump" {
            for q in try qs.quads(matching: QuadPattern.all) {
                print("\(q)")
            }
        } else {
            warn("Unrecognized operation: '\(op)'")
            exit(1)
        }
    } else {
        LOOP: while let input = readLine(prompt: "> ") {
            switch input.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) {
            case "exit":
                break LOOP
            case "":
                continue LOOP
            default:
                break
            }
            let sparql = Data(input.utf8)
            do {
                let graph: Term? = nil
                guard var p = SPARQLParser(data: sparql) else { fatalError("Failed to construct SPARQL parser") }
                let q = try p.parseQuery()
                switch (config.type, config.languageAware) {
                case (.memoryDatabase, false):
                    let s = qs as! MemoryQuadStore
                    count = try cliQuery(in: s, query: q, graph: graph)
                case (.memoryDatabase, true):
                    let s = qs as! LanguageMemoryQuadStore
                    count = try cliQuery(in: s, query: q, graph: graph)
                case (.sqliteFileDatabase(_), false), (.sqliteMemoryDatabase, false):
                    let s = qs as! SQLiteQuadStore
                    count = try cliQuery(in: s, query: q, graph: graph)
                case (.sqliteFileDatabase(_), true), (.sqliteMemoryDatabase, true):
                    let s = qs as! SQLiteLanguageQuadStore
                    count = try cliQuery(in: s, query: q, graph: graph)
                default:
                    fatalError("Unusable configuration type: \(config)")
                }
            } catch let e {
                warn("*** Failed to evaluate query:")
                warn("*** - \(e)")
            }
        }
    }
} catch let error {
    print("*** \(error)")
}


let endTime = getCurrentTime()
let elapsed = Double(endTime - startTime)
let tps = Double(count) / elapsed
if verbose {
    //    Logger.shared.printSummary()
    warn("elapsed time: \(elapsed)s (\(tps)/s)")
}
