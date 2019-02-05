import XCTest
@testable import KineoTests

XCTMain([
	testCase(FilePageDatabaseTest.allTests),
	testCase(SimpleQueryEvaluationTest.allTests),
	testCase(QueryPlanEvaluationTest.allTests),
	testCase(QueryParserTest.allTests),
	testCase(SPARQLSyntaxTest.allTests),
	testCase(TermIdentityMapTest.allTests),
	testCase(TreesTest.allTests),
])
