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

extension Node {
    var term : Term? {
        switch  self {
        case .bound(let t):
            return t
        default:
            return nil
        }
    }
}

class QueryRewritingTest: XCTestCase {
    var rewriter : SPARQLQueryRewriter!

    let iriNode : Node = .bound(Term(iri: "http://example.org/食べる"))
    let blankNode : Node = .bound(Term(value: "b1", type: .blank))
    let langLiteralNode : Node = .bound(Term(value: "foo", type: .language("en-US")))
    let integerNode : Node = .bound(Term(integer: 7))
    let xVariableNode : Node = .variable("x", binding: true)
    let yVariableNode : Node = .variable("y", binding: true)
    let yVariableNonBindingNode : Node = .variable("y", binding: false)

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
        XCTAssertEqual(rewritten, .triple(tp))
    }
    
    func testProjectionMergingPushdown() throws {
        let tp = TriplePattern(subject: blankNode, predicate: iriNode, object: xVariableNode)
        let proj1 = Set(["x", "y", "z"])
        let proj2 = Set(["a", "b", "x"])
        let a : Algebra = .project(.project(.distinct(.triple(tp)), proj1), proj2)
        
        let rewritten = try rewriter.simplify(algebra: a)
        XCTAssertEqual(rewritten, .distinct(.triple(tp)))
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
        // If projection immediately gets rid of a new binding produced by an extend(a, expr, var), get rid of the extend.
        let tp = TriplePattern(subject: xVariableNode, predicate: iriNode, object: yVariableNode)
        let tpXOnly = TriplePattern(subject: xVariableNode, predicate: iriNode, object: yVariableNonBindingNode)
        let proj = Set(["x"])
        let a : Algebra = .project(.extend(.triple(tp), .node(integerNode), "y"), proj)
        
        let rewritten = try rewriter.simplify(algebra: a)
        print(rewritten)
        XCTAssertEqual(rewritten, .triple(tpXOnly))
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
        let rewritten = try rewriter.simplify(algebra: a)
        XCTAssertEqual(rewritten, .filter(.triple(tp), Expression(integer: 3)))
    }
    
    func testProjectionTableRewriting() throws {
        let nodes = [xVariableNode, yVariableNode]
        let rows : [[Term?]] = [
            [iriNode.term, integerNode.term],
            [nil, integerNode.term],
            [blankNode.term, nil]
        ]
        let table : Algebra = .table(nodes, rows)
        
        let proj = Set(["y"])
        let a : Algebra = .project(table, proj)
        let rewritten = try rewriter.simplify(algebra: a)
        XCTAssertEqual(rewritten, .table([yVariableNode], [[integerNode.term], [integerNode.term], [nil]]))
    }
    
    func testSliceTableRewriting_limit_offset() throws {
        let nodes = [xVariableNode, yVariableNode]
        let rows : [[Term?]] = [
            [iriNode.term, integerNode.term],
            [nil, integerNode.term],
            [blankNode.term, nil],
            [nil, nil]
        ]
        let table : Algebra = .table(nodes, rows)
        
        let a : Algebra = .slice(table, 1, 2)
        print(a.serialize())
        let rewritten = try rewriter.simplify(algebra: a)
        print(rewritten.serialize())
        XCTAssertEqual(rewritten, .table(nodes, [
            [nil, integerNode.term],
            [blankNode.term, nil],
        ]))
    }
    
    func testSliceTableRewriting_limit() throws {
        let nodes = [xVariableNode, yVariableNode]
        let rows : [[Term?]] = [
            [iriNode.term, integerNode.term],
            [nil, integerNode.term],
            [blankNode.term, nil],
            [nil, nil]
        ]
        let table : Algebra = .table(nodes, rows)
        
        let a : Algebra = .slice(table, nil, 2)
        print(a.serialize())
        let rewritten = try rewriter.simplify(algebra: a)
        print(rewritten.serialize())
        XCTAssertEqual(rewritten, .table(nodes, [
            [iriNode.term, integerNode.term],
            [nil, integerNode.term],
        ]))
    }
    
    func testSliceTableRewriting_offset() throws {
        let nodes = [xVariableNode, yVariableNode]
        let rows : [[Term?]] = [
            [iriNode.term, integerNode.term],
            [nil, integerNode.term],
            [blankNode.term, nil],
            [nil, nil]
        ]
        let table : Algebra = .table(nodes, rows)
        
        let a : Algebra = .slice(table, 2, nil)
        let rewritten = try rewriter.simplify(algebra: a)
        XCTAssertEqual(rewritten, .table(nodes, [
            [blankNode.term, nil],
            [nil, nil]
            ]))
    }
    
    func testFilterTableInlining() throws {
        let nodes = [xVariableNode, yVariableNode]
        let rows : [[Term?]] = [
            [iriNode.term, integerNode.term],
            [blankNode.term, nil],
            [nil, integerNode.term],
            [nil, nil]
        ]
        let table : Algebra = .table(nodes, rows)
        let expr : Expression = .isnumeric(.node(yVariableNode))
        let a : Algebra = .filter(table, expr)
        
        print(a.serialize())
        let rewritten = try rewriter.simplify(algebra: a)
        print(rewritten.serialize())
        XCTAssertEqual(rewritten, .table(nodes, [
            [iriNode.term, integerNode.term],
            [nil, integerNode.term],
        ]))
    }
    
}
