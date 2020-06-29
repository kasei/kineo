import XCTest
import Foundation
import SPARQLSyntax
import DiomedeQuadStore
@testable import Kineo

#if os(Linux)
extension DiomedeStore_SPARQLEvaluationTest {
    static var allTests : [(String, (MemoryStore_SPARQLEvaluationTest) -> () throws -> Void)] {
        return [
            ("test10Evaluation_basic", MemoryStore_SPARQLEvaluationTest.test10Evaluation_basic),
            ("test10Evaluation_triple_match", MemoryStore_SPARQLEvaluationTest.test10Evaluation_triple_match),
            ("test10Evaluation_open_world", MemoryStore_SPARQLEvaluationTest.test10Evaluation_open_world),
            ("test10Evaluation_algebra", MemoryStore_SPARQLEvaluationTest.test10Evaluation_algebra),
            ("test10Evaluation_bnode_coreference", MemoryStore_SPARQLEvaluationTest.test10Evaluation_bnode_coreference),
            ("test10Evaluation_optional", MemoryStore_SPARQLEvaluationTest.test10Evaluation_optional),
            ("test10Evaluation_graph", MemoryStore_SPARQLEvaluationTest.test10Evaluation_graph),
            ("test10Evaluation_dataset", MemoryStore_SPARQLEvaluationTest.test10Evaluation_dataset),
            ("test10Evaluation_type_promotion", MemoryStore_SPARQLEvaluationTest.test10Evaluation_type_promotion),
            ("test10Evaluation_cast", MemoryStore_SPARQLEvaluationTest.test10Evaluation_cast),
            ("test10Evaluation_boolean_effective_value", MemoryStore_SPARQLEvaluationTest.test10Evaluation_boolean_effective_value),
            ("test10Evaluation_bound", MemoryStore_SPARQLEvaluationTest.test10Evaluation_bound),
            ("test10Evaluation_expr_builtin", MemoryStore_SPARQLEvaluationTest.test10Evaluation_expr_builtin),
            ("test10Evaluation_expr_ops", MemoryStore_SPARQLEvaluationTest.test10Evaluation_expr_ops),
            ("test10Evaluation_expr_equals", MemoryStore_SPARQLEvaluationTest.test10Evaluation_expr_equals),
            ("test10Evaluation_regex", MemoryStore_SPARQLEvaluationTest.test10Evaluation_regex),
            ("test10Evaluation_i18n", MemoryStore_SPARQLEvaluationTest.test10Evaluation_i18n),
            ("test10Evaluation_construct", MemoryStore_SPARQLEvaluationTest.test10Evaluation_construct),
            ("test10Evaluation_ask", MemoryStore_SPARQLEvaluationTest.test10Evaluation_ask),
            ("test10Evaluation_distinct", MemoryStore_SPARQLEvaluationTest.test10Evaluation_distinct),
            ("test10Evaluation_sort", MemoryStore_SPARQLEvaluationTest.test10Evaluation_sort),
            ("test10Evaluation_solution_seq", MemoryStore_SPARQLEvaluationTest.test10Evaluation_solution_seq),
            ("test10Evaluation_reduced", MemoryStore_SPARQLEvaluationTest.test10Evaluation_reduced),
            ("test11Evaluation_aggregates", MemoryStore_SPARQLEvaluationTest.test11Evaluation_aggregates),
            ("test11Evaluation_bind", MemoryStore_SPARQLEvaluationTest.test11Evaluation_bind),
            ("test11Evaluation_bindings", MemoryStore_SPARQLEvaluationTest.test11Evaluation_bindings),
            ("test11Evaluation_construct", MemoryStore_SPARQLEvaluationTest.test11Evaluation_construct),
            ("test11Evaluation_exists", MemoryStore_SPARQLEvaluationTest.test11Evaluation_exists),
            ("test11Evaluation_functions", MemoryStore_SPARQLEvaluationTest.test11Evaluation_functions),
            ("test11Evaluation_grouping", MemoryStore_SPARQLEvaluationTest.test11Evaluation_grouping),
            ("test11Evaluation_negation", MemoryStore_SPARQLEvaluationTest.test11Evaluation_negation),
            ("test11Evaluation_project_expression", MemoryStore_SPARQLEvaluationTest.test11Evaluation_project_expression),
            ("test11Evaluation_property_path", MemoryStore_SPARQLEvaluationTest.test11Evaluation_property_path),
            ("test11Evaluation_subquery", MemoryStore_SPARQLEvaluationTest.test11Evaluation_subquery),
            ("test11Evaluation_syntax_query", MemoryStore_SPARQLEvaluationTest.test11Evaluation_syntax_query),
        ]
    }
}

