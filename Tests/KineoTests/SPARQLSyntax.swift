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
    var fileManager: FileManager!
    override func setUp() {
        super.setUp()
        fileManager = FileManager.default
        guard let rdfTestsBase = ProcessInfo.processInfo.environment["KINEO_W3C_TEST_PATH"] else { fatalError("*** KINEO_W3C_TEST_PATH environment variable must be set") }
        let base = NSURL(fileURLWithPath: rdfTestsBase)
        sparqlBase = base.appendingPathComponent("sparql11")
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func setup<D : Database>(_ database: D) throws {
        try database.update(version: Version(0)) { (m) in
            do {
                _ = try QuadStore.create(mediator: m)
            } catch let e {
                warn("*** \(e)")
                throw DatabaseUpdateError.rollback
            }
        }
    }

    func parse<D : Database>(_ database: D, files: [String], graph defaultGraphTerm: Term? = nil) throws {
        let version = Version(1)
        try database.update(version: version) { (m) in
            do {
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
                    let store = try QuadStore.create(mediator: m)
                    try store.load(quads: quads)
                }
            } catch let e {
                warn("*** Failed during load of RDF; \(e)")
                throw DatabaseUpdateError.rollback
            }
        }
    }
    
    func runSyntaxTests(_ path: URL, testType: Term, expectFailure: Bool = false, skip: Set<String>? = nil) {
        do {
            let tmp = try TemporaryFile(creatingTempDirectoryForFilename: "testModel.db")
            let filename = tmp.fileURL.path
            guard let database = FilePageDatabase(filename, size: 16384) else { warn("Failed to open \(filename)"); exit(1) }
            try setup(database)
            let manifest = path.appendingPathComponent("manifest.ttl")
            try parse(database, files: [manifest.path])
            let manifestTerm = Term(iri: manifest.absoluteString)
            let items = try manifestItems(database, manifest: manifestTerm, type: testType)
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

    func manifestItems<D: Database>(_ database: D, manifest: Term, type: Term? = nil) throws -> AnyIterator<TermResult> {
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

extension Query {
    func execute<D : Database>(_ database: D, defaultGraph: Term) throws -> AnyIterator<TermResult> {
        var results = [TermResult]()
        try self.execute(database, defaultGraph: defaultGraph) { (r) in
            results.append(r)
        }
        return AnyIterator(results.makeIterator())
    }
    
    func execute<D : Database>(_ database: D, defaultGraph: Term, _ cb: (TermResult) throws -> ()) throws {
        let query = self
        try database.read { (m) in
            let store       = try QuadStore(mediator: m)
            let e       = SimpleQueryEvaluator(store: store, defaultGraph: defaultGraph, verbose: false)
            let results = try e.evaluate(query: query, activeGraph: defaultGraph)
            guard case let .bindings(_, iter) = results else { fatalError() }
            for result in iter {
                try cb(result)
            }
        }
    }
}



// https://oleb.net/blog/2018/03/temp-file-helper/
struct TemporaryFile {
    let directoryURL: URL
    let fileURL: URL
    /// Deletes the temporary directory and all files in it.
    let deleteDirectory: () throws -> Void
    
    /// Creates a temporary directory with a unique name and initializes the
    /// receiver with a `fileURL` representing a file named `filename` in that
    /// directory.
    ///
    /// - Note: This doesn't create the file!
    init(creatingTempDirectoryForFilename filename: String) throws {
        let (directory, deleteDirectory) = try FileManager.default
            .urlForUniqueTemporaryDirectory()
        self.directoryURL = directory
        self.fileURL = directory.appendingPathComponent(filename)
        self.deleteDirectory = deleteDirectory
    }
}

extension FileManager {
    /// Creates a temporary directory with a unique name and returns its URL.
    ///
    /// - Returns: A tuple of the directory's URL and a delete function.
    ///   Call the function to delete the directory after you're done with it.
    ///
    /// - Note: You should not rely on the existence of the temporary directory
    ///   after the app is exited.
    func urlForUniqueTemporaryDirectory(preferredName: String? = nil) throws
        -> (url: URL, deleteDirectory: () throws -> Void)
    {
        let basename = preferredName ?? UUID().uuidString
        
        var counter = 0
        var createdSubdirectory: URL? = nil
        repeat {
            do {
                let tempDir: URL
                if #available(OSX 10.12, *) {
                    tempDir = temporaryDirectory
                } else {
                    tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
                }
                let subdirName = counter == 0 ? basename : "\(basename)-\(counter)"
                let subdirectory = tempDir
                    .appendingPathComponent(subdirName, isDirectory: true)
                try createDirectory(at: subdirectory, withIntermediateDirectories: false)
                createdSubdirectory = subdirectory
            } catch CocoaError.fileWriteFileExists {
                // Catch file exists error and try again with another name.
                // Other errors propagate to the caller.
                counter += 1
            }
        } while createdSubdirectory == nil
        
        let directory = createdSubdirectory!
        let deleteDirectory: () throws -> Void = {
            try self.removeItem(at: directory)
        }
        return (directory, deleteDirectory)
    }
}