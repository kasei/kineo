import XCTest
import Kineo
import SPARQLSyntax

#if os(Linux)
extension QueryEvaluationPerformanceTest {
    static var allTests : [(String, (QueryEvaluationPerformanceTest) -> () throws -> Void)] {
        return [
            ("testPerformance_pipelinedAggregation", testPerformance_pipelinedAggregation),
            ("testPerformance_nonPipelinedAggregation", testPerformance_nonPipelinedAggregation)
        ]
    }
}
#endif

struct PerformanceTestStore: QuadStoreProtocol, Sequence {
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

class QueryEvaluationPerformanceTest: XCTestCase {
    var store: PerformanceTestStore!
    var graph: Term = Term(iri: "http://example.org/")
    let MIN_VALUE0 = 100
    let MAX_VALUE0 = 6_000

    let MIN_VALUE1 = 500
    let MAX_VALUE1 = 50_000
    var quads_dataset_numeric_0: [Quad]!
    var quads_dataset_numeric_1: [Quad]!

    override func setUp() {
        super.setUp()
        let quads = [Quad]()
        store = PerformanceTestStore(quads: quads)
    }

    private func numericDatasetQuads(min_value: Int, max_value: Int) -> [Quad] {
        var quads = [Quad]()
        let s1 = Term(iri: "http://example.org/s1")
        let s2 = Term(iri: "http://example.org/s2")
        let p = Term(iri: "http://example.org/ns/p")
        
        let third = Double(max_value)/3.0
        for n in min_value..<max_value {
            let i = Term(integer: n)
            let f = Term(float: Double(n)-third)
            quads.append(Quad(subject: s1, predicate: p, object: i, graph: self.graph))
            quads.append(Quad(subject: s2, predicate: p, object: f, graph: self.graph))
        }
        return quads
    }
    
    private func setUpNumericDataset0() {
        if quads_dataset_numeric_0 == nil {
            quads_dataset_numeric_0 = numericDatasetQuads(min_value: MIN_VALUE0, max_value: MAX_VALUE0)
        }
        store = PerformanceTestStore(quads: quads_dataset_numeric_0)
    }
    
    private func setUpNumericDataset1() {
        if quads_dataset_numeric_1 == nil {
            quads_dataset_numeric_1 = numericDatasetQuads(min_value: MIN_VALUE1, max_value: MAX_VALUE1)
        }
        store = PerformanceTestStore(quads: quads_dataset_numeric_1)
    }
    
    private func eval(query: Query) throws -> AnyIterator<TermResult> {
        let dataset = store.dataset(withDefault: self.graph)
        let e = QueryPlanEvaluator(store: store, dataset: dataset)
//        let e = SimpleQueryEvaluator(store: store, dataset: dataset)
        let results = try e.evaluate(query: query)
        guard case let .bindings(_, seq) = results else { fatalError() }
        return AnyIterator(seq.makeIterator())
    }
    
    func testPerformance_pipelinedAggregation() throws {
        setUpNumericDataset1()
        let sparql = """
            SELECT ?s (AVG(?o) AS ?x) WHERE {
                ?s ?p ?o
            }
            GROUP BY ?s
        """
        guard let data = sparql.data(using: .utf8) else { XCTFail(); return }
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let q = try p.parseQuery()
        self.measure {
            do {
                let results = try Array(eval(query: q))
                for r in results {
                    let n = r["x"]!
                    let s = r["s"]!
                    let value = n.numericValue
                    switch s.value {
                    case "http://example.org/s1":
                        let numbers = (MIN_VALUE1..<MAX_VALUE1)
                        let sum = numbers.reduce(0, +)
                        let avg = Double(sum)/Double(numbers.count)
                        let expected = avg
                        XCTAssertEqual(value, expected, accuracy: 0.5)
                    case "http://example.org/s2":
                        let third = Double(MAX_VALUE1)/3.0
                        let numbers = (MIN_VALUE1..<MAX_VALUE1).map { Double($0)-third }
                        let sum = numbers.reduce(0.0, +)
                        let avg = sum/Double(numbers.count)
                        let expected = avg
                        XCTAssertEqual(value, expected, accuracy: 0.5)
                    default:
                        XCTFail()
                    }
                }
                XCTAssertEqual(results.count, 2)
            } catch let e {
                XCTFail("Failed to evaluate query: \(e)")
            }
        }
    }
    
    func testPerformance_nonPipelinedAggregation() throws {
        setUpNumericDataset0()
        let sparql = """
            SELECT ?s (AVG(?o) AS ?x) (SUM(?o) AS ?y) WHERE {
                ?s ?p ?o
            }
            GROUP BY ?s
        """
        guard let data = sparql.data(using: .utf8) else { XCTFail(); return }
        guard var p = SPARQLParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let q = try p.parseQuery()
        self.measure {
            do {
                let results = try Array(eval(query: q))
                for r in results {
                    let x = r["x"]!
                    let y = r["y"]!
                    let s = r["s"]!
                    let avgValue = x.numericValue
                    let sumValue = y.numericValue
                    switch s.value {
                    case "http://example.org/s1":
                        let numbers = (MIN_VALUE0..<MAX_VALUE0)
                        let sum = numbers.reduce(0, +)
                        let avg = Double(sum)/Double(numbers.count)
                        XCTAssertEqual(avgValue, avg, accuracy: 0.5)
                        XCTAssertEqual(sumValue, Double(sum), accuracy: 0.5)
                    case "http://example.org/s2":
                        let third = Double(MAX_VALUE0)/3.0
                        let numbers = (MIN_VALUE0..<MAX_VALUE0).map { Double($0)-third }
                        let sum = numbers.reduce(0.0, +)
                        let avg = sum/Double(numbers.count)
                        XCTAssertEqual(avgValue, avg, accuracy: 1.5)
                        XCTAssertEqual(sumValue, sum, accuracy: 1.5)
                    default:
                        XCTFail()
                    }
                }
                XCTAssertEqual(results.count, 2)
            } catch let e {
                XCTFail("Failed to evaluate query: \(e)")
            }
        }
    }
}
