import Foundation
import XCTest
import Kineo
import SPARQLSyntax

#if os(Linux)
extension LanguageQuadStoreTest {
    static var allTests : [(String, (LanguageQuadStoreTest) -> () throws -> Void)] {
        return [
            ("testAcceptValues", testAcceptValues),
        ]
    }
}
#endif

class LanguageQuadStoreTest: XCTestCase {
    let PREFIXES = "@prefix foaf: <http://xmlns.com/foaf/0.1/> .\n"
    var graph: Term!
    
    override func setUp() {
        self.graph = Term(iri: "http://graph.example.org/")
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func load<T: MutableQuadStoreProtocol>(turtle: String, into store: T, version: Version) throws {
        let parser = RDFParserCombined(base: "http://example.org/", produceUniqueBlankIdentifiers: false)
        var quads = [Quad]()
        try parser.parse(string: "\(PREFIXES) \(turtle)", syntax: .turtle) { (s, p, o) in
            let t = Triple(subject: s, predicate: p, object: o)
            let q = Quad(triple: t, graph: self.graph)
            quads.append(q)
        }
        try store.load(version: version, quads: quads)
    }
    
    func withStore(_ turtle: String, _ acceptLanguages: [(String, Double)], runTests handler: (LanguageAwareQuadStore) throws -> ()) throws {
        let store = MemoryQuadStore(version: 0)
        try load(turtle: turtle, into: store, version: 1)
        let lmstore = LanguageMemoryQuadStore(quadstore: store, acceptLanguages: acceptLanguages)
        try handler(lmstore)
        
        let filename = "/tmp/kineo-\(UUID().uuidString).db"
        let pageSize = 2048
        let database: FilePageDatabase! = FilePageDatabase(filename, size: pageSize)
        let pqstore = try PageQuadStore(database: database)
        try database.update(version: 1) { (m) in
            _ = try MediatedPageQuadStore.create(mediator: m)
        }
        try load(turtle: turtle, into: pqstore, version: 1)
        let lfstore = try LanguagePageQuadStore(database: database, acceptLanguages: acceptLanguages)
        try handler(lfstore)
        let fileManager = FileManager.default
        try? fileManager.removeItem(atPath: filename)
    }
    
    func testAcceptValues() throws {
        let turtle = "<mars> foaf:name 'Mars' ; foaf:nick 'kasei'@en, '火星'@ja, 'mangala'@sa ."
        let nicks = QuadPattern(subject: Node(variable: "s"), predicate: Node(term: Term(iri: "http://xmlns.com/foaf/0.1/nick")), object: Node(variable: "o"), graph: Node(term: graph))
        
        try withStore(turtle, []) { (lstore) throws in
            // no preference should produce all language literals
            /*
             
             Model (assuming site-preference is lexicographic):
             <mars> foaf:name 'Mars' .
             <mars> foaf:nick 'kasei'@en .
             <mars> foaf:nick '火星'@ja .
             <mars> foaf:nick 'mangala'@sa .
             
             **/
//            print("======> Accept-Language: (none)")
            XCTAssertEqual(lstore.count, 4)
            try XCTAssertEqual(Array(lstore.quads(matching: nicks)).count, 3)
        }
        
        try withStore(turtle, [("*", 1.0)]) { (lstore : LanguageAwareQuadStore) throws in
            // "*" should produce a single language literal (arbitrary from the client perspective)
            /*
             
             Model (assuming site-preference is lexicographic):
             <mars> foaf:name 'Mars' .
             <mars> foaf:nick 'kasei'@en .
             
             **/
//            print("======> Accept-Language: *")
            XCTAssertEqual(lstore.count, 2)
            try XCTAssertEqual(Array(lstore.quads(matching: nicks)).count, 1)
//            if lstore.count == 4 {
//                let qp = QuadPattern(
//                    subject: Node(variable: "s"),
//                    predicate: Node(variable: "p"),
//                    object: Node(variable: "o"),
//                    graph: Node(variable: "g")
//                )
//            }
        }
        
        try withStore(turtle, [("en", 1.0)]) { (lstore) throws in
            // "en" should produce a single @en language literal
            /*
             
             Model (assuming site-preference is lexicographic):
             <mars> foaf:name 'Mars' .
             <mars> foaf:nick 'kasei'@en .
             
             **/
//            print("======> Accept-Language: en")
            XCTAssertEqual(lstore.count, 2)
            try XCTAssertEqual(Array(lstore.quads(matching: nicks)).count, 1)
        }
        
        try withStore(turtle, [("ja", 0.9), ("en", 1.0)]) { (lstore) throws in
            // "ja;q=0.9, en" should produce a single @en language literal
            /*
             
             Model (assuming site-preference is lexicographic):
             <mars> foaf:name 'Mars' .
             <mars> foaf:nick 'kasei'@en .
             
             **/
//            print("======> Accept-Language: ja;q=0.9, en")
            XCTAssertEqual(lstore.count, 2)
            try XCTAssertEqual(Array(lstore.quads(matching: nicks)).count, 1)
        }
        
        try withStore(turtle, [("ja", 1.0), ("en", 1.0)]) { (lstore) throws in
            // "ja, en" should produce a single language literal, either @en or @ja (based on the site-configuration)
            /*
             
             Model (assuming site-preference is lexicographic):
             <mars> foaf:name 'Mars' .
             <mars> foaf:nick 'kasei'@en .
             
             **/
//            print("======> Accept-Language: ja, en")
            XCTAssertEqual(lstore.count, 2)
            try XCTAssertEqual(Array(lstore.quads(matching: nicks)).count, 1)
        }
        
        try withStore(turtle, [("ja", 1.0), ("en", 0.9)]) { (lstore) throws in
            // "ja, en;q=0.9" should produce a single @ja language literal
            /*
             
             Model (assuming site-preference is lexicographic):
             <mars> foaf:name 'Mars' .
             <mars> foaf:nick '火星'@ja .
             
             **/
//            print("======> Accept-Language: ja, en;q=0.9")
            XCTAssertEqual(lstore.count, 2)
            try XCTAssertEqual(Array(lstore.quads(matching: nicks)).count, 1)
        }
        
        try withStore(turtle, [("xx", 1.0), ("en", 0.9)]) { (lstore) throws in
            // "xx, en;q=0.9" should produce a single @en language literal, since @xx does not exist
            /*
             
             Model (assuming site-preference is lexicographic):
             <mars> foaf:name 'Mars' .
             <mars> foaf:nick 'kasei'@en .
             
             **/
//            print("======> Accept-Language: xx, en;q=0.9")
            XCTAssertEqual(lstore.count, 2)
            try XCTAssertEqual(Array(lstore.quads(matching: nicks)).count, 1)
        }
        
        try withStore(turtle, [("xx", 1.0)]) { (lstore) throws in
            // "xx" should produce no results, since @xx does not exist and no other language is acceptable
            /*
             
             Model (assuming site-preference is lexicographic):
             <mars> foaf:name 'Mars' .
             
             **/
//            print("======> Accept-Language: xx")
            XCTAssertEqual(lstore.count, 1)
            try XCTAssertEqual(Array(lstore.quads(matching: nicks)).count, 0)
        }
        
        try withStore(turtle, [("xx", 1.0), ("*", 0.1)]) { (lstore) throws in
            // "xx, *;q=0.1" should produce a single language literal (arbitrary from the client perspective), since @xx does not exist
            /*
             
             Model (assuming site-preference is lexicographic):
             <mars> foaf:name 'Mars' .
             <mars> foaf:nick 'kasei'@en .
             
             **/
//            print("======> Accept-Language: xx, *;q=0.1")
            XCTAssertEqual(lstore.count, 2)
            try XCTAssertEqual(Array(lstore.quads(matching: nicks)).count, 1)
        }
    }

    func testMultipleLanguageLiterals() throws {
        let turtle = "<mars> foaf:nick 'mars'@en, 'kasei'@en, 'red planet'@en, '火星'@ja, 'かせい'@ja, 'mangala'@sa ."
        let nicks = QuadPattern(subject: Node(variable: "s"), predicate: Node(term: Term(iri: "http://xmlns.com/foaf/0.1/nick")), object: Node(variable: "o"), graph: Node(term: graph))
        
        try withStore(turtle, []) { (lstore) throws in
            // no preference should produce all language literals
            /*
             
             Model (assuming site-preference is lexicographic):
             <mars> foaf:nick "mars"@en .
             <mars> foaf:nick "kasei"@en .
             <mars> foaf:nick "red planet"@en .
             <mars> foaf:nick "\u706B\u661F"@ja .
             <mars> foaf:nick "\u304B\u305B\u3044"@ja .
             <mars> foaf:nick "mangala"@sa .

             **/
            XCTAssertEqual(lstore.count, 6)
            try XCTAssertEqual(Array(lstore.quads(matching: nicks)).count, 6)
        }
        
        try withStore(turtle, [("*", 1.0)]) { (lstore) throws in
            // "*" should produce a all literals of a single language (arbitrary from the client perspective)
            /*
             
             Model (assuming site-preference is lexicographic):
             <mars> foaf:nick "mars"@en .
             <mars> foaf:nick "kasei"@en .
             <mars> foaf:nick "red planet"@en .

             **/
            XCTAssertEqual(lstore.count, 3)
            try XCTAssertEqual(Array(lstore.quads(matching: nicks)).count, 3)
        }
        
        try withStore(turtle, [("en", 1.0)]) { (lstore) throws in
            // "en" should produce all the @en language literals
            /*
             
             Model (assuming site-preference is lexicographic):
             <mars> foaf:nick "mars"@en .
             <mars> foaf:nick "kasei"@en .
             <mars> foaf:nick "red planet"@en .

             **/
            XCTAssertEqual(lstore.count, 3)
            try XCTAssertEqual(Array(lstore.quads(matching: nicks)).count, 3)
        }
        
        try withStore(turtle, [("ja", 0.9), ("en", 1.0)]) { (lstore) throws in
            // "ja;q=0.9, en" should produce all the @en language literals
            /*
             
             Model (assuming site-preference is lexicographic):
             <mars> foaf:nick "mars"@en .
             <mars> foaf:nick "kasei"@en .
             <mars> foaf:nick "red planet"@en .

             **/
            XCTAssertEqual(lstore.count, 3)
            try XCTAssertEqual(Array(lstore.quads(matching: nicks)).count, 3)
        }
        
        try withStore(turtle, [("ja", 1.0), ("en", 0.9)]) { (lstore) throws in
            // "ja, en;q=0.9" should produce all @ja language literals
            /*
             
             Model (assuming site-preference is lexicographic):
             <mars> foaf:nick "\u706B\u661F"@ja .
             <mars> foaf:nick "\u304B\u305B\u3044"@ja .

             **/
            XCTAssertEqual(lstore.count, 2)
            try XCTAssertEqual(Array(lstore.quads(matching: nicks)).count, 2)
        }
        
        try withStore(turtle, [("xx", 1.0), ("en", 0.1), ("sa", 0.9)]) { (lstore) throws in
            // "xx, en;q=0.1, sa;q=0.9" should produce a single @sa language literal, since @xx does not exist
            /*
             
             Model (assuming site-preference is lexicographic):
             <mars> foaf:nick 'mangala'@sa .

             **/
            XCTAssertEqual(lstore.count, 1)
            try XCTAssertEqual(Array(lstore.quads(matching: nicks)).count, 1)
        }
        
        try withStore(turtle, [("xx", 1.0)]) { (lstore) throws in
            // "xx" should produce no results, since @xx does not exist and no other language is acceptable
            /*
             
             Model (assuming site-preference is lexicographic):
             
             **/
            XCTAssertEqual(lstore.count, 0)
            try XCTAssertEqual(Array(lstore.quads(matching: nicks)).count, 0)
        }
        
        try withStore(turtle, [("xx", 1.0), ("*", 0.1)]) { (lstore) throws in
            // "xx, *;q=0.1" should produce all the literals of a single language (arbitrary from the client perspective), since @xx does not exist
            /*
             
             Model (assuming site-preference is lexicographic):
             <mars> foaf:nick "mars"@en .
             <mars> foaf:nick "kasei"@en .
             <mars> foaf:nick "red planet"@en .

             **/
            XCTAssertEqual(lstore.count, 3)
            try XCTAssertEqual(Array(lstore.quads(matching: nicks)).count, 3)
        }
    }
}
