//
//  SPARQLTestSuite.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 5/2/18.
//

import Foundation
import SPARQLSyntax

public struct SPARQLTestRunner {
    var quadstore: MemoryQuadStore
    public var verbose: Bool
    
    public enum TestResult: Equatable {
        case success(iri: String)
        case failure(iri: String, reason: String)
    }
    
    public init() {
        self.verbose = false
        self.quadstore = MemoryQuadStore()
    }
    
    func parse<Q : MutableQuadStoreProtocol>(version: Version, quadstore: Q, files: [String], graph defaultGraphTerm: Term? = nil) throws {
        for filename in files {
            #if os (OSX)
            guard let path = NSURL(fileURLWithPath: filename).absoluteString else { throw DatabaseError.DataError("Not a valid graph path: \(filename)") }
            #else
            let path = NSURL(fileURLWithPath: filename).absoluteString
            #endif
            let graph   = defaultGraphTerm ?? Term(value: path, type: .iri)
            
            let parser = RDFParser()
            var quads = [Quad]()
            //                    print("Parsing RDF...")
            _ = try parser.parse(file: filename, base: graph.value) { (s, p, o) in
                let q = Quad(subject: s, predicate: p, object: o, graph: graph)
                quads.append(q)
            }
            
            //                    print("Loading RDF...")
            try quadstore.load(version: version, quads: quads)
        }
    }
    
    func parse<D: PageDatabase>(_ database: D, files: [String], graph defaultGraphTerm: Term? = nil) throws {
        let store = try PageQuadStore(database: database)
        do {
            try parse(version: Version(0), quadstore: store, files: files, graph: defaultGraphTerm)
        } catch let e {
            warn("*** Failed during load of RDF; \(e)")
            throw DatabaseUpdateError.rollback
        }
    }
    
