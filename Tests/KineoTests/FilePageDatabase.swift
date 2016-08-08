import XCTest
import Kineo

class FilePageDatabaseTest: XCTestCase {
    var tempFilename : String {
        return "/tmp/kineo-\(ProcessInfo.processInfo.globallyUniqueString).db"
    }
    
    func removeFile() {
        let r : Int32 = tempFilename.withCString { (ptr) -> Int32 in print("removing \(ptr)"); return unlink(ptr) }
        print("rm \(tempFilename) => \(r)")
        if r != 0 {
            "error".withCString { perror($0) }
        }
    }
    
    override func setUp() {
        super.setUp()
    }
    
    func testOpen() {
        let pageSize = 1024
        let database : FilePageDatabase! = FilePageDatabase(self.tempFilename, size: pageSize)
        defer { removeFile() }
        
        XCTAssertNotNil(database)
        XCTAssertEqual(database.pageSize, pageSize)
        XCTAssertEqual(database.pageCount, 1)
    }
    
    func testTreeData() throws {
        let pageSize = 256
        guard let database = FilePageDatabase(self.tempFilename, size: pageSize) else { XCTFail(); return }
        defer { removeFile() }

        XCTAssertEqual(database.pageCount, 1)

        let treeName = "testvalues"
        try database.update(version: 1) { (m) in
            let pairs : [(UInt32, String)] = []
            _ = try m.create(tree: treeName, pairs: pairs)
        }
        
        XCTAssertEqual(database.pageCount, 2)
        try database.read { (m) in
            guard let pid = try? m.getRoot(named: treeName) else { XCTFail(); return }
            XCTAssertEqual(pid, 1, "An empty tree created in a fresh database should appear on page 1")
        }
        
        try database.update(version: 2) { (m) in
            guard let t : Tree<UInt32, String> = m.tree(name: treeName) else { fatalError("No such tree") }
            for key : UInt32 in 0..<14 {
                let value = "<<\(key)>>"
                try t.add(pair: (key, value))
            }
        }

        XCTAssertEqual(database.pageCount, 3)
        try database.read { (m) in
            guard let pid = try? m.getRoot(named: treeName) else { XCTFail(); return }
            XCTAssertEqual(pid, 2, "After inserting pairs into the tree which all fit in one page, the root should appear on page 2")
        }
        
        try database.update(version: 3) { (m) in
            guard let t : Tree<UInt32, String> = m.tree(name: treeName) else { fatalError("No such tree") }
            try t.add(pair: (787, "Dreamliner"))
            try t.add(pair: (350, "XWB"))
        }

        XCTAssertEqual(database.pageCount, 6)
        try database.read { (m) in
            guard let pid = try? m.getRoot(named: treeName) else { XCTFail(); return }
            XCTAssertEqual(pid, 5, "After inserting pairs that cause a root split, the root should appear on page 5")
        }

        /**
        try database.read { (m) in
            var roots = [Int:String]()
            for name in m.rootNames {
                if let i = try? m.getRoot(named: name) {
                    roots[Int(i)] = name
                }
            }
            
            let pages = Array(0..<m.pageCount)
            for pid in pages {
                let name = roots[pid] ?? "_"
                printPageInfo(mediator: m, name : name, page : pid)
            }
        }
        **/
        
    }
}

/**
private func printPageInfo(mediator m : FilePageRMediator, name : String, page : PageId) {
    if let (type, date, previous) = m._pageInfo(page: page) {
        var prev : String
        switch previous {
        case .none, .some(0):
            prev = ""
        case .some(let value):
            prev = "Previous page: \(value)"
        }
        
        let name_padded = name.padding(toLength: 16, withPad: " ", startingAt: 0)
        let type_padded = type.padding(toLength: 24, withPad: " ", startingAt: 0)
        print("  \(page)\t\(date)\t\(name_padded)\t\(type_padded)\t\t\(prev)")
    }
}
**/
