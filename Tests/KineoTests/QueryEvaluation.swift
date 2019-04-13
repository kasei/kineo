import XCTest
import Kineo
import SPARQLSyntax

#if os(Linux)
extension SimpleQueryEvaluationTest {
    static var allTests : [(String, (SimpleQueryEvaluationTest) -> () throws -> Void)] {
        return [
            ("testTripleEval", testTripleEval),
            ("testQuadEvalNoSuchGraph", testQuadEvalNoSuchGraph),
            ("testQuadEval", testQuadEval),
            ("testTripleEvalWithBoundPredicate", testTripleEvalWithBoundPredicate),
            ("testFilterEval", testFilterEval),
            ("testUnionEval", testUnionEval),
            ("testProjectEval", testProjectEval),
            ("testJoinEval", testJoinEval),
            ("testLeftJoinEval", testLeftJoinEval),
            ("testLimitEval", testLimitEval),
            ("testCountAllEval", testCountAllEval),
            ("testCountAllEvalWithGroup", testCountAllEvalWithGroup),
            ("testCountEval", testCountEval),
            ("testSumEval", testSumEval),
            ("testAvgEval", testAvgEval),
            ("testMultiAggEval", testMultiAggEval),
            ("testSortEval", testSortEval),
            ("testIRINamedGraphEval", testIRINamedGraphEval),
            ("testVarNamedGraphEval", testVarNamedGraphEval),
            ("testExtendEval", testExtendEval),
            ("testHashFunctions", testHashFunctions),
            ("testTermAccessors", testTermAccessors),
            ("testAggregationProjection", testAggregationProjection),
            ("testEmptyAggregation", testEmptyAggregation),
            ("testRankWindowFunction1", testRankWindowFunction1),
            ("testRankWindowFunction2", testRankWindowFunction2),
            ("testRankWindowFunctionWithHaving", testRankWindowFunctionWithHaving),
            ("testWindowFunction1", testWindowFunction1),
            ("testWindowFunction2", testWindowFunction2),
            ("testWindowFunction4", testWindowFunction4),
            ("testWindowFunction5", testWindowFunction5),
            ("testWindowFunction6", testWindowFunction6),
            ("testWindowFunction7", testWindowFunction7),
            ("testWindowFunction8", testWindowFunction8),
            ("testWindowFunction9", testWindowFunction9),
            ("testWindowFunction10", testWindowFunction10),
            ("testWindowFunction11", testWindowFunction11),
            ("testWindowFunction_aggregates", testWindowFunction_aggregates),
            ("testWindowFunctionPartition", testWindowFunctionPartition),
            ("testWindowFunctionRank", testWindowFunctionRank),
            ("testWindowFunctionNtile", testWindowFunctionNtile),
            ("testDistinctAggregate", testDistinctAggregate),
        ]
    }
}
extension QueryPlanEvaluationTest {
    static var allTests : [(String, (QueryPlanEvaluationTest) -> () throws -> Void)] {
        return [
            ("testTripleEval", testTripleEval),
            ("testQuadEvalNoSuchGraph", testQuadEvalNoSuchGraph),
            ("testQuadEval", testQuadEval),
            ("testTripleEvalWithBoundPredicate", testTripleEvalWithBoundPredicate),
            ("testFilterEval", testFilterEval),
            ("testUnionEval", testUnionEval),
            ("testProjectEval", testProjectEval),
            ("testJoinEval", testJoinEval),
            ("testLeftJoinEval", testLeftJoinEval),
            ("testLimitEval", testLimitEval),
            ("testCountAllEval", testCountAllEval),
            ("testCountAllEvalWithGroup", testCountAllEvalWithGroup),
            ("testCountEval", testCountEval),
            ("testSumEval", testSumEval),
            ("testAvgEval", testAvgEval),
            ("testMultiAggEval", testMultiAggEval),
            ("testSortEval", testSortEval),
            ("testIRINamedGraphEval", testIRINamedGraphEval),
            ("testVarNamedGraphEval", testVarNamedGraphEval),
            ("testExtendEval", testExtendEval),
            ("testHashFunctions", testHashFunctions),
            ("testTermAccessors", testTermAccessors),
            ("testAggregationProjection", testAggregationProjection),
            ("testEmptyAggregation", testEmptyAggregation),
            ("testRankWindowFunction1", testRankWindowFunction1),
            ("testRankWindowFunction2", testRankWindowFunction2),
            ("testRankWindowFunctionWithHaving", testRankWindowFunctionWithHaving),
            ("testWindowFunction1", testWindowFunction1),
            ("testWindowFunction2", testWindowFunction2),
            ("testWindowFunction3", testWindowFunction3),
            ("testWindowFunction5", testWindowFunction5),
            ("testWindowFunction6", testWindowFunction6),
            ("testWindowFunction7", testWindowFunction7),
            ("testWindowFunction8", testWindowFunction8),
            ("testWindowFunction9", testWindowFunction9),
            ("testWindowFunction10", testWindowFunction10),
            ("testWindowFunction11", testWindowFunction11),
            ("testWindowFunction_aggregates", testWindowFunction_aggregates),
            ("testWindowFunctionPartition", testWindowFunctionPartition),
            ("testWindowFunctionRank", testWindowFunctionRank),
            ("testWindowFunctionNtile", testWindowFunctionNtile),
            ("testDistinctAggregate", testDistinctAggregate),
        ]
    }
}
#endif

struct TestStore: QuadStoreProtocol, Sequence {
    typealias IDType = Term

    public func effectiveVersion(matching pattern: QuadPattern) throws -> UInt64? {
        return nil
    }

    var quads: [Quad]
    var count: Int { return quads.count }

    func graphs() -> AnyIterator<Term> {
        var graphs = Set<Term>()
        for q in self {
            graphs.insert(q.graph)
        }
        return AnyIterator(graphs.makeIterator())
    }

    func graphTerms(in graph: Term) -> AnyIterator<Term> {
        var terms = Set<Term>()
        for q in self {
            if q.graph == graph {
                terms.insert(q.subject)
                terms.insert(q.object)
            }
        }
        return AnyIterator(terms.makeIterator())
    }

    func makeIterator() -> AnyIterator<Quad> {
        return AnyIterator(quads.makeIterator())
    }

    func results(matching pattern: QuadPattern) throws -> AnyIterator<TermResult> {
        var results = [TermResult]()
        for q in self {
            if let r = pattern.matches(quad: q) {
                results.append(r)
            }
        }
        return AnyIterator(results.makeIterator())
    }

    func quads(matching pattern: QuadPattern) throws -> AnyIterator<Quad> {
        let s = quads.filter { pattern.matches(quad: $0) != nil }
        return AnyIterator(s.makeIterator())
    }
}

protocol QueryEvaluationTests {
    associatedtype Evaluator: QueryEvaluatorProtocol
    var store: TestStore! { get }
    var graph: Term! { get }
    func evaluator(dataset: Dataset) -> Evaluator
}

extension QueryEvaluationTests {
    var testQuads: [Quad] {
        let parser = NTriplesParser(reader: "")
        
        guard let b1 = parser.parseQuad(line: "<http://example.org/Berlin> <http://xmlns.com/foaf/0.1/name> \"Berlin\"", graph: self.graph) else { fatalError() }
        guard let b2 = parser.parseQuad(line: "<http://example.org/Berlin> <http://xmlns.com/foaf/0.1/homepage> <http://www.berlin.de/en/>", graph: self.graph) else { fatalError() }
        guard let s = parser.parseQuad(line: "_:a <http://purl.org/dc/elements/1.1/title> \"Santa Monica\"", graph: self.graph) else { fatalError() }
        
        let numbers = Term(value: "http://example.org/numbers", type: .iri)
        guard let n0 = parser.parseQuad(line: "_:n1 <http://xmlns.com/foaf/0.1/name> \"a number\"", graph: numbers) else { fatalError() }
        guard let n1 = parser.parseQuad(line: "_:n1 <http://example.org/value> \"32.7\"^^<http://www.w3.org/2001/XMLSchema#float>", graph: numbers) else { fatalError() }
        guard let n2 = parser.parseQuad(line: "_:n2 <http://example.org/value> \"-118\"^^<http://www.w3.org/2001/XMLSchema#integer>", graph: numbers) else { fatalError() }
        
        let other = Term(value: "http://example.org/other", type: .iri)
        guard let x1 = parser.parseQuad(line: "_:x <http://example.org/p> \"hello\"@en", graph: other) else { fatalError() }
        
        let quads = [b1, b2, s, n0, n1, n2, x1]
        return quads
    }

    func parse(query: String) -> Algebra? {
        let qp      = QueryParser(reader: query)
        do {
            let query   = try qp.parse()
            return query?.algebra
        } catch {
            return nil
        }
    }
    
    func eval(query: Query) throws -> AnyIterator<TermResult> {
        let dataset = store.dataset(withDefault: self.graph)
        let e = evaluator(dataset: dataset)
        let results = try e.evaluate(query: query)
        guard case let .bindings(_, seq) = results else { fatalError() }
        return AnyIterator(seq.makeIterator())
    }
    
    func eval(algebra: Algebra) throws -> AnyIterator<TermResult> {
        let e = SimpleQueryEvaluator(store: store, defaultGraph: self.graph)
        return try e.evaluate(algebra: algebra, activeGraph: self.graph)
    }
    
    func eval(query: String) throws -> AnyIterator<TermResult> {
        guard let algebra = parse(query: query) else { XCTFail(); fatalError() }
        return try eval(algebra: algebra)
    }

