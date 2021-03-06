import XCTest
import Kineo
import SPARQLSyntax

#if os(Linux)
extension NTriplesSerializationTest {
    static var allTests : [(String, (NTriplesSerializationTest) -> () throws -> Void)] {
        return [
            ("testTriples", testTriples),
            ("testEscaping1", testEscaping1),
            ("testEscaping2", testEscaping2),
        ]
    }
}
#endif

class NTriplesSerializationTest: XCTestCase {
    var serializer: NTriplesSerializer!
    override func setUp() {
        super.setUp()
        self.serializer = NTriplesSerializer()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    private func parse(query: String) -> Query? {
        let qp      = QueryParser(reader: query)
        do {
            let query   = try qp.parse()
            return query
        } catch {
            return nil
        }
    }
    
    func testTriples() {
        let i = Term(iri: "http://example.org/食べる")
        let b = Term(value: "b1", type: .blank)
        let l = Term(value: "foo", type: .language("en-US"))
        let d = Term(integer: 7)
        let triple1 = Triple(subject: b, predicate: i, object: l)
        let triple2 = Triple(subject: b, predicate: i, object: d)
        
        guard let data = try? serializer.serialize([triple1, triple2]) else { XCTFail(); return }
        let string = String(data: data, encoding: .utf8)!
        XCTAssertEqual(string, "_:b1 <http://example.org/\\u98DF\\u3079\\u308B> \"foo\"@en-US .\n_:b1 <http://example.org/\\u98DF\\u3079\\u308B> \"7\"^^<http://www.w3.org/2001/XMLSchema#integer> .\n")
        XCTAssert(true)
    }
    
    func testEscaping1() {
        let b = Term(value: "b1", type: .blank)
        let i = Term(iri: "http://example.org/^foo")
        let l = Term(string: "\n \"")
        let triple = Triple(subject: b, predicate: i, object: l)
        
        guard let data = try? serializer.serialize([triple]) else { XCTFail(); return }
        let string = String(data: data, encoding: .utf8)!
        XCTAssertEqual(string, "_:b1 <http://example.org/\\u005Efoo> \"\\n \\\"\" .\n")
        XCTAssert(true)
    }
    
    func testEscaping2() {
        let b = Term(value: "b1", type: .blank)
        let i = Term(iri: "http://example.org/foo")
        let l = Term(string: "a\u{0300}")
        let triple = Triple(subject: b, predicate: i, object: l)
        
        guard let data = try? serializer.serialize([triple]) else { XCTFail(); return }
        let string = String(data: data, encoding: .utf8)!
        XCTAssertEqual(string, "_:b1 <http://example.org/foo> \"a\\u0300\" .\n")
        XCTAssert(true)
    }
}
