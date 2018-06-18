import XCTest
import Kineo
import SPARQLSyntax

#if os(Linux)
extension TurtleSerializationTest {
    static var allTests : [(String, (TurtleSerializationTest) -> () throws -> Void)] {
        return [
            ("testTriples", testTriples),
            ("testEscaping", testEscaping),
            ("testGrouping", testGrouping),
        ]
    }
}
#endif

class TurtleSerializationTest: XCTestCase {
    var serializer: TurtleSerializer!
    override func setUp() {
        super.setUp()
        self.serializer = TurtleSerializer()
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
        XCTAssertEqual(string, "_:b1 <http://example.org/食べる> \"foo\"@en-US, 7 .\n")
        XCTAssert(true)
    }
    
    func testEscaping() {
        let b = Term(value: "b1", type: .blank)
        let i = Term(iri: "http://example.org/^foo")
        let l = Term(string: "\n\"")
        let triple = Triple(subject: b, predicate: i, object: l)
        
        guard let data = try? serializer.serialize([triple]) else { XCTFail(); return }
        let string = String(data: data, encoding: .utf8)!
        XCTAssertEqual(string, "_:b1 <http://example.org/\\U0000005Efoo> \"\\n\\\"\" .\n")
        XCTAssert(true)
    }

    func testGrouping() {
        let i1 = Term(iri: "http://example.org/i1")
        let i2 = Term(iri: "http://example.org/i2")
        let b = Term(value: "b1", type: .blank)
        let d1 = Term(integer: 1)
        let d2 = Term(integer: 2)
        let triple1 = Triple(subject: b, predicate: i1, object: d1)
        let triple2 = Triple(subject: b, predicate: i1, object: d2)
        let triple3 = Triple(subject: b, predicate: i2, object: d1)
        let triple4 = Triple(subject: b, predicate: i2, object: d2)
        
        guard let data = try? serializer.serialize([triple1, triple4, triple2, triple3]) else { XCTFail(); return }
        let string = String(data: data, encoding: .utf8)!
        XCTAssertEqual(string, "_:b1 <http://example.org/i1> 1, 2; <http://example.org/i2> 1, 2 .\n")
        XCTAssert(true)
    }
    
}
