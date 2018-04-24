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
    
    private func parse(query: String) -> Algebra? {
        let qp      = QueryParser(reader: query)
        do {
            let query   = try qp.parse()
            return query?.algebra
        } catch {
            return nil
        }
    }
    
    func testJSON1() throws {
        let serializer = SPARQLJSONSerializer<TermResult>()
        
        var i = self.uniformResults.makeIterator()
        let q = try Query(form: .select(.variables(["name", "value"])), algebra: .joinIdentity)
        let j = try serializer.serialize(&i, for: q)
        let s = String(data: j, encoding: .utf8)!
        let expected = """
        {"head":{"vars":["name","value"]},"results":{"bindings":[{"name":{"type":"literal","value":"Berlin","datatype":"http:\\/\\/www.w3.org\\/2001\\/XMLSchema#string"},"value":{"type":"literal","value":"1.2E0","datatype":"http:\\/\\/www.w3.org\\/2001\\/XMLSchema#double"}},{"name":{"type":"literal","value":"Berlin","datatype":"http:\\/\\/www.w3.org\\/2001\\/XMLSchema#string"},"value":{"type":"literal","value":"7","datatype":"http:\\/\\/www.w3.org\\/2001\\/XMLSchema#integer"}}]}}
        """
        XCTAssertEqual(s, expected)
    }
    
    func testJSON2() throws {
        let serializer = SPARQLJSONSerializer<TermResult>()
        
        var i = self.nonUniformResults.makeIterator()
        let q = try Query(form: .select(.variables(["name", "value", "boolean", "blank", "iri"])), algebra: .joinIdentity)
        let j = try serializer.serialize(&i, for: q)
        let s = String(data: j, encoding: .utf8)!
        let expected = """
        {"head":{"vars":["name","value","boolean","blank","iri"]},"results":{"bindings":[{"name":{"type":"literal","value":"Berlin","datatype":"http:\\/\\/www.w3.org\\/2001\\/XMLSchema#string"},"value":{"type":"literal","value":"1.2E0","datatype":"http:\\/\\/www.w3.org\\/2001\\/XMLSchema#double"}},{"iri":{"type":"uri","value":"http:\\/\\/example.org\\/Berlin"},"blank":{"type":"bnode","value":"b1"},"boolean":{"type":"literal","value":"true","datatype":"http:\\/\\/www.w3.org\\/2001\\/XMLSchema#boolean"}},{"name":{"type":"literal","value":"Berlin","datatype":"http:\\/\\/www.w3.org\\/2001\\/XMLSchema#string"},"value":{"type":"literal","value":"7","datatype":"http:\\/\\/www.w3.org\\/2001\\/XMLSchema#integer"}}]}}
        """
        XCTAssertEqual(s, expected)
    }
    
    func testJSONPretty() throws {
        let serializer = SPARQLJSONSerializer<TermResult>()
        serializer.encoder.outputFormatting = .prettyPrinted

        var i = self.uniformLanguageResults.makeIterator()
        let q = try Query(form: .select(.variables(["name", "value"])), algebra: .joinIdentity)
        let j = try serializer.serialize(&i, for: q)
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
                  "type" : "literal",
                  "value" : "1.2E0",
                  "datatype" : "http:\\/\\/www.w3.org\\/2001\\/XMLSchema#double"
                }
              },
              {
                "name" : {
                  "type" : "literal",
                  "value" : "Berlin",
                  "datatype" : "http:\\/\\/www.w3.org\\/2001\\/XMLSchema#string"
                },
                "value" : {
                  "type" : "literal",
                  "value" : "7",
                  "datatype" : "http:\\/\\/www.w3.org\\/2001\\/XMLSchema#integer"
                }
              }
            ]
          }
        }
        """
        XCTAssertEqual(s, expected)

    }
}
