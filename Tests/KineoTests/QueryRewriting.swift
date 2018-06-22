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

    let iriNode : Node = .bound(Term(iri: "http://example.org/食べる"))
    let blankNode : Node = .bound(Term(value: "b1", type: .blank))
    let langLiteralNode : Node = .bound(Term(value: "foo", type: .language("en-US")))
    let integerNode : Node = .bound(Term(integer: 7))
    let xVariableNode : Node = .variable("x", binding: true)
    let yVariableNode : Node = .variable("y", binding: true)

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
        let tp = TriplePattern(subject: blankNode, predicate: iriNode, object: xVariableNode)
        let proj = Set(["x"])
        let a : Algebra = .project(.distinct(.bgp([tp])), proj)
        
        let rewritten = try rewriter.simplify(algebra: a)
        XCTAssertEqual(rewritten, .distinct(.project(.bgp([tp]), proj)))
    }
    
    func testProjectionMerging() throws {
        let tp = TriplePattern(subject: blankNode, predicate: iriNode, object: xVariableNode)
        let proj1 = Set(["x", "y", "z"])
        let proj2 = Set(["a", "b", "x"])
        let a : Algebra = .project(.project(.triple(tp), proj1), proj2)
        
        let rewritten = try rewriter.simplify(algebra: a)
        XCTAssertEqual(rewritten, .project(.triple(tp), Set(["x"])))
    }
    
    func testProjectionMergingPushdown() throws {
        let tp = TriplePattern(subject: blankNode, predicate: iriNode, object: xVariableNode)
        let proj1 = Set(["x", "y", "z"])
        let proj2 = Set(["a", "b", "x"])
        let a : Algebra = .project(.project(.distinct(.triple(tp)), proj1), proj2)
        
        let rewritten = try rewriter.simplify(algebra: a)
        XCTAssertEqual(rewritten, .project(.distinct(.triple(tp)), Set(["x"])))
        //        print(rewritten.serialize())
    }
    
    func testProjectionTripleInlining() throws {
            let tp = TriplePattern(subject: xVariableNode, predicate: iriNode, object: yVariableNode)
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
            let tp = TriplePattern(subject: xVariableNode, predicate: iriNode, object: yVariableNode)
        let proj = Set(["x"])
        let a : Algebra = .project(.extend(.triple(tp), .node(integerNode), "y"), proj)
        
        let rewritten = try rewriter.simplify(algebra: a)
        XCTAssertEqual(rewritten, .project(.triple(tp), Set(["x"])))
    }

    func testProjectionDoubleBindElission() throws {
        let tp = TriplePattern(subject: xVariableNode, predicate: iriNode, object: yVariableNode)
        let proj = Set(["x", "z"])
        let a : Algebra = .project(
            .extend(
                .extend(
                    .triple(tp),
                    .node(.variable("y", binding: true)),
                    "z"
                ),
                .node(integerNode),
                "y"
            ),
            proj
        )
        
        let rewritten = try rewriter.simplify(algebra: a)
        print(a.serialize())
        print(rewritten.serialize())
        XCTAssertEqual(rewritten, .project(.extend(.triple(tp), .node(.variable("y", binding: true)), "z"), Set(["x", "z"])))
    }

    func testSlicePushdown() throws {
        let tp = TriplePattern(subject: blankNode, predicate: iriNode, object: xVariableNode)
        let a : Algebra = .slice(.distinct(.bgp([tp])), 1, 2)
        let rewritten = try rewriter.simplify(algebra: a)
        XCTAssertEqual(rewritten, .distinct(.slice(.bgp([tp]), 1, 2)))
    }

    
    func testConstantFolding_true() throws {
        let tp = TriplePattern(subject: blankNode, predicate: iriNode, object: xVariableNode)
        let expr : Expression = .node(.bound(.trueValue))
        let a : Algebra = .filter(.triple(tp), expr)
        let rewritten = try rewriter.simplify(algebra: a)
        XCTAssertEqual(rewritten, .triple(tp))
    }
    
    func testExpressionConstantFolding_false() throws {
        let tp = TriplePattern(subject: blankNode, predicate: iriNode, object: xVariableNode)
        let expr : Expression = .node(.bound(.falseValue))
        let a : Algebra = .filter(.triple(tp), expr)
        let rewritten = try rewriter.simplify(algebra: a)
        XCTAssertEqual(rewritten, .unionIdentity)
    }
    
    func testExpressionConstantFolding_addition() throws {
        let tp = TriplePattern(subject: blankNode, predicate: iriNode, object: xVariableNode)
        let expr : Expression = .add(Expression(integer: 1), Expression(integer: 2))
        let a : Algebra = .filter(.triple(tp), expr)
        print(a.serialize())
        let rewritten = try rewriter.simplify(algebra: a)
        print(rewritten.serialize())
        XCTAssertEqual(rewritten, .filter(.triple(tp), Expression(integer: 3)))
    }
    
}
