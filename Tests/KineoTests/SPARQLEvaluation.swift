import XCTest
import Foundation
import SPARQLSyntax
@testable import Kineo

#if os(Linux)
extension SPARQLEvaluationTest {
    static var allTests : [(String, (SPARQLEvaluationTest) -> () throws -> Void)] {
        return [
            ("testPositive11Evaluation", testPositive11Evaluation),
        ]
    }
}
#endif

// swiftlint:disable type_body_length
class SPARQLEvaluationTest: XCTestCase {
    var sparqlBase: URL!
    var testRunner: SPARQLTestRunner!
    override func setUp() {
        super.setUp()
        guard let rdfTestsBase = ProcessInfo.processInfo.environment["KINEO_W3C_TEST_PATH"] else { fatalError("*** KINEO_W3C_TEST_PATH environment variable must be set") }
        let base = NSURL(fileURLWithPath: rdfTestsBase)
        sparqlBase = base.appendingPathComponent("sparql11")
        testRunner = SPARQLTestRunner()
    }
    
    override func tearDown() {
        super.tearDown()
    }
   
    func handle(testResults results: [SPARQLTestRunner.TestResult]) {
        for result in results {
            switch result {
            case let .success(test):
                XCTAssertTrue(true, test)
            case let .failure(test, reason):
                XCTFail("failed test <\(test)>: \(reason)")
            }
        }
    }
    
    func runEvaluationTests(inPathComponent dir: String) throws {
        print("Manifest directory: \(dir)")
        let sparql11Path = sparqlBase.appendingPathComponent("data-sparql11")
        let path = sparql11Path.appendingPathComponent(dir)
        let positiveTestType = Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#QueryEvaluationTest")
        let results = try testRunner.runEvaluationTests(inPath: path, testType: positiveTestType)
        handle(testResults: results)
    }

    func test11Evaluation_aggregates() throws {
        try runEvaluationTests(inPathComponent: "aggregates")
    }

    func test11Evaluation_bind() throws {
        try runEvaluationTests(inPathComponent: "bind")
    }
    
    func test11Evaluation_bindings() throws {
        try runEvaluationTests(inPathComponent: "bindings")
    }
    
    func test11Evaluation_construct() throws {
        try runEvaluationTests(inPathComponent: "construct")
    }
    
    func test11Evaluation_exists() throws {
        try runEvaluationTests(inPathComponent: "exists")
    }
    
    func test11Evaluation_functions() throws {
        try runEvaluationTests(inPathComponent: "functions")
    }
    
    func test11Evaluation_grouping() throws {
        try runEvaluationTests(inPathComponent: "grouping")
    }
    
    func test11Evaluation_negation() throws {
        try runEvaluationTests(inPathComponent: "negation")
    }
    
    func test11Evaluation_project_expression() throws {
        try runEvaluationTests(inPathComponent: "project-expression")
    }
    
    func test11Evaluation_property_path() throws {
        try runEvaluationTests(inPathComponent: "property-path")
    }
    
    func test11Evaluation_subquery() throws {
        try runEvaluationTests(inPathComponent: "subquery")
    }
    
    func test11Evaluation_syntax_query() throws {
        try runEvaluationTests(inPathComponent: "syntax-query")
    }
}
