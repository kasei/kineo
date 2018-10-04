import XCTest
import Kineo
import SPARQLSyntax

#if os(Linux)
extension SPARQLXMLSyntaxTest {
    static var allTests : [(String, (SPARQLXMLSyntaxTest) -> () throws -> Void)] {
        return [
            ("testXML1", testXML1),
            ("testXML2", testXML2),
        ]
    }
}
#endif

class SPARQLXMLSyntaxTest: XCTestCase {
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
    
    func testXML1() throws {
        let serializer = SPARQLXMLSerializer<TermResult>()
        
        let seq : [TermResult] = self.uniformResults
        let results = QueryResult<[TermResult], [Triple]>.bindings(["name", "value"], seq)
        let j = try serializer.serialize(results)
        let s = String(data: j, encoding: .utf8)!
        let expected = """
        <?xml version="1.0" standalone="yes"?><sparql xmlns="http://www.w3.org/2005/sparql-results#"><head><variable name="name"></variable><variable name="value"></variable></head><results><result><binding name="name"><literal datatype="http://www.w3.org/2001/XMLSchema#string">Berlin</literal></binding><binding name="value"><literal datatype="http://www.w3.org/2001/XMLSchema#double">1.2E0</literal></binding></result><result><binding name="name"><literal datatype="http://www.w3.org/2001/XMLSchema#string">Berlin</literal></binding><binding name="value"><literal datatype="http://www.w3.org/2001/XMLSchema#integer">7</literal></binding></result></results></sparql>
        """
        XCTAssertEqual(s, expected)
    }
    
    func testXML2() throws {
        let serializer = SPARQLXMLSerializer<TermResult>()
        
        let seq : [TermResult] = self.nonUniformResults
        let results = QueryResult<[TermResult], [Triple]>.bindings(["name", "value", "boolean", "blank", "iri"], seq)
        let j = try serializer.serialize(results)
        let s = String(data: j, encoding: .utf8)!
        let expected = """
        <?xml version="1.0" standalone="yes"?><sparql xmlns="http://www.w3.org/2005/sparql-results#"><head><variable name="name"></variable><variable name="value"></variable><variable name="boolean"></variable><variable name="blank"></variable><variable name="iri"></variable></head><results><result><binding name="name"><literal datatype="http://www.w3.org/2001/XMLSchema#string">Berlin</literal></binding><binding name="value"><literal datatype="http://www.w3.org/2001/XMLSchema#double">1.2E0</literal></binding></result><result><binding name="blank"><bnode>b1</bnode></binding><binding name="boolean"><literal datatype="http://www.w3.org/2001/XMLSchema#boolean">true</literal></binding><binding name="iri"><uri>http://example.org/Berlin</uri></binding></result><result><binding name="name"><literal datatype="http://www.w3.org/2001/XMLSchema#string">Berlin</literal></binding><binding name="value"><literal datatype="http://www.w3.org/2001/XMLSchema#integer">7</literal></binding></result></results></sparql>
        """
        XCTAssertEqual(s, expected)
    }
    
    func testXML_boolean() throws {
        let serializer = SPARQLXMLSerializer<TermResult>()
        
        let results = QueryResult<[TermResult], [Triple]>.boolean(true)
        let j = try serializer.serialize(results)
        let s = String(data: j, encoding: .utf8)!
        let expected = """
        <?xml version="1.0" standalone="yes"?><sparql xmlns="http://www.w3.org/2005/sparql-results#"><boolean>true</boolean></sparql>
        """
        XCTAssertEqual(s, expected)
    }
}