extension MemoryStore_SPARQLEvaluationTest {
    static var allTests : [(String, (MemoryStore_SPARQLEvaluationTest) -> () throws -> Void)] {
        return [
            ("test10Evaluation_basic", MemoryStore_SPARQLEvaluationTest.test10Evaluation_basic),
            ("test10Evaluation_triple_match", MemoryStore_SPARQLEvaluationTest.test10Evaluation_triple_match),
            ("test10Evaluation_open_world", MemoryStore_SPARQLEvaluationTest.test10Evaluation_open_world),
            ("test10Evaluation_algebra", MemoryStore_SPARQLEvaluationTest.test10Evaluation_algebra),
            ("test10Evaluation_bnode_coreference", MemoryStore_SPARQLEvaluationTest.test10Evaluation_bnode_coreference),
            ("test10Evaluation_optional", MemoryStore_SPARQLEvaluationTest.test10Evaluation_optional),
            ("test10Evaluation_graph", MemoryStore_SPARQLEvaluationTest.test10Evaluation_graph),
            ("test10Evaluation_dataset", MemoryStore_SPARQLEvaluationTest.test10Evaluation_dataset),
            ("test10Evaluation_type_promotion", MemoryStore_SPARQLEvaluationTest.test10Evaluation_type_promotion),
            ("test10Evaluation_cast", MemoryStore_SPARQLEvaluationTest.test10Evaluation_cast),
            ("test10Evaluation_boolean_effective_value", MemoryStore_SPARQLEvaluationTest.test10Evaluation_boolean_effective_value),
            ("test10Evaluation_bound", MemoryStore_SPARQLEvaluationTest.test10Evaluation_bound),
            ("test10Evaluation_expr_builtin", MemoryStore_SPARQLEvaluationTest.test10Evaluation_expr_builtin),
            ("test10Evaluation_expr_ops", MemoryStore_SPARQLEvaluationTest.test10Evaluation_expr_ops),
            ("test10Evaluation_expr_equals", MemoryStore_SPARQLEvaluationTest.test10Evaluation_expr_equals),
            ("test10Evaluation_regex", MemoryStore_SPARQLEvaluationTest.test10Evaluation_regex),
            ("test10Evaluation_i18n", MemoryStore_SPARQLEvaluationTest.test10Evaluation_i18n),
            ("test10Evaluation_construct", MemoryStore_SPARQLEvaluationTest.test10Evaluation_construct),
            ("test10Evaluation_ask", MemoryStore_SPARQLEvaluationTest.test10Evaluation_ask),
            ("test10Evaluation_distinct", MemoryStore_SPARQLEvaluationTest.test10Evaluation_distinct),
            ("test10Evaluation_sort", MemoryStore_SPARQLEvaluationTest.test10Evaluation_sort),
            ("test10Evaluation_solution_seq", MemoryStore_SPARQLEvaluationTest.test10Evaluation_solution_seq),
            ("test10Evaluation_reduced", MemoryStore_SPARQLEvaluationTest.test10Evaluation_reduced),
            ("test11Evaluation_aggregates", MemoryStore_SPARQLEvaluationTest.test11Evaluation_aggregates),
            ("test11Evaluation_bind", MemoryStore_SPARQLEvaluationTest.test11Evaluation_bind),
            ("test11Evaluation_bindings", MemoryStore_SPARQLEvaluationTest.test11Evaluation_bindings),
            ("test11Evaluation_construct", MemoryStore_SPARQLEvaluationTest.test11Evaluation_construct),
            ("test11Evaluation_exists", MemoryStore_SPARQLEvaluationTest.test11Evaluation_exists),
            ("test11Evaluation_functions", MemoryStore_SPARQLEvaluationTest.test11Evaluation_functions),
            ("test11Evaluation_grouping", MemoryStore_SPARQLEvaluationTest.test11Evaluation_grouping),
            ("test11Evaluation_negation", MemoryStore_SPARQLEvaluationTest.test11Evaluation_negation),
            ("test11Evaluation_project_expression", MemoryStore_SPARQLEvaluationTest.test11Evaluation_project_expression),
            ("test11Evaluation_property_path", MemoryStore_SPARQLEvaluationTest.test11Evaluation_property_path),
            ("test11Evaluation_subquery", MemoryStore_SPARQLEvaluationTest.test11Evaluation_subquery),
            ("test11Evaluation_syntax_query", MemoryStore_SPARQLEvaluationTest.test11Evaluation_syntax_query),
        ]
    }
}
#endif

