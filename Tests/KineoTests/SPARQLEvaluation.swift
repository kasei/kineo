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
    var quadstore: MemoryQuadStore!
    
    override func setUp() {
        super.setUp()
        guard let rdfTestsBase = ProcessInfo.processInfo.environment["KINEO_W3C_TEST_PATH"] else { fatalError("*** KINEO_W3C_TEST_PATH environment variable must be set") }
        let base = NSURL(fileURLWithPath: rdfTestsBase)
        sparqlBase = base.appendingPathComponent("sparql11")
        
        quadstore = MemoryQuadStore()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func parse<Q : MutableQuadStoreProtocol>(quadstore: Q, files: [String], graph defaultGraphTerm: Term? = nil) throws {
        for filename in files {
            #if os (OSX)
            guard let path = NSURL(fileURLWithPath: filename).absoluteString else { throw DatabaseError.DataError("Not a valid graph path: \(filename)") }
            #else
            let path = NSURL(fileURLWithPath: filename).absoluteString
            #endif
            let graph   = defaultGraphTerm ?? Term(value: path, type: .iri)
            
            let parser = RDFParser()
            var quads = [Quad]()
            //                    print("Parsing RDF...")
            _ = try parser.parse(file: filename, base: graph.value) { (s, p, o) in
                let q = Quad(subject: s, predicate: p, object: o, graph: graph)
                quads.append(q)
            }
            
            //                    print("Loading RDF...")
            try quadstore.load(version: Version(0), quads: quads)
        }
    }
    
    func parse<D: PageDatabase>(_ database: D, files: [String], graph defaultGraphTerm: Term? = nil) throws {
        let store = try PageQuadStore(database: database)
        do {
            try parse(quadstore: store, files: files, graph: defaultGraphTerm)
        } catch let e {
            warn("*** Failed during load of RDF; \(e)")
            throw DatabaseUpdateError.rollback
        }
    }
    
    func runEvaluationTests(_ path: URL, testType: Term, expectFailure: Bool = false, skip: Set<String>? = nil) {
        do {
            let manifest = path.appendingPathComponent("manifest.ttl")
            try parse(quadstore: quadstore, files: [manifest.path])
            let manifestTerm = Term(iri: manifest.absoluteString)
            let items = try Array(manifestItems(quadstore: quadstore, manifest: manifestTerm, type: testType))
            for item in items {
                guard let test = item["test"] else { XCTFail("Failed to access test IRI"); continue }
                if let skip = skip {
                    if skip.contains(test.value) {
                        continue
                    }
                }
                guard let action = item["query"] else { XCTFail("Did not find an mf:action property for this test"); continue }
                print("Parsing \(action)...")
                guard let url = URL(string: action.value) else { XCTFail("Failed to construct URL for action: \(action)"); continue }
                
                if expectFailure {
                    let sparql = try Data(contentsOf: url)
                    guard var p = SPARQLParser(data: sparql) else { XCTFail("Failed to construct SPARQL parser"); continue }
                    XCTAssertThrowsError(try p.parseQuery(), "Did not find expected syntax error while parsing \(url)")
                } else {
                    do {
                        let sparql = try Data(contentsOf: url)
                        guard var p = SPARQLParser(data: sparql) else { XCTFail("Failed to construct SPARQL parser"); continue }
                        _ = try p.parseQuery()
                    } catch let e {
                        XCTFail("failed to parse \(url): \(e)")
                    }
                }
            }
        } catch let e {
            XCTFail("Failed to run syntax tests: \(e)")
        }
    }
    
    func manifestItems<Q: QuadStoreProtocol>(quadstore: Q, manifest: Term, type: Term? = nil) throws -> AnyIterator<TermResult> {
        let testType = type ?? Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#QueryEvaluationTest")
        let sparql = """
        PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
        PREFIX mf: <http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#>
        PREFIX qt: <http://www.w3.org/2001/sw/DataAccess/tests/test-query#>
        PREFIX dawgt: <http://www.w3.org/2001/sw/DataAccess/tests/test-dawg#>
        SELECT * WHERE {
        <\(manifest.value)> a mf:Manifest ;
        mf:entries/rdf:rest*/rdf:first ?test .
        ?test a <\(testType.value)> .
        ?test mf:action ?action .
        ?action qt:query ?query .
        ?test dawgt:approval dawgt:Approved .
        }
        """
        guard var p = SPARQLParser(data: sparql.data(using: .utf8)!) else { fatalError("Failed to construct SPARQL parser") }
        let q = try p.parseQuery()
        let results = try q.execute(quadstore: quadstore, defaultGraph: manifest)
        return results
    }
    
    func manifestItems<D: PageDatabase>(_ database: D, manifest: Term, type: Term? = nil) throws -> AnyIterator<TermResult> {
        let testType = type ?? Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#QueryEvaluationTest")
        let sparql = """
        PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
        PREFIX mf: <http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#>
        PREFIX qt: <http://www.w3.org/2001/sw/DataAccess/tests/test-query#>
        PREFIX dawgt: <http://www.w3.org/2001/sw/DataAccess/tests/test-dawg#>
        SELECT * WHERE {
        <\(manifest.value)> a mf:Manifest ;
        mf:entries/rdf:rest*/rdf:first ?test .
        ?test a <\(testType.value)> .
        ?test mf:action ?action .
        ?action qt:query ?query .
        ?test dawgt:approval dawgt:Approved .
        }
        """
        guard var p = SPARQLParser(data: sparql.data(using: .utf8)!) else { fatalError("Failed to construct SPARQL parser") }
        let q = try p.parseQuery()
        let results = try q.execute(database, defaultGraph: manifest)
        return results
    }
    
    func testPositive11Evaluation() {
        let sparql11Path = sparqlBase.appendingPathComponent("data-sparql11")
        let subdirs = ["aggregates", "bind", "bindings", "construct", "exists", "functions", "grouping", "negation", "project-expression", "property-path", "subquery", "syntax-query"]
        for dir in subdirs {
            print("Manifest directory: \(dir)")
            let path = sparql11Path.appendingPathComponent(dir)
            let positiveTestType = Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#QueryEvaluationTest")
            runEvaluationTests(path, testType: positiveTestType)
        }
    }
}
