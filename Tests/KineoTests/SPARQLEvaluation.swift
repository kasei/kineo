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
    
    func runEvaluationTests(inPath path: URL, skip: Set<String>? = nil) throws {
        print("Manifest directory: \(path)")
        let positiveTestType = Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#QueryEvaluationTest")
        let results = try testRunner.runEvaluationTests(inPath: path, testType: positiveTestType, skip: skip)
        handle(testResults: results)
    }

    func test10Evaluation_basic() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("basic")
        let skip = Set([
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/basic/manifest#term-6",
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/basic/manifest#term-7"
            ])
        try runEvaluationTests(inPath: path, skip: skip)
    }
    
    func test10Evaluation_triple_match() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("triple-match")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_open_world() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("open-world")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_algebra() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("algebra")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_bnode_coreference() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("bnode-coreference")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_optional() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("optional")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_optional_filter() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("optional-filter")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_graph() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("graph")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_dataset() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("dataset")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_type_promotion() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("type-promotion")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_cast() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("cast")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_boolean_effective_value() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("boolean-effective-value")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_bound() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("bound")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_expr_builtin() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("expr-builtin")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_expr_ops() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("expr-ops")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_expr_equals() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("expr-equals")
        let skip = Set([
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/expr-equals/manifest#eq-graph-1",
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/expr-equals/manifest#eq-graph-2",
            ])
        try runEvaluationTests(inPath: path, skip: skip)
    }
    
    func test10Evaluation_regex() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("regex")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_i18n() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("i18n")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_construct() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("construct")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_ask() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("ask")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_distinct() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("distinct")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_sort() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("sort")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_solution_seq() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("solution-seq")
        try runEvaluationTests(inPath: path)
    }
    
    func test10Evaluation_reduced() throws {
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("reduced")
        try runEvaluationTests(inPath: path)
    }
    
    
    
    
    

    func test11Evaluation_aggregates() throws {
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("aggregates")
        try runEvaluationTests(inPath: path)
    }

    func test11Evaluation_bind() throws {
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("bind")
        try runEvaluationTests(inPath: path)
    }
    
    func test11Evaluation_bindings() throws {
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("bindings")
        try runEvaluationTests(inPath: path)
    }
    
    func test11Evaluation_construct() throws {
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("construct")
        try runEvaluationTests(inPath: path)
    }
    
    func test11Evaluation_exists() throws {
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("exists")
        try runEvaluationTests(inPath: path)
    }
    
    func test11Evaluation_functions() throws {
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("functions")
        try runEvaluationTests(inPath: path)
    }
    
    func test11Evaluation_grouping() throws {
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("grouping")
        try runEvaluationTests(inPath: path)
    }
    
    func test11Evaluation_negation() throws {
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("negation")
        try runEvaluationTests(inPath: path)
    }
    
    func test11Evaluation_project_expression() throws {
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("project-expression")
        try runEvaluationTests(inPath: path)
    }
    
    func test11Evaluation_property_path() throws {
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("property-path")
        try runEvaluationTests(inPath: path)
    }
    
    func test11Evaluation_subquery() throws {
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("subquery")
        try runEvaluationTests(inPath: path)
    }
    
    func test11Evaluation_syntax_query() throws {
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("syntax-query")
        try runEvaluationTests(inPath: path)
    }
}
