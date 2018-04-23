import XCTest
import Kineo
import SPARQLSyntax

#if os(Linux)
extension QueryParserTest {
    static var allTests : [(String, (QueryParserTest) -> () throws -> Void)] {
        return [
            ("testTriple", testTriple),
            ("testQuad", testQuad),
            ("testJoin", testJoin),
            ("testUnion", testUnion),
            ("testProject", testProject),
        ]
    }
}
#endif

class QueryParserTest: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

//    func testPerformanceExample() {
//        // This is an example of a performance test case.
//        self.measure {
//            // Put the code you want to measure the time of here.
//        }
//    }

    private func parse(query: String) -> Query? {
        let qp      = QueryParser(reader: query)
        do {
            let query   = try qp.parse()
            return query
        } catch {
            return nil
        }
    }

    func testTriple() {
        XCTAssertNil(parse(query: "triple"))
        XCTAssertNil(parse(query: "triple ?foo"))
        XCTAssertNil(parse(query: "triple _:a <http://xmlns.com/foaf/0.1/name>"))
        XCTAssertNil(parse(query: "triple <s> <http://xmlns.com/foaf/0.1/name> ?o ?g"))
        guard let query = parse(query: "triple ?s ?p ?o\n") else { XCTFail(); return }
        let algebra = query.algebra
        guard case .triple(_) = algebra else {
            XCTFail()
            return
        }
        XCTAssert(true)
        XCTAssertEqual(algebra.inscope, Set(["s", "p", "o"]))
    }

    func testQuad() {
        XCTAssertNil(parse(query: "quad"))
        XCTAssertNil(parse(query: "quad _:s"))
        XCTAssertNil(parse(query: "quad ?s <p>"))
        XCTAssertNil(parse(query: "quad ?.s <http://xmlns.com/foaf/0.1/name> ?o"))

        guard let query = parse(query: "quad ?.s <http://xmlns.com/foaf/0.1/name> ?o ?g") else { XCTFail(); return }
        let algebra = query.algebra
        guard case .quad(_) = algebra else {
            XCTFail()
            return
        }
        XCTAssert(true)
        XCTAssertEqual(algebra.inscope, Set(["o", "g"]))
    }

    func testJoin() {
        XCTAssertNil(parse(query: "join"))
        XCTAssertNil(parse(query: "triple ?s ?p ?o\njoin"))

        guard let query = parse(query: "triple ?s <http://www.w3.org/2003/01/geo/wgs84_pos#lat> ?lat\ntriple ?s <http://www.w3.org/2003/01/geo/wgs84_pos#long> ?long\njoin") else { XCTFail(); return }
        let algebra = query.algebra
        guard case .innerJoin(.triple(_), .triple(_)) = algebra else {
            XCTFail()
            return
        }
        XCTAssert(true)
        XCTAssertEqual(algebra.inscope, Set(["s", "lat", "long"]))
    }

    func testUnion() {
        XCTAssertNil(parse(query: "union"))
        XCTAssertNil(parse(query: "triple ?s ?p ?o\nunion"))

        guard let query = parse(query: "triple ?s <http://xmlns.com/foaf/0.1/name> ?name\ntriple ?s <http://purl.org/dc/elements/1.1/title> ?name\nunion") else { XCTFail(); return }
        let algebra = query.algebra
        guard case .union(.triple(_), .triple(_)) = algebra else {
            XCTFail()
            return
        }
        XCTAssert(true)
        XCTAssertEqual(algebra.inscope, Set(["s", "name"]))
    }

    func testProject() {
        XCTAssertNil(parse(query: "project"))
        XCTAssertNil(parse(query: "triple ?s ?p ?o\nproject"))

        guard let query = parse(query: "triple ?s ?p ?o\nproject s o") else { XCTFail(); return }
        let algebra = query.algebra
        guard case .project(.triple(_), let vars) = algebra else {
            XCTFail()
            return
        }
        XCTAssert(true)
        let vs = Set(vars)
        XCTAssertEqual(vs, Set(["s", "o"]))
        XCTAssertEqual(algebra.inscope, Set(["o", "s"]))
    }

//    * `leftjoin` - Join the two patterns on the top of the stack
//    * `avg KEY RESULT GROUPVAR1 GROUPVAR2 ...` - Aggregate the pattern on the top of the stack, grouping by the group variables, binding the *average* of the `?KEY` variable to `?RESULT`
//    * `sum KEY RESULT GROUPVAR1 GROUPVAR2 ...` - Aggregate the pattern on the top of the stack, grouping by the group variables, binding the *sum* of the `?KEY` variable to `?RESULT`
//    * `count KEY RESULT GROUPVAR1 GROUPVAR2 ...` - Aggregate the pattern on the top of the stack, grouping by the group variables, binding the *count* of bound values of `?KEY` to `?RESULT`
//    * `countall RESULT GROUPVAR1 GROUPVAR2 ...` - Aggregate the pattern on the top of the stack, grouping by the group variables, binding the *count* of results to `?RESULT`
//    * `limit COUNT` - Limit the result count to `COUNT`
//    * `graph ?VAR` - Evaluate the pattern on the top of the stack with each named graph in the store as the active graph (and bound to `?VAR`)
//    * `graph <IRI>` - Change the active graph to `IRI`
//    * `extend RESULT EXPR` - Evaluate results for the pattern on the top of the stack, evaluating `EXPR` for each row, and binding the result to `?RESULT`
//    * `filter EXPR` - Evaluate results for the pattern on the top of the stack, evaluating `EXPR` for each row, and returning the result iff a true value is produced
//    * `sort VAR` - Sort the results for the pattern on the top of the stack by `?VAR`

}
