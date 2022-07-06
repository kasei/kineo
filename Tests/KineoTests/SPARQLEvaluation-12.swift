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
class SPARQL12EvaluationTest: SPARQLEvaluationTestImpl<MemoryQuadStore> {
    typealias M = MemoryQuadStore
    var sparqlBase: URL!
    var testRunner: SPARQLTestRunner<M>!
    override func setUp() {
        super.setUp()
        guard let rdfTestsBase = ProcessInfo.processInfo.environment["KINEO_W3C_TEST_PATH_12"] else { fatalError("*** KINEO_W3C_TEST_PATH_12 environment variable must be set") }
        let base = NSURL(fileURLWithPath: rdfTestsBase)
        sparqlBase = base.appendingPathComponent("tests")
        testRunner = SPARQLTestRunner(newStore: { return M() })
        testRunner.requireTestApproval = false
    }
    
    override func tearDown() {
        super.tearDown()
    }

    override func getTestRunner() -> SPARQLTestRunner<M>! {
        return testRunner
    }

    override func getSPARQLBase() -> URL? {
        if let rdfTestsBase = ProcessInfo.processInfo.environment["KINEO_W3C_TEST_PATH"] {
            let base = NSURL(fileURLWithPath: rdfTestsBase)
            return base.appendingPathComponent("sparql11")
        } else {
            return nil
        }
    }
    
    override func getSPARQLBase12() -> URL? {
        if let rdfTestsBase = ProcessInfo.processInfo.environment["KINEO_W3C_TEST_PATH_12"] {
            let base = NSURL(fileURLWithPath: rdfTestsBase)
            return base.appendingPathComponent("tests")
        } else {
            return nil
        }
    }

    func test12Evaluation_xsdfunctions() throws {
        guard let sparqlBase = getSPARQLBase12() else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("xsd_functions")
        try runEvaluationTests(inPath: path)
    }
}
