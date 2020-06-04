//
//  SPARQLTestSuite.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 5/2/18.
//

import Foundation
import SPARQLSyntax

public struct SPARQLTestRunner {
    typealias TestedQuadStore = SQLiteQuadStore
//    typealias TestedQuadStore = MemoryQuadStore

    public var requireTestApproval: Bool
    public var quadstore: MemoryQuadStore
    public var verbose: Bool
    public var testSimpleQueryEvaluation: Bool
    public var testQueryPlanEvaluation: Bool

    public enum TestError: Error {
        case unsupportedFormat(String)
    }
    
    public enum TestResult: Equatable {
        case success(iri: String)
        case failure(iri: String, reason: String)
    }
    
    public init() {
        self.verbose = false
        self.testSimpleQueryEvaluation = true
        self.testQueryPlanEvaluation = true
        self.quadstore = MemoryQuadStore()
        self.requireTestApproval = true
    }
    
    func quadStore(from dataset: Dataset, defaultGraph: Term) throws -> TestedQuadStore {
        let q = try TestedQuadStore()
        do {
            let defaultUrls = dataset.defaultGraphs.compactMap { URL(string: $0.value) }
            try q.load(version: Version(0), files: defaultUrls.map{ $0.path }, graph: defaultGraph)
            
            let namedUrls = dataset.namedGraphs.compactMap { URL(string: $0.value) }
            for url in namedUrls {
                try q.load(version: Version(0), files: [url.path], graph: Term(iri: url.absoluteString))
            }
        } catch let e {
            print("*** \(e)")
            throw e
        }
        return q
    }
    
    public func runSyntaxTest(iri: String, inPath path: URL, expectFailure: Bool = false) throws -> TestResult {
        let results = try runSyntaxTests(inPath: path, testType: nil, expectFailure: expectFailure) { (test) in
            return (test == iri)
        }
        guard let result = results.first else { fatalError() }
        return result
    }
    
    public func runSyntaxTests(inPath path: URL, testType: Term?, expectFailure: Bool = false, skip: Set<String>? = nil) throws -> [TestResult] {
        if let skip = skip {
            return try runSyntaxTests(inPath: path, testType: testType, expectFailure: expectFailure) {
                return !skip.contains($0)
            }
        } else {
            return try runSyntaxTests(inPath: path, testType: testType, expectFailure: expectFailure) { (_) in return true }
        }
    }
    
    public func runSyntaxTests(inPath path: URL, testType: Term?, expectFailure: Bool = false, withAcceptancePredicate accept: (String) -> Bool) throws -> [TestResult] {
        var results = [TestResult]()
        do {
            let manifest = path.appendingPathComponent("manifest.ttl")
            try quadstore.load(version: Version(0), files: [manifest.path])
            let manifestTerm = Term(iri: manifest.absoluteString)
            let items = try manifestSyntaxItems(quadstore: quadstore, manifest: manifestTerm, type: testType)
            for item in items {
                guard let test = item["test"] else {
                    fatalError("Failed to access test IRI")
                }
                if !accept(test.value) {
                    continue
                }
                if verbose {
                    print("Running syntax test: \(test.value)")
                }
                guard let action = item["action"] else {
                    results.append(.failure(iri: test.value, reason: "Did not find an mf:action property for this test"))
                    continue
                }
                //                print("Parsing \(action)...")
                guard let url = URL(string: action.value) else {
                    results.append(.failure(iri: test.value, reason: "Failed to construct URL for action: \(action)"))
                    continue
                }
                if expectFailure {
                    let sparql = try Data(contentsOf: url)
                    guard var p = SPARQLParser(data: sparql) else {
                        results.append(.failure(iri: test.value, reason: "Failed to construct SPARQL parser"))
                        continue
                    }
                    
                    do {
                        _ = try p.parseQuery()
                        results.append(.failure(iri: test.value, reason: "Did not find expected syntax error while parsing \(url)"))
                    } catch {
                        results.append(.success(iri: test.value))
                    }
                } else {
                    do {
                        let sparql = try Data(contentsOf: url)
                        guard var p = SPARQLParser(data: sparql) else {
                            results.append(.failure(iri: test.value, reason: "Failed to construct SPARQL parser"))
                            continue
                        }
                        _ = try p.parseQuery()
                        results.append(.success(iri: test.value))
                    } catch let e {
                        results.append(.failure(iri: test.value, reason: "failed to parse \(url): \(e)"))
                    }
                }
            }
        } catch let e {
            fatalError("Failed to run syntax tests: \(e)")
        }
        return results
    }
    
    public func runEvaluationTest(iri: String, inPath path: URL) throws -> TestResult {
        let results = try runEvaluationTests(inPath: path, testType: nil) { (test) in
            return (test == iri)
        }
        guard let result = results.first else { fatalError() }
        return result
    }
    
