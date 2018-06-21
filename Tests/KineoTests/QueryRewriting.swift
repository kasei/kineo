import XCTest
import Kineo
import SPARQLSyntax

#if os(Linux)
extension QueryRewritingTest {
    static var allTests : [(String, (QueryRewritingTest) -> () throws -> Void)] {
        return [
            ("testProjectionPushdown", testProjectionPushdown),
        ]
    }
}
#endif

class QueryRewritingTest: XCTestCase {
    var rewriter : SPARQLQueryRewriter!
    
    override func setUp() {
        rewriter = SPARQLQueryRewriter()
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testProjectionPushdown() throws {
        let i : Node = .bound(Term(iri: "http://example.org/食べる"))
        let b : Node = .bound(Term(value: "b1", type: .blank))
        let v : Node = .variable("x", binding: true)
        let tp = TriplePattern(subject: b, predicate: i, object: v)
        let proj = Set(["x"])
        let a : Algebra = .project(.distinct(.triple(tp)), proj)
        
        let rewritten = try rewriter.simplify(algebra: a)
        XCTAssertEqual(rewritten, .distinct(.project(.triple(tp), proj)))
    }
    
    func testProjectionMerging() throws {
        let i : Node = .bound(Term(iri: "http://example.org/食べる"))
        let b : Node = .bound(Term(value: "b1", type: .blank))
        let v : Node = .variable("x", binding: true)
        let tp = TriplePattern(subject: b, predicate: i, object: v)
        let proj1 = Set(["x", "y", "z"])
        let proj2 = Set(["a", "b", "x"])
        let a : Algebra = .project(.project(.triple(tp), proj1), proj2)
        
        let rewritten = try rewriter.simplify(algebra: a)
        XCTAssertEqual(rewritten, .project(.triple(tp), Set(["x"])))
    }
    
    func testProjectionMergingPushdown() throws {
        let i : Node = .bound(Term(iri: "http://example.org/食べる"))
        let b : Node = .bound(Term(value: "b1", type: .blank))
        let l : Node = .bound(Term(value: "foo", type: .language("en-US")))
        let d : Node = .bound(Term(integer: 7))
        let v : Node = .variable("x", binding: true)
        let tp = TriplePattern(subject: b, predicate: i, object: v)
        let proj1 = Set(["x", "y", "z"])
        let proj2 = Set(["a", "b", "x"])
        let a : Algebra = .project(.project(.distinct(.triple(tp)), proj1), proj2)
        
        let rewritten = try rewriter.simplify(algebra: a)
        XCTAssertEqual(rewritten, .project(.distinct(.triple(tp)), Set(["x"])))
        //        print(rewritten.serialize())
    }
    
    func testProjectionTripleInlining() throws {
        let i : Node = .bound(Term(iri: "http://example.org/食べる"))
        let b : Node = .bound(Term(value: "b1", type: .blank))
        let l : Node = .bound(Term(value: "foo", type: .language("en-US")))
        let d : Node = .bound(Term(integer: 7))
        let x : Node = .variable("x", binding: true)
        let y : Node = .variable("y", binding: true)
        let tp = TriplePattern(subject: x, predicate: i, object: y)
        let proj = Set(["x"])
        let a : Algebra = .project(.triple(tp), proj)
        
        let rewritten = try rewriter.simplify(algebra: a)
        print(rewritten.serialize())
        guard case let .triple(t) = rewritten else { XCTFail(); return }
        let object = t.object
        guard case let .variable("y", binding: binding) = object else { XCTFail(); return }
        XCTAssertFalse(binding, "Projection changed triple pattern node to be non-binding")
        print(rewritten.serialize())
    }
    
    func testProjectionBindElission() throws {
        let i : Node = .bound(Term(iri: "http://example.org/食べる"))
        let d : Node = .bound(Term(integer: 7))
        let x : Node = .variable("x", binding: true)
        let y : Node = .variable("y", binding: true)
        let tp = TriplePattern(subject: x, predicate: i, object: y)
        let proj = Set(["x"])
        let a : Algebra = .project(.extend(.triple(tp), .node(d), "y"), proj)
        
        let rewritten = try rewriter.simplify(algebra: a)
        XCTAssertEqual(rewritten, .project(.triple(tp), Set(["x"])))
    }

    func testProjectionDoubleBindElission() throws {
        let i : Node = .bound(Term(iri: "http://example.org/食べる"))
        let b : Node = .bound(Term(value: "b1", type: .blank))
        let l : Node = .bound(Term(value: "foo", type: .language("en-US")))
        let d : Node = .bound(Term(integer: 7))
        let x : Node = .variable("x", binding: true)
        let y : Node = .variable("y", binding: true)
        let tp = TriplePattern(subject: x, predicate: i, object: y)
        let proj = Set(["x", "z"])
        let a : Algebra = .project(
            .extend(
                .extend(
                    .triple(tp),
                    .node(.variable("y", binding: true)),
                    "z"
                ),
                .node(d),
                "y"
            ),
            proj
        )
        
        let rewritten = try rewriter.simplify(algebra: a)
        print(a.serialize())
        print(rewritten.serialize())
        XCTAssertEqual(rewritten, .project(.extend(.triple(tp), .node(.variable("y", binding: true)), "z"), Set(["x", "z"])))
    }
}
