import XCTest
import Foundation
@testable import Kineo

#if os(Linux)
extension AlgebraTest {
    static var allTests : [(String, (AlgebraTest) -> () throws -> Void)] {
        return [
            ("testReplacement1", testReplacement1),
            ("testReplacement2", testReplacement2),
            ("testJoinIdentityReplacement", testJoinIdentityReplacement),
            ("testFilterExpressionReplacement", testFilterExpressionReplacement),
            ("testExpressionReplacement", testExpressionReplacement),
            ("testNodeBinding", testNodeBinding),
            ("testNodeBindingWithProjection", testNodeBindingWithProjection),
        ]
    }
}
#endif

// swiftlint:disable type_body_length
class AlgebraTest: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testReplacement1() {
        let subj: Node = .bound(Term(value: "b", type: .blank))
        let pred: Node = .bound(Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", type: .iri))
        let obj: Node = .variable("o", binding: true)
        let t = TriplePattern(subject: subj, predicate: pred, object: obj)
        let algebra: Algebra = .bgp([t])

        let rewrite = algebra.replace { (algebra: Algebra) in
            switch algebra {
            case .bgp(_):
                return .joinIdentity
            default:
                return nil
            }
        }

        guard case .joinIdentity = rewrite else {
            XCTFail("Unexpected rewritten algebra: \(rewrite.serialize())")
            return
        }

        XCTAssert(true)
    }

    func testReplacement2() {
        let subj: Node = .bound(Term(value: "b", type: .blank))
        let type: Node = .bound(Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", type: .iri))
        let name: Node = .bound(Term(value: "http://xmlns.com/foaf/0.1/name", type: .iri))
        let vtype: Node = .variable("type", binding: true)
        let vname: Node = .variable("name", binding: true)
        let t1 = TriplePattern(subject: subj, predicate: type, object: vtype)
        let t2 = TriplePattern(subject: subj, predicate: name, object: vname)
        let algebra: Algebra = .innerJoin(.bgp([t1]), .triple(t2))

        let rewrite = algebra.replace { (algebra: Algebra) in
            switch algebra {
            case .bgp(_):
                return .joinIdentity
            default:
                return nil
            }
        }

        guard case .innerJoin(.joinIdentity, .triple(_)) = rewrite else {
            XCTFail("Unexpected rewritten algebra: \(rewrite.serialize())")
            return
        }

        XCTAssert(true)
    }

    func testJoinIdentityReplacement() {
        let subj: Node = .bound(Term(value: "b", type: .blank))
        let name: Node = .bound(Term(value: "http://xmlns.com/foaf/0.1/name", type: .iri))
        let vname: Node = .variable("name", binding: true)
        let t = TriplePattern(subject: subj, predicate: name, object: vname)
        let algebra: Algebra = .innerJoin(.joinIdentity, .triple(t))
        let rewrite = algebra.replace { (algebra: Algebra) in
            switch algebra {
            case .innerJoin(.joinIdentity, let a), .innerJoin(let a, .joinIdentity):
                return a
            default:
                return nil
            }
        }

        guard case .triple(_) = rewrite else {
            XCTFail("Unexpected rewritten algebra: \(rewrite.serialize())")
            return
        }

        XCTAssert(true)
    }

    func testFilterExpressionReplacement() {
        let subj: Node = .bound(Term(value: "b", type: .blank))
        let name: Node = .bound(Term(value: "http://xmlns.com/foaf/0.1/name", type: .iri))
        let greg: Node = .bound(Term(value: "Gregory", type: .language("en")))
        let vname: Node = .variable("name", binding: true)
        let expr: Expression = .eq(.node(vname), .node(greg))

        let t = TriplePattern(subject: subj, predicate: name, object: vname)
        let algebra: Algebra = .filter(.triple(t), expr)

        let rewrite = algebra.replace { (expr: Expression) in
            switch expr {
            case .eq(let a, let b):
                return .ne(a, b)
            default:
                return nil
            }
        }

        guard case .filter(.triple(_), .ne(_, _)) = rewrite else {
            XCTFail("Unexpected rewritten algebra: \(rewrite.serialize())")
            return
        }

        XCTAssert(true)
    }

    func testExpressionReplacement() {
        let greg: Node = .bound(Term(value: "Gregory", type: .language("en")))
        let vname: Node = .variable("name", binding: true)
        let expr: Expression = .eq(.node(vname), .node(greg))

        let rewrite = expr.replace { (expr: Expression) in
            switch expr {
            case .eq(let a, let b):
                return .ne(a, b)
            default:
                return nil
            }
        }

        XCTAssertEqual(expr.description, "(?name == \"Gregory\"@en)")
        XCTAssertEqual(rewrite.description, "(?name != \"Gregory\"@en)")
    }

    func testNodeBinding() {
        let subj: Node = .bound(Term(value: "b", type: .blank))
        let type: Node = .bound(Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", type: .iri))
        let name: Node = .bound(Term(value: "http://xmlns.com/foaf/0.1/name", type: .iri))
        let vtype: Node = .variable("type", binding: true)
        let vname: Node = .variable("name", binding: true)
        let t1 = TriplePattern(subject: subj, predicate: type, object: vtype)
        let t2 = TriplePattern(subject: subj, predicate: name, object: vname)
        let algebra: Algebra = .project(.innerJoin(.triple(t1), .triple(t2)), ["name", "type"])

        let rewrite = algebra.bind("type", to: .bound(Term(value: "http://xmlns.com/foaf/0.1/Person", type: .iri)))
        guard case .project(.innerJoin(_, _), let projection) = rewrite else {
            XCTFail("Unexpected rewritten algebra: \(rewrite.serialize())")
            return
        }
        XCTAssertEqual(projection, ["name"])
    }

    func testNodeBindingWithProjection() {
        let subj: Node = .bound(Term(value: "b", type: .blank))
        let type: Node = .bound(Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", type: .iri))
        let name: Node = .bound(Term(value: "http://xmlns.com/foaf/0.1/name", type: .iri))
        let vtype: Node = .variable("type", binding: true)
        let vname: Node = .variable("name", binding: true)
        let t1 = TriplePattern(subject: subj, predicate: type, object: vtype)
        let t2 = TriplePattern(subject: subj, predicate: name, object: vname)
        let algebra: Algebra = .project(.innerJoin(.triple(t1), .triple(t2)), ["name", "type"])

        let person: Node = .bound(Term(value: "http://xmlns.com/foaf/0.1/Person", type: .iri))
        let rewrite = algebra.bind("type", to: person, preservingProjection: true)
        guard case .project(.extend(.innerJoin(_, _), .node(person), "type"), let projection) = rewrite else {
            XCTFail("Unexpected rewritten algebra: \(rewrite.serialize())")
            return
        }
        XCTAssertEqual(projection, ["name", "type"])
    }
}
