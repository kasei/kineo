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
    var sparql10Base: URL!
    var testRunner: SPARQLTestRunner<MemoryQuadStore>!
    
    override func setUp() {
        super.setUp()
        if let rdfTestsBase = ProcessInfo.processInfo.environment["KINEO_W3C_TEST_PATH"] {
            let base = NSURL(fileURLWithPath: rdfTestsBase)
            sparqlBase = base.appendingPathComponent("sparql11")
            sparql10Base = base.appendingPathComponent("sparql10")
        } else {
            sparqlBase = nil
        }
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
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let subdirs = ["syntax-query"]
        for dir in subdirs {
            let path = sparqlBase.appendingPathComponent(dir)
            let positiveTestType = Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#PositiveSyntaxTest11")
            let results = try testRunner.runSyntaxTests(inPath: path, testType: positiveTestType)
            handle(testResults: results)
        }
    }
    
    func testNegative11Syntax() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let subdirs = ["syntax-query"]
        for dir in subdirs {
            let path = sparqlBase.appendingPathComponent(dir)
            let negativeTestType = Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#NegativeSyntaxTest11")
            let results = try testRunner.runSyntaxTests(inPath: path, testType: negativeTestType, expectFailure: true)
            handle(testResults: results)
        }
    }
    
    func testPositive10Syntax() throws {
        guard sparql10Base != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let subdirs = ["syntax-sparql1", "syntax-sparql2", "syntax-sparql3", "syntax-sparql4", "syntax-sparql5"]
        let skip = Set([
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/syntax-sparql1/manifest#syntax-lit-08", // syntax changed in SPARQL 1.1, disallowing floats with a trailing dot without fractional digits ("7.")
            ])
        for dir in subdirs {
            let path = sparql10Base.appendingPathComponent(dir)
            let testType = Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#PositiveSyntaxTest")
            let results = try testRunner.runSyntaxTests(inPath: path, testType: testType, skip: skip)
            handle(testResults: results)
        }
    }
    
    func testNegative10Syntax() throws {
        guard sparql10Base != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let subdirs = ["syntax-sparql1", "syntax-sparql2", "syntax-sparql3", "syntax-sparql4", "syntax-sparql5"]
        for dir in subdirs {
            let path = sparql10Base.appendingPathComponent(dir)
            let testType = Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#NegativeSyntaxTest")
            let results = try testRunner.runSyntaxTests(inPath: path, testType: testType, expectFailure: true)
            handle(testResults: results)
        }
    }
}
