import Foundation
import XCTest
import Kineo
import SPARQLSyntax

#if os(Linux)
extension GraphAPITest {
    static var allTests : [(String, (GraphAPITest) -> () throws -> Void)] {
        return [
            ("testGraphAPI", testGraphAPI),
        ]
    }
}
#endif

class GraphAPITest: XCTestCase {
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func load<T: MutableQuadStoreProtocol>(turtle: String, into store: T, graph: Term, version: Version) throws {
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

    func testGraphAPI() throws {
        let turtle = """
        @base <http://example.org/base/> .
        _:greg a foaf:Person ; foaf:name "Greg", "Gregory" .
        <tag:g> a foaf:Person ; foaf:nick "Greg" .

        <list1> <values> (1 3 9 4 2) .
        """
        let s = try SQLiteQuadStore()
        let g = Term(iri: "http://example.org/a")
        try load(turtle: turtle, into: s, graph: g, version: 0)
        
        let graph = s.graph(g)
        XCTAssertEqual(graph.term, g)
        let names = try graph.extensionOf(Term(iri: "http://xmlns.com/foaf/0.1/name"))
        XCTAssertEqual(names.count, 2)
        
        let v1 = graph.vertex(Term(iri: "tag:g"))
        let out = try v1.outgoing(Term(iri: "http://xmlns.com/foaf/0.1/nick"))
        XCTAssertEqual(out.count, 1)
        let name = out[0]
        
        let graphs = try name.graphs()
        XCTAssertEqual(graphs.count, 1)
        
        let incoming = try name.incoming(Term(iri: "http://xmlns.com/foaf/0.1/name"))
        XCTAssertEqual(incoming.count, 1)
        let v2 = incoming[0]
        XCTAssertEqual(v2.term.value, "greg")
        
        let lists = try graph.extensionOf(Term(iri: "http://example.org/base/values"))
        XCTAssertEqual(lists.count, 1)
        let list = lists[0].1
        let v = try list.listElements()
        XCTAssertNotNil(v)
        let values = v!
        let expected = [1,3,9,4,2].map { Term(integer: $0) }
        XCTAssertEqual(values.map { $0.term }, expected)
    }
}
