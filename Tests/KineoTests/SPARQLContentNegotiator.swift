import Foundation
import XCTest
import Kineo
import SPARQLSyntax

#if os(Linux)
extension SPARQLContentNegotiatorTest {
    static var allTests : [(String, (SPARQLContentNegotiatorTest) -> () throws -> Void)] {
        return [
            ("testSharedConneg", testSharedConneg),
            ("testExtendedSharedConneg", testExtendedSharedConneg),
        ]
    }
}
#endif

class SPARQLContentNegotiatorTest: XCTestCase {
    var boolResult : QueryResult<[SPARQLResultSolution<Term>], [Triple]>!
    var triplesResult : QueryResult<[SPARQLResultSolution<Term>], [Triple]>!
    var bindingsResult : QueryResult<[SPARQLResultSolution<Term>], [Triple]>!

    override func setUp() {
        boolResult = QueryResult.boolean(true)
        triplesResult = QueryResult.triples([])
        bindingsResult = QueryResult.bindings(["a"], [])
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testSharedSerializerConneg() {
        let c = SPARQLContentNegotiator.shared
        let boolResult : QueryResult<[SPARQLResultSolution<Term>], [Triple]> = QueryResult.boolean(true)
        let triplesResult : QueryResult<[SPARQLResultSolution<Term>], [Triple]> = QueryResult.triples([])
        let bindingsResult : QueryResult<[SPARQLResultSolution<Term>], [Triple]> = QueryResult.bindings(["a"], [])
        
        // default serializer for */*
        XCTAssertEqual(c.negotiateSerializer(for: boolResult, accept: ["*/*"])!.canonicalMediaType, "application/sparql-results+json")
        XCTAssertEqual(c.negotiateSerializer(for: triplesResult, accept: ["*/*"])!.canonicalMediaType, "application/turtle")
        XCTAssertEqual(c.negotiateSerializer(for: bindingsResult, accept: ["*/*"])!.canonicalMediaType, "application/sparql-results+json")
        
        // default serializer for text/turtle
        XCTAssertNil(c.negotiateSerializer(for: boolResult, accept: ["text/turtle"]))
        XCTAssertEqual(c.negotiateSerializer(for: triplesResult, accept: ["text/turtle"])!.canonicalMediaType, "application/turtle")
        XCTAssertNil(c.negotiateSerializer(for: bindingsResult, accept: ["text/turtle"]))
        
        // default serializer for text/tab-separated-values
        XCTAssertNil(c.negotiateSerializer(for: boolResult, accept: ["text/tab-separated-values"]))
        XCTAssertNil(c.negotiateSerializer(for: triplesResult, accept: ["text/tab-separated-values"]))
        XCTAssertEqual(c.negotiateSerializer(for: bindingsResult, accept: ["text/tab-separated-values"])!.canonicalMediaType, "text/tab-separated-values")

        
        // serializer for application/n-triples, text/tab-separated-values, application/sparql-results+xml
        XCTAssertEqual(c.negotiateSerializer(for: boolResult, accept: ["application/n-triples", "text/tab-separated-values", "application/sparql-results+xml"])!.canonicalMediaType, "application/sparql-results+xml")
        
        XCTAssertEqual(c.negotiateSerializer(for: triplesResult, accept: ["application/n-triples", "text/tab-separated-values", "application/sparql-results+xml"])!.canonicalMediaType, "application/n-triples")
        XCTAssertEqual(c.negotiateSerializer(for: bindingsResult, accept: ["application/n-triples", "text/tab-separated-values", "application/sparql-results+xml"])!.canonicalMediaType, "text/tab-separated-values")
    }

    func testSharedParserConneg() {
        let c = SPARQLContentNegotiator.shared
        let makeResp : (String) -> HTTPURLResponse = { (ct) in
            return HTTPURLResponse(url: URL(string: "http://example.org/sparql")!, statusCode: 200, httpVersion: "1.1", headerFields: [
                "Content-Type": ct
            ])!
        }
        
        XCTAssertTrue(c.negotiateParser(for: makeResp("application/sparql-results+xml")) is SPARQLXMLParser)
        XCTAssertTrue(c.negotiateParser(for: makeResp("application/sparql-results+json")) is SPARQLJSONParser)
        XCTAssertTrue(c.negotiateParser(for: makeResp("application/sparql-results+json;charset=utf-8")) is SPARQLJSONParser)
    }

    func testExtendedSharedConneg() {
        SPARQLContentNegotiator.shared.addSerializer(TestSerializer())

        let c = SPARQLContentNegotiator.shared

        XCTAssertEqual(c.negotiateSerializer(for: boolResult, accept: ["text/html"])!.canonicalMediaType, "x-text/html")
        XCTAssertEqual(c.negotiateSerializer(for: triplesResult, accept: ["text/html"])!.canonicalMediaType, "x-text/html")
        XCTAssertEqual(c.negotiateSerializer(for: bindingsResult, accept: ["text/html"])!.canonicalMediaType, "x-text/html")
    }
}

struct TestSerializer: SPARQLSerializable {
    var serializesTriples = true
    var serializesBindings = true
    var serializesBoolean = true
    var canonicalMediaType = "x-text/html"
    var acceptableMediaTypes = ["text/html", "x-text/html"]
    
    func serialize<R, T>(_ results: QueryResult<R, T>) throws -> Data where R : Sequence, T : Sequence, R.Element == SPARQLResultSolution<Term>, T.Element == Triple {
        return "<html><h1>Hello!</h1></html>".data(using: .utf8)!
    }
}
