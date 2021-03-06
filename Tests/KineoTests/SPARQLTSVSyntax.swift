import XCTest
import Kineo
import SPARQLSyntax

#if os(Linux)
extension SPARQLTSVSyntaxParserTest {
    static var allTests : [(String, (SPARQLTSVSyntaxParserTest) -> () throws -> Void)] {
        return [
            ("testTSV1", testTSV1),
        ]
    }
}
extension SPARQLTSVSyntaxSerializerTest {
    static var allTests : [(String, (SPARQLTSVSyntaxSerializerTest) -> () throws -> Void)] {
        return [
            ("testTSV1", testTSV1),
            ("testTSV2", testTSV2),
        ]
    }
}
#endif

class SPARQLTSVSyntaxParserTest: XCTestCase {
    var uniformResults: [SPARQLResultSolution<Term>]!
    var uniformLanguageResults: [SPARQLResultSolution<Term>]!
    var nonUniformResults: [SPARQLResultSolution<Term>]!
    override func setUp() {
        super.setUp()
        let iri = Term(iri: "http://example.org/Berlin")
        let bool = Term(boolean: true)
        let blank = Term(value: "b1", type: .blank)
        let lit0 = Term(string: "Berlin")
        let lit1 = Term(value: "Berlin", type: .language("en"))
        let v1 = Term(double: 1.2)
        let v2 = Term(integer: 7)
        
        let r0 = SPARQLResultSolution<Term>(bindings: ["name": lit0, "value": v1])
        let r1 = SPARQLResultSolution<Term>(bindings: ["name": lit1, "value": v1])
        let r2 = SPARQLResultSolution<Term>(bindings: ["name": lit0, "value": v2])
        let r3 = SPARQLResultSolution<Term>(bindings: ["boolean": bool, "blank": blank, "iri": iri])
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
        let expected : [SPARQLResultSolution<Term>] = [
            SPARQLResultSolution<Term>(bindings: ["x": Term(iri: "http://example/x"), "literal": Term(string: "String")]),
            SPARQLResultSolution<Term>(bindings: ["x": Term(iri: "http://example/x"), "literal": Term(string: "String-with-dquote\"")]),
            SPARQLResultSolution<Term>(bindings: ["x": Term(value: "blank0", type: .blank), "literal": Term(string: "Blank node")]),
            SPARQLResultSolution<Term>(bindings: ["literal": Term(string: "Missing 'x'")]),
            SPARQLResultSolution<Term>(bindings: [:]),
            SPARQLResultSolution<Term>(bindings: ["x": Term(iri: "http://example/x")]),
            SPARQLResultSolution<Term>(bindings: ["x": Term(value: "blank1", type: .blank), "literal": Term(value: "String-with-lang", type: .language("en"))]),
            SPARQLResultSolution<Term>(bindings: ["x": Term(value: "blank1", type: .blank), "literal": Term(integer: 123)]),
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

class SPARQLTSVSyntaxSerializerTest: XCTestCase {
    var uniformResults: [SPARQLResultSolution<Term>]!
    var uniformLanguageResults: [SPARQLResultSolution<Term>]!
    var nonUniformResults: [SPARQLResultSolution<Term>]!
    override func setUp() {
        super.setUp()
        let iri = Term(iri: "http://example.org/Berlin")
        let bool = Term(boolean: true)
        let blank = Term(value: "b1", type: .blank)
        let lit0 = Term(string: "Berlin")
        let lit1 = Term(value: "Berlin", type: .language("en"))
        let v1 = Term(double: 1.2)
        let v2 = Term(integer: 7)
        
        let r0 = SPARQLResultSolution<Term>(bindings: ["name": lit0, "value": v1])
        let r1 = SPARQLResultSolution<Term>(bindings: ["name": lit1, "value": v1])
        let r2 = SPARQLResultSolution<Term>(bindings: ["name": lit0, "value": v2])
        let r3 = SPARQLResultSolution<Term>(bindings: ["boolean": bool, "blank": blank, "iri": iri])
        self.uniformResults = [r0, r2]
        self.uniformLanguageResults = [r1, r2]
        self.nonUniformResults = [r0, r3, r2]
    }
    
    func testTSV1() throws {
        let serializer = SPARQLTSVSerializer<SPARQLResultSolution<Term>>()
        
        let seq : [SPARQLResultSolution<Term>] = self.uniformResults
        let results = QueryResult<[SPARQLResultSolution<Term>], [Triple]>.bindings(["name", "value"], seq)
        let j = try serializer.serialize(results)
        let s = String(data: j, encoding: .utf8)!
        let expected = """
        ?name\t?value
        "Berlin"\t"1.2E0"^^<http://www.w3.org/2001/XMLSchema#double>
        "Berlin"\t7
        
        """
        XCTAssertEqual(s, expected)
    }
    
    func testTSV2() throws {
        let serializer = SPARQLTSVSerializer<SPARQLResultSolution<Term>>()
        
        let seq : [SPARQLResultSolution<Term>] = self.nonUniformResults
        let results = QueryResult<[SPARQLResultSolution<Term>], [Triple]>.bindings(["name", "value", "boolean", "blank", "iri"], seq)
        let j = try serializer.serialize(results)
        let s = String(data: j, encoding: .utf8)!
        let expected = """
        ?name\t?value\t?boolean\t?blank\t?iri
        "Berlin"\t"1.2E0"^^<http://www.w3.org/2001/XMLSchema#double>\t\t\t
        \t\t"true"^^<http://www.w3.org/2001/XMLSchema#boolean>\t_:b1\t<http://example.org/Berlin>
        "Berlin"\t7\t\t\t
        
        """
        XCTAssertEqual(s, expected)
    }
}
