import XCTest
import Kineo
import SPARQLSyntax

#if os(Linux)
extension ConfigurationTest {
    static var allTests : [(String, (ConfigurationTest) -> () throws -> Void)] {
        return [
            ("testCLIConfiguration_file", testCLIConfiguration_file),
            ("testCLIConfiguration_memory", testCLIConfiguration_memory),
            ("testCLIConfiguration_memory_language", testCLIConfiguration_memory_language),
            ("testCLIConfiguration_memory_dataset", testCLIConfiguration_memory_dataset),
        ]
    }
}
#endif

class ConfigurationTest: XCTestCase {
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testCLIConfiguration_file() throws {
        let filename = "filename.db"
        var args = ["process-name", "--file=\(filename)"]
        let config = try QuadStoreConfiguration(arguments: &args)
        XCTAssertEqual(args.count, 1)
        XCTAssertFalse(config.languageAware)
        if case .filePageDatabase(filename) = config.type {
            XCTAssert(true)
        } else {
            XCTFail("expected database type")
        }
    }
    
    func testCLIConfiguration_memory() throws {
        var args = ["process-name", "-m"]
        let config = try QuadStoreConfiguration(arguments: &args)
        XCTAssertEqual(args.count, 1)
        XCTAssertFalse(config.languageAware)
        if case .memoryDatabase = config.type {
            XCTAssert(true)
        } else {
            XCTFail("expected database type")
        }
    }
    
    func testCLIConfiguration_memory_language() throws {
        var args = ["process-name", "-l", "-m"]
        let config = try QuadStoreConfiguration(arguments: &args)
        XCTAssertEqual(args.count, 1)
        XCTAssertTrue(config.languageAware)
        if case .memoryDatabase = config.type {
            XCTAssert(true)
        } else {
            XCTFail("expected database type")
        }
    }
    
    func testCLIConfiguration_memory_dataset() throws {
        var args = ["process-name", "-m", "-d", "default1", "-n", "name1", "--default-graph=default2"]
        let config = try QuadStoreConfiguration(arguments: &args)
        XCTAssertEqual(args.count, 1)
        XCTAssertFalse(config.languageAware)
        if case .memoryDatabase = config.type {
            XCTAssert(true)
        } else {
            XCTFail("expected database type")
        }
        if case let .loadFiles(defaultGraphs, namedGraphs) = config.initialize {
            XCTAssertEqual(defaultGraphs, ["default1", "default2"])
            XCTAssertEqual(namedGraphs, [Term(iri: "name1"): "name1"])
        } else {
            XCTFail("expected initialization dataset")
        }
    }
}