    public func runEvaluationTests(inPath path: URL, testType: Term?, skip: Set<String>? = nil) throws -> [TestResult] {
        if let skip = skip {
            return try runEvaluationTests(inPath: path, testType: testType) {
                return !skip.contains($0)
            }
        } else {
            return try runEvaluationTests(inPath: path, testType: testType) { (_) in return true }
        }
    }
    
    public func runEvaluationTests(inPath path: URL, testType: Term?, withAcceptancePredicate accept: (String) -> Bool) throws -> [TestResult] {
        var results = [TestResult]()
        do {
            let manifest = path.appendingPathComponent("manifest.ttl")
            try quadstore.load(version: Version(0), files: [manifest.path])
            let manifestTerm = Term(iri: manifest.absoluteString)
            let testRecords = try Array(manifestEvaluationItems(quadstore: quadstore, manifest: manifestTerm, type: testType))
            for testRecord in testRecords {
                guard let test = testRecord["test"] else {
                    fatalError("Failed to access test IRI")
                }
                if !accept(test.value) {
                    continue
                }
                if verbose {
                    print("Running evaluation test: \(test.value)")
                }
                guard let action = testRecord["action"] else {
                    results.append(.failure(iri: test.value, reason: "Failed to access action term"))
                    continue
                }
                guard let testResult = testRecord["result"] else {
                    results.append(.failure(iri: test.value, reason: "Failed to access result term"))
                    continue
                }
                guard let query = testRecord["query"] else {
                    results.append(.failure(iri: test.value, reason: "Did not find an mf:action property for this test"))
                    continue
                    
                }
                var dataset : Dataset = try datasetDescription(from: quadstore, for: action, defaultGraph: manifestTerm)
                
                let testDefaultGraph = Term(iri: "tag:kasei.us,2018:default-graph")
                if verbose {
                    print("Parsing results: \(testResult)...")
                }
                guard let testResultUrl = URL(string: testResult.value) else {
                    results.append(.failure(iri: test.value, reason: "Failed to construct URL for result: \(testResult)"))
                    continue }
                
                guard let url = URL(string: query.value) else {
                    results.append(.failure(iri: test.value, reason: "Failed to construct URL for action: \(query)"))
                    continue
                }
                
                do {
                    if verbose {
                        print("Parsing query: \(query)...")
                    }
                    let sparql = try Data(contentsOf: url)
                    if verbose {
                        if let s = String(data: sparql, encoding: .utf8) {
                            print("\(s)")
                        }
                    }
                    guard var p = SPARQLParser(data: sparql, base: url.absoluteString) else {
                        results.append(.failure(iri: test.value, reason: "Failed to construct SPARQL parser"))
                        continue
                    }
                    
                    let query = try p.parseQuery()
                    if verbose {
                        print("\(query.serialize())")
                    }
                    if let queryDataset = query.dataset {
                        if !queryDataset.isEmpty {
                            if verbose {
                                print("Query specifies a custom dataset")
                            }
                            dataset = queryDataset
                        }
                    }
                    if verbose {
                        print("Test dataset: \(dataset)")
                    }

                    let expectedResult = try expectedResults(for: query, from: testResultUrl)

                    let testQuadStore = try quadStore(from: dataset, defaultGraph: testDefaultGraph)
                    let testDataset = Dataset(defaultGraphs: [testDefaultGraph], namedGraphs: dataset.namedGraphs)
                    if verbose {
                        print("Test quadstore: \(testQuadStore)")
                        for (i, q) in testQuadStore.enumerated() {
                            print("[\(i)] \(q)")
                        }
                        print("======================")
                    }
                    
                    if testSimpleQueryEvaluation {
                        print("Evaluating query with SimpleQueryEvaluator")
                        let simpleEvaluator = SimpleQueryEvaluator(store: testQuadStore, dataset: testDataset, verbose: verbose)
                        let simpleResult = try runQueryEvaluation(
                            test: test,
                            query: query,
                            in: testQuadStore,
                            dataset: testDataset,
                            defaultGraph: testDefaultGraph,
                            using: simpleEvaluator,
                            expectedResult: expectedResult
                        )
                        results.append(simpleResult)
                    }

                    if testQueryPlanEvaluation {
                        print("Evaluating query with QueryPlanEvaluator")
                        let planEvaluator = QueryPlanEvaluator(store: testQuadStore, dataset: testDataset, base: query.base)
                        let planResult = try runQueryEvaluation(
                            test: test,
                            query: query,
                            in: testQuadStore,
                            dataset: testDataset,
                            defaultGraph: testDefaultGraph,
                            using: planEvaluator,
                            expectedResult: expectedResult
                        )
                        results.append(planResult)
                    }
                } catch let e {
                    results.append(.failure(iri: test.value, reason: "failed to evaluate test \(test): \(e)"))
                }
            }
        } catch let e {
            print("Failed to run syntax tests: \(e)")
            throw e
        }
        return results
    }

