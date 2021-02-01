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
import Diomede
import DiomedeQuadStore

/// Parse the supplied RDF files and load the resulting RDF triples into the database's
/// QuadStore in the supplied named graph (or into a graph named with the corresponding
/// filename, if no graph name is given).
///
/// - parameter files: Filenames of Turtle or N-Triples files to parse.
/// - parameter startTime: The timestamp to use as the database transaction version number.
/// - parameter graph: The graph into which parsed triples should be load.
func parse(into store: MutableQuadStoreProtocol, files: [String], version: Version, graph defaultGraphTerm: Term? = nil, verbose: Bool = false) throws -> Int {
    var count = 0
    for filename in files {
        #if os (OSX)
        let filenameURL = NSURL(fileURLWithPath: filename)
        guard let path = filenameURL.absoluteURL?.absoluteString else { throw DatabaseError.DataError("Not a valid graph path: \(filename)") }
        #else
        let path = NSURL(fileURLWithPath: filename).absoluteURL.absoluteString
        #endif
        let graph   = defaultGraphTerm ?? Term(value: path, type: .iri)
        
        if path.hasSuffix(".nt") {
            let reader = FileReader(filename: filename)
            let parser = NTriplesParser(reader: reader)
            
            let i = parser.makeIterator()
            let quads = AnySequence(i.lazy.map { Quad(triple: $0, graph: graph) })
            try store.load(version: version, quads: quads)
        } else {
            let parser = RDFParserCombined()
            var quads = [Quad]()
            if verbose {
                warn("Parsing RDF...")
            }
            
            count = try parser.parse(file: filename, defaultGraph: graph, base: graph.value) { (s, p, o, g) in
                let q = Quad(subject: s, predicate: p, object: o, graph: g)
                quads.append(q)
            }
            
            if verbose {
                print("Loading RDF...")
            }
            try store.load(version: version, quads: quads)
        }
    }
    return count
}

/// Parse a SPARQL query from the supplied file, produce a query plan for it in the context
/// of the database's QuadStore, and print a serialized form of the resulting query plan.
///
/// - parameter query: The query to plan.
/// - parameter graph: The graph name to use as the initial active graph.
func explain<Q: QuadStoreProtocol>(in store: Q, query: Query, graph: Term? = nil, multiple: Bool, verbose: Bool) throws {
    let dataset = store.dataset(defaultGraph: graph)
    let planner     = queryPlanner(store: store, dataset: dataset)
    if multiple {
        planner.maxInFlightPlans = Int.max
        let plans        = try planner.plans(query: query)
        let ce = QueryPlanSimpleCostEstimator()
        for (i, plan) in plans.enumerated() {
            let cost = try ce.cost(for: plan)
            print("\(i) Query plan [\(cost)]")
            print(plan.serialize(depth: 0))
        }
    } else {
        let plan        = try planner.plan(query: query)
        let ce = QueryPlanSimpleCostEstimator()
        let cost = try ce.cost(for: plan)
        print("Query plan [\(cost)]")
        print(plan.serialize(depth: 0))
    }
}

@discardableResult
func time<T>(_ name: String, verbose: Bool = true, handler: () throws -> T) rethrows -> T {
    let startTime = getCurrentTime()
    defer {
        let endTime = getCurrentTime()
        let elapsed = endTime - startTime
        if verbose {
            warn("\(name): \(elapsed)s")
        }
    }
    return try handler()
}

func runQuery<Q: QuadStoreProtocol>(_ query: Query, in store: Q, graph: Term?, verbose: Bool) throws -> QueryResult<AnySequence<SPARQLResultSolution<Term>>, [Triple]> {
    let dataset = store.dataset(defaultGraph: graph)
    try time("computing last-modified", verbose: verbose) {
        let simpleEvaluator       = SimpleQueryEvaluator(store: store, dataset: dataset, verbose: verbose)
        if let mtime = try simpleEvaluator.effectiveVersion(matching: query) {
            let date = getDateString(seconds: mtime)
            if verbose {
                print("# Last-Modified: \(date)")
            }
        } else if verbose {
            print("# Last-Modified: (no version available)")
        }
    }
    
    //    let e       = SimpleQueryEvaluator(store: store, dataset: dataset, verbose: verbose)
    let planner     = queryPlanner(store: store, dataset: dataset)
    let e           = QueryPlanEvaluator(planner: planner)
    let results     = try e.evaluate(query: query)
    return results
}

