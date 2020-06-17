import XCTest
import Foundation
import SPARQLSyntax
@testable import Kineo

#if os(Linux)
extension SPARQLSyntaxTest {
    static var allTests : [(String, (SPARQLSyntaxTest) -> () throws -> Void)] {
        return [
            ("testPositive10Syntax", testPositive10Syntax),
            ("testNegative10Syntax", testNegative10Syntax),
            ("testPositive11Syntax", testPositive11Syntax),
            ("testNegative11Syntax", testNegative11Syntax),
        ]
    }
}
#endif

// swiftlint:disable type_body_length
class SPARQLSyntaxTest: XCTestCase {
    var sparqlBase: URL!
    var testRunner: SPARQLTestRunner<MemoryQuadStore>!
    
    override func setUp() {
        super.setUp()
        guard let rdfTestsBase = ProcessInfo.processInfo.environment["KINEO_W3C_TEST_PATH"] else { fatalError("*** KINEO_W3C_TEST_PATH environment variable must be set") }
        let base = NSURL(fileURLWithPath: rdfTestsBase)
        sparqlBase = base.appendingPathComponent("sparql11")
        let newStore = { return MemoryQuadStore() }
        testRunner = SPARQLTestRunner(newStore: newStore)
    }
    
    override func tearDown() {
        super.tearDown()
    }

    func handle<M: MutableQuadStoreProtocol>(testResults results: [SPARQLTestRunner<M>.TestResult]) {
        for result in results {
            switch result {
            case let .success(test, _):
                XCTAssertTrue(true, test)
            case let .failure(test, _, reason):
                XCTFail("failed test <\(test)>: \(reason)")
            }
        }
    }
    
    func testPositive11Syntax() throws {
        let sparql11Path = sparqlBase.appendingPathComponent("data-sparql11")
        let subdirs = ["syntax-query"]
        for dir in subdirs {
            let path = sparql11Path.appendingPathComponent(dir)
            let positiveTestType = Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#PositiveSyntaxTest11")
            let results = try testRunner.runSyntaxTests(inPath: path, testType: positiveTestType)
            handle(testResults: results)
        }
    }
    
    func testNegative11Syntax() throws {
        let sparql11Path = sparqlBase.appendingPathComponent("data-sparql11")
        let subdirs = ["syntax-query"]
        for dir in subdirs {
            let path = sparql11Path.appendingPathComponent(dir)
            let negativeTestType = Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#NegativeSyntaxTest11")
            let results = try testRunner.runSyntaxTests(inPath: path, testType: negativeTestType, expectFailure: true)
            handle(testResults: results)
        }
    }
    
    func testPositive10Syntax() throws {
        let sparql10Path = sparqlBase.appendingPathComponent("data-r2")
        let subdirs = ["syntax-sparql1", "syntax-sparql2", "syntax-sparql3", "syntax-sparql4", "syntax-sparql5"]
        let skip = Set([
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/syntax-sparql1/manifest#syntax-lit-08", // syntax changed in SPARQL 1.1, disallowing floats with a trailing dot without fractional digits ("7.")
            ])
        for dir in subdirs {
            let path = sparql10Path.appendingPathComponent(dir)
            let testType = Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#PositiveSyntaxTest")
            let results = try testRunner.runSyntaxTests(inPath: path, testType: testType, skip: skip)
            handle(testResults: results)
        }
    }
    
    func testNegative10Syntax() throws {
        let sparql10Path = sparqlBase.appendingPathComponent("data-r2")
        let subdirs = ["syntax-sparql1", "syntax-sparql2", "syntax-sparql3", "syntax-sparql4", "syntax-sparql5"]
        for dir in subdirs {
            let path = sparql10Path.appendingPathComponent(dir)
            let testType = Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#NegativeSyntaxTest")
            let results = try testRunner.runSyntaxTests(inPath: path, testType: testType, expectFailure: true)
            handle(testResults: results)
        }
    }
}