    private func runQueryEvaluation<QE: QueryEvaluatorProtocol>(test: Term, query: Query, in store: TestedQuadStore, dataset: Dataset, defaultGraph: Term, using queryEvaluator: QE, expectedResult: QueryResult<[SPARQLResult<Term>], [Triple]>) throws -> TestResult {
        let result = try evaluate(query: query, in: store, dataset: dataset, defaultGraph: defaultGraph, evaluator: queryEvaluator)
        if result == expectedResult {
            return .success(iri: test.value)
        } else {
            if verbose {
                print("*** Test results did not match expected data")
                print("Got:")
                print("\(result)")
                print("Expected:")
                print("\(expectedResult)")
            }
            return .failure(iri: test.value, reason: "Test results did not match expected results using \(queryEvaluator)")
        }
    }
    
    func evaluate<QE: QueryEvaluatorProtocol>(query: Query, in store: TestedQuadStore, dataset: Dataset, defaultGraph: Term, evaluator e: QE) throws -> QueryResult<[SPARQLResult<Term>], [Triple]> {
        do {
            let result = try e.evaluate(query: query, activeGraph: defaultGraph)
//            print("Successful query plan evaluation")
            switch result {
            case let .bindings(vars, rows):
                return .bindings(vars, Array(rows))
            case .boolean(let b):
                return .boolean(b)
            case .triples(let t):
                return .triples(Array(t))
            }
        } catch let error {
            print("*** Failed to generate query plan: \(error)")
            throw error
        }
    }
    
    func datasetDescription(from quadstore: MemoryQuadStore, for term: Term, defaultGraph graph: Term) throws -> Dataset {
        var d = Dataset()
        let prefix = "http://www.w3.org/2001/sw/DataAccess/tests/test-query#"
        let predicates = ["data", "graphData"].map { "\(prefix)\($0)" }
        let keyPaths : [WritableKeyPath<Dataset, [Term]>] = [\Dataset.defaultGraphs, \Dataset.namedGraphs]
        
        for (predicate, keyPath) in zip(predicates, keyPaths) {
            let pattern = QuadPattern(subject: .bound(term), predicate: .bound(Term(iri: predicate)), object: .variable("term", binding: true), graph: .bound(graph))
            let quads = try quadstore.quads(matching: pattern)
            let terms = quads.map { $0.object }
            d[keyPath: keyPath] = terms
        }
        
        return d
    }
    
