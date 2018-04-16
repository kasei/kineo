import XCTest
import Foundation
import Kineo

#if os(Linux)
extension RDFTest {
    static var allTests : [(String, (RDFTest) -> () throws -> Void)] {
        return [
            ("testConstructorInteger", testConstructorInteger),
            ("testConstructorDecimal", testConstructorDecimal),
            ("testConstructorDecimal2", testConstructorDecimal2),
            ("testConstructorFloat", testConstructorFloat),
            ("testConstructorFloat2", testConstructorFloat2),
            ("testConstructorDouble", testConstructorDouble),
            ("testConstructorDouble2", testConstructorDouble2),
            ("testConstructorDouble3", testConstructorDouble3),
        ]
    }
}
#endif

// swiftlint:disable type_body_length
class RDFTest: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testConstructorInteger() {
        let t = Term(integer: 7)
        XCTAssertEqual(t.value, "7")
    }
    
    func testConstructorDecimal() {
        let t = Term(decimal: 7.1)
        XCTAssertEqual(t.value, "7.1")
    }
    
    func testConstructorDecimal2() {
        let t = Term(value: "-017.10", type: .datatype("http://www.w3.org/2001/XMLSchema#decimal"))
        XCTAssertEqual(t.value, "-17.1")
    }
    
    func testConstructorFloat() {
        let t = Term(float: -70.1)
        XCTAssertEqual(t.value, "-7.01E1")
    }
    
    func testConstructorFloat2() {
        let t = Term(float: -0.701, exponent: 1)
        XCTAssertEqual(t.value, "-7.01E0")
    }
    
    func testConstructorDouble() {
        let t = Term(double: 700.1)
        XCTAssertEqual(t.value, "7.001E2")
    }
    
    func testConstructorDouble2() {
        let t = Term(double: 7001.0, exponent: -1)
        XCTAssertEqual(t.value, "7.001E2")
    }
    
    func testConstructorDouble3() {
        let t = Term(double: 0.00123)
        XCTAssertEqual(t.value, "1.23E-3")
    }

}