protocol SPARQLEvaluationTestImpl {
    associatedtype M: MutableQuadStoreProtocol
    var testRunner: SPARQLTestRunner<M>! { get }
    var sparqlBase: URL! { get }
}

extension SPARQLEvaluationTestImpl {
    func handle(testResults results: [SPARQLTestRunner<M>.TestResult]) {
        for result in results {
            switch result {
            case let .success(test, _):
                XCTAssertTrue(true, test)
            case let .failure(test, _, reason):
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
    
    func _test10Evaluation_basic() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("basic")
        let skip = Set([
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/basic/manifest#term-6",
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/basic/manifest#term-7"
        ])
        try runEvaluationTests(inPath: path, skip: skip)
    }
    
    func _test10Evaluation_triple_match() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("triple-match")
        try runEvaluationTests(inPath: path)
    }
    
    func _test10Evaluation_open_world() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        // many of these tests rely on not canonicalizing Terms on load
        //        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("open-world")
        //        try runEvaluationTests(inPath: path)
    }
    
    func _test10Evaluation_algebra() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("algebra")
        try runEvaluationTests(inPath: path)
    }
    
    func _test10Evaluation_bnode_coreference() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("bnode-coreference")
        try runEvaluationTests(inPath: path)
    }
    
    func _test10Evaluation_optional() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("optional")
        try runEvaluationTests(inPath: path)
    }
    
    func _test10Evaluation_graph() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("graph")
        try runEvaluationTests(inPath: path)
    }
    
    func _test10Evaluation_dataset() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("dataset")
        try runEvaluationTests(inPath: path)
    }
    
    func _test10Evaluation_type_promotion() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("type-promotion")
        try runEvaluationTests(inPath: path)
    }
    
    func _test10Evaluation_cast() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("cast")
        try runEvaluationTests(inPath: path)
    }
    
    func _test10Evaluation_boolean_effective_value() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("boolean-effective-value")
        try runEvaluationTests(inPath: path)
    }
    
    func _test10Evaluation_bound() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("bound")
        try runEvaluationTests(inPath: path)
    }
    
    func _test10Evaluation_expr_builtin() throws {
        // many of these tests rely on not canonicalizing Terms on load
        let skip = Set([
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/expr-builtin/manifest#sameTerm-simple",
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/expr-builtin/manifest#dawg-str-2",
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/expr-builtin/manifest#dawg-str-1",
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/expr-builtin/manifest#sameTerm-not-eq",
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/expr-builtin/manifest#sameTerm-eq",
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/expr-builtin/manifest#dawg-datatype-2",
        ])
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("expr-builtin")
        try runEvaluationTests(inPath: path, skip: skip)
    }
    
    func _test10Evaluation_expr_ops() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("expr-ops")
        try runEvaluationTests(inPath: path)
    }
    
    func _test10Evaluation_expr_equals() throws {
        // many of these tests rely on not canonicalizing Terms on load
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("expr-equals")
        let skip = Set([
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/expr-equals/manifest#eq-graph-1",
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/expr-equals/manifest#eq-graph-2",
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/expr-equals/manifest#eq-2-1",
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/expr-equals/manifest#eq-2-2",
        ])
        try runEvaluationTests(inPath: path, skip: skip)
    }
    
    func _test10Evaluation_regex() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("regex")
        try runEvaluationTests(inPath: path)
    }
    
    func _test10Evaluation_i18n() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("i18n")
        try runEvaluationTests(inPath: path)
    }
    
    func _test10Evaluation_construct() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("construct")
        try runEvaluationTests(inPath: path)
    }
    
    func _test10Evaluation_ask() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("ask")
        try runEvaluationTests(inPath: path)
    }
    
    func _test10Evaluation_distinct() throws {
        // many of these tests rely on not canonicalizing Terms on load
        let skip = Set([
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/distinct/manifest#distinct-9",
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/distinct/manifest#distinct-2",
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/distinct/manifest#distinct-1",
        ])
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("distinct")
        try runEvaluationTests(inPath: path, skip: skip)
    }
    
    func _test10Evaluation_sort() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("sort")
        try runEvaluationTests(inPath: path)
    }
    
    func _test10Evaluation_solution_seq() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("solution-seq")
        try runEvaluationTests(inPath: path)
    }
    
    func _test10Evaluation_reduced() throws {
        // many of these tests rely on not canonicalizing Terms on load
        let skip = Set([
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/reduced/manifest#reduced-1",
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/reduced/manifest#reduced-2",
        ])
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-r2").appendingPathComponent("reduced")
        try runEvaluationTests(inPath: path, skip: skip)
    }
    
    
    
    
    
    
    func _test11Evaluation_aggregates() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("aggregates")
        try runEvaluationTests(inPath: path)
    }
    
    func _test11Evaluation_bind() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("bind")
        try runEvaluationTests(inPath: path)
    }
    
    func _test11Evaluation_bindings() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("bindings")
        try runEvaluationTests(inPath: path)
    }
    
    func _test11Evaluation_construct() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("construct")
        try runEvaluationTests(inPath: path)
    }
    
    func _test11Evaluation_exists() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("exists")
        try runEvaluationTests(inPath: path)
    }
    
    func _test11Evaluation_functions() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("functions")
        try runEvaluationTests(inPath: path)
    }
    
    func _test11Evaluation_grouping() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("grouping")
        try runEvaluationTests(inPath: path)
    }
    
    func _test11Evaluation_negation() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("negation")
        try runEvaluationTests(inPath: path)
    }
    
    func _test11Evaluation_project_expression() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("project-expression")
        try runEvaluationTests(inPath: path)
    }
    
    func _test11Evaluation_property_path() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("property-path")
        try runEvaluationTests(inPath: path)
    }
    
    func _test11Evaluation_subquery() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("subquery")
        try runEvaluationTests(inPath: path)
    }
    
    func _test11Evaluation_syntax_query() throws {
        guard sparqlBase != nil else { throw XCTSkip("SPARQL tests base location missing; set the KINEO_W3C_TEST_PATH environment variable") }
        let path = sparqlBase.appendingPathComponent("data-sparql11").appendingPathComponent("syntax-query")
        try runEvaluationTests(inPath: path)
    }

}

