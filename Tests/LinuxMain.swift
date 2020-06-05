import XCTest
@testable import KineoTests

XCTMain([
	testCase(ConfigurationTest.allTests),
	testCase(GraphAPITest.allTests),
	testCase(LanguageMemoryQuadStoreTest.allTests),
	testCase(LanguageSQLiteQuadStoreTest.allTests),
	testCase(NTriplesSerializationTest.allTests),
	testCase(QuadStoreGraphDescriptionTest.allTests),
	testCase(QueryEvaluationPerformanceTest.allTests),
	testCase(QueryParserTest.allTests),
	testCase(QueryPlanEvaluationTest.allTests),
	testCase(QueryRewritingTest.allTests),
	testCase(SerializationPerformanceTest.allTests),
	testCase(SimpleQueryEvaluationTest.allTests),
	testCase(SPARQLContentNegotiatorTest.allTests),
	testCase(SPARQLEvaluationTest.allTests),
	testCase(SPARQLJSONSyntaxTest.allTests),
	testCase(SPARQLSyntaxTest.allTests),
	testCase(SPARQLTSVSyntaxParserTest.allTests),
	testCase(SPARQLTSVSyntaxSerializerTest.allTests),
	testCase(SPARQLXMLSyntaxTest.allTests),
	testCase(TermIdentityMapTest.allTests),
	testCase(TurtleSerializationTest.allTests),
])
