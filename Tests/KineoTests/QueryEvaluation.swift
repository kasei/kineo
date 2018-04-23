import XCTest
import Kineo
import SPARQLSyntax

#if os(Linux)
extension QueryEvaluationTest {
    static var allTests : [(String, (QueryEvaluationTest) -> () throws -> Void)] {
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
        ]
    }
}
#endif

struct TestStore: QuadStoreProtocol {
    typealias IDType = Term

    public func effectiveVersion(matching pattern: QuadPattern) throws -> UInt64? {
        return nil
    }

    var quads: [Quad]
    var count: Int { return quads.count }

    func graphIDs() -> AnyIterator<Term> {
        return graphs()
    }

    func graphs() -> AnyIterator<Term> {
        var graphs = Set<Term>()
        for q in self {
            graphs.insert(q.graph)
        }
        return AnyIterator(graphs.makeIterator())
    }

    func graphNodeIDs() -> AnyIterator<Term> {
        return graphNodeTerms()
    }

    func graphNodeTerms() -> AnyIterator<Term> {
        var terms = Set<Term>()
        for q in self {
            terms.insert(q.subject)
            terms.insert(q.object)
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

class QueryEvaluationTest: XCTestCase {
    var store: TestStore!
    var graph: Term!

    override func setUp() {
        super.setUp()
        self.graph = Term(value: "http://example.org/", type: .iri)
        let parser = NTriplesParser(reader: "")

        guard let b1 = parser.parseQuad(line: "<http://example.org/Berlin> <http://xmlns.com/foaf/0.1/name> \"Berlin\"", graph: self.graph) else { return }
        guard let b2 = parser.parseQuad(line: "<http://example.org/Berlin> <http://xmlns.com/foaf/0.1/homepage> <http://www.berlin.de/en/>", graph: self.graph) else { return }
        guard let s = parser.parseQuad(line: "_:a <http://purl.org/dc/elements/1.1/title> \"Santa Monica\"", graph: self.graph) else { return }

        let numbers = Term(value: "http://example.org/numbers", type: .iri)
        guard let n0 = parser.parseQuad(line: "_:n1 <http://xmlns.com/foaf/0.1/name> \"a number\"", graph: numbers) else { return }
        guard let n1 = parser.parseQuad(line: "_:n1 <http://example.org/value> \"32.7\"^^<http://www.w3.org/2001/XMLSchema#float>", graph: numbers) else { return }
        guard let n2 = parser.parseQuad(line: "_:n2 <http://example.org/value> \"-118\"^^<http://www.w3.org/2001/XMLSchema#integer>", graph: numbers) else { return }

        let other = Term(value: "http://example.org/other", type: .iri)
        guard let x1 = parser.parseQuad(line: "_:x <http://example.org/p> \"hello\"@en", graph: other) else { return }

        let quads = [b1, b2, s, n0, n1, n2, x1]

        store = TestStore(quads: quads)
    }

    private func parse(query: String) -> Algebra? {
        let qp      = QueryParser(reader: query)
        do {
            let query   = try qp.parse()
            return query?.algebra
        } catch {
            return nil
        }
    }

    private func eval(query: Query) throws -> AnyIterator<TermResult> {
        let e = SimpleQueryEvaluator(store: store, defaultGraph: self.graph)
        return try e.evaluate(query: query, activeGraph: self.graph)
    }
    
    private func eval(algebra: Algebra) throws -> AnyIterator<TermResult> {
        let e = SimpleQueryEvaluator(store: store, defaultGraph: self.graph)
        return try e.evaluate(algebra: algebra, activeGraph: self.graph)
    }
    
    private func eval(query: String) throws -> AnyIterator<TermResult> {
        guard let algebra = parse(query: query) else { XCTFail(); fatalError() }
        return try eval(algebra: algebra)
    }

    func testTripleEval() {
        guard let results = try? Array(eval(query: "triple ?s ?p ?o\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 3)
    }

    func testQuadEvalNoSuchGraph() {
        guard let results = try? Array(eval(query: "quad ?s ?p ?o <http://no-such-graph/>\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 0)
    }

    func testQuadEval() {
        guard let results = try? Array(eval(query: "quad ?s ?p ?o <http://example.org/>\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 3)
    }

    func testTripleEvalWithBoundPredicate() {
        guard let results = try? Array(eval(query: "triple ?s <http://xmlns.com/foaf/0.1/name> ?o\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 1)
    }

    func testFilterEval() {
        guard let results = try? Array(eval(query: "triple ?s ?p ?o\nfilter ?s isiri")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 2)
    }

    func testUnionEval() {
        guard let results = try? Array(eval(query: "triple ?s <http://xmlns.com/foaf/0.1/name> ?o\ntriple ?s <http://purl.org/dc/elements/1.1/title> ?o\nunion")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 2)
    }

    func testProjectEval() {
        guard let nonProjectedResults = try? Array(eval(query: "triple ?s <http://xmlns.com/foaf/0.1/name> ?o\n")) else { XCTFail(); return }
        guard let nonProjectedResult = nonProjectedResults.first else { XCTFail(); return }
        XCTAssertEqual(Set(nonProjectedResult.keys), Set(["s", "o"]))

        guard let projectedResults = try? Array(eval(query: "triple ?s <http://xmlns.com/foaf/0.1/name> ?o\nproject o\n")) else { XCTFail(); return }
        guard let projectedResult = projectedResults.first else { XCTFail(); return }
        XCTAssertEqual(Set(projectedResult.keys), Set(["o"]))
    }

    func testJoinEval() {
        guard let results = try? Array(eval(query: "triple ?s <http://xmlns.com/foaf/0.1/name> ?name\ntriple ?s <http://xmlns.com/foaf/0.1/homepage> ?page\njoin")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 1)
        guard let result = results.first else { XCTFail(); return }
        XCTAssertEqual(Set(result.keys), Set(["s", "name", "page"]))

        guard let s = result["s"] else { XCTFail(); return }
        XCTAssertEqual(s, Term(value: "http://example.org/Berlin", type: .iri))

        guard let name = result["name"] else { XCTFail(); return }
        XCTAssertEqual(name, Term(value: "Berlin", type: .datatype("http://www.w3.org/2001/XMLSchema#string")))

        guard let page = result["page"] else { XCTFail(); return }
        XCTAssertEqual(page, Term(value: "http://www.berlin.de/en/", type: .iri))
    }

    func testLeftJoinEval() {
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

    func testLimitEval() {
        guard let results0 = try? Array(eval(query: "triple ?s ?p ?o\nlimit 0")) else { XCTFail(); return }
        XCTAssertEqual(results0.count, 0)

        guard let results1 = try? Array(eval(query: "triple ?s ?p ?o\nlimit 1")) else { XCTFail(); return }
        XCTAssertEqual(results1.count, 1)

        guard let results2 = try? Array(eval(query: "triple ?s ?p ?o\nlimit 2")) else { XCTFail(); return }
        XCTAssertEqual(results2.count, 2)
    }

    func testCountAllEval() {
        guard let results = try? Array(eval(query: "triple ?s <http://xmlns.com/foaf/0.1/name> ?name\ntriple ?s <http://purl.org/dc/elements/1.1/title> ?name\nunion\ntriple ?s <http://xmlns.com/foaf/0.1/homepage> ?page\nleftjoin\ncountall cnt\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 1)
        guard let result = results.first else { XCTFail(); return }
        guard let c = result["cnt"] else { XCTFail(); return }
        XCTAssertEqual(c, Term(integer: 2))
    }

    func testCountAllEvalWithGroup() {
        guard let results = try? Array(eval(query: "triple ?s ?p ?o\ncountall cnt s\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 2)
        var data = [TermType:Int]()
        for r in results {
            data[r["s"]!.type] = Int(r["cnt"]!.numericValue)
        }
        XCTAssertEqual(data, [.iri: 2, .blank: 1])
    }

    func testCountEval() {
        guard let results = try? Array(eval(query: "triple ?s <http://xmlns.com/foaf/0.1/name> ?name\ntriple ?s <http://purl.org/dc/elements/1.1/title> ?name\nunion\ntriple ?s <http://xmlns.com/foaf/0.1/homepage> ?page\nleftjoin\ncount page cnt")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 1)
        guard let result = results.first else { XCTFail(); return }
        guard let value = result["cnt"] else { XCTFail(); return }
        XCTAssertEqual(value, Term(integer: 1))
    }

    func testSumEval() {
        guard let results = try? Array(eval(query: "quad ?s ?p ?o <http://example.org/numbers>\nsum o sum\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 1)
        guard let result = results.first else { XCTFail(); return }
        guard let value = result["sum"] else { XCTFail(); return }
        XCTAssertEqual(value.numericValue, -85.3, accuracy: 0.1)
    }

    func testAvgEval() {
        guard let results = try? Array(eval(query: "quad ?s ?p ?o <http://example.org/numbers>\navg o avg\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 1)
        guard let result = results.first else { XCTFail(); return }
        guard let value = result["avg"] else { XCTFail(); return }
        XCTAssertEqual(value.numericValue, -42.65, accuracy: 0.1)
    }

    func testMultiAggEval() {
        let quad: Algebra = .quad(QuadPattern(
            subject: .variable("s", binding: true),
            predicate: .variable("p", binding: true),
            object: .variable("o", binding: true),
            graph: .bound(Term(value: "http://example.org/numbers", type: .iri))
            ))
        let agg: Algebra = .aggregate(quad, [], [
            (.sum(.node(.variable("o", binding: false)), false), "sum"),
            (.avg(.node(.variable("o", binding: false)), false), "avg")
            ])

        guard let results = try? Array(eval(algebra: agg)) else { XCTFail(); return }
        XCTAssertEqual(results.count, 1)
        guard let result = results.first else { XCTFail(); return }
        guard let sum = result["sum"] else { XCTFail(); return }
        guard let avg = result["avg"] else { XCTFail(); return }

        XCTAssertEqual(sum.numericValue, -85.3, accuracy: 0.1)
        XCTAssertEqual(avg.numericValue, -42.65, accuracy: 0.1)
    }

    func testSortEval() {
        let quad: Algebra = .quad(QuadPattern(
            subject: .variable("s", binding: true),
            predicate: .bound(Term(value: "http://example.org/value", type: .iri)),
            object: .variable("o", binding: true),
            graph: .bound(Term(value: "http://example.org/numbers", type: .iri))
            ))

        let ascending: Algebra = .order(quad, [(true, .node(.variable("o", binding: false)))])
        guard let ascResults = try? Array(eval(algebra: ascending)) else { XCTFail(); return }

        XCTAssertEqual(ascResults.count, 2)
        let ascValues = ascResults.map { $0["o"]!.numericValue }
        XCTAssertEqual(ascValues[0], -118.0, accuracy: 0.1)
        XCTAssertEqual(ascValues[1], 32.7, accuracy: 0.1)

        let descending: Algebra = .order(quad, [(false, .node(.variable("o", binding: false)))])
        guard let descResults = try? Array(eval(algebra: descending)) else { XCTFail(); return }

        XCTAssertEqual(descResults.count, 2)
        let descValues = descResults.map { $0["o"]!.numericValue }
        XCTAssertEqual(descValues[0], 32.7, accuracy: 0.1)
        XCTAssertEqual(descValues[1], -118.0, accuracy: 0.1)

        let negated: Algebra = .order(quad, [(false, .neg(.node(.variable("o", binding: false))))])
        guard let negResults = try? Array(eval(algebra: negated)) else { XCTFail(); return }

        XCTAssertEqual(negResults.count, 2)
        let negValues = negResults.map { $0["o"]!.numericValue }
        XCTAssertEqual(negValues[0], -118.0, accuracy: 0.1)
        XCTAssertEqual(negValues[1], 32.7, accuracy: 0.1)
    }

    func testIRINamedGraphEval() {
        guard let results = try? Array(eval(query: "triple ?s ?p ?o\ngraph <http://example.org/other>\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 1)
    }

    func testVarNamedGraphEval() {
        guard let results = try? Array(eval(query: "triple ?s ?p ?o\ngraph ?g\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 4)
        var graphs = Set<String>()
        for r in results {
            graphs.insert(r["g"]!.value)
        }
        XCTAssertEqual(graphs, Set(["http://example.org/numbers", "http://example.org/other"]))
    }

    func testExtendEval() {
        guard let algebra = parse(query: "quad ?s ?p ?o <http://example.org/numbers>\nextend value ?o 1 + int\nsort ?value") else { XCTFail(); fatalError() }
        guard let results = try? Array(eval(algebra: algebra)) else { XCTFail(); return }

        XCTAssertEqual(results.count, 3)
        let values = results.compactMap { $0["value"] }.compactMap { $0.numeric }
        XCTAssertTrue(values[0] === .integer(-117))
        XCTAssertTrue(values[1] === .integer(33))
    }
    
    func testHashFunctions() {
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
    
    func testTermAccessors() {
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

    func testAggregationProjection() {
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
            print(q.serialize())
            let results = try Array(eval(query: q))
            XCTAssertEqual(results.count, 2)
        } catch {
            XCTFail()
        }
    }

    func testEmptyAggregation() {
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
            print(q.serialize())
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
}
