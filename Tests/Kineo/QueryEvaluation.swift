import XCTest
import Kineo

struct TestStore : QuadStoreProtocol {
    var quads : [Quad]
    
    func graphs() -> AnyIterator<Term> {
        var graphs = Set<Term>()
        for q in self {
            graphs.insert(q.graph)
        }
        return AnyIterator(graphs.makeIterator())
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
    var store : TestStore!
    var graph : Term!
    
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
    
    private func parse(query : String) -> Algebra? {
        let qp      = QueryParser(reader: query)
        do {
            let query   = try qp.parse()
            return query
        } catch {
            return nil
        }
    }
    
    private func eval(algebra : Algebra) throws -> AnyIterator<TermResult> {
        let e = SimpleQueryEvaluator(store: store, defaultGraph: self.graph)
        return try e.evaluate(algebra: algebra, activeGraph: self.graph)
    }

    private func eval(query : String) throws -> AnyIterator<TermResult> {
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
        XCTAssertEqualWithAccuracy(value.numericValue, -85.3, accuracy: 0.1)
    }
    
    func testAvgEval() {
        guard let results = try? Array(eval(query: "quad ?s ?p ?o <http://example.org/numbers>\navg o avg\n")) else { XCTFail(); return }
        XCTAssertEqual(results.count, 1)
        guard let result = results.first else { XCTFail(); return }
        guard let value = result["avg"] else { XCTFail(); return }
        XCTAssertEqualWithAccuracy(value.numericValue, -42.65, accuracy: 0.1)
    }
    
    func testMultiAggEval() {
        let quad : Algebra = .quad(QuadPattern(
            subject: .variable("s", binding: true),
            predicate: .variable("p", binding: true),
            object: .variable("o", binding: true),
            graph: .bound(Term(value: "http://example.org/numbers", type: .iri))
            ))
        let agg : Algebra = .aggregate(quad, [], [
            (.sum(.node(.variable("o", binding: false))), "sum"),
            (.avg(.node(.variable("o", binding: false))), "avg")
            ])
        
        guard let results = try? Array(eval(algebra: agg)) else { XCTFail(); return }
        XCTAssertEqual(results.count, 1)
        guard let result = results.first else { XCTFail(); return }
        guard let sum = result["sum"] else { XCTFail(); return }
        guard let avg = result["avg"] else { XCTFail(); return }

        XCTAssertEqualWithAccuracy(sum.numericValue, -85.3, accuracy: 0.1)
        XCTAssertEqualWithAccuracy(avg.numericValue, -42.65, accuracy: 0.1)
    }
    
    func testSortEval() {
        let quad : Algebra = .quad(QuadPattern(
            subject: .variable("s", binding: true),
            predicate: .bound(Term(value: "http://example.org/value", type: .iri)),
            object: .variable("o", binding: true),
            graph: .bound(Term(value: "http://example.org/numbers", type: .iri))
            ))

        let ascending : Algebra = .order(quad, [(true, .node(.variable("o", binding: false)))])
        guard let ascResults = try? Array(eval(algebra: ascending)) else { XCTFail(); return }
        
        XCTAssertEqual(ascResults.count, 2)
        let ascValues = ascResults.map { $0["o"]!.numericValue }
        XCTAssertEqualWithAccuracy(ascValues[0], -118.0, accuracy: 0.1)
        XCTAssertEqualWithAccuracy(ascValues[1], 32.7, accuracy: 0.1)

        let descending : Algebra = .order(quad, [(false, .node(.variable("o", binding: false)))])
        guard let descResults = try? Array(eval(algebra: descending)) else { XCTFail(); return }
        
        XCTAssertEqual(descResults.count, 2)
        let descValues = descResults.map { $0["o"]!.numericValue }
        XCTAssertEqualWithAccuracy(descValues[0], 32.7, accuracy: 0.1)
        XCTAssertEqualWithAccuracy(descValues[1], -118.0, accuracy: 0.1)
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
        guard let algebra = parse(query: "quad ?s ?p ?o <http://example.org/numbers>\nextend value ?o 1 + int\nsort value") else { XCTFail(); fatalError() }
        guard let results = try? Array(eval(algebra: algebra)) else { XCTFail(); return }
        
        XCTAssertEqual(results.count, 3)
        let values = results.flatMap { $0["value"] }.flatMap { $0.numeric }
        XCTAssertTrue(values[0] === .integer(-117))
        XCTAssertTrue(values[1] === .integer(33))
    }
}
