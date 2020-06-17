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

extension SPARQLEvaluationTestImpl {
    func _test12Evaluation_xsdfunctions() throws {
        let path = sparqlBase.appendingPathComponent("xsd_functions")
        try runEvaluationTests(inPath: path)
    }
}

// swiftlint:disable type_body_length
class SPARQL12EvaluationTest: XCTestCase, SPARQLEvaluationTestImpl {
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
   
    func test12Evaluation_xsdfunctions() throws { try _test12Evaluation_xsdfunctions() }
}
