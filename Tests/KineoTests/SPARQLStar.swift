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
        
        let q0_id = Term(value: "T 1 2 3", type: .datatype(.custom(MemoryQuadStore.embeddedStatementDatatype)))
        let q1_id = Term(value: "T 1 5 6", type: .datatype(.custom(MemoryQuadStore.embeddedStatementDatatype)))
        let q2_id = Term(value: "T 7 2 8", type: .datatype(.custom(MemoryQuadStore.embeddedStatementDatatype)))
        let q3_id = Term(value: "T 1 2 8", type: .datatype(.custom(MemoryQuadStore.embeddedStatementDatatype)))

        let star0 = Quad(subject: q0_id, predicate: Term(iri: "http://example.org/accordingTo"), object: Term(string: "Wikipedia"), graph: graph)
        let star1 = Quad(subject: q1_id, predicate: Term(iri: "http://example.org/accordingTo"), object: Term(string: "Wikipedia"), graph: graph)
        let star2 = Quad(subject: q2_id, predicate: Term(iri: "http://example.org/accordingTo"), object: Term(string: "City of Santa Monica"), graph: graph)
        
        // this is a non-asserted triple used as a subject
        let star3 = Quad(subject: q3_id, predicate: Term(iri: "http://example.org/accordingTo"), object: Term(string: "Misinformation"), graph: graph)
        
        let quads = [b1, b2, s, star0, star1, star2, star3]
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
        try store.load(version: 0, quads: self.testStarQuads)
        XCTAssertEqual(store.count, 7)
        
        let qids = Set(store.compactMap { store.id(for: $0) })
        XCTAssertEqual(qids, Set([
            Term(value: "Q 1 2 3 4", type: .datatype(.custom(MemoryQuadStore.embeddedStatementDatatype))),
            Term(value: "Q 1 5 6 4", type: .datatype(.custom(MemoryQuadStore.embeddedStatementDatatype))),
            Term(value: "Q 7 2 8 4", type: .datatype(.custom(MemoryQuadStore.embeddedStatementDatatype))),
            Term(value: "Q T 1 2 3 10 11 4", type: .datatype(.custom(MemoryQuadStore.embeddedStatementDatatype))),
            Term(value: "Q T 1 5 6 10 11 4", type: .datatype(.custom(MemoryQuadStore.embeddedStatementDatatype))),
            Term(value: "Q T 7 2 8 10 14 4", type: .datatype(.custom(MemoryQuadStore.embeddedStatementDatatype))),
            Term(value: "Q T 1 2 8 10 16 4", type: .datatype(.custom(MemoryQuadStore.embeddedStatementDatatype))),
        ]))
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
        XCTAssertEqual(store.count, 7)

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

    func testUnassertedSPARQLStarQuery() throws {
        let store = MemoryQuadStore()
        try store.load(version: 0, quads: self.testStarQuads)
        XCTAssertEqual(store.count, 7)

        let data = """
        SELECT * WHERE {
            << ?s <http://xmlns.com/foaf/0.1/name> ?o >> <http://example.org/accordingTo> "Misinformation"
        }
        """.data(using: .utf8)!
        guard let p = SPARQLStarParser(data: data) else { fatalError("Failed to construct SPARQL parser") }
        let q = try p.parseQuery()
        let results = try Array(eval(query: q, store: store, in: graph))
        XCTAssertEqual(results.count, 1)
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
