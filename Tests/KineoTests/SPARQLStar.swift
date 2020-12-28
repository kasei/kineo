import XCTest
import Kineo
import SPARQLSyntax

class SPARQLStarTests: XCTestCase {
    override func setUp() {
        self.graph = Term(iri: "http://example.org/graph")
        super.setUp()
    }

    var graph: Term!
  
    var testStarQuads: [Quad] {
        let parser = NTriplesParser(reader: "")
//        let graph = Term(iri: "http://example.org/graph")
        guard let b1 = parser.parseQuad(line: "<http://example.org/Berlin> <http://xmlns.com/foaf/0.1/name> \"Berlin\"", graph: graph) else { fatalError() }
        guard let b2 = parser.parseQuad(line: "<http://example.org/Berlin> <http://xmlns.com/foaf/0.1/homepage> <http://www.berlin.de/en/>", graph: graph) else { fatalError() }
        guard let s = parser.parseQuad(line: "<http://example.org/Santa_Monica> <http://xmlns.com/foaf/0.1/name> \"Santa Monica\"", graph: graph) else { fatalError() }
        
        let q0_id = Term(value: "0", type: .datatype(.custom(MemoryQuadStore.statementIDDatatype)))
        let q1_id = Term(value: "1", type: .datatype(.custom(MemoryQuadStore.statementIDDatatype)))
        let q2_id = Term(value: "2", type: .datatype(.custom(MemoryQuadStore.statementIDDatatype)))
        let star0 = Quad(subject: q0_id, predicate: Term(iri: "http://example.org/accordingTo"), object: Term(string: "Wikipedia"), graph: graph)
        let star1 = Quad(subject: q1_id, predicate: Term(iri: "http://example.org/accordingTo"), object: Term(string: "Wikipedia"), graph: graph)
        let star2 = Quad(subject: q2_id, predicate: Term(iri: "http://example.org/accordingTo"), object: Term(string: "City of Santa Monica"), graph: graph)
        let quads = [b1, b2, s, star0, star1, star2]
        return quads
    }
    
    var testQuads: [Quad] {
        let parser = NTriplesParser(reader: "")
//        let graph = Term(iri: "http://example.org/graph")
        guard let b1 = parser.parseQuad(line: "<http://example.org/Berlin> <http://xmlns.com/foaf/0.1/name> \"Berlin\"", graph: graph) else { fatalError() }
        guard let b2 = parser.parseQuad(line: "<http://example.org/Berlin> <http://xmlns.com/foaf/0.1/homepage> <http://www.berlin.de/en/>", graph: graph) else { fatalError() }
        guard let s = parser.parseQuad(line: "_:a <http://purl.org/dc/elements/1.1/title> \"Santa Monica\"", graph: graph) else { fatalError() }
        
        let numbers = Term(value: "http://example.org/numbers", type: .iri)
        guard let n0 = parser.parseQuad(line: "_:n1 <http://xmlns.com/foaf/0.1/name> \"a number\"", graph: numbers) else { fatalError() }
        guard let n1 = parser.parseQuad(line: "_:n1 <http://example.org/value> \"32.7\"^^<http://www.w3.org/2001/XMLSchema#float>", graph: numbers) else { fatalError() }
        guard let n2 = parser.parseQuad(line: "_:n2 <http://example.org/value> \"-118\"^^<http://www.w3.org/2001/XMLSchema#integer>", graph: numbers) else { fatalError() }
        
        let other = Term(value: "http://example.org/other", type: .iri)
        guard let x1 = parser.parseQuad(line: "_:x <http://example.org/p> \"hello\"@en", graph: other) else { fatalError() }
        
        let quads = [b1, b2, s, n0, n1, n2, x1]
        return quads
    }
    
    func testStoreQuadIDs() throws {
        let store = MemoryQuadStore()
        try store.load(version: 0, quads: self.testQuads)
        XCTAssertEqual(store.count, 7)
        
        let quads = self.testQuads
        for (expectedID, q) in quads.enumerated() {
            guard let idTerm = store.id(for: q) else { continue }
            let gotID = Int(idTerm.value)
            XCTAssertEqual(gotID, expectedID)
            XCTAssertEqual(idTerm.type, TermType.datatype(.custom(MemoryQuadStore.statementIDDatatype)))
            let q2 = store.quad(withIdentifier: idTerm)
            XCTAssertEqual(q2, q)
        }
    }
    
    func eval<S: RDFStarStoreProtocol>(query: Query, store: S, in graph: Term) throws -> AnyIterator<SPARQLResultSolution<Term>> {
        let dataset = store.dataset(withDefault: graph)
        let e = SimpleQueryEvaluator(store: store, dataset: dataset)
        let results = try e.evaluate(query: query)
        guard case let .bindings(_, seq) = results else { fatalError() }
        return AnyIterator(seq.makeIterator())
    }

    func testSimpleSPARQLStarQuery_noData() throws {
        let store = MemoryQuadStore()
        try store.load(version: 0, quads: self.testQuads)
        XCTAssertEqual(store.count, 7)
        
        let data = """
        SELECT * WHERE {
            << ?s <http://xmlns.com/foaf/0.1/name> ?o >> ?y ?z
        }
        """.data(using: .utf8)!
        guard let p = SPARQLStarParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let q = try p.parseQuery()
        let results = try Array(eval(query: q, store: store, in: graph))
        XCTAssertEqual(results.count, 0) // there are no embedded triples in self.testQuads
        
    }

    func testSimpleSPARQLStarQuery() throws {
        let store = MemoryQuadStore()
        try store.load(version: 0, quads: self.testStarQuads)
        XCTAssertEqual(store.count, 6)
        
        let data = """
        SELECT * WHERE {
            << ?s <http://xmlns.com/foaf/0.1/name> ?o >> ?y ?z
        }
        """.data(using: .utf8)!
        guard let p = SPARQLStarParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let q = try p.parseQuery()
        let results = try Array(eval(query: q, store: store, in: graph))
        XCTAssertEqual(results.count, 2)
        let expectedSZ = [
            "http://example.org/Berlin": "Wikipedia",
            "http://example.org/Santa_Monica": "City of Santa Monica",
        ]
        var gotSZ = [String:String]()
        for r in results {
            let b = r.bindings
            let keys = Set(b.keys)
            XCTAssertEqual(keys, Set(["s", "o", "y", "z"]))
            if let s = r["s"], let z = r["z"] {
                gotSZ[s.value] = z.value
            }
        }
        XCTAssertEqual(gotSZ, expectedSZ)
    }
}
