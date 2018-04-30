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
//    var fileManager: FileManager!
//    var tmp: TemporaryFile!
//    var database: FilePageDatabase!
    var quadstore: MemoryQuadStore!
    
    override func setUp() {
        super.setUp()
        guard let rdfTestsBase = ProcessInfo.processInfo.environment["KINEO_W3C_TEST_PATH"] else { fatalError("*** KINEO_W3C_TEST_PATH environment variable must be set") }
        let base = NSURL(fileURLWithPath: rdfTestsBase)
        sparqlBase = base.appendingPathComponent("sparql11")

        quadstore = MemoryQuadStore()
//        fileManager = FileManager.default
//        self.tmp = try! TemporaryFile(creatingTempDirectoryForFilename: "testModel.db")
//        let filename = tmp.fileURL.path
//        guard let database = FilePageDatabase(filename, size: 16384) else { warn("Failed to open \(filename)"); exit(1) }
//        print("setting up database in file \(tmp)")
//        try! setup(database)
//        self.database = database
    }
    
    override func tearDown() {
//        try? self.tmp.deleteDirectory()
        super.tearDown()
    }
    
    func parse<Q : MutableQuadStoreProtocol>(version: Version, quadstore: Q, files: [String], graph defaultGraphTerm: Term? = nil) throws {
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
            try quadstore.load(version: version, quads: quads)
        }
    }
    
    func parse<D: PageDatabase>(_ database: D, files: [String], graph defaultGraphTerm: Term? = nil) throws {
        let version = Version(1)
        let store = try PageQuadStore(database: database)
        do {
            try parse(version: version, quadstore: store, files: files, graph: defaultGraphTerm)
        } catch let e {
            warn("*** Failed during load of RDF; \(e)")
            throw DatabaseUpdateError.rollback
        }
    }
    
    func runSyntaxTests(_ path: URL, testType: Term, expectFailure: Bool = false, skip: Set<String>? = nil) {
        do {
            let manifest = path.appendingPathComponent("manifest.ttl")
//            try parse(database, files: [manifest.path])
            try parse(version: Version(0), quadstore: quadstore, files: [manifest.path])
            let manifestTerm = Term(iri: manifest.absoluteString)
//            let items = try manifestItems(database, manifest: manifestTerm, type: testType)
            let items = try manifestItems(quadstore: quadstore, manifest: manifestTerm, type: testType)
            for item in items {
                guard let test = item["test"] else { XCTFail("Failed to access test IRI"); continue }
                if let skip = skip {
                    if skip.contains(test.value) {
                        continue
                    }
                }
                guard let action = item["action"] else { XCTFail("Did not find an mf:action property for this test"); continue }
//                print("Parsing \(action)...")
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
        let testType = type ?? Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#PositiveSyntaxTest")
        let sparql = """
        PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
        PREFIX mf: <http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#>
        PREFIX dawgt: <http://www.w3.org/2001/sw/DataAccess/tests/test-dawg#>
        SELECT * WHERE {
        <\(manifest.value)> a mf:Manifest ;
        mf:entries/rdf:rest*/rdf:first ?test .
        ?test a <\(testType.value)> ;
        mf:action ?action ;
        dawgt:approval dawgt:Approved .
        }
        """
        guard var p = SPARQLParser(data: sparql.data(using: .utf8)!) else { fatalError("Failed to construct SPARQL parser") }
        let q = try p.parseQuery()
        let result = try q.execute(quadstore: quadstore, defaultGraph: manifest)
        var results = [TermResult]()
        guard case let .bindings(_, iter) = result else { fatalError() }
        for result in iter {
            results.append(result)
        }
        return AnyIterator(results.makeIterator())
    }
    
    func manifestItems<D: PageDatabase>(_ database: D, manifest: Term, type: Term? = nil) throws -> AnyIterator<TermResult> {
        let testType = type ?? Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#PositiveSyntaxTest")
        let sparql = """
        PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
        PREFIX mf: <http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#>
        PREFIX dawgt: <http://www.w3.org/2001/sw/DataAccess/tests/test-dawg#>
        SELECT * WHERE {
            <\(manifest.value)> a mf:Manifest ;
                mf:entries/rdf:rest*/rdf:first ?test .
            ?test a <\(testType.value)> ;
                mf:action ?action ;
                dawgt:approval dawgt:Approved .
        }
        """
        guard var p = SPARQLParser(data: sparql.data(using: .utf8)!) else { fatalError("Failed to construct SPARQL parser") }
        let q = try p.parseQuery()
        let results = try q.execute(database, defaultGraph: manifest)
        return results
    }

    func testPositive11Syntax() {
        let sparql11Path = sparqlBase.appendingPathComponent("data-sparql11")
        let subdirs = ["syntax-query"]
        for dir in subdirs {
            let path = sparql11Path.appendingPathComponent(dir)
            let positiveTestType = Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#PositiveSyntaxTest11")
            runSyntaxTests(path, testType: positiveTestType)
        }
    }
    
    func testNegative11Syntax() {
        let sparql11Path = sparqlBase.appendingPathComponent("data-sparql11")
        let subdirs = ["syntax-query"]
        for dir in subdirs {
            let path = sparql11Path.appendingPathComponent(dir)
            let negativeTestType = Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#NegativeSyntaxTest11")
            runSyntaxTests(path, testType: negativeTestType, expectFailure: true)
        }
    }
    
    func testPositive10Syntax() {
        let sparql10Path = sparqlBase.appendingPathComponent("data-r2")
        let subdirs = ["syntax-sparql1", "syntax-sparql2", "syntax-sparql3", "syntax-sparql4", "syntax-sparql5"]
        let skip = Set([
            "http://www.w3.org/2001/sw/DataAccess/tests/data-r2/syntax-sparql1/manifest#syntax-lit-08", // syntax changed in SPARQL 1.1, disallowing floats with a trailing dot without fractional digits ("7.")
            ])
        for dir in subdirs {
            let path = sparql10Path.appendingPathComponent(dir)
            let testType = Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#PositiveSyntaxTest")
            runSyntaxTests(path, testType: testType, skip: skip)
        }
    }
    
    func testNegative10Syntax() {
        let sparql10Path = sparqlBase.appendingPathComponent("data-r2")
        let subdirs = ["syntax-sparql1", "syntax-sparql2", "syntax-sparql3", "syntax-sparql4", "syntax-sparql5"]
        for dir in subdirs {
            let path = sparql10Path.appendingPathComponent(dir)
            let testType = Term(iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#NegativeSyntaxTest")
            runSyntaxTests(path, testType: testType, expectFailure: true)
        }
    }
}

//
//
//// https://oleb.net/blog/2018/03/temp-file-helper/
//struct TemporaryFile {
//    let directoryURL: URL
//    let fileURL: URL
//    /// Deletes the temporary directory and all files in it.
//    let deleteDirectory: () throws -> Void
//
//    /// Creates a temporary directory with a unique name and initializes the
//    /// receiver with a `fileURL` representing a file named `filename` in that
//    /// directory.
//    ///
//    /// - Note: This doesn't create the file!
//    init(creatingTempDirectoryForFilename filename: String) throws {
//        let (directory, deleteDirectory) = try FileManager.default
//            .urlForUniqueTemporaryDirectory()
//        self.directoryURL = directory
//        self.fileURL = directory.appendingPathComponent(filename)
//        self.deleteDirectory = deleteDirectory
//    }
//}
//
//extension FileManager {
//    /// Creates a temporary directory with a unique name and returns its URL.
//    ///
//    /// - Returns: A tuple of the directory's URL and a delete function.
//    ///   Call the function to delete the directory after you're done with it.
//    ///
//    /// - Note: You should not rely on the existence of the temporary directory
//    ///   after the app is exited.
//    func urlForUniqueTemporaryDirectory(preferredName: String? = nil) throws
//        -> (url: URL, deleteDirectory: () throws -> Void)
//    {
//        let basename = preferredName ?? UUID().uuidString
//
//        var counter = 0
//        var createdSubdirectory: URL? = nil
//        repeat {
//            do {
//                let tempDir: URL
//                if #available(OSX 10.12, *) {
//                    tempDir = temporaryDirectory
//                } else {
//                    tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
//                }
//                let subdirName = counter == 0 ? basename : "\(basename)-\(counter)"
//                let subdirectory = tempDir
//                    .appendingPathComponent(subdirName, isDirectory: true)
//                try createDirectory(at: subdirectory, withIntermediateDirectories: false)
//                createdSubdirectory = subdirectory
//            } catch CocoaError.fileWriteFileExists {
//                // Catch file exists error and try again with another name.
//                // Other errors propagate to the caller.
//                counter += 1
//            }
//        } while createdSubdirectory == nil
//
//        let directory = createdSubdirectory!
//        let deleteDirectory: () throws -> Void = {
//            try self.removeItem(at: directory)
//        }
//        return (directory, deleteDirectory)
//    }
//}