// swiftlint:disable type_body_length
class MemoryStore_SPARQLEvaluationTest: XCTestCase, SPARQLEvaluationTestImpl {
    typealias M = MemoryQuadStore
    var sparqlBase: URL!
    var testRunner: SPARQLTestRunner<M>!
    override func setUp() {
        super.setUp()
        if let rdfTestsBase = ProcessInfo.processInfo.environment["KINEO_W3C_TEST_PATH"] {
            let base = NSURL(fileURLWithPath: rdfTestsBase)
            sparqlBase = base.appendingPathComponent("sparql11")
        } else {
            sparqlBase = nil
        }
        testRunner = SPARQLTestRunner(newStore: { return M() })
//        testRunner.verbose = true
    }
    
    override func tearDown() {
        super.tearDown()
    }
   
    func test10Evaluation_algebra() throws { return try _test10Evaluation_algebra() }
    func test10Evaluation_ask() throws { return try _test10Evaluation_ask() }
    func test10Evaluation_basic() throws { return try _test10Evaluation_basic() }
    func test10Evaluation_bnode_coreference() throws { return try _test10Evaluation_bnode_coreference() }
    func test10Evaluation_boolean_effective_value() throws { return try _test10Evaluation_boolean_effective_value() }
    func test10Evaluation_bound() throws { return try _test10Evaluation_bound() }
    func test10Evaluation_cast() throws { return try _test10Evaluation_cast() }
    func test10Evaluation_construct() throws { return try _test10Evaluation_construct() }
    func test10Evaluation_dataset() throws { return try _test10Evaluation_dataset() }
    func test10Evaluation_distinct() throws { return try _test10Evaluation_distinct() }
    func test10Evaluation_expr_builtin() throws { return try _test10Evaluation_expr_builtin() }
    func test10Evaluation_expr_equals() throws { return try _test10Evaluation_expr_equals() }
    func test10Evaluation_expr_ops() throws { return try _test10Evaluation_expr_ops() }
    func test10Evaluation_graph() throws { return try _test10Evaluation_graph() }
    func test10Evaluation_i18n() throws { return try _test10Evaluation_i18n() }
    func test10Evaluation_open_world() throws { return try _test10Evaluation_open_world() }
    func test10Evaluation_optional() throws { return try _test10Evaluation_optional() }
    func test10Evaluation_reduced() throws { return try _test10Evaluation_reduced() }
    func test10Evaluation_regex() throws { return try _test10Evaluation_regex() }
    func test10Evaluation_solution_seq() throws { return try _test10Evaluation_solution_seq() }
    func test10Evaluation_sort() throws { return try _test10Evaluation_sort() }
    func test10Evaluation_triple_match() throws { return try _test10Evaluation_triple_match() }
    func test10Evaluation_type_promotion() throws { return try _test10Evaluation_type_promotion() }
    func test11Evaluation_aggregates() throws { return try _test11Evaluation_aggregates() }
    func test11Evaluation_bind() throws { return try _test11Evaluation_bind() }
    func test11Evaluation_bindings() throws { return try _test11Evaluation_bindings() }
    func test11Evaluation_construct() throws { return try _test11Evaluation_construct() }
    func test11Evaluation_exists() throws { return try _test11Evaluation_exists() }
    func test11Evaluation_functions() throws { return try _test11Evaluation_functions() }
    func test11Evaluation_grouping() throws { return try _test11Evaluation_grouping() }
    func test11Evaluation_negation() throws { return try _test11Evaluation_negation() }
    func test11Evaluation_project_expression() throws { return try _test11Evaluation_project_expression() }
    func test11Evaluation_property_path() throws { return try _test11Evaluation_property_path() }
    func test11Evaluation_subquery() throws { return try _test11Evaluation_subquery() }
    func test11Evaluation_syntax_query() throws { return try _test11Evaluation_syntax_query() }
}

