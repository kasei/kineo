import XCTest
import Foundation
import SPARQLSyntax
@testable import Kineo

#if os(Linux)
extension TermIdentityMapTest {
    static var allTests : [(String, (TermIdentityMapTest) -> () throws -> Void)] {
        return [
            ("testIntegerToID", testIntegerToID),
            ("testIDToInteger", testIDToInteger),
            ("testIntToID", testIntToID),
            ("testIDToInt", testIDToInt),
            ("testCommonIRIToID", testCommonIRIToID),
            ("testIDToCommonIRI", testIDToCommonIRI),
            ("testInlinedStringToID", testInlinedStringToID),
            ("testIDToInlinedString", testIDToInlinedString),
            ("testBooleanToID", testBooleanToID),
            ("testIDToBoolean", testIDToBoolean),
            ("testDateToID", testDateToID),
            ("testIDToDate", testIDToDate),
            ("testDateTimeToID", testDateTimeToID),
            ("testIDToDateTime", testIDToDateTime),
            ("testDecimalToID", testDecimalToID),
            ("testIDToDecimal", testIDToDecimal),
        ]
    }
}
#endif

class MockTermIdentityMap: PackedIdentityMap {
    public typealias Item = Term
    public typealias Result = UInt64
    
    public init () {}
    
    public func term(for id: Result) -> Term? {
        return self.unpack(id: id)
    }
    
    public func id(for value: Item) -> Result? {
        return self.pack(value: value)
    }

    func getOrSetID(for value: Item) throws -> Result {
        throw DatabaseError.PermissionError("Cannot call getOrSetID on read-only MockTermIdentityMap object")
    }
}

// swiftlint:disable type_body_length
class TermIdentityMapTest: XCTestCase {
    var map : MockTermIdentityMap!
    let integer_base        = PackedTermType.integer.typedEmptyValue
    let int_base            = PackedTermType.int.typedEmptyValue
    let common_iri_base     = PackedTermType.commonIRI.typedEmptyValue
    let inlined_string_base = PackedTermType.inlinedString.typedEmptyValue
    let boolean_base        = PackedTermType.boolean.typedEmptyValue
    let decimal_base        = PackedTermType.decimal.typedEmptyValue
    let APRIL_22_2018_ID    = PackedTermType.date.typedEmptyValue + 0xbd396 // 0xbd396 == ((2018*12 + 4) << 5) + 22


    // 0xa87e24b0d303e8 =
    // zZZZ ZZZY YYYY YYYY YYYY MMMM DDDD Dhhh hhmm mmmm ssss ssss ssss ssss
    // 1
    // 010100
    // 0011111100010
    // 0100
    // 10110
    // 00011
    // 010011
    // 0000001111101000

    let APRIL_22_2018_03_19_01_EST = PackedTermType.dateTime.typedEmptyValue + 0xa87e24b0d303e8 // 2018-04-22T03:19:01-05:00

