import XCTest
import Kineo
import SPARQLSyntax

#if os(Linux)
extension SPARQLTSVSyntaxTest {
    static var allTests : [(String, (SPARQLTSVSyntaxTest) -> () throws -> Void)] {
        return [
            ("testTSV1", testTSV1),
        ]
    }
}
#endif

class SPARQLTSVSyntaxTest: XCTestCase {
    var uniformResults: [TermResult]!
    var uniformLanguageResults: [TermResult]!
    var nonUniformResults: [TermResult]!
    override func setUp() {
        super.setUp()
        let iri = Term(iri: "http://example.org/Berlin")
        let bool = Term(boolean: true)
        let blank = Term(value: "b1", type: .blank)
        let lit0 = Term(string: "Berlin")
        let lit1 = Term(value: "Berlin", type: .language("en"))
        let v1 = Term(double: 1.2)
        let v2 = Term(integer: 7)
        
        let r0 = TermResult(bindings: ["name": lit0, "value": v1])
        let r1 = TermResult(bindings: ["name": lit1, "value": v1])
        let r2 = TermResult(bindings: ["name": lit0, "value": v2])
        let r3 = TermResult(bindings: ["boolean": bool, "blank": blank, "iri": iri])
        self.uniformResults = [r0, r2]
        self.uniformLanguageResults = [r1, r2]
        self.nonUniformResults = [r0, r3, r2]
    }
    
    func testTSV1() throws {
        let tsv = """
        ?x\t?literal
        <http://example/x>\t"String"
        <http://example/x>\t"String-with-dquote\\""
        _:blank0\t"Blank node"
        \t"Missing 'x'"
        \t
        <http://example/x>\t
        _:blank1\t"String-with-lang"@en
        _:blank1\t123
        """
        let parser = SPARQLTSVParser(encoding: .utf8, produceUniqueBlankIdentifiers: false)
        let data = tsv.data(using: .utf8)!
        let r = try parser.parse(data)
        guard case QueryResult.bindings(let names, let rows) = r else {
            XCTFail("Unexpected query results")
            return
        }
        XCTAssertEqual(names, ["x", "literal"])
        XCTAssertEqual(rows.count, 8)
        let expected : [TermResult] = [
            TermResult(bindings: ["x": Term(iri: "http://example/x"), "literal": Term(string: "String")]),
            TermResult(bindings: ["x": Term(iri: "http://example/x"), "literal": Term(string: "String-with-dquote\"")]),
            TermResult(bindings: ["x": Term(value: "blank0", type: .blank), "literal": Term(string: "Blank node")]),
            TermResult(bindings: ["literal": Term(string: "Missing 'x'")]),
            TermResult(bindings: [:]),
            TermResult(bindings: ["x": Term(iri: "http://example/x")]),
            TermResult(bindings: ["x": Term(value: "blank1", type: .blank), "literal": Term(value: "String-with-lang", type: .language("en"))]),
            TermResult(bindings: ["x": Term(value: "blank1", type: .blank), "literal": Term(integer: 123)]),
        ]
        
        if rows.elementsEqual(expected) {
            XCTAssertTrue(true)
        } else {
            XCTFail()
            for (a, b) in zip(rows, expected) {
                if a != b {
                    print("Rows do not match:")
                    print("- \(a)")
                    print("- \(b)")
                }
            }
        }
    }
}
