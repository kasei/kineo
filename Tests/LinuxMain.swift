import XCTest
@testable import KineoTests

XCTMain([
	testCase(FilePageDatabaseTest.allTests),
	testCase(QueryEvaluationTest.allTests),
	testCase(QueryParserTest.allTests),
	testCase(SPARQLSyntaxTest.allTests),
	testCase(TermIdentityMapTest.allTests),
	testCase(TreesTest.allTests),
])
