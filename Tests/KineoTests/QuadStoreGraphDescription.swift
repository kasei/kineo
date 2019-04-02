import XCTest
import Kineo
import SPARQLSyntax

#if os(Linux)
extension QuadStoreGraphDescriptionTest {
    static var allTests : [(String, (QuadStoreGraphDescriptionTest) -> () throws -> Void)] {
        return [
            ("testGraphPredicates", testGraphPredicates),
        ]
    }
}
#endif

class QuadStoreGraphDescriptionTest: XCTestCase {
    var store: MemoryQuadStore!
    
    override func setUp() {
        super.setUp()
        self.store = MemoryQuadStore(version: 0)
    }

    func load(turtle: String, graph: Term, version: Version) throws {
        let PREFIXES = "@prefix foaf: <http://xmlns.com/foaf/0.1/> .\n"
        let parser = RDFParserCombined(base: "http://example.org/", produceUniqueBlankIdentifiers: false)
        var quads = [Quad]()
        try parser.parse(string: "\(PREFIXES) \(turtle)", syntax: .turtle) { (s, p, o) in
            let t = Triple(subject: s, predicate: p, object: o)
            let q = Quad(triple: t, graph: graph)
            quads.append(q)
        }
        try store.load(version: version, quads: quads)
    }
    
    func testGraphPredicates() throws {
        let turtle = """
        _:alice a foaf:Person ; foaf:name "Alice" ; foaf:knows _:bob .
        _:bob a foaf:Person ; foaf:name "Bob" ; foaf:knows _:alice .
        _:eve a foaf:Agent ; foaf:name "Eve" ; foaf:knows _:alice, _:bob .
        """
        let g = Term(iri: "http://example.org/people")
        try load(turtle: turtle, graph: g, version: 1)
        let d = try store.graphDescription(g, limit: 100)
        
        let foaf = Namespace(value: "http://xmlns.com/foaf/0.1/")
        let predStrings = [foaf.name, foaf.knows, Namespace.rdf.type]
        let preds = predStrings.map { Term(iri: $0) }
        XCTAssertEqual(d.triplesCount, 10)
        XCTAssertEqual(d.predicates, Set(preds))
        XCTAssertEqual(d.histograms.count, 1)
        let h = d.histograms.first { $0.position == .predicate }!
        XCTAssertEqual(h.buckets.count, preds.count)
        XCTAssertEqual(Set(h.buckets.map { $0.term }), Set(preds))
        let counts = Dictionary(uniqueKeysWithValues: h.buckets.map { ($0.term, $0.count) })
        XCTAssertEqual(counts, [
            Term(iri: foaf.name): 3,
            Term(iri: foaf.knows): 4,
            Term(iri: Namespace.rdf.type): 3,
            ])
    }
}
