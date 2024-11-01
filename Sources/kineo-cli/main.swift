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
import ArgumentParser

@main
struct KineoCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
            // Optional abstracts and discussions are used for help output.
            abstract: "SPARQL/RDF Query and Update Tool",

            // Commands can define a version for automatic '--version' support.
            version: "0.0.107",

            // Pass an array to `subcommands` to set up a nested tree of subcommands.
            // With language support for type-level introspection, this could be
            // provided by automatically finding nested `ParsableCommand` types.
            subcommands: [REPL.self, Query.self, Explain.self, Dataset.self, Graphs.self, Create.self, Load.self, Dump.self],

            // A default subcommand, when provided, is automatically selected if a
            // subcommand is not given on the command line.
            defaultSubcommand: REPL.self)
}

struct Options: ParsableArguments {
    @Flag(name: [.customLong("verbose"), .customShort("v")],
          help: "Use verbose output.")
    var verbose = false
    
    @Option(name: [.customShort("d"), .customLong("default-graph")]) var defaultGraphFiles: [String] = []
    @Option(name: [.customShort("n"), .customLong("named-graph")]) var namedGraphFiles: [String] = []
    @Option(name: [.customShort("D"), .customLong("data-path")]) var dataPaths: [String] = []
    @Option(name: [.customShort("q"), .customLong("db-file")]) var dbPath: String? = nil

    func quadStore() throws -> AnyMutableQuadStore {
        var arguments = ["kineo-cli"]
        if let dbPath = dbPath {
            arguments.append("-q")
            arguments.append(dbPath)
        }
        for d in defaultGraphFiles {
            arguments.append("-d")
            arguments.append(d)
        }
        for n in namedGraphFiles {
            arguments.append("-n")
            // let url = URL(fileURLWithPath: n)
            // arguments.append(url.absoluteString)
            arguments.append(n)
        }
        for d in dataPaths {
            arguments.append("-D")
            arguments.append(d)
        }
        
        let config = try QuadStoreConfiguration(arguments: &arguments)
//        let startTime = getCurrentTime()
        let startSecond = getCurrentDateSeconds()
//        var count = 0
        let qs  = try quadStore(config, startSecond: startSecond, verbose: verbose)
        return qs
    }
    
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

    func quadStore(_ config: QuadStoreConfiguration, startSecond: UInt64, verbose: Bool) throws -> AnyMutableQuadStore {
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
}

extension KineoCLI {
    struct REPL: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "REPL")
        
        @OptionGroup var options: Options
        