    func booleanResults<Q: QuadStoreProtocol>(from quadstore: Q, defaultGraph: Term) throws -> QueryResult<[SPARQLResult<Term>], [Triple]> {
        let pattern = QuadPattern(
            subject: .variable("rs", binding: true),
            predicate: .bound(Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/result-set#boolean")),
            object: .variable("result", binding: true),
            graph: .bound(defaultGraph)
        )
        let result = try quadstore.quads(matching: pattern).map { $0.object }.first!
        return QueryResult.boolean(result.booleanValue!)
    }
    
    func bindingResults<Q: QuadStoreProtocol>(from quadstore: Q, defaultGraph: Term) throws -> QueryResult<[SPARQLResult<Term>], [Triple]> {
        let varsPattern = QuadPattern(
            subject: .variable("rs", binding: true),
            predicate: .bound(Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/result-set#resultVariable")),
            object: .variable("var", binding: true),
            graph: .bound(defaultGraph)
        )
        let vars = try quadstore.quads(matching: varsPattern).map { $0.object.value }
        
        let solutionsPattern = QuadPattern(
            subject: .variable("rs", binding: true),
            predicate: .bound(Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/result-set#solution")),
            object: .variable("s", binding: true),
            graph: .bound(defaultGraph)
        )
        let solutions = try quadstore.quads(matching: solutionsPattern).map { $0.object }
        var results = [SPARQLResult<Term>]()
        for solution in solutions {
            let bindingsPattern = QuadPattern(
                subject: .bound(solution),
                predicate: .bound(Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/result-set#binding")),
                object: .variable("s", binding: true),
                graph: .bound(defaultGraph)
            )
            let bindings = try quadstore.quads(matching: bindingsPattern).map { $0.object }
            var d = [String:Term]()
            for binding in bindings {
                let valuePattern = QuadPattern(
                    subject: .bound(binding),
                    predicate: .bound(Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/result-set#value")),
                    object: .variable("s", binding: true),
                    graph: .bound(defaultGraph)
                )
                let variablePattern = QuadPattern(
                    subject: .bound(binding),
                    predicate: .bound(Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/result-set#variable")),
                    object: .variable("s", binding: true),
                    graph: .bound(defaultGraph)
                )
                let values = try quadstore.quads(matching: valuePattern).map { $0.object }
                let variables = try quadstore.quads(matching: variablePattern).map { $0.object }
                if let value = values.first, let variable = variables.first {
                    d[variable.value] = value
                }
            }
            let result = SPARQLResult<Term>(bindings: d)
            results.append(result)
        }
        return QueryResult<[SPARQLResult<Term>], [Triple]>.bindings(vars, results)
    }
    
    func expectedResults(for query: Query, from url: URL) throws -> QueryResult<[SPARQLResult<Term>], [Triple]> {
        if url.absoluteString.hasSuffix("srx") {
            let srxParser = SPARQLXMLParser()
            return try srxParser.parse(Data(contentsOf: url))
        } else if url.absoluteString.hasSuffix("ttl") || url.absoluteString.hasSuffix("rdf") {
            let syntax = RDFParserCombined.guessSyntax(filename: url.absoluteString)
            let parser = RDFParserCombined()
            var triples = [Triple]()
            _ = try parser.parse(file: url.path, syntax: syntax, base: url.absoluteString) { (s, p, o) in
                triples.append(Triple(subject: s, predicate: p, object: o))
            }
            switch query.form {
            case .construct(_), .describe(_):
                return QueryResult<[SPARQLResult<Term>], [Triple]>.triples(triples)
            default:
                let quadstore = MemoryQuadStore(version: Version(0))
                let graph = Term(iri: "http://example.org/")
                let quads = triples.map { Quad(triple: $0, graph: graph) }
                try quadstore.load(version: Version(0), quads: quads)
                if query.form == .ask {
                    return try booleanResults(from: quadstore, defaultGraph: graph)
                } else {
                    return try bindingResults(from: quadstore, defaultGraph: graph)
                }
            }
        } else {
            throw TestError.unsupportedFormat("Failed to load expected results from file \(url)")
        }
    }
    
    public func manifestEvaluationItems<Q: QuadStoreProtocol>(quadstore: Q, manifest: Term, type: Term? = nil) throws -> AnyIterator<SPARQLResult<Term>> {
        if verbose {
            print("Retrieving evaluation tests from manifest file...")
        }
        let sparql = """
        PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
        PREFIX mf: <http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#>
        PREFIX qt: <http://www.w3.org/2001/sw/DataAccess/tests/test-query#>
        PREFIX dawgt: <http://www.w3.org/2001/sw/DataAccess/tests/test-dawg#>
        SELECT * WHERE {
            ?manifest a mf:Manifest ;
                mf:entries/rdf:rest*/rdf:first ?test .
            ?test a ?test_type ;
                mf:action ?action ;
                mf:result ?result ;
                dawgt:approval ?approval ;
            .
            ?action qt:query ?query .
        }
        """
        guard var p = SPARQLParser(data: sparql.data(using: .utf8)!) else { fatalError("Failed to construct SPARQL parser") }
        var q = try p.parseQuery()
        if self.requireTestApproval {
            q = try q.replace(["approval": Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-dawg#Approved")])
        }
        var bind = ["manifest": manifest]
        if let tt = type {
            bind["test_type"] = tt
        }
        let result = try q.execute(quadstore: quadstore, defaultGraph: manifest, bind: bind)
        var results = [SPARQLResult<Term>]()
        guard case let .bindings(_, iter) = result else { fatalError() }
        for result in iter {
            results.append(result)
        }
        return AnyIterator(results.makeIterator())
    }

    func manifestSyntaxItems<Q: QuadStoreProtocol>(quadstore: Q, manifest: Term, type: Term? = nil) throws -> AnyIterator<SPARQLResult<Term>> {
        if verbose {
            print("Retrieving syntax tests from manifest file...")
        }
        let sparql = """
        PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
        PREFIX mf: <http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#>
        PREFIX dawgt: <http://www.w3.org/2001/sw/DataAccess/tests/test-dawg#>
        SELECT * WHERE {
            ?manifest a mf:Manifest ;
                mf:entries/rdf:rest*/rdf:first ?test .
            ?test a ?test_type ;
                mf:action ?action ;
                dawgt:approval dawgt:Approved .
        }
        """
        guard var p = SPARQLParser(data: sparql.data(using: .utf8)!) else { fatalError("Failed to construct SPARQL parser") }
        let q = try p.parseQuery()
        var bind = ["manifest": manifest]
        if let tt = type {
            bind["test_type"] = tt
        }
        let result = try q.execute(quadstore: quadstore, defaultGraph: manifest, bind: bind)
        var results = [SPARQLResult<Term>]()
        guard case let .bindings(_, iter) = result else { fatalError() }
        for result in iter {
            results.append(result)
        }
        return AnyIterator(results.makeIterator())
    }
}