    func _testTripleEval() {
        guard let results = try? Array(eval(query: "triple ?s ?p ?o\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 3)
    }

    func _testQuadEvalNoSuchGraph() {
        guard let results = try? Array(eval(query: "quad ?s ?p ?o <http://no-such-graph/>\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 0)
    }
    
    func _testQuadEval() {
        guard let results = try? Array(eval(query: "quad ?s ?p ?o <http://example.org/>\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 3)
    }
    
    func _testTripleEvalWithBoundPredicate() {
        guard let results = try? Array(eval(query: "triple ?s <http://xmlns.com/foaf/0.1/name> ?o\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 1)
    }
    
    func _testFilterEval() {
        guard let results = try? Array(eval(query: "triple ?s ?p ?o\nfilter ?s isiri")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 2)
    }
    
    func _testUnionEval() {
        guard let results = try? Array(eval(query: "triple ?s <http://xmlns.com/foaf/0.1/name> ?o\ntriple ?s <http://purl.org/dc/elements/1.1/title> ?o\nunion")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 2)
    }
    
    func _testProjectEval() {
        guard let nonProjectedResults = try? Array(eval(query: "triple ?s <http://xmlns.com/foaf/0.1/name> ?o\n")) else { XCTFail(); return }
        guard let nonProjectedResult = nonProjectedResults.first else { XCTFail(); return }
        XCTAssertEqual(Set(nonProjectedResult.keys), Set(["s", "o"]))
        
        guard let projectedResults = try? Array(eval(query: "triple ?s <http://xmlns.com/foaf/0.1/name> ?o\nproject o\n")) else { XCTFail(); return }
        guard let projectedResult = projectedResults.first else { XCTFail(); return }
        XCTAssertEqual(Set(projectedResult.keys), Set(["o"]))
    }
    
    func _testJoinEval() {
        guard let results = try? Array(eval(query: "triple ?s <http://xmlns.com/foaf/0.1/name> ?name\ntriple ?s <http://xmlns.com/foaf/0.1/homepage> ?page\njoin")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 1)
        guard let result = results.first else { XCTFail(); return }
        XCTAssertEqual(Set(result.keys), Set(["s", "name", "page"]))
        
        guard let s = result["s"] else { XCTFail(); return }
        XCTAssertEqual(s, Term(value: "http://example.org/Berlin", type: .iri))
        
        guard let name = result["name"] else { XCTFail(); return }
        XCTAssertEqual(name, Term(value: "Berlin", type: .datatype(.string)))
        
        guard let page = result["page"] else { XCTFail(); return }
        XCTAssertEqual(page, Term(value: "http://www.berlin.de/en/", type: .iri))
    }
    
    func _testLeftJoinEval() {
        guard let results = try? Array(eval(query: "triple ?s <http://xmlns.com/foaf/0.1/name> ?name\ntriple ?s <http://purl.org/dc/elements/1.1/title> ?name\nunion\ntriple ?s <http://xmlns.com/foaf/0.1/homepage> ?page\nleftjoin")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 2)
        
        var seen = Set<String>()
        for result in results {
            guard let s = result["s"] else { XCTFail(); return }
            guard let name = result["name"] else { XCTFail(); return }
            seen.insert(name.value)
            switch s.type {
            case .blank:
                XCTAssertEqual(Set(result.keys), Set(["s", "name"]))
            case .iri:
                XCTAssertEqual(Set(result.keys), Set(["s", "name", "page"]))
            default:
                fatalError()
            }
        }
        XCTAssertEqual(seen, Set(["Berlin", "Santa Monica"]))
    }
    
    func _testLimitEval() {
        guard let results0 = try? Array(eval(query: "triple ?s ?p ?o\nlimit 0")) else { XCTFail(); return }
        XCTAssertEqual(results0.count, 0)
        
        guard let results1 = try? Array(eval(query: "triple ?s ?p ?o\nlimit 1")) else { XCTFail(); return }
        XCTAssertEqual(results1.count, 1)
        
        guard let results2 = try? Array(eval(query: "triple ?s ?p ?o\nlimit 2")) else { XCTFail(); return }
        XCTAssertEqual(results2.count, 2)
    }
    
    func _testCountAllEval() {
        guard let results = try? Array(eval(query: "triple ?s <http://xmlns.com/foaf/0.1/name> ?name\ntriple ?s <http://purl.org/dc/elements/1.1/title> ?name\nunion\ntriple ?s <http://xmlns.com/foaf/0.1/homepage> ?page\nleftjoin\ncountall cnt\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 1)
        guard let result = results.first else { XCTFail(); return }
        guard let c = result["cnt"] else { XCTFail(); return }
        XCTAssertEqual(c, Term(integer: 2))
    }
    
    func _testCountAllEvalWithGroup() {
        guard let results = try? Array(eval(query: "triple ?s ?p ?o\ncountall cnt s\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 2)
        var data = [TermType:Int]()
        for r in results {
            data[r["s"]!.type] = Int(r["cnt"]!.numericValue)
        }
        XCTAssertEqual(data, [.iri: 2, .blank: 1])
    }
    
    func _testCountEval() {
        guard let results = try? Array(eval(query: "triple ?s <http://xmlns.com/foaf/0.1/name> ?name\ntriple ?s <http://purl.org/dc/elements/1.1/title> ?name\nunion\ntriple ?s <http://xmlns.com/foaf/0.1/homepage> ?page\nleftjoin\ncount page cnt")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 1)
        guard let result = results.first else { XCTFail(); return }
        guard let value = result["cnt"] else { XCTFail(); return }
        XCTAssertEqual(value, Term(integer: 1))
    }
    
    func _testSumEval() {
        guard let results = try? Array(eval(query: "quad ?s ?p ?o <http://example.org/numbers>\nfilter ?o isnumeric\nsum o sum\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 1)
        guard let result = results.first else { XCTFail(); return }
        guard let value = result["sum"] else { XCTFail(); return }
        XCTAssertEqual(value.numericValue, -85.3, accuracy: 0.1)
    }
    
    func _testAvgEval() {
        guard let results = try? Array(eval(query: "quad ?s ?p ?o <http://example.org/numbers>\nfilter ?o isnumeric\navg o avg\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 1)
        guard let result = results.first else { XCTFail(); return }
        guard let value = result["avg"] else { XCTFail(); return }
        XCTAssertEqual(value.numericValue, -42.65, accuracy: 0.1)
    }
    
    func _testMultiAggEval() {
        let quad: Algebra = .quad(QuadPattern(
            subject: .variable("s", binding: true),
            predicate: .variable("p", binding: true),
            object: .variable("o", binding: true),
            graph: .bound(Term(value: "http://example.org/numbers", type: .iri))
        ))
        let numerics: Algebra = .filter(quad, .isnumeric(.node(.variable("o", binding: false))))
        let agg: Algebra = .aggregate(numerics, [], [
            Algebra.AggregationMapping(aggregation: .sum(.node(.variable("o", binding: false)), false), variableName: "sum"),
            Algebra.AggregationMapping(aggregation: .avg(.node(.variable("o", binding: false)), false), variableName: "avg"),
            ])
        
        guard let results = try? Array(eval(algebra: agg)) else { XCTFail(); return }
        XCTAssertEqual(results.count, 1)
        guard let result = results.first else { XCTFail(); return }
        guard let sum = result["sum"] else { XCTFail(); return }
        guard let avg = result["avg"] else { XCTFail(); return }
        
        XCTAssertEqual(sum.numericValue, -85.3, accuracy: 0.1)
        XCTAssertEqual(avg.numericValue, -42.65, accuracy: 0.1)
    }
    
    func _testSortEval() {
        let quad: Algebra = .quad(QuadPattern(
            subject: .variable("s", binding: true),
            predicate: .bound(Term(value: "http://example.org/value", type: .iri)),
            object: .variable("o", binding: true),
            graph: .bound(Term(value: "http://example.org/numbers", type: .iri))
        ))
        
        let ascending: Algebra = .order(quad, [Algebra.SortComparator(ascending: true, expression: .node(.variable("o", binding: false)))])
        guard let ascResults = try? Array(eval(algebra: ascending)) else { XCTFail(); return }
        
        XCTAssertEqual(ascResults.count, 2)
        let ascValues = ascResults.map { $0["o"]!.numericValue }
        XCTAssertEqual(ascValues[0], -118.0, accuracy: 0.1)
        XCTAssertEqual(ascValues[1], 32.7, accuracy: 0.1)
        
        let descending: Algebra = .order(quad, [Algebra.SortComparator(ascending: false, expression: .node(.variable("o", binding: false)))])
        guard let descResults = try? Array(eval(algebra: descending)) else { XCTFail(); return }
        
        XCTAssertEqual(descResults.count, 2)
        let descValues = descResults.map { $0["o"]!.numericValue }
        XCTAssertEqual(descValues[0], 32.7, accuracy: 0.1)
        XCTAssertEqual(descValues[1], -118.0, accuracy: 0.1)
        
        let negated: Algebra = .order(quad, [Algebra.SortComparator(ascending: false, expression: .neg(.node(.variable("o", binding: false))))])
        guard let negResults = try? Array(eval(algebra: negated)) else { XCTFail(); return }
        
        XCTAssertEqual(negResults.count, 2)
        let negValues = negResults.map { $0["o"]!.numericValue }
        XCTAssertEqual(negValues[0], -118.0, accuracy: 0.1)
        XCTAssertEqual(negValues[1], 32.7, accuracy: 0.1)
    }
    
    func _testIRINamedGraphEval() {
        guard let results = try? Array(eval(query: "triple ?s ?p ?o\ngraph <http://example.org/other>\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 1)
    }
    
    func _testVarNamedGraphEval() {
        guard let results = try? Array(eval(query: "triple ?s ?p ?o\ngraph ?g\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 4)
        var graphs = Set<String>()
        for r in results {
            graphs.insert(r["g"]!.value)
        }
        XCTAssertEqual(graphs, Set(["http://example.org/numbers", "http://example.org/other"]))
    }
    
    func _testExtendEval() {
        guard let algebra = parse(query: "quad ?s ?p ?o <http://example.org/numbers>\nextend value ?o 1 + int\nsort ?value") else { XCTFail(); fatalError() }
        guard let results = try? Array(eval(algebra: algebra)) else { XCTFail(); return }
        
        XCTAssertEqual(results.count, 3)
        let values = results.compactMap { $0["value"] }.compactMap { $0.numeric }
        XCTAssertTrue(values[0] === .integer(-117))
        XCTAssertTrue(values[1] === .integer(33))
    }
    
    func _testHashFunctions() {
        let sparql = """
            SELECT * WHERE {
                BIND(MD5("abc") AS ?md5)
                BIND(SHA1("abc") AS ?sha1)
                BIND(SHA256("abc") AS ?sha256)
                BIND(SHA384("abc") AS ?sha384)
                BIND(SHA512("abc") AS ?sha512)
            }
        """
        guard let data = sparql.data(using: .utf8) else { XCTFail(); return }
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        do {
            let q = try p.parseQuery()
            let results = try Array(eval(query: q))
            XCTAssertEqual(results.count, 1)
            guard let result = results.first else {
                XCTFail()
                return
            }
            
            let expected = [
                "md5": "900150983cd24fb0d6963f7d28e17f72",
                "sha1": "a9993e364706816aba3e25717850c26c9cd0d89d",
                "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                "sha384": "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7",
                "sha512": "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
                ]
            
            for (varName, expectedHashValue) in expected {
                guard let term = result[varName] else {
                    XCTFail()
                    return
                }
                XCTAssertEqual(term.value, expectedHashValue, "Expected value for \(varName) hash")
            }
        } catch {
            XCTFail()
        }
    }
    
    func _testTermAccessors() {
        let sparql = """
            SELECT * WHERE {
                BIND(LANG("abc"@en-US) AS ?lang)
                BIND(LANGMATCHES("en", "en") AS ?langmatches1)
                BIND(LANGMATCHES("en", "en-us") AS ?langmatches2)
                BIND(LANGMATCHES("en-us", "en") AS ?langmatches3)
                BIND(LANGMATCHES("en-us", "en-gb") AS ?langmatches4)
            }
        """
        guard let data = sparql.data(using: .utf8) else { XCTFail(); return }
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        do {
            let q = try p.parseQuery()
            let results = try Array(eval(query: q))
            XCTAssertEqual(results.count, 1)
            guard let result = results.first else {
                XCTFail()
                return
            }
            
            let expected = [
                "lang": "en-us",
                "langmatches1": "true",
                "langmatches2": "false",
                "langmatches3": "true",
                "langmatches4": "false",
                ]
            
            for (varName, expectedValue) in expected {
                guard let term = result[varName] else {
                    XCTFail()
                    return
                }
                XCTAssertEqual(term.value, expectedValue, "Expected value for \(varName) accessor")
            }
        } catch {
            XCTFail()
        }
    }
    
    func _testAggregationProjection() {
        let sparql = """
            SELECT * WHERE {
                BIND(1 AS ?z)
                {
                    SELECT ?s (MIN(?p) AS ?x) WHERE {
                        ?s ?p ?o
                    }
                    GROUP BY ?s
                }
            }
        """
        guard let data = sparql.data(using: .utf8) else { XCTFail(); return }
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        do {
            let q = try p.parseQuery()
            //            print(q.serialize())
            let results = try Array(eval(query: q))
            XCTAssertEqual(results.count, 2)
        } catch {
            XCTFail()
        }
    }
    
    func _testEmptyAggregation() {
        let sparql = """
            SELECT (SUM(?x) AS ?sum) WHERE {
                BIND(1 AS ?x)
                FILTER(?x > 1)
            }
        """
        guard let data = sparql.data(using: .utf8) else { XCTFail(); return }
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        do {
            let q = try p.parseQuery()
            //            print(q.serialize())
            let results = try Array(eval(query: q))
            XCTAssertEqual(results.count, 1)
            
            guard let result = results.first else {
                XCTFail()
                return
            }
            
            let expected = [
                "sum": "0",
                ]
            
            for (varName, expectedValue) in expected {
                guard let term = result[varName] else {
                    XCTFail()
                    return
                }
                XCTAssertEqual(term.value, expectedValue, "Expected value for \(varName) over empty group")
            }
        } catch {
            XCTFail()
        }
    }
    
    func _testRankWindowFunction1() throws {
        let data = "SELECT ?s ?p ?o (RANK() OVER (ORDER BY ?o) AS ?rank) WHERE { ?s ?p ?o } ORDER BY DESC(?rank)".data(using: .utf8)!
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let results = try Array(eval(query: p.parseQuery()))
        XCTAssertEqual(results.count, 3)
        
        let ranks = results.map { $0["rank"]! }.map { $0.numericValue }
        let values = results.map { $0["o"]! }.map { $0.value }
        XCTAssertEqual(ranks, [3.0, 2.0, 1.0])
        XCTAssertEqual(values, [
            "Santa Monica",
            "Berlin",
            "http://www.berlin.de/en/"
            ])
    }
    
    func _testRankWindowFunction2() throws {
        let data = "SELECT ?s ?p ?o (RANK() OVER (ORDER BY DESC(?o)) AS ?rank) WHERE { ?s ?p ?o } ORDER BY ASC(?rank)".data(using: .utf8)!
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let results = try Array(eval(query: p.parseQuery()))
        XCTAssertEqual(results.count, 3)
        
        let ranks = results.map { $0["rank"]! }.map { $0.numericValue }
        let values = results.map { $0["o"]! }.map { $0.value }
        XCTAssertEqual(ranks, [1.0, 2.0, 3.0])
        XCTAssertEqual(values, [
            "Santa Monica",
            "Berlin",
            "http://www.berlin.de/en/"
            ])
    }
    
    func _testRankWindowFunctionWithHaving() throws {
        let data = """
        SELECT ?s ?p ?o (RANK() OVER (ORDER BY ?o) AS ?rank)
        WHERE { ?s ?p ?o }
        HAVING (?rank <= 2)
        ORDER BY ?rank
        """.data(using: .utf8)!
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let results = try Array(eval(query: p.parseQuery()))
        XCTAssertEqual(results.count, 2)
        
        let ranks = results.map { $0["rank"]! }.map { $0.numericValue }
        let values = results.map { $0["o"]! }.map { $0.value }
        XCTAssertEqual(ranks, [1.0, 2.0])
        XCTAssertEqual(values, [
            "http://www.berlin.de/en/",
            "Berlin",
            ])
    }
    
    func _testWindowFunction1() throws {
        let data = """
        PREFIX : <http://example.org/>
        SELECT ?date ?value (AVG(?value) OVER (ORDER BY ?date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS ?movingAverage) WHERE {
            VALUES (?date ?value) {
                (1 1.0)     # 1.0
                (2 2.0)     # 1.5
                (3 3.0)     # 2.0
                (4 -2.0)    # 1.0
                (5 8.0)     # 3.0
                (6 2.7)     # 2.9
                (7 -1.7)    # 3.0
            }
        }
        """.data(using: .utf8)!
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let results = try Array(eval(query: p.parseQuery()))
        XCTAssertEqual(results.count, 7)
        
        let avgs = results.map { $0["movingAverage"] }.compactMap { $0?.numericValue }
        let values = results.map { $0["value"]! }.compactMap { $0.numericValue }
        let expectedAvgs = [1.0, 1.5, 2.0, 1.0, 3.0, 2.9, 3.0]
        let expectedValues = [1.0, 2.0, 3.0, -2.0, 8.0, 2.7, -1.7]
        for (got, expected) in zip(avgs, expectedAvgs) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
        for (got, expected) in zip(values, expectedValues) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
    }
    
    func _testWindowFunction2() throws {
        let data = """
        PREFIX : <http://example.org/>
        SELECT ?date ?value (AVG(?value) OVER (ORDER BY ?date ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS ?movingAverage) WHERE {
            VALUES (?date ?value) {
                (1 1.0)     # 1.0
                (2 2.0)     # 1.5
                (3 3.0)     # 2.0
                (4 -2.0)    # 1.0
                (5 8.0)     # 3.0
                (6 2.7)     # 2.9
                (7 -1.7)    # 3.0
            }
        }
        """.data(using: .utf8)!
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let results = try Array(eval(query: p.parseQuery()))
        XCTAssertEqual(results.count, 7)
        
        let avgs = results.map { $0["movingAverage"] }.compactMap { $0?.numericValue }
        let values = results.map { $0["value"]! }.compactMap { $0.numericValue }
        let expectedAvgs = [1.0, 1.5, 2.0, 1.0, 2.75, 2.925, 1.75]
        let expectedValues = [1.0, 2.0, 3.0, -2.0, 8.0, 2.7, -1.7]
        for (got, expected) in zip(avgs, expectedAvgs) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
        for (got, expected) in zip(values, expectedValues) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
    }
    
    func _testWindowFunction3() throws {
        let data = """
        PREFIX : <http://example.org/>
        SELECT ?date ?value (AVG(?value) OVER (ORDER BY ?date ROWS BETWEEN CURRENT ROW AND UNBOUNDED) AS ?movingAverage) WHERE {
            VALUES (?date ?value) {
                (1 1.0)     # 1.857
                (2 2.0)     # 2.0
                (3 3.0)     # 2.0
                (4 -2.0)    # 1.75
                (5 8.0)     # 3.0
                (6 2.7)     # 0.5
                (7 -1.7)    # -1.7
            }
        }
        """.data(using: .utf8)!
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let results = try Array(eval(query: p.parseQuery()))
        XCTAssertEqual(results.count, 7)
        
        let avgs = results.map { $0["movingAverage"] }.compactMap { $0?.numericValue }
        let values = results.map { $0["value"]! }.compactMap { $0.numericValue }
        let expectedAvgs = [1.857, 2.0, 2.0, 1.75, 3.0, 0.5, -1.7]
        let expectedValues = [1.0, 2.0, 3.0, -2.0, 8.0, 2.7, -1.7]
        for (got, expected) in zip(avgs, expectedAvgs) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
        for (got, expected) in zip(values, expectedValues) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
    }
    
    func _testWindowFunction4() throws {
        let data = """
        PREFIX : <http://example.org/>
        SELECT ?date ?value (AVG(?value) OVER (ORDER BY ?date ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING) AS ?movingAverage) WHERE {
            VALUES (?date ?value) {
                (1 1.0)     # 0.0
                (2 2.0)     # 1.0
                (3 3.0)     # 1.5
                (4 -2.0)    # 2.5
                (5 8.0)     # 0.5
                (6 2.7)     # 3.0
                (7 -1.7)    # 5.35
            }
        }
        """.data(using: .utf8)!
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let results = try Array(eval(query: p.parseQuery()))
        XCTAssertEqual(results.count, 7)
        
        let avgs = results.map { $0["movingAverage"] }.compactMap { $0?.numericValue }
        let values = results.map { $0["value"]! }.compactMap { $0.numericValue }
        let expectedAvgs = [0.0, 1.0, 1.5, 2.5, 0.5, 3.0, 5.35]
        let expectedValues = [1.0, 2.0, 3.0, -2.0, 8.0, 2.7, -1.7]
        for (got, expected) in zip(avgs, expectedAvgs) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
        for (got, expected) in zip(values, expectedValues) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
    }
    
    func _testWindowFunction5() throws {
        let data = """
        PREFIX : <http://example.org/>
        SELECT ?date ?value (AVG(?value) OVER (ORDER BY ?date ROWS BETWEEN CURRENT ROW AND 1 FOLLOWING) AS ?movingAverage) WHERE {
            VALUES (?date ?value) {
                (1 1.0)     # 1.5
                (2 2.0)     # 2.5
                (3 3.0)     # 0.5
                (4 -2.0)    # 3.0
                (5 8.0)     # 5.35
                (6 2.7)     # 0.5
                (7 -1.7)    # -1.7
            }
        }
        """.data(using: .utf8)!
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let results = try Array(eval(query: p.parseQuery()))
        XCTAssertEqual(results.count, 7)
        
        let avgs = results.map { $0["movingAverage"] }.compactMap { $0?.numericValue }
        let values = results.map { $0["value"]! }.compactMap { $0.numericValue }
        let expectedAvgs = [1.5, 2.5, 0.5, 3.0, 5.35, 0.5, -1.7]
        let expectedValues = [1.0, 2.0, 3.0, -2.0, 8.0, 2.7, -1.7]
        for (got, expected) in zip(avgs, expectedAvgs) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
        for (got, expected) in zip(values, expectedValues) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
    }
    
    func _testWindowFunction6() throws {
        let data = """
        PREFIX : <http://example.org/>
        SELECT ?date ?value (AVG(?value) OVER (ORDER BY ?date ROWS BETWEEN UNBOUNDED AND 1 PRECEDING) AS ?movingAverage) WHERE {
            VALUES (?date ?value) {
                (1 1.0)     # 0
                (2 2.0)     # 1.0
                (3 3.0)     # 1.5
                (4 -2.0)    # 2.0
                (5 8.0)     # 1.0
                (6 2.7)     # 2.4
                (7 -1.7)    # 2.45
            }
        }
        """.data(using: .utf8)!
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let results = try Array(eval(query: p.parseQuery()))
        XCTAssertEqual(results.count, 7)
        
        let avgs = results.map { $0["movingAverage"] }.compactMap { $0?.numericValue }
        let values = results.map { $0["value"]! }.compactMap { $0.numericValue }
        let expectedAvgs = [0.0, 1.0, 1.5, 2.0, 1.0, 2.4, 2.45]
        let expectedValues = [1.0, 2.0, 3.0, -2.0, 8.0, 2.7, -1.7]
        for (got, expected) in zip(avgs, expectedAvgs) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
        for (got, expected) in zip(values, expectedValues) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
    }
    
    func _testWindowFunction7() throws {
        let data = """
        PREFIX : <http://example.org/>
        SELECT ?date ?value (AVG(?value) OVER (ORDER BY ?date ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED) AS ?movingAverage) WHERE {
            VALUES (?date ?value) {
                (1 1.0)     # 2.0
                (2 2.0)     # 2.0
                (3 3.0)     # 1.75
                (4 -2.0)    # 3.0
                (5 8.0)     # 0.5
                (6 2.7)     # -1.7
                (7 -1.7)    # 0.0
            }
        }
        """.data(using: .utf8)!
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let results = try Array(eval(query: p.parseQuery()))
        XCTAssertEqual(results.count, 7)
        
        let avgs = results.map { $0["movingAverage"] }.compactMap { $0?.numericValue }
        let values = results.map { $0["value"]! }.compactMap { $0.numericValue }
        let expectedAvgs = [2.0, 2.0, 1.75, 3.0, 0.5, -1.7, 0.0]
        let expectedValues = [1.0, 2.0, 3.0, -2.0, 8.0, 2.7, -1.7]
        for (got, expected) in zip(avgs, expectedAvgs) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
        for (got, expected) in zip(values, expectedValues) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
    }
    
    func _testWindowFunction8() throws {
        let data = """
        PREFIX : <http://example.org/>
        SELECT ?date ?value (AVG(?value) OVER (ORDER BY ?date ROWS BETWEEN 1 FOLLOWING AND 3 FOLLOWING) AS ?movingAverage) WHERE {
            VALUES (?date ?value) {
                (1 1.0)     # 1.0
                (2 2.0)     # 3.0
                (3 3.0)     # 2.9
                (4 -2.0)    # 3.0
                (5 8.0)     # 0.5
                (6 2.7)     # -1.7
                (7 -1.7)    # 0.0
            }
        }
        """.data(using: .utf8)!
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let results = try Array(eval(query: p.parseQuery()))
        XCTAssertEqual(results.count, 7)
        
        let avgs = results.map { $0["movingAverage"] }.compactMap { $0?.numericValue }
        let values = results.map { $0["value"]! }.compactMap { $0.numericValue }
        let expectedAvgs = [1.0, 3.0, 2.9, 3.0, 0.5, -1.7, 0.0]
        let expectedValues = [1.0, 2.0, 3.0, -2.0, 8.0, 2.7, -1.7]
        for (got, expected) in zip(avgs, expectedAvgs) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
        for (got, expected) in zip(values, expectedValues) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
    }
    
    func _testWindowFunction9() throws {
        let data = """
        PREFIX : <http://example.org/>
        SELECT ?date ?value (AVG(?value) OVER (ORDER BY ?date ROWS BETWEEN UNBOUNDED AND 1 FOLLOWING) AS ?movingAverage) WHERE {
            VALUES (?date ?value) {
                (1 1.0)     # 1.5
                (2 2.0)     # 2.0
                (3 3.0)     # 1.0
                (4 -2.0)    # 2.4
                (5 8.0)     # 2.45
                (6 2.7)     # 1.857
                (7 -1.7)    # 1.857
            }
        }
        """.data(using: .utf8)!
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let results = try Array(eval(query: p.parseQuery()))
        XCTAssertEqual(results.count, 7)
        
        let avgs = results.map { $0["movingAverage"] }.compactMap { $0?.numericValue }
        let values = results.map { $0["value"]! }.compactMap { $0.numericValue }
        let expectedAvgs = [1.5, 2.0, 1.0, 2.4, 2.45, 1.857, 1.857]
        let expectedValues = [1.0, 2.0, 3.0, -2.0, 8.0, 2.7, -1.7]
        for (got, expected) in zip(avgs, expectedAvgs) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
        for (got, expected) in zip(values, expectedValues) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
    }
    
    func _testWindowFunction10() throws {
        let data = """
        PREFIX : <http://example.org/>
        SELECT ?date ?value (AVG(?value) OVER (ORDER BY ?date ROWS BETWEEN 1 PRECEDING AND 2 FOLLOWING) AS ?movingAverage) WHERE {
            VALUES (?date ?value) {
                (1 1.0)     # 2.0
                (2 2.0)     # 1.0
                (3 3.0)     # 2.75
                (4 -2.0)    # 2.925
                (5 8.0)     # 1.75
                (6 2.7)     # 3.0
                (7 -1.7)    # 0.5
            }
        }
        """.data(using: .utf8)!
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let results = try Array(eval(query: p.parseQuery()))
        XCTAssertEqual(results.count, 7)
        
        let avgs = results.map { $0["movingAverage"] }.compactMap { $0?.numericValue }
        let values = results.map { $0["value"]! }.compactMap { $0.numericValue }
        let expectedAvgs = [2.0, 1.0, 2.75, 2.925, 1.75, 3.0, 0.5]
        let expectedValues = [1.0, 2.0, 3.0, -2.0, 8.0, 2.7, -1.7]
        for (got, expected) in zip(avgs, expectedAvgs) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
        for (got, expected) in zip(values, expectedValues) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
    }
    
    func _testWindowFunction11() throws {
        let data = """
        PREFIX : <http://example.org/>
        SELECT ?date ?value (AVG(?value) OVER (ORDER BY ?date ROWS BETWEEN 2 PRECEDING AND UNBOUNDED) AS ?movingAverage) WHERE {
            VALUES (?date ?value) {
                (1 1.0)     # 1.857
                (2 2.0)     # 1.857
                (3 3.0)     # 1.857
                (4 -2.0)    # 2.0
                (5 8.0)     # 2.0
                (6 2.7)     # 1.75
                (7 -1.7)    # 3.0
            }
        }
        """.data(using: .utf8)!
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let results = try Array(eval(query: p.parseQuery()))
        XCTAssertEqual(results.count, 7)
        
        let avgs = results.map { $0["movingAverage"] }.compactMap { $0?.numericValue }
        let values = results.map { $0["value"]! }.compactMap { $0.numericValue }
        let expectedAvgs = [1.857, 1.857, 1.857, 2.0, 2.0, 1.75, 3.0]
        let expectedValues = [1.0, 2.0, 3.0, -2.0, 8.0, 2.7, -1.7]
        for (got, expected) in zip(avgs, expectedAvgs) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
        for (got, expected) in zip(values, expectedValues) {
            XCTAssertEqual(got, expected, accuracy: 0.01)
        }
    }
    
    func _testWindowFunctionPartition() throws {
        let data = """
        PREFIX : <http://example.org/>
        SELECT
            ?seq
            ?partition
            (SUM(?value) OVER (PARTITION BY ?partition ORDER BY ?seq ROWS BETWEEN 1 PRECEDING AND CURRENT ROW) AS ?sum)
            (ROW_NUMBER() OVER (PARTITION BY ?partition ORDER BY ?value) AS ?row)
        WHERE {
            VALUES (?seq ?partition ?value) {
                (1      1   3)
                (2      2   1)
                (5      3   0)
                (6      1   -10)
                (9      2   17)
                (10     2   2)
                (100    2   7)
            }
        }
        ORDER BY ?partition ?seq
        """.data(using: .utf8)!
        
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let results = try Array(eval(query: p.parseQuery()))
        XCTAssertEqual(results.count, 7)
        
        let gotSums = results.map { $0["sum"] }.compactMap { $0?.numericValue }.map { Int($0) }
        let gotRows = results.map { $0["row"] }.compactMap { $0?.numericValue }.map { Int($0) }
        XCTAssertEqual(gotRows, [2, 1, 1, 4, 2, 3, 1])
        let expectedSums = [3, -7, 1, 18, 19, 9, 0]
        for (got, expected) in zip(gotSums, expectedSums) {
            XCTAssertEqual(got, expected)
        }
    }
    
    func _testWindowFunction_aggregates() throws {
        let data = """
        PREFIX : <http://example.org/>
        SELECT
            ?date
            (COUNT(*) OVER (ORDER BY ?date ROWS BETWEEN 2 PRECEDING AND UNBOUNDED) AS ?countAll)
            (COUNT(?date) OVER (ORDER BY ?date ROWS BETWEEN 2 PRECEDING AND UNBOUNDED) AS ?count)
            (SUM(?date) OVER (ORDER BY ?date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS ?sum)
            (MIN(?value) OVER (ORDER BY ?date ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS ?min)
            (MAX(?value) OVER (ORDER BY ?date ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS ?max)
            (GROUP_CONCAT(STR(?value)) OVER (ORDER BY ?date ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS ?groupConcat)
        WHERE {
            VALUES (?date ?value) {
                (1      3)
                (2      1)
                (5      0)
                (6      -10)
                (9      17)
                (10     2)
                (100    7)
            }
        }
        """.data(using: .utf8)!
        
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let results = try Array(eval(query: p.parseQuery()))
        XCTAssertEqual(results.count, 7)
        
        let gotCountAllValues = results.map { $0["countAll"] }.compactMap { $0?.numericValue }.map { Int($0) }
        for (got, expected) in zip(gotCountAllValues, [7, 7, 7, 6, 5, 4, 3]) {
            XCTAssertEqual(got, expected)
        }
        
        let gotCountValues = results.map { $0["count"] }.compactMap { $0?.numericValue }.map { Int($0) }
        for (got, expected) in zip(gotCountValues, [7, 7, 7, 6, 5, 4, 3]) {
            XCTAssertEqual(got, expected)
        }
        
        let gotSumValues = results.map { $0["sum"] }.compactMap { $0?.numericValue }.map { Int($0) }
        for (got, expected) in zip(gotSumValues, [1, 3, 8, 13, 20, 25, 119]) {
            XCTAssertEqual(got, expected)
        }
        
        let gotMinValues = results.map { $0["min"] }.compactMap { $0?.numericValue }.map { Int($0) }
        for (got, expected) in zip(gotMinValues, [1, 0, -10, -10, -10, 2, 2]) {
            XCTAssertEqual(got, expected)
        }
        
        let gotMaxValues = results.map { $0["max"] }.compactMap { $0?.numericValue }.map { Int($0) }
        for (got, expected) in zip(gotMaxValues, [3, 3, 1, 17, 17, 17, 7]) {
            XCTAssertEqual(got, expected)
        }
        
        let gotGroupConcatValues = results.map { $0["groupConcat"] }.compactMap { $0?.value }
        let expectedGroupConcatValues = ["3 1", "3 1 0", "1 0 -10", "0 -10 17", "-10 17 2", "17 2 7", "2 7"]
        for (got, expected) in zip(gotGroupConcatValues, expectedGroupConcatValues) {
            XCTAssertEqual(got, expected)
        }
    }

    func _testDistinctAggregate() throws {
        let data = """
        PREFIX : <http://example.org/>
        SELECT
            (GROUP_CONCAT(DISTINCT ?str) AS ?groupConcat)
            (SUM(DISTINCT ?value) AS ?sum)
            (COUNT(DISTINCT ?value) AS ?count)
            (AVG(DISTINCT ?value) AS ?avg)
        WHERE {
            VALUES (?seq ?value ?str) {
                (1  1.0     "e")
                (2  1       "b")
                (3  2e0     "e")
                (4  2.0     "e")
                (5  2       "Z")
                (6  1       "火星")
                (7  1       "é")
            }
        }
        """.data(using: .utf8)!
        
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let results = try Array(eval(query: p.parseQuery()))
        XCTAssertEqual(results.count, 1)
        
        let gotSumValues = results.map { $0["sum"] }.compactMap { $0?.numericValue }
        let expectedSumValues = [8.0]
        for (got, expected) in zip(gotSumValues, expectedSumValues) {
            XCTAssertEqual(got, expected)
        }
        
        let gotAvgValues = results.map { $0["avg"] }.compactMap { $0?.numericValue }
        let expectedAvgValues = [1.6]
        for (got, expected) in zip(gotAvgValues, expectedAvgValues) {
            XCTAssertEqual(got, expected)
        }
        
        let gotCountValues = results.map { $0["count"] }.compactMap { $0?.numericValue }
        let expectedCountValues = [5.0]
        for (got, expected) in zip(gotCountValues, expectedCountValues) {
            XCTAssertEqual(got, expected)
        }
        
        let gotGroupConcatValues = results.map { $0["groupConcat"] }.compactMap { $0?.value }
        let expectedGroupConcatValues = ["Z b e é 火星"]
        for (got, expected) in zip(gotGroupConcatValues, expectedGroupConcatValues) {
            XCTAssertEqual(got, expected)
        }
    }

    func _testWindowFunctionRank() throws {
        let data = """
        PREFIX : <http://example.org/>
        SELECT
            ?partition
            ?value
            (RANK() OVER (PARTITION BY ?partition ORDER BY ?value) AS ?rank)
        WHERE {
            VALUES (?partition ?value) {
                (1 1)
                (1 2)
                (1 2)
                (1 3)
                (2 4)
                (2 4)
                (2 5)
            }
        }
        ORDER BY ?partition ?value ?rank
        """.data(using: .utf8)!
        
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let results = try Array(eval(query: p.parseQuery()))
        XCTAssertEqual(results.count, 7)
        
        let gotRanks = results.map { $0["rank"] }.compactMap { $0?.numericValue }.map { Int($0) }
        XCTAssertEqual(gotRanks, [1, 2, 2, 4, 1, 1, 3])
    }

    func _testWindowFunctionRank2() throws {
        let data = """
        SELECT ?row ?partition ?value (RANK() OVER (PARTITION BY ?partition ORDER BY ?value) AS ?rank) WHERE {
            VALUES (?row ?partition ?value) {
                (1 1 1)
                (2 1 2)
                (3 1 2)
                (4 1 2)
                (5 2 3)
                (6 2 3)
            }
        }
        ORDER BY ?partition ?value ?rank
        """.data(using: .utf8)!
        
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let results = try Array(eval(query: p.parseQuery()))
        XCTAssertEqual(results.count, 6)
        
        let gotRanks = results.map { $0["rank"] }.compactMap { $0?.numericValue }.map { Int($0) }
        XCTAssertEqual(gotRanks, [1, 2, 2, 2, 1, 1])
    }
    
    func _testWindowFunctionNtile() throws {
        let data = """
        SELECT
            ?row
            ?partition
            ?value
            (NTILE(2) OVER (ORDER BY ?value ?row) AS ?n2)
            (NTILE(3) OVER (ORDER BY ?value ?row) AS ?n3)
            (NTILE(5) OVER (ORDER BY ?value ?row) AS ?n5)
            (NTILE(5) OVER (ORDER BY ?value) AS ?n5tie)
        WHERE {
            VALUES (?row ?partition ?value) {
                (1 1 1)     # 1 1 1
                (2 1 1)     # 1 1 1
                (3 1 5)     # 2 2 3
                (4 1 7)     # 2 3 4
                (5 1 2)     # 1 2 2
                (6 1 1)     # 1 1 2
                (7 1 10)    # 2 3 5
            }
        }
        ORDER BY ?row
        """.data(using: .utf8)!
        
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let results = try Array(eval(query: p.parseQuery()))
        XCTAssertEqual(results.count, 7)
        
        let gotN2 = results.map { $0["n2"] }.compactMap { $0?.numericValue }.map { Int($0) }
        XCTAssertEqual(gotN2, [1, 1, 2, 2, 1, 1, 2])
        
        let gotN3 = results.map { $0["n3"] }.compactMap { $0?.numericValue }.map { Int($0) }
        XCTAssertEqual(gotN3, [1, 1, 2, 3, 2, 1, 3])
        
        let gotN5 = results.map { $0["n5"] }.compactMap { $0?.numericValue }.map { Int($0) }
        XCTAssertEqual(gotN5, [1, 1, 3, 4, 2, 2, 5])
        
        let gotN5tie = results.map { $0["n5tie"] }.compactMap { $0?.numericValue }.map { Int($0) }
        XCTAssertEqual(gotN5tie, [1, 1, 3, 4, 2, 1, 5])
    }
}

class SimpleQueryEvaluationTest: XCTestCase, QueryEvaluationTests {
    typealias Evaluator = SimpleQueryEvaluator<TestStore>
    var store: TestStore!
    var graph: Term!
    
    override func setUp() {
        super.setUp()
        self.graph = Term(value: "http://example.org/", type: .iri)
        self.store = TestStore(quads: testQuads)
    }
    
    func evaluator(dataset: Dataset) -> Evaluator {
        let e = SimpleQueryEvaluator(store: store, dataset: dataset)
        return e
    }
    
    func testTripleEval() { _testTripleEval() }
    func testQuadEvalNoSuchGraph() { _testQuadEvalNoSuchGraph() }
    func testQuadEval() { _testQuadEval() }
    func testTripleEvalWithBoundPredicate() { _testTripleEvalWithBoundPredicate() }
    func testFilterEval() { _testFilterEval() }
    func testUnionEval() { _testUnionEval() }
    func testProjectEval() { _testProjectEval() }
    func testJoinEval() { _testJoinEval() }
    func testLeftJoinEval() { _testLeftJoinEval() }
    func testLimitEval() { _testLimitEval() }
    func testCountAllEval() { _testCountAllEval() }
    func testCountAllEvalWithGroup() { _testCountAllEvalWithGroup() }
    func testCountEval() { _testCountEval() }
    func testSumEval() { _testSumEval() }
    func testAvgEval() { _testAvgEval() }
    func testMultiAggEval() { _testMultiAggEval() }
    func testSortEval() { _testSortEval() }
    func testIRINamedGraphEval() { _testIRINamedGraphEval() }
    func testVarNamedGraphEval() { _testVarNamedGraphEval() }
    func testExtendEval() { _testExtendEval() }
    func testHashFunctions() { _testHashFunctions() }
    func testTermAccessors() { _testTermAccessors() }
    func testAggregationProjection() { _testAggregationProjection() }
    func testEmptyAggregation() { _testEmptyAggregation() }
    func testRankWindowFunction1() throws { try _testRankWindowFunction1() }
    func testRankWindowFunction2() throws { try _testRankWindowFunction2() }
    func testRankWindowFunctionWithHaving() throws { try _testRankWindowFunctionWithHaving() }
    func testWindowFunction1() throws { try _testWindowFunction1() }
    func testWindowFunction2() throws { try _testWindowFunction2() }
    func testWindowFunction3() throws { try _testWindowFunction3() }
    func testWindowFunction4() throws { try _testWindowFunction4() }
    func testWindowFunction5() throws { try _testWindowFunction5() }
    func testWindowFunction6() throws { try _testWindowFunction6() }
    func testWindowFunction7() throws { try _testWindowFunction7() }
    func testWindowFunction8() throws { try _testWindowFunction8() }
    func testWindowFunction9() throws { try _testWindowFunction9() }
    func testWindowFunction10() throws { try _testWindowFunction10() }
    func testWindowFunction11() throws { try _testWindowFunction11() }
    func testWindowFunction_aggregates() throws { try _testWindowFunction_aggregates() }
    func testWindowFunctionPartition() throws { try _testWindowFunctionPartition() }
    func testDistinctAggregate() throws { try _testDistinctAggregate() }
    func testWindowFunctionRank() throws { try _testWindowFunctionRank() }
    func testWindowFunctionRank2() throws { try _testWindowFunctionRank2() }
    func testWindowFunctionNtile() throws { try _testWindowFunctionNtile() }
}

class QueryPlanEvaluationTest: XCTestCase, QueryEvaluationTests {
    typealias Evaluator = QueryPlanEvaluator<TestStore>
    var store: TestStore!
    var graph: Term!
    
    override func setUp() {
        super.setUp()
        self.graph = Term(value: "http://example.org/", type: .iri)
        self.store = TestStore(quads: testQuads)
    }
    
    func evaluator(dataset: Dataset) -> Evaluator {
        let e = QueryPlanEvaluator(store: store, dataset: dataset)
        e.planner.allowStoreOptimizedPlans = false
        return e
    }
    
    func testTripleEval() { _testTripleEval() }
    func testQuadEvalNoSuchGraph() { _testQuadEvalNoSuchGraph() }
    func testQuadEval() { _testQuadEval() }
    func testTripleEvalWithBoundPredicate() { _testTripleEvalWithBoundPredicate() }
    func testFilterEval() { _testFilterEval() }
    func testUnionEval() { _testUnionEval() }
    func testProjectEval() { _testProjectEval() }
    func testJoinEval() { _testJoinEval() }
    func testLeftJoinEval() { _testLeftJoinEval() }
    func testLimitEval() { _testLimitEval() }
    func testCountAllEval() { _testCountAllEval() }
    func testCountAllEvalWithGroup() { _testCountAllEvalWithGroup() }
    func testCountEval() { _testCountEval() }
    func testSumEval() { _testSumEval() }
    func testAvgEval() { _testAvgEval() }
    func testMultiAggEval() { _testMultiAggEval() }
    func testSortEval() { _testSortEval() }
    func testIRINamedGraphEval() { _testIRINamedGraphEval() }
    func testVarNamedGraphEval() { _testVarNamedGraphEval() }
    func testExtendEval() { _testExtendEval() }
    func testHashFunctions() { _testHashFunctions() }
    func testTermAccessors() { _testTermAccessors() }
    func testAggregationProjection() { _testAggregationProjection() }
    func testEmptyAggregation() { _testEmptyAggregation() }
    func testRankWindowFunction1() throws { try _testRankWindowFunction1() }
    func testRankWindowFunction2() throws { try _testRankWindowFunction2() }
    func testRankWindowFunctionWithHaving() throws { try _testRankWindowFunctionWithHaving() }
    func testWindowFunction1() throws { try _testWindowFunction1() }
    func testWindowFunction2() throws { try _testWindowFunction2() }
    func testWindowFunction3() throws { try _testWindowFunction3() }
    func testWindowFunction4() throws { try _testWindowFunction4() }
    func testWindowFunction5() throws { try _testWindowFunction5() }
    func testWindowFunction6() throws { try _testWindowFunction6() }
    func testWindowFunction7() throws { try _testWindowFunction7() }
    func testWindowFunction8() throws { try _testWindowFunction8() }
    func testWindowFunction9() throws { try _testWindowFunction9() }
    func testWindowFunction10() throws { try _testWindowFunction10() }
    func testWindowFunction11() throws { try _testWindowFunction11() }
    func testWindowFunction_aggregates() throws { try _testWindowFunction_aggregates() }
    func testWindowFunctionPartition() throws { try _testWindowFunctionPartition() }
    func testDistinctAggregate() throws { try _testDistinctAggregate() }
    func testWindowFunctionRank() throws { try _testWindowFunctionRank() }
    func testWindowFunctionRank2() throws { try _testWindowFunctionRank2() }
    func testWindowFunctionNtile() throws { try _testWindowFunctionNtile() }
}
