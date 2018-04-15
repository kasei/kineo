import XCTest
import Foundation
import Kineo

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
    
    func testQuerySerializedTokens() {
        guard var p = SPARQLParser(string: "PREFIX ex: <http://example.org/> SELECT * WHERE {\n_:s ex:value ?o . FILTER(?o != 7.0)\n}\n") else { XCTFail(); return }
        do {
            let q = try p.parseQuery()
            print("*** \(q.serialize())")
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
}
