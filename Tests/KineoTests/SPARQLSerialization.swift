import XCTest
import Foundation
@testable import Kineo

#if os(Linux)
extension SPARQLSerializationTest {
    static var allTests : [(String, (SPARQLSerializationTest) -> () throws -> Void)] {
        return [
            ("testProjectedSPARQLTokens", testProjectedSPARQLTokens),
            ("testNonProjectedSPARQLTokens", testNonProjectedSPARQLTokens),
            ("testQueryModifiedSPARQLSerialization1", testQueryModifiedSPARQLSerialization1),
            ("testQueryModifiedSPARQLSerialization2", testQueryModifiedSPARQLSerialization2),
            ("testQuerySerializedTokens_1", testQuerySerializedTokens_1),
            ("testQuerySerializedTokens_2", testQuerySerializedTokens_2),
        ]
    }
}
#endif

// swiftlint:disable type_body_length
class SPARQLSerializationTest: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testProjectedSPARQLTokens() {
        let subj: Node = .bound(Term(value: "b", type: .blank))
        let type: Node = .bound(Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", type: .iri))
        let name: Node = .bound(Term(value: "http://xmlns.com/foaf/0.1/name", type: .iri))
        let vtype: Node = .variable("type", binding: true)
        let vname: Node = .variable("name", binding: true)
        let t1 = TriplePattern(subject: subj, predicate: type, object: vtype)
        let t2 = TriplePattern(subject: subj, predicate: name, object: vname)
        let algebra: Algebra = .project(.innerJoin(.triple(t1), .triple(t2)), ["name", "type"])
        do {
            let query = try Query(form: .select(.variables(["name", "type"])), algebra: algebra)
            let tokens = Array(query.sparqlTokens)
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
        } catch {
            XCTFail()
        }
    }
    
    func testNonProjectedSPARQLTokens() {
        let subj: Node = .bound(Term(value: "b", type: .blank))
        let type: Node = .bound(Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", type: .iri))
        let name: Node = .bound(Term(value: "http://xmlns.com/foaf/0.1/name", type: .iri))
        let vtype: Node = .variable("type", binding: true)
        let vname: Node = .variable("name", binding: true)
        let t1 = TriplePattern(subject: subj, predicate: type, object: vtype)
        let t2 = TriplePattern(subject: subj, predicate: name, object: vname)
        let algebra: Algebra = .innerJoin(.triple(t1), .triple(t2))
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
        
        do {
            let query = try Query(form: .select(.variables(["name", "type"])), algebra: algebra)
            let qtokens = Array(query.sparqlTokens)
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
        } catch {
            XCTFail()
        }
    }
    
    func testQueryModifiedSPARQLSerialization1() {
        let subj: Node = .bound(Term(value: "b", type: .blank))
        let type: Node = .bound(Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", type: .iri))
        let name: Node = .bound(Term(value: "http://xmlns.com/foaf/0.1/name", type: .iri))
        let vtype: Node = .variable("type", binding: true)
        let vname: Node = .variable("name", binding: true)
        let t1 = TriplePattern(subject: subj, predicate: type, object: vtype)
        let t2 = TriplePattern(subject: subj, predicate: name, object: vname)
        let algebra: Algebra = .slice(.order(.innerJoin(.triple(t1), .triple(t2)), [(false, .node(.variable("name", binding: false)))]), nil, 5)
        do {
            let query = try Query(form: .select(.variables(["name", "type"])), algebra: algebra)
            let qtokens = Array(query.sparqlTokens)
            
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
            let sparql = s.serialize(query.sparqlTokens)
            let expected = "SELECT ?name ?type WHERE { _:b a ?type . _:b <http://xmlns.com/foaf/0.1/name> ?name . } ORDER BY DESC ( ?name ) LIMIT 5"
            
            XCTAssertEqual(sparql, expected)
        } catch {
            XCTFail()
        }
    }
    
    func testQueryModifiedSPARQLSerialization2() {
        let subj: Node = .bound(Term(value: "b", type: .blank))
        let name: Node = .bound(Term(value: "http://xmlns.com/foaf/0.1/name", type: .iri))
        let vname: Node = .variable("name", binding: true)
        let t = TriplePattern(subject: subj, predicate: name, object: vname)
        do {
            let sq = try Query(form: .select(.star), algebra: .slice(.triple(t), nil, 5))
            let algebra: Algebra = .order(.subquery(sq), [(false, .node(.variable("name", binding: false)))])
            
            let query = try Query(form: .select(.star), algebra: algebra)
            
            let qtokens = Array(query.sparqlTokens)
            // SELECT * WHERE { { SELECT * WHERE { _:b foaf:name ?name . } LIMIT 5 } } ORDER BY DESC(?name)
            XCTAssertEqual(qtokens, [
                .keyword("SELECT"),
                .star,
                .keyword("WHERE"),
                .lbrace,
                .lbrace,
                .keyword("SELECT"),
                .star,
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
        } catch {
            XCTFail()
        }
    }
    
    func testQuerySerializedTokens_1() {
        guard var p = SPARQLParser(string: "PREFIX ex: <http://example.org/> SELECT * WHERE {\n_:s ex:value ?o . FILTER(?o != 7.0)\n}\n") else { XCTFail(); return }
        do {
            let q = try p.parseQuery()
            let tokens = Array(q.sparqlTokens)
            let expected: [SPARQLToken] = [
                .keyword("SELECT"),
                .star,
                .keyword("WHERE"),
                .lbrace,
                .bnode("b1"),
                .iri("http://example.org/value"),
                ._var("o"),
                .dot,
                .keyword("FILTER"),
                .lparen,
                ._var("o"),
                .notequals,
                .string1d("7.0"),
                .hathat,
                .iri("http://www.w3.org/2001/XMLSchema#decimal"),
                .rparen,
                .rbrace
            ]
            guard tokens.count == expected.count else { XCTFail("Got \(tokens.count), but expected \(expected.count)"); return }
            for (t, expect) in zip(tokens, expected) {
                XCTAssertEqual(t, expect)
            }
        } catch let e {
            XCTFail("\(e)")
        }
    }
    
    func testQuerySerializedTokens_2() {
        guard var p = SPARQLParser(string: "PREFIX ex: <http://example.org/> SELECT ?o WHERE {\n_:s ex:value ?o . FILTER(?o != 7.0)\n}\n") else { XCTFail(); return }
        do {
            let q = try p.parseQuery()
            let tokens = Array(q.sparqlTokens)
            let expected: [SPARQLToken] = [
                .keyword("SELECT"),
                ._var("o"),
                .keyword("WHERE"),
                .lbrace,
                .bnode("b1"),
                .iri("http://example.org/value"),
                ._var("o"),
                .dot,
                .keyword("FILTER"),
                .lparen,
                ._var("o"),
                .notequals,
                .string1d("7.0"),
                .hathat,
                .iri("http://www.w3.org/2001/XMLSchema#decimal"),
                .rparen,
                .rbrace
            ]
            
            //            guard tokens.count == expected.count else { XCTFail("Got \(tokens.count), but expected \(expected.count)"); return }
            for (t, expect) in zip(tokens, expected) {
                XCTAssertEqual(t, expect)
            }
        } catch let e {
            XCTFail("\(e)")
        }
    }
}
