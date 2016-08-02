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

        let quads = [b1, b2, s]
        
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
    
    private func eval(query : String) throws -> AnyIterator<TermResult> {
        guard let algebra = parse(query: query) else { XCTFail(); fatalError() }
        let e = SimpleQueryEvaluator(store: store, defaultGraph: self.graph)
        return try e.evaluate(algebra: algebra, activeGraph: self.graph)
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
    
//    * `avg KEY RESULT GROUPVAR1 GROUPVAR2 ...` - Aggregate the pattern on the top of the stack, grouping by the group variables, binding the *average* of the `?KEY` variable to `?RESULT`
//    * `sum KEY RESULT GROUPVAR1 GROUPVAR2 ...` - Aggregate the pattern on the top of the stack, grouping by the group variables, binding the *sum* of the `?KEY` variable to `?RESULT`
//    * `count KEY RESULT GROUPVAR1 GROUPVAR2 ...` - Aggregate the pattern on the top of the stack, grouping by the group variables, binding the *count* of bound values of `?KEY` to `?RESULT`
//    * `countall RESULT GROUPVAR1 GROUPVAR2 ...` - Aggregate the pattern on the top of the stack, grouping by the group variables, binding the *count* of results to `?RESULT`
//    * `graph ?VAR` - Evaluate the pattern on the top of the stack with each named graph in the store as the active graph (and bound to `?VAR`)
//    * `graph <IRI>` - Change the active graph to `IRI`
//    * `extend RESULT EXPR` - Evaluate results for the pattern on the top of the stack, evaluating `EXPR` for each row, and binding the result to `?RESULT`
//    * `filter EXPR` - Evaluate results for the pattern on the top of the stack, evaluating `EXPR` for each row, and returning the result iff a true value is produced
//    * `sort VAR` - Sort the results for the pattern on the top of the stack by `?VAR`

}
