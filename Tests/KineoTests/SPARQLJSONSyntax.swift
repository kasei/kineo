import XCTest
import Kineo
import SPARQLSyntax

#if os(Linux)
extension SPARQLJSONSyntaxTest {
    static var allTests : [(String, (SPARQLJSONSyntaxTest) -> () throws -> Void)] {
        return [
            ("testJSON1", testJSON1),
            ("testJSON2", testJSON2),
        ]
    }
}
#endif

class SPARQLJSONSyntaxTest: XCTestCase {
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
    
    func testJSON1() throws {
        let serializer = SPARQLJSONSerializer<SPARQLResultSolution<Term>>()
        
        let seq : [SPARQLResultSolution<Term>] = self.uniformResults
        let results = QueryResult<[SPARQLResultSolution<Term>], [Triple]>.bindings(["name", "value"], seq)
        let j = try serializer.serialize(results)
        let s = String(data: j, encoding: .utf8)!
        let expected = """
        {"head":{"vars":["name","value"]},"results":{"bindings":[{"name":{"datatype":"http:\\/\\/www.w3.org\\/2001\\/XMLSchema#string","type":"literal","value":"Berlin"},"value":{"datatype":"http:\\/\\/www.w3.org\\/2001\\/XMLSchema#double","type":"literal","value":"1.2E0"}},{"name":{"datatype":"http:\\/\\/www.w3.org\\/2001\\/XMLSchema#string","type":"literal","value":"Berlin"},"value":{"datatype":"http:\\/\\/www.w3.org\\/2001\\/XMLSchema#integer","type":"literal","value":"7"}}]}}
        """
        XCTAssertEqual(s, expected)
    }
    
    func testJSON2() throws {
        let serializer = SPARQLJSONSerializer<SPARQLResultSolution<Term>>()
        
        let seq : [SPARQLResultSolution<Term>] = self.nonUniformResults
        let results = QueryResult<[SPARQLResultSolution<Term>], [Triple]>.bindings(["name", "value", "boolean", "blank", "iri"], seq)
        let j = try serializer.serialize(results)
        let s = String(data: j, encoding: .utf8)!
        let expected = """
        {"head":{"vars":["name","value","boolean","blank","iri"]},"results":{"bindings":[{"name":{"datatype":"http:\\/\\/www.w3.org\\/2001\\/XMLSchema#string","type":"literal","value":"Berlin"},"value":{"datatype":"http:\\/\\/www.w3.org\\/2001\\/XMLSchema#double","type":"literal","value":"1.2E0"}},{"blank":{"type":"bnode","value":"b1"},"boolean":{"datatype":"http:\\/\\/www.w3.org\\/2001\\/XMLSchema#boolean","type":"literal","value":"true"},"iri":{"type":"uri","value":"http:\\/\\/example.org\\/Berlin"}},{"name":{"datatype":"http:\\/\\/www.w3.org\\/2001\\/XMLSchema#string","type":"literal","value":"Berlin"},"value":{"datatype":"http:\\/\\/www.w3.org\\/2001\\/XMLSchema#integer","type":"literal","value":"7"}}]}}
        """
        XCTAssertEqual(s, expected)
    }
    
    func testJSON_boolean() throws {
        let serializer = SPARQLJSONSerializer<SPARQLResultSolution<Term>>()
        
        let results = QueryResult<[SPARQLResultSolution<Term>], [Triple]>.boolean(true)
        let j = try serializer.serialize(results)
        let s = String(data: j, encoding: .utf8)!
        let expected = """
        {"boolean":"true","head":{}}
        """
        XCTAssertEqual(s, expected)
    }
    
    func testJSONPretty() throws {
        let serializer = SPARQLJSONSerializer<SPARQLResultSolution<Term>>()
        serializer.encoder.outputFormatting.insert(.prettyPrinted)

        let seq : [SPARQLResultSolution<Term>] = self.uniformLanguageResults
        let results = QueryResult<[SPARQLResultSolution<Term>], [Triple]>.bindings(["name", "value"], seq)
        let j = try serializer.serialize(results)
        let s = String(data: j, encoding: .utf8)!
        let expected = """
        {
          "head" : {
            "vars" : [
              "name",
              "value"
            ]
          },
          "results" : {
            "bindings" : [
              {
                "name" : {
                  "type" : "literal",
                  "value" : "Berlin",
                  "xml:lang" : "en"
                },
                "value" : {
                  "datatype" : "http:\\/\\/www.w3.org\\/2001\\/XMLSchema#double",
                  "type" : "literal",
                  "value" : "1.2E0"
                }
              },
              {
                "name" : {
                  "datatype" : "http:\\/\\/www.w3.org\\/2001\\/XMLSchema#string",
                  "type" : "literal",
                  "value" : "Berlin"
                },
                "value" : {
                  "datatype" : "http:\\/\\/www.w3.org\\/2001\\/XMLSchema#integer",
                  "type" : "literal",
                  "value" : "7"
                }
              }
            ]
          }
        }
        """
        XCTAssertEqual(s, expected)

    }
}
