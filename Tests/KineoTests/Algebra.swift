import XCTest
import Foundation
import Kineo

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
        let subj : Node = .bound(Term(value: "b", type: .blank))
        let pred : Node = .bound(Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", type: .iri))
        let obj : Node = .variable("o", binding: true)
        let t = TriplePattern(subject: subj, predicate: pred, object: obj)
        let algebra : Algebra = .bgp([t])

        let rewrite = algebra.replace { (algebra : Algebra) in
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
        let subj : Node = .bound(Term(value: "b", type: .blank))
        let type : Node = .bound(Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", type: .iri))
        let name : Node = .bound(Term(value: "http://xmlns.com/foaf/0.1/name", type: .iri))
        let vtype : Node = .variable("type", binding: true)
        let vname : Node = .variable("name", binding: true)
        let t1 = TriplePattern(subject: subj, predicate: type, object: vtype)
        let t2 = TriplePattern(subject: subj, predicate: name, object: vname)
        let algebra : Algebra = .innerJoin(.bgp([t1]), .triple(t2))

        let rewrite = algebra.replace { (algebra : Algebra) in
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
        let subj : Node = .bound(Term(value: "b", type: .blank))
        let name : Node = .bound(Term(value: "http://xmlns.com/foaf/0.1/name", type: .iri))
        let vname : Node = .variable("name", binding: true)
        let t = TriplePattern(subject: subj, predicate: name, object: vname)
        let algebra : Algebra = .innerJoin(.joinIdentity, .triple(t))
        let rewrite = algebra.replace { (algebra : Algebra) in
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
        let subj : Node = .bound(Term(value: "b", type: .blank))
        let name : Node = .bound(Term(value: "http://xmlns.com/foaf/0.1/name", type: .iri))
        let greg : Node = .bound(Term(value: "Gregory", type: .language("en")))
        let vname : Node = .variable("name", binding: true)
        let expr : Expression = .eq(.node(vname), .node(greg))

        let t = TriplePattern(subject: subj, predicate: name, object: vname)
        let algebra : Algebra = .filter(.triple(t), expr)

        let rewrite = algebra.replace { (expr : Expression) in
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
        let greg : Node = .bound(Term(value: "Gregory", type: .language("en")))
        let vname : Node = .variable("name", binding: true)
        let expr : Expression = .eq(.node(vname), .node(greg))

        let rewrite = expr.replace { (expr : Expression) in
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
        let subj : Node = .bound(Term(value: "b", type: .blank))
        let type : Node = .bound(Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", type: .iri))
        let name : Node = .bound(Term(value: "http://xmlns.com/foaf/0.1/name", type: .iri))
        let vtype : Node = .variable("type", binding: true)
        let vname : Node = .variable("name", binding: true)
        let t1 = TriplePattern(subject: subj, predicate: type, object: vtype)
        let t2 = TriplePattern(subject: subj, predicate: name, object: vname)
        let algebra : Algebra = .project(.innerJoin(.triple(t1), .triple(t2)), ["name", "type"])

        let rewrite = algebra.bind("type", to: .bound(Term(value: "http://xmlns.com/foaf/0.1/Person", type: .iri)))
        guard case .project(.innerJoin(_, _), let projection) = rewrite else {
            XCTFail("Unexpected rewritten algebra: \(rewrite.serialize())")
            return
        }
        XCTAssertEqual(projection, ["name"])
    }

    func testNodeBindingWithProjection() {
        let subj : Node = .bound(Term(value: "b", type: .blank))
        let type : Node = .bound(Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", type: .iri))
        let name : Node = .bound(Term(value: "http://xmlns.com/foaf/0.1/name", type: .iri))
        let vtype : Node = .variable("type", binding: true)
        let vname : Node = .variable("name", binding: true)
        let t1 = TriplePattern(subject: subj, predicate: type, object: vtype)
        let t2 = TriplePattern(subject: subj, predicate: name, object: vname)
        let algebra : Algebra = .project(.innerJoin(.triple(t1), .triple(t2)), ["name", "type"])

        let person : Node = .bound(Term(value: "http://xmlns.com/foaf/0.1/Person", type: .iri))
        let rewrite = algebra.bind("type", to: person, preservingProjection: true)
        guard case .project(.extend(.innerJoin(_, _), .node(person), "type"), let projection) = rewrite else {
            XCTFail("Unexpected rewritten algebra: \(rewrite.serialize())")
            return
        }
        XCTAssertEqual(projection, ["name", "type"])
    }

    func testProjectedSPARQLTokens() {
        let subj : Node = .bound(Term(value: "b", type: .blank))
        let type : Node = .bound(Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", type: .iri))
        let name : Node = .bound(Term(value: "http://xmlns.com/foaf/0.1/name", type: .iri))
        let vtype : Node = .variable("type", binding: true)
        let vname : Node = .variable("name", binding: true)
        let t1 = TriplePattern(subject: subj, predicate: type, object: vtype)
        let t2 = TriplePattern(subject: subj, predicate: name, object: vname)
        let algebra : Algebra = .project(.innerJoin(.triple(t1), .triple(t2)), ["name", "type"])
        let tokens = Array(algebra.sparqlTokens(depth: 0))
        XCTAssertEqual(tokens, [
            .keyword("SELECT"),
            ._var("name"),
            ._var("type"),
            .keyword("WHERE"),
            .lbrace,
            .bnode("b"),
            .keyword("A"),
            ._var("type"),
            .dot,
            .bnode("b"),
            .iri("http://xmlns.com/foaf/0.1/name"),
            ._var("name"),
            .dot,
            .rbrace,
            ])
    }

    func testNonProjectedSPARQLTokens() {
        let subj : Node = .bound(Term(value: "b", type: .blank))
        let type : Node = .bound(Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", type: .iri))
        let name : Node = .bound(Term(value: "http://xmlns.com/foaf/0.1/name", type: .iri))
        let vtype : Node = .variable("type", binding: true)
        let vname : Node = .variable("name", binding: true)
        let t1 = TriplePattern(subject: subj, predicate: type, object: vtype)
        let t2 = TriplePattern(subject: subj, predicate: name, object: vname)
        let algebra : Algebra = .innerJoin(.triple(t1), .triple(t2))

        let tokens = Array(algebra.sparqlTokens(depth: 0))
        XCTAssertEqual(tokens, [
            .bnode("b"),
            .keyword("A"),
            ._var("type"),
            .dot,
            .bnode("b"),
            .iri("http://xmlns.com/foaf/0.1/name"),
            ._var("name"),
            .dot,
            ])

        let qtokens = Array(algebra.sparqlQueryTokens())
        XCTAssertEqual(qtokens, [
            .keyword("SELECT"),
            ._var("name"),
            ._var("type"),
            .keyword("WHERE"),
            .lbrace,
            .bnode("b"),
            .keyword("A"),
            ._var("type"),
            .dot,
            .bnode("b"),
            .iri("http://xmlns.com/foaf/0.1/name"),
            ._var("name"),
            .dot,
            .rbrace,
            ])
    }

    func testQueryModifiedSPARQLSerialization1() {
        let subj : Node = .bound(Term(value: "b", type: .blank))
        let type : Node = .bound(Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", type: .iri))
        let name : Node = .bound(Term(value: "http://xmlns.com/foaf/0.1/name", type: .iri))
        let vtype : Node = .variable("type", binding: true)
        let vname : Node = .variable("name", binding: true)
        let t1 = TriplePattern(subject: subj, predicate: type, object: vtype)
        let t2 = TriplePattern(subject: subj, predicate: name, object: vname)
        let algebra : Algebra = .slice(.order(.innerJoin(.triple(t1), .triple(t2)), [(false, .node(.variable("name", binding: false)))]), nil, 5)

        let qtokens = Array(algebra.sparqlQueryTokens())
        XCTAssertEqual(qtokens, [
            .keyword("SELECT"),
            ._var("name"),
            ._var("type"),
            .keyword("WHERE"),
            .lbrace,
            .bnode("b"),
            .keyword("A"),
            ._var("type"),
            .dot,
            .bnode("b"),
            .iri("http://xmlns.com/foaf/0.1/name"),
            ._var("name"),
            .dot,
            .rbrace,
            .keyword("ORDER"),
            .keyword("BY"),
            .keyword("DESC"),
            .lparen,
            ._var("name"),
            .rparen,
            .keyword("LIMIT"),
            .integer("5")
            ])

        let s = SPARQLSerializer()
        let sparql = s.serialize(algebra.sparqlQueryTokens())
        let expected = "SELECT ?name ?type WHERE { _:b a ?type . _:b <http://xmlns.com/foaf/0.1/name> ?name . } ORDER BY DESC ( ?name ) LIMIT 5"

        XCTAssertEqual(sparql, expected)
    }


    func testQueryModifiedSPARQLSerialization2() {
        let subj : Node = .bound(Term(value: "b", type: .blank))
        let name : Node = .bound(Term(value: "http://xmlns.com/foaf/0.1/name", type: .iri))
        let vname : Node = .variable("name", binding: true)
        let t = TriplePattern(subject: subj, predicate: name, object: vname)
        let algebra : Algebra = .order(.slice(.triple(t), nil, 5), [(false, .node(.variable("name", binding: false)))])

        let qtokens = Array(algebra.sparqlQueryTokens())
        // SELECT * WHERE { { SELECT * WHERE { _:b foaf:name ?name . } LIMIT 5 } } ORDER BY DESC(?name)
        XCTAssertEqual(qtokens, [
            .keyword("SELECT"),
            ._var("name"),
            .keyword("WHERE"),
            .lbrace,
            .lbrace,
            .keyword("SELECT"),
            ._var("name"),
            .keyword("WHERE"),
            .lbrace,
            .bnode("b"),
            .iri("http://xmlns.com/foaf/0.1/name"),
            ._var("name"),
            .dot,
            .rbrace,
            .keyword("LIMIT"),
            .integer("5"),
            .rbrace,
            .rbrace,
            .keyword("ORDER"),
            .keyword("BY"),
            .keyword("DESC"),
            .lparen,
            ._var("name"),
            .rparen,
            ])
    }
}