    func quadStore(from dataset: Dataset, defaultGraph: Term) throws -> MemoryQuadStore {
        let q = MemoryQuadStore()
        do {
            let defaultUrls = dataset.defaultGraphs.compactMap { URL(string: $0.value) }
            try parse(version: Version(0), quadstore: q, files: defaultUrls.map{ $0.path }, graph: defaultGraph)
            
            let namedUrls = dataset.namedGraphs.compactMap { URL(string: $0.value) }.map { $0.path }
            for url in namedUrls {
                try parse(version: Version(0), quadstore: q, files: [url], graph: Term(iri: url))
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
            try parse(version: Version(0), quadstore: quadstore, files: [manifest.path])
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
    
    public func runEvaluationTest() -> TestResult {
        return .failure(iri: "", reason: "")
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
            try parse(version: Version(0), quadstore: quadstore, files: [manifest.path])
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
                let dataset = try datasetDescription(from: quadstore, for: action, defaultGraph: manifestTerm)
                
                let testDefaultGraph = Term(iri: "tag:kasei.us,2018:default-graph")
                if verbose {
                    print("Test dataset: \(dataset)")
                }
                let testQuadStore = try quadStore(from: dataset, defaultGraph: testDefaultGraph)
                if verbose {
                    print("Test quadstore: \(testQuadStore)")
                }
                if verbose {
                    print("Parsing results: \(testResult)...")
                }
                guard let testResultUrl = URL(string: testResult.value) else {
                    results.append(.failure(iri: test.value, reason: "Failed to construct URL for result: \(testResult)"))
                    continue }
                let expectedResult = try expectedResults(for: testResultUrl)
                
                if verbose {
                    print("Parsing query: \(query)...")
                }
                guard let url = URL(string: query.value) else {
                    results.append(.failure(iri: test.value, reason: "Failed to construct URL for action: \(query)"))
                    continue
                }
                
                do {
                    let sparql = try Data(contentsOf: url)
                    guard var p = SPARQLParser(data: sparql) else {
                        results.append(.failure(iri: test.value, reason: "Failed to construct SPARQL parser"))
                        continue
                    }
                    
                    let query = try p.parseQuery()
                    let result = try query.execute(quadstore: testQuadStore, defaultGraph: testDefaultGraph)
                    if result == expectedResult {
                        results.append(.success(iri: test.value))
                    } else {
                        if verbose {
                            print("*** Test results did not match expected data")
                            print("Got:")
                            print("\(result)")
                            print("Expected:")
                            print("\(expectedResult)")
                        }
                        results.append(.failure(iri: test.value, reason: "Test results did not match expected results"))
                    }
                } catch let e {
                    results.append(.failure(iri: test.value, reason: "failed to parse \(url): \(e)"))
                }
            }
        } catch let e {
            fatalError("Failed to run syntax tests: \(e)")
        }
        return results
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
    
    func expectedResults(for url: URL) throws -> QueryResult<[TermResult], [Triple]> {
        if url.absoluteString.hasSuffix("srx") {
            let srxParser = SPARQLXMLParser()
            return try srxParser.parse(Data(contentsOf: url))
        } else if url.absoluteString.hasSuffix("ttl") {
            let parser = RDFParser()
            var triples = [Triple]()
            _ = try parser.parse(file: url.path, base: url.absoluteString) { (s, p, o) in
                triples.append(Triple(subject: s, predicate: p, object: o))
            }
            return QueryResult<[TermResult], [Triple]>.triples(triples)
        } else {
            fatalError("Failed to load expected results from file \(url)")
        }
    }
    
    public func manifestEvaluationItems<Q: QuadStoreProtocol>(quadstore: Q, manifest: Term, type: Term? = nil) throws -> AnyIterator<TermResult> {
        if verbose {
            print("Retrieving evaluation tests from manifest file...")
        }
        let testType : Node = type == nil ? .variable("test_type", binding: false) : .bound(type!)
        let sparql = """
        PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
        PREFIX mf: <http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#>
        PREFIX qt: <http://www.w3.org/2001/sw/DataAccess/tests/test-query#>
        PREFIX dawgt: <http://www.w3.org/2001/sw/DataAccess/tests/test-dawg#>
        SELECT * WHERE {
            <\(manifest.value)> a mf:Manifest ;
                mf:entries/rdf:rest*/rdf:first ?test .
            ?test a \(testType) ;
                mf:action ?action ;
                mf:result ?result ;
                dawgt:approval dawgt:Approved .
            ?action qt:query ?query .
        }
        """
        guard var p = SPARQLParser(data: sparql.data(using: .utf8)!) else { fatalError("Failed to construct SPARQL parser") }
        let q = try p.parseQuery()
        let result = try q.execute(quadstore: quadstore, defaultGraph: manifest)
        var results = [TermResult]()
        guard case let .bindings(_, iter) = result else { fatalError() }
        for result in iter {
            results.append(result)
        }
        return AnyIterator(results.makeIterator())
    }

    func manifestSyntaxItems<Q: QuadStoreProtocol>(quadstore: Q, manifest: Term, type: Term? = nil) throws -> AnyIterator<TermResult> {
        if verbose {
            print("Retrieving syntax tests from manifest file...")
        }
        let testType : Node = type == nil ? .variable("test_type", binding: false) : .bound(type!)
        let sparql = """
        PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
        PREFIX mf: <http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#>
        PREFIX dawgt: <http://www.w3.org/2001/sw/DataAccess/tests/test-dawg#>
        SELECT * WHERE {
            <\(manifest.value)> a mf:Manifest ;
                mf:entries/rdf:rest*/rdf:first ?test .
            ?test a \(testType.description) ;
                mf:action ?action ;
                dawgt:approval dawgt:Approved .
        }
        """
        guard var p = SPARQLParser(data: sparql.data(using: .utf8)!) else { fatalError("Failed to construct SPARQL parser") }
        let q = try p.parseQuery()
        let result = try q.execute(quadstore: quadstore, defaultGraph: manifest)
        var results = [TermResult]()
        guard case let .bindings(_, iter) = result else { fatalError() }
        for result in iter {
            results.append(result)
        }
        return AnyIterator(results.makeIterator())
    }
}
