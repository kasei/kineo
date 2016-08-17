import Foundation
import XCTest
import Kineo

class TreesTest: XCTestCase {
    var tempFilename : String!
    
    func removeFile() {
        let fileManager = FileManager.default
        try? fileManager.removeItem(atPath: tempFilename)
    }
    
    override func setUp() {
        self.tempFilename = "/tmp/kineo-\(ProcessInfo.processInfo.globallyUniqueString).db"
        super.setUp()
    }
    
    override func tearDown() {
        removeFile()
    }
    
    func testTreeData() throws {
        let pageSize = 256
        guard let database = FilePageDatabase(self.tempFilename, size: pageSize) else { XCTFail(); return }
        
        XCTAssertEqual(database.pageCount, 1)
        
        let treeName = "testvalues"
        try database.update(version: 101) { (m) in
            let pairs : [(UInt32, String)] = []
            _ = try m.create(tree: treeName, pairs: pairs)
        }
        
        XCTAssertEqual(database.pageCount, 2)
        try database.read { (m) in
            guard let pid = try? m.getRoot(named: treeName) else { XCTFail(); return }
            XCTAssertEqual(pid, 1, "An empty tree created in a fresh database should appear on page 1")
            guard let t : Tree<UInt32, String> = m.tree(name: treeName) else { fatalError("No such tree") }
            XCTAssertEqual(t.version, 101)
        }
        
        try database.update(version: 102) { (m) in
            guard let t : Tree<UInt32, String> = m.tree(name: treeName) else { fatalError("No such tree") }
            for k : UInt32 in 0..<14 {
                let key = k * 2
                let value = "<<\(key)>>"
                try t.add(pair: (key, value))
            }
        }
        
        XCTAssertEqual(database.pageCount, 3)
        try database.read { (m) in
            guard let pid = try? m.getRoot(named: treeName) else { XCTFail(); return }
            XCTAssertEqual(pid, 2, "After inserting pairs into the tree which all fit in one page, the root should appear on page 2")
            guard let t : Tree<UInt32, String> = m.tree(name: treeName) else { fatalError("No such tree") }
            XCTAssertEqual(t.version, 102)

            if let (node, _) : (TreeNode<UInt32,String>, PageStatus) = try? m.readPage(pid) {
                let versions = walkTreeNode(m, node: node) { $0.version }
                print("Tree versions: \(versions)")
            }
        }
        
        try database.update(version: 103) { (m) in
            guard let t : Tree<UInt32, String> = m.tree(name: treeName) else { fatalError("No such tree") }
            try t.add(pair: (1, "==\(1)=="))
        }

        XCTAssertEqual(database.pageCount, 6)
        try database.read { (m) in
            guard let pid = try? m.getRoot(named: treeName) else { XCTFail(); return }
            XCTAssertEqual(pid, 5, "After inserting a pair that causes a split, the root should appear on page 5")
            guard let t : Tree<UInt32, String> = m.tree(name: treeName) else { fatalError("No such tree") }
            XCTAssertEqual(t.version, 103)
            
            if let (node, _) : (TreeNode<UInt32,String>, PageStatus) = try? m.readPage(pid) {
                let versions = walkTreeNode(m, node: node) { $0.version }
                XCTAssertEqual(versions, [103, 103, 103])
            }
        }

        try database.update(version: 104) { (m) in
            guard let t : Tree<UInt32, String> = m.tree(name: treeName) else { fatalError("No such tree") }
            try t.add(pair: (99, "==\(999)=="))
        }

        XCTAssertEqual(database.pageCount, 8)
        try database.read { (m) in
            guard let pid = try? m.getRoot(named: treeName) else { XCTFail(); return }
            XCTAssertEqual(pid, 7, "After inserting a pair into the right-most leaf, the root should appear on page 7")
            guard let t : Tree<UInt32, String> = m.tree(name: treeName) else { fatalError("No such tree") }
            XCTAssertEqual(t.version, 103)
            
            if let (node, _) : (TreeNode<UInt32,String>, PageStatus) = try? m.readPage(pid) {
                let versions = walkTreeNode(m, node: node) { $0.version }
                let rootVersion = 104
                let leftChildVersion = 103
                let rightChildVersion = 104
                XCTAssertEqual(versions, [rootVersion, leftChildVersion, rightChildVersion])
            }
        }
        
    }
    
    private func walkTreeNode<T>(_ mediator : RMediator, node : TreeNode<UInt32,String>, cb : (TreeNode<UInt32,String>) -> T) -> [T] {
        switch node {
        case .leafNode(_):
            return [cb(node)]
        case .internalNode(let i):
            var results = [cb(node)]
            for (_,pid) in i.pairs {
                //                print("- node walk going to page \(pid)")
                if let (child, _) : (TreeNode<UInt32,String>, PageStatus) = try? mediator.readPage(pid) {
                    results += walkTreeNode(mediator, node: child, cb: cb)
                }
            }
            return results
        }
    }
}
