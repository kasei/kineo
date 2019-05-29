import XCTest
import Foundation
import SPARQLSyntax
@testable import Kineo

#if os(Linux)
extension SPARQL12EvaluationTest {
    static var allTests : [(String, (SPARQL12EvaluationTest) -> () throws -> Void)] {
        return [
            ("test12Evaluation_xsdfunctions", test12Evaluation_xsdfunctions),
        ]
    }
}
#endif

// swiftlint:disable type_body_length
class SPARQL12EvaluationTest: XCTestCase {
    var sparql12Base: URL!
    var testRunner: SPARQLTestRunner!
    override func setUp() {
        super.setUp()
        guard let rdfTestsBase = ProcessInfo.processInfo.environment["KINEO_W3C_TEST_PATH_12"] else { fatalError("*** KINEO_W3C_TEST_PATH environment variable must be set") }
        let base = NSURL(fileURLWithPath: rdfTestsBase)
        sparql12Base = base.appendingPathComponent("tests")
        testRunner = SPARQLTestRunner()
        testRunner.requireTestApproval = false
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
    
    func runEvaluationTests(inPath path: URL, skip: Set<String>? = nil) throws {
        print("Manifest directory: \(path)")
        let positiveTestType = Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#QueryEvaluationTest")
        let results = try testRunner.runEvaluationTests(inPath: path, testType: positiveTestType, skip: skip)
        handle(testResults: results)
    }

    func test12Evaluation_xsdfunctions() throws {
        let path = sparql12Base.appendingPathComponent("xsd_functions")
        try runEvaluationTests(inPath: path)
    }
}