        mutating func run() throws {
            var arguments = ["kineo-cli"]
            for d in options.defaultGraphFiles {
                arguments.append("-d")
                arguments.append(d)
            }
            for n in options.namedGraphFiles {
                arguments.append("-n")
                // let url = URL(fileURLWithPath: n)
                // arguments.append(url.absoluteString)
                arguments.append(n)
            }
            for d in options.dataPaths {
                arguments.append("-D")
                arguments.append(d)
            }
            
            do {
                let qs = try options.quadStore()
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
                        _ = try cliQuery(in: qs, query: q, graph: graph)
                    } catch let e {
                        warn("*** Failed to evaluate query:")
                        warn("*** - \(e)")
                    }
                }
            } catch let error {
                print("*** \(error)")
                throw ExitCode(1)
            }
        }

        func readLine(prompt: String) -> String? {
            print(prompt, terminator: "")
            return Swift.readLine(strippingNewline: true)
        }

        func cliQuery<Q: QuadStoreProtocol>(in store: Q, query: SPARQLSyntax.Query, graph: Term? = nil, verbose: Bool = false) throws -> Int {
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
    }
    
    struct Query: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Query")
        
        @Argument var queryString: String
        @OptionGroup var options: Options
        @Option(name: [.customShort("G"), .customLong("active-graph")]) var graphString: String? = nil
        
        mutating func run() throws {
            let verbose = options.verbose
            //            print("Query: \(queryString)")
            //            print("options: \(options)")
            
            let qs = try options.quadStore()
            var graph: Term? = nil
            if let iri = graphString {
                graph = Term(value: iri, type: .iri)
            }
            let qfile = queryString
            do {
                let sparql = try data(fromFileOrString: qfile)
                guard var p = SPARQLParser(data: sparql) else { fatalError("Failed to construct SPARQL parser") }
                let q = try p.parseQuery()
                //                for _ in 0..<10 {
                _ = try query(in: qs, query: q, graph: graph, verbose: verbose)
                //                }
            } catch let e {
                warn("*** Failed to evaluate query:")
                warn("*** - \(e)")
            }
            
        }
    }
    
    struct Explain: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Explain")
        
        @Argument var queryString: String
        @Flag(name: [.customShort("m"), .long]) var multiple: Bool = false
        @OptionGroup var options: Options
        @Option(name: [.customShort("G"), .customLong("active-graph")]) var graphString: String? = nil
        
        mutating func run() throws {
            let verbose = options.verbose
            
            let qs = try options.quadStore()
            var graph: Term? = nil
            if let iri = graphString {
                graph = Term(value: iri, type: .iri)
            }
            let qfile = queryString
            do {
                let sparql = try data(fromFileOrString: qfile)
                guard var p = SPARQLParser(data: sparql) else { fatalError("Failed to construct SPARQL parser") }
                let q = try p.parseQuery()
                
                print("Parsed query:")
                print(q.serialize())
                try explain(in: qs, query: q, graph: graph, multiple: multiple, verbose: verbose)
            } catch let e {
                warn("*** Failed to evaluate query:")
                warn("*** - \(e)")
            }
            
        }
        
        /// Parse a SPARQL query from the supplied file, produce a query plan for it in the context
        /// of the database's QuadStore, and print a serialized form of the resulting query plan.
        ///
        /// - parameter query: The query to plan.
        /// - parameter graph: The graph name to use as the initial active graph.
        func explain<Q: QuadStoreProtocol>(in store: Q, query: SPARQLSyntax.Query, graph: Term? = nil, multiple: Bool, verbose: Bool) throws {
            let dataset = store.dataset(defaultGraph: graph)
            let metrics = QueryPlanEvaluationMetrics()
            let planner     = queryPlanner(store: store, dataset: dataset, metrics: metrics)
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
        
    }
    
    struct Dataset: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Describe the RDF Dataset")
        
        @OptionGroup var options: Options
        @Option(name: [.customShort("G"), .customLong("active-graph")]) var graphString: String? = nil
        
        mutating func run() throws {
            let qs = try options.quadStore()
            var graph: Term? = nil
            if let iri = graphString {
                graph = Term(value: iri, type: .iri)
            }
            
            _ = try printDataset(in: qs, graph: graph)
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

    }
    
    struct Graphs: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List the graphs in the dataset")
        
        @OptionGroup var options: Options
        
        mutating func run() throws {
            let qs = try options.quadStore()
            _ = try printGraphs(in: qs)
        }

        func printGraphs(in store: QuadStoreProtocol) throws -> Int {
            var count = 0
            for graph in store.graphs() {
                count += 1
                print("\(graph.value)")
            }
            return count
        }

    }
    
    struct Dump: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Dump the contents of the RDF dataset")

        @OptionGroup var options: Options
        
        mutating func run() throws {
            let qs = try options.quadStore()
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
        }
    }
    
    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a database file, optionally pre-loading RDF files")

        @OptionGroup var options: Options
        
        mutating func run() throws {
            _ = try options.quadStore()
        }
    }
    
    struct Load: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Load RDF files into a dataset")

        @OptionGroup var options: Options
        
        mutating func run() throws {
            _ = try options.quadStore()
        }
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
    let metrics     = QueryPlanEvaluationMetrics(verbose: verbose)
    let planner     = queryPlanner(store: store, dataset: dataset, metrics: metrics)
    let e           = QueryPlanEvaluator(planner: planner)
    let results     = try e.evaluate(query: query)
    return results
}

func queryPlanner<Q : QuadStoreProtocol>(store: Q, dataset: DatasetProtocol, metrics: QueryPlanEvaluationMetrics) -> QueryPlanner<Q> {
    let planner = QueryPlanner(store: store, dataset: dataset, metrics: metrics)
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