func queryPlanner<Q : QuadStoreProtocol>(store: Q, dataset: DatasetProtocol) -> QueryPlanner<Q> {
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
    return try time("evaluating query plan", verbose: verbose) {
        let results = try runQuery(query, in: store, graph: graph, verbose: verbose)
        return printResult(results)
    }
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
    case let .bindings(order, iter):
        for result in iter {
            count += 1
            print("\(count)\t\(result.description(orderedBy: order))")
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
        print("\(graph.value)")
    }
    return count
}

func printDataset<Q: QuadStoreProtocol>(in store: Q, graph: Term? = nil) throws -> Int {
    let dataset = store.dataset(defaultGraph: graph)
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

func printSPARQL(_ qfile: String, pretty: Bool = false, silent: Bool = false, includeComments: Bool = false) throws {
    let url = URL(fileURLWithPath: qfile)
    let sparql = try Data(contentsOf: url)
    let stream = InputStream(data: sparql)
    stream.open()
    let lexer = try SPARQLLexer(source: stream, includeComments: includeComments)
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

func readLine(prompt: String) -> String? {
    print(prompt, terminator: "")
    return readLine()
}

private func humanReadable(count: Int) -> String {
    var names = ["", "k", "m", "b"]
    var unit = names.remove(at: 0)
    var size = count
    while !names.isEmpty && size >= 1000 {
        unit = names.remove(at: 0)
        size /= 1000
    }
    return "\(size)\(unit)"
}

func quadStore(_ config: QuadStoreConfiguration, verbose: Bool) throws -> AnyMutableQuadStore {
//    print("Using AnyQuadStore")
    let mqs = try config.anymutablestore()
    
    if verbose {
        if let d = mqs._store as? DiomedeQuadStore {
            d.progressHandler = { (status) in
                switch status {
                case let .loadProgress(count: i, rate: tps):
                    let s = String(format: "\(humanReadable(count: i)) triples (%.1f t/s)", tps)
                    print("\(s)")
                @unknown default:
                    break
                }
            }
        }
    }
    
    if case let .loadFiles(defaultFiles, namedFiles) = config.initialize {
        let graph = Term(iri: "tag:kasei.us,2018:default-graph")
        _ = try parse(into: mqs, files: defaultFiles, version: startSecond, graph: graph, verbose: verbose)
        try namedFiles.forEach { (graph, file) throws in
            _ = try parse(into: mqs, files: [file], version: startSecond, graph: graph, verbose: verbose)
        }
        return mqs
    } else {
        return mqs
    }
}

func usage(_ pname: String) {
    print("""
        Usage:
        
            \(pname) -q DATABASE.db [DATASET ARGUMENTS] COMMAND [ARGUMENTS]
        
                Evaluate commands using the named quadstore file.
        
            \(pname) [-m] [DATASET ARGUMENTS] COMMAND [ARGUMENTS]

                Evaluate commands using an in-memory (non-persistent) quadstore.

        Dataset Arguments:
        
            -d, --default-graph=FILENAME
        
                Parse RDF from the named file into the default graph. This
                option may be used repeatedly to parse multiple files into
                the default graph.
            
            -n, --named-graph=FILENAME

                Parse RDF from the named file into a graph named with the
                corresponding file: URL.

            -g IRI FILENAME

                Parse RDF from the named file into the graph named IRI.

            -D PATH

                Parse RDF files in subdirectories of the supplied path to construct
                a complete RDF dataset. Files in the $PATH/default directory will be
                merged into the default graph. Files in the $PATH/named directory
                will be loaded into a graph named with their corresponding file: URL.
        

        Commands:
        
            create
            load

                Load data into a new or existing quadstore as specified in the
                Dataset Arguments.

            graphs

                Print the names of all the named graphs in the quadstore
                (including the name of the default graph).

            dataset

                Print the dataset used to evaluate queries. This will indicate
                which named graph is used as the default graph during query
                planning.

            query [-G DEFAULT-GRAPH-IRI] QUERY

                Evaluate the given SPARQL query and print the results.
        
                If a DEFAULT-GRAPH-IRI is specified, the corresponding graph
                is used as the default graph during query evaluation. Otherwise,
                the first graph encountered in the database (typically the first
                one to have been loaded) will be used as the default graph.

            explain QUERY

                Print the serialized query plan for the given SPARQL query.

            dump

                Print an N-Quads serialization of the quadstore.


        If no command is given, an interactive prompt is provided which
        will repeatedly: accept SPARQL queries (on a single line),
        evaluate the query, and print the results.

        """)
}

DiomedeConfiguration.default.mapSize = 24_567_000_000

var verbose = false
let config = try QuadStoreConfiguration(arguments: &CommandLine.arguments)

let argscount = CommandLine.arguments.count
var args = PeekableIterator(generator: CommandLine.arguments.makeIterator())
guard let pname = args.next() else { fatalError("Missing command name") }
guard argscount >= 1 else {
    usage(pname)
    exit(1)
}

while true {
    if let next = args.peek(), next.hasPrefix("-") {
        if next == "-v" {
            _ = args.next()
            verbose = true
        } else if next == "--help" {
            usage(pname)
            exit(0)
        } else {
            print("Unrecognized option: \(next)")
            exit(1)
        }
    } else {
        break
    }
}

let startTime = getCurrentTime()
let startSecond = getCurrentDateSeconds()
var count = 0

do {
    let qs  = try quadStore(config, verbose: verbose)
    if let op = args.next() {
        if op == "load" || op == "create" {
        } else if op == "dataset" {
            var graph: Term? = nil
            if let next = args.peek(), next == "-G" {
                _ = args.next()
                guard let iri = args.next() else { fatalError("No IRI value given after -g") }
                graph = Term(value: iri, type: .iri)
            }
            count = try printDataset(in: qs, graph: graph)
        } else if op == "graphs" {
            count = try printGraphs(in: qs)
        } else if op == "explain" || op == "plans" {
            let multiple = op == "plans"
            var graph: Term? = nil
            if let next = args.peek(), next == "-G" {
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
                try explain(in: qs, query: q, graph: graph, multiple: multiple, verbose: verbose)
            } catch let e {
                warn("*** Failed to explain query: \(e)")
            }
        } else if op == "query" {
            var graph: Term? = nil
            if let next = args.peek(), next == "-G" {
                _ = args.next()
                guard let iri = args.next() else { fatalError("No IRI value given after -g") }
                graph = Term(value: iri, type: .iri)
            }
            guard let qfile = args.next() else { fatalError("No query file given") }
            do {
                let sparql = try data(fromFileOrString: qfile)
                guard var p = SPARQLParser(data: sparql) else { fatalError("Failed to construct SPARQL parser") }
                let q = try p.parseQuery()
//                for _ in 0..<10 {
                    count = try query(in: qs, query: q, graph: graph, verbose: verbose)
//                }
            } catch let e {
                warn("*** Failed to evaluate query:")
                warn("*** - \(e)")
            }
        } else if op == "dump" {
            QUAD: for q in try qs.quads(matching: QuadPattern.all) {
                var line = ""
                for t in q {
                    guard let d = t.ntriplesData(), let s = String(data: d, encoding: .utf8) else { continue QUAD }
                    line += s
                    line += " "
                }
                line += " ."
                print(line)
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
                count = try cliQuery(in: qs, query: q, graph: graph)
            } catch let e {
                warn("*** Failed to evaluate query:")
                warn("*** - \(e)")
            }
        }
    }
} catch let error {
    print("*** \(error)")
    exit(1)
}


let endTime = getCurrentTime()
let elapsed = Double(endTime - startTime)
let tps = Double(count) / elapsed
if verbose {
    //    Logger.shared.printSummary()
    warn("elapsed time: \(elapsed)s (\(tps)/s)")
}