    override func setUp() {
        self.map = MockTermIdentityMap()
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testIntegerToID() {
        for v : UInt64 in stride(from: 0, to: 1_000_000_000, by: 101_997) {
            let id = map.id(for: Term(integer: Int(v)))
            XCTAssertEqual(id, integer_base + v)
        }
        
        let integerOverflows : [UInt64] = [0x00ffffffffffffff, 0x01ffffffffffffff]
        for v in integerOverflows {
            let id = map.id(for: Term(value: "\(v)", type: .datatype(.integer)))
            XCTAssertNil(id)
        }
    }
    
    func testIDToInteger() {
        for v : UInt64 in stride(from: 0, to: 1_000_000_000, by: 101_997) {
            let id = integer_base + v
            let term = map.term(for: id)
            XCTAssertNotNil(term)
            XCTAssertEqual(term!.value, "\(v)")
        }
    }
    
    func testIntToID() {
        for v : UInt64 in stride(from: 0, to: 1_000_000_000, by: 101_997) {
            let id = map.id(for: Term(value: "\(v)", type: .datatype("http://www.w3.org/2001/XMLSchema#int")))
            XCTAssertEqual(id, int_base + v)
        }
        
        let integerOverflows : [UInt64] = [2147483648]
        for v in integerOverflows {
            let id = map.id(for: Term(value: "\(v)", type: .datatype("http://www.w3.org/2001/XMLSchema#int")))
            XCTAssertNil(id)
        }
    }
    
    func testIDToInt() {
        for v : UInt64 in stride(from: 0, to: 1_000_000_000, by: 101_997) {
            let id = int_base + v
            let term = map.term(for: id)
            XCTAssertNotNil(term)
            XCTAssertEqual(term!.value, "\(v)")
        }
    }
    
    let expectedCommonIRIs : [UInt64:String] = [
        1: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type",
        2: "http://www.w3.org/1999/02/22-rdf-syntax-ns#List",
        3: "http://www.w3.org/1999/02/22-rdf-syntax-ns#Resource",
        4: "http://www.w3.org/1999/02/22-rdf-syntax-ns#first",
        5: "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest",
        6: "http://www.w3.org/2000/01/rdf-schema#comment",
        7: "http://www.w3.org/2000/01/rdf-schema#label",
        8: "http://www.w3.org/2000/01/rdf-schema#seeAlso",
        9: "http://www.w3.org/2000/01/rdf-schema#isDefinedBy",
        0x100: "http://www.w3.org/1999/02/22-rdf-syntax-ns#_0",
        0x181: "http://www.w3.org/1999/02/22-rdf-syntax-ns#_129",
        0x1ff: "http://www.w3.org/1999/02/22-rdf-syntax-ns#_255",
        ]

    let expectedInlinedStrings : [UInt64:String] = [
        0x1261626300000000: "abc",
        0x12e781abe6989f00: "火星"
    ]
    
    func testCommonIRIToID() {
        for (v, iri) in expectedCommonIRIs {
            let id = map.id(for: Term(iri: iri))
            XCTAssertEqual(id, common_iri_base + v)
        }
    }
    
    func testIDToCommonIRI() {
        for (v, iri) in expectedCommonIRIs {
            let id = common_iri_base + v
            let term = map.term(for: id)
            XCTAssertNotNil(term)
            XCTAssertEqual(term!.value, iri)
        }
    }
    
    func testInlinedStringToID() {
        for (expected, string) in expectedInlinedStrings {
            let id = map.id(for: Term(string: string))
            XCTAssertEqual(id, expected)
        }
    }
    
    func testIDToInlinedString() {
        for (id, string) in expectedInlinedStrings {
            let term = map.term(for: id)
            XCTAssertNotNil(term)
            XCTAssertEqual(term!.value, string)
            XCTAssertEqual(term!.type, .datatype(.string))
        }
    }

    func testBooleanToID() {
        let falseId = map.id(for: Term(boolean: false))
        XCTAssertEqual(falseId, boolean_base)
        
        let trueId = map.id(for: Term(boolean: true))
        XCTAssertEqual(trueId, boolean_base + 1)
    }
    
    func testIDToBoolean() {
        let falseTerm = map.term(for: boolean_base)
        XCTAssertNotNil(falseTerm)
        XCTAssertEqual(falseTerm!.value, "false")
        
        let trueTerm = map.term(for: boolean_base+1)
        XCTAssertNotNil(trueTerm)
        XCTAssertEqual(trueTerm!.value, "true")
    }
    
    func testDateToID() {
        let id = map.id(for: Term(year: 2018, month: 4, day: 22))
        XCTAssertEqual(id, APRIL_22_2018_ID)
    }
    
    func testIDToDate() {
        let term = map.term(for: APRIL_22_2018_ID)
        XCTAssertNotNil(term)
        XCTAssertEqual(term!.value, "2018-04-22")
    }
    
    func testDateTimeToID() {
        let id = map.id(for: Term(year: 2018, month: 4, day: 22, hours: 3, minutes: 19, seconds: 1.0, offset: (-5 * 60)))
        XCTAssertEqual(id, APRIL_22_2018_03_19_01_EST)
        let term = map.term(for: APRIL_22_2018_03_19_01_EST)
        XCTAssertNotNil(term)
        XCTAssertEqual(term!.value, "2018-04-22T03:19:01-05:00")
    }
    
    func testIDToDateTime() {
        let term = map.term(for: APRIL_22_2018_03_19_01_EST)
        XCTAssertNotNil(term)
        XCTAssertEqual(term!.value, "2018-04-22T03:19:01-05:00")
    }
    
    let expectedDecimals : [UInt64:String] = [
        0x0200000000007b: "1.23",
        0x01000000001ebe: "787.0",
        0x0280000000007b: "-1.23",
        0x04000000000023: "0.0035",
        0x04800000000023: "-0.0035",
    ]
    
    func testDecimalToID() {
        for (expected, string) in expectedDecimals {
            let id = map.id(for: Term(value: string, type: .datatype(.decimal)))
            XCTAssertEqual(id, decimal_base + expected)
        }
    }
    
    func testIDToDecimal() {
        for (id, string) in expectedDecimals {
            let term = map.term(for: decimal_base + id)
            XCTAssertNotNil(term)
            XCTAssertEqual(term!.value, string)
            XCTAssertEqual(term!.type, .datatype(.decimal))
        }
    }
    
    // not testable without a persistent identitymap (these are not generally inlined):
    //  blank          = 0x01
    //  iri            = 0x02
    //  language       = 0x10
    //  datatype       = 0x11
}
