import XCTest
@testable import KineoTests

XCTMain([
	testCase(AlgebraTest.allTests),
	testCase(QueryEvaluationTest.allTests),
	testCase(FilePageDatabaseTest.allTests),
	testCase(QueryParserTest.allTests),
	testCase(RDFTest.allTests),
	testCase(SPARQLParserTest.allTests),
	testCase(SPARQLSerializationTest.allTests),
	testCase(TermIdentityMapTest.allTests),
	testCase(TreesTest.allTests),
])
