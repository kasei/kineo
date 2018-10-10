import XCTest
import Kineo
import SPARQLSyntax

#if os(Linux)
extension ConfigurationTest {
    static var allTests : [(String, (ConfigurationTest) -> () throws -> Void)] {
        return [
            ("testCLIConfiguration_1", testCLIConfiguration_1),
            ("testCLIConfiguration_2", testCLIConfiguration_2),
            ("testCLIConfiguration_3", testCLIConfiguration_3),
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
    
    func testCLIConfiguration_1() throws {
        let filename = "filename.db"
        var args = ["process-name", filename]
        let config = try QuadStoreConfiguration(arguments: &args)
        XCTAssertEqual(args.count, 1)
        XCTAssertFalse(config.languageAware)
        if case .filePageDatabase(filename) = config.type {
            XCTAssert(true)
        } else {
            XCTFail("expected database type")
        }
    }
    
    func testCLIConfiguration_2() throws {
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
    
    func testCLIConfiguration_3() throws {
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
}