// swiftlint:disable type_body_length
class DiomedeStore_SPARQLEvaluationTest: XCTestCase, SPARQLEvaluationTestImpl {
    typealias M = DiomedeQuadStore
    var sparqlBase: URL!
    var filename: URL!
    var testRunner: SPARQLTestRunner<M>!
    override func setUp() {
        super.setUp()
        if let rdfTestsBase = ProcessInfo.processInfo.environment["KINEO_W3C_TEST_PATH"] {
            let base = NSURL(fileURLWithPath: rdfTestsBase)
            sparqlBase = base.appendingPathComponent("sparql11")
        } else {
            sparqlBase = nil
        }
        testRunner = SPARQLTestRunner {
            let f = FileManager.default
            let dir = f.temporaryDirectory
            let filename = "kineo-test-\(UUID().uuidString).db"
            let path = dir.appendingPathComponent(filename)
            self.filename = path
            guard let store = DiomedeQuadStore(path: self.filename.path, create: true) else {
                fatalError()
            }
            return store
        }
    }
    
    override func tearDown() {
        super.tearDown()
        #if os(macOS)
        let f = FileManager.default
        try? f.trashItem(at: self.filename, resultingItemURL: nil)
        #endif
    }
   
    func test10Evaluation_algebra() throws {
        return try _test10Evaluation_algebra()
        
    }
    func test10Evaluation_ask() throws { return try _test10Evaluation_ask() }
    func test10Evaluation_basic() throws { return try _test10Evaluation_basic() }
    func test10Evaluation_bnode_coreference() throws { return try _test10Evaluation_bnode_coreference() }
    func test10Evaluation_boolean_effective_value() throws { return try _test10Evaluation_boolean_effective_value() }
    func test10Evaluation_bound() throws { return try _test10Evaluation_bound() }
    func test10Evaluation_cast() throws { return try _test10Evaluation_cast() }
    func test10Evaluation_construct() throws { return try _test10Evaluation_construct() }
    func test10Evaluation_dataset() throws { return try _test10Evaluation_dataset() }
    func test10Evaluation_distinct() throws { return try _test10Evaluation_distinct() }
    func test10Evaluation_expr_builtin() throws { return try _test10Evaluation_expr_builtin() }
    func test10Evaluation_expr_equals() throws { return try _test10Evaluation_expr_equals() }
    func test10Evaluation_expr_ops() throws { return try _test10Evaluation_expr_ops() }
    func test10Evaluation_graph() throws { return try _test10Evaluation_graph() }
    func test10Evaluation_i18n() throws { return try _test10Evaluation_i18n() }
    func test10Evaluation_open_world() throws { return try _test10Evaluation_open_world() }
    func test10Evaluation_optional() throws { return try _test10Evaluation_optional() }
    func test10Evaluation_reduced() throws { return try _test10Evaluation_reduced() }
    func test10Evaluation_regex() throws { return try _test10Evaluation_regex() }
    func test10Evaluation_solution_seq() throws { return try _test10Evaluation_solution_seq() }
    func test10Evaluation_sort() throws { return try _test10Evaluation_sort() }
    func test10Evaluation_triple_match() throws { return try _test10Evaluation_triple_match() }
    func test10Evaluation_type_promotion() throws { return try _test10Evaluation_type_promotion() }
    func test11Evaluation_aggregates() throws { return try _test11Evaluation_aggregates() }
    func test11Evaluation_bind() throws { return try _test11Evaluation_bind() }
    func test11Evaluation_bindings() throws { return try _test11Evaluation_bindings() }
    func test11Evaluation_construct() throws { return try _test11Evaluation_construct() }
    func test11Evaluation_exists() throws { return try _test11Evaluation_exists() }
    func test11Evaluation_functions() throws { return try _test11Evaluation_functions() }
    func test11Evaluation_grouping() throws { return try _test11Evaluation_grouping() }
    func test11Evaluation_negation() throws { return try _test11Evaluation_negation() }
    func test11Evaluation_project_expression() throws { return try _test11Evaluation_project_expression() }
    func test11Evaluation_property_path() throws { return try _test11Evaluation_property_path() }
    func test11Evaluation_subquery() throws { return try _test11Evaluation_subquery() }
    func test11Evaluation_syntax_query() throws { return try _test11Evaluation_syntax_query() }
}
