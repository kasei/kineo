import Foundation
import XCTest
import Kineo

class TreesTest: XCTestCase {
    var tempFilename: String!

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
        try database.update(version: 101) { (dbm) in
            let pairs: [(UInt32, String)] = []
            _ = try dbm.create(tree: treeName, pairs: pairs)
        }

        XCTAssertEqual(database.pageCount, 2)
        database.read { (dbm) in
            guard let pid = try? dbm.getRoot(named: treeName) else { XCTFail(); return }
            XCTAssertEqual(pid, 1, "An empty tree created in a fresh database should appear on page 1")
            assertValidTreeVersionMtime(dbm, pid, "tree read 1")
            guard let t: Tree<UInt32, String> = dbm.tree(name: treeName) else { fatalError("No such tree") }
            XCTAssertEqual(t.version, 101)
        }

        try database.update(version: 102) { (dbm) in
            guard let t: Tree<UInt32, String> = dbm.tree(name: treeName) else { fatalError("No such tree") }
            for k: UInt32 in 0..<14 {
                let key = k * 2
                let value = "<<\(key)>>"
                try t.add(pair: (key, value))
            }
        }

        XCTAssertEqual(database.pageCount, 3)
        database.read { (dbm) in
            guard let pid = try? dbm.getRoot(named: treeName) else { XCTFail(); return }
            XCTAssertEqual(pid, 2, "After inserting pairs into the tree which all fit in one page, the root should appear on page 2")
            assertValidTreeVersionMtime(dbm, pid, "tree read 2")
            guard let t: Tree<UInt32, String> = dbm.tree(name: treeName) else { fatalError("No such tree") }
            XCTAssertEqual(t.version, 102)

            assertTreeVersions(dbm, pid, [102])
        }

        try database.update(version: 103) { (dbm) in
            guard let t: Tree<UInt32, String> = dbm.tree(name: treeName) else { fatalError("No such tree") }
            try t.add(pair: (1, "==\(1)=="))
        }

        XCTAssertEqual(database.pageCount, 6)
        database.read { (dbm) in
            guard let pid = try? dbm.getRoot(named: treeName) else { XCTFail(); return }
            XCTAssertEqual(pid, 5, "After inserting a pair that causes a split, the root should appear on page 5")
            assertValidTreeVersionMtime(dbm, pid, "tree read 3")
            guard let t: Tree<UInt32, String> = dbm.tree(name: treeName) else { fatalError("No such tree") }
            XCTAssertEqual(t.version, 103)

            assertTreeVersions(dbm, pid, [103, 103, 103])
        }

        try database.update(version: 104) { (dbm) in
            guard let t: Tree<UInt32, String> = dbm.tree(name: treeName) else { fatalError("No such tree") }
            try t.add(pair: (99, "==\(999)=="))
        }

        XCTAssertEqual(database.pageCount, 8)
        database.read { (dbm) in
            guard let pid = try? dbm.getRoot(named: treeName) else { XCTFail(); return }
            XCTAssertEqual(pid, 7, "After inserting a pair into the right-most leaf, the root should appear on page 7")
            assertValidTreeVersionMtime(dbm, pid, "tree read 4")
            guard let t: Tree<UInt32, String> = dbm.tree(name: treeName) else { fatalError("No such tree") }
            XCTAssertEqual(t.version, 104)

            let oldVersion = UInt64(103)
            let newVersion = UInt64(104)
            assertTreeVersions(dbm, pid, [newVersion, oldVersion, newVersion])
        }
    }

    func testTreeMtimes() throws {
        let pageSize = 256
        guard let database = FilePageDatabase(self.tempFilename, size: pageSize) else { XCTFail(); return }
        let treeName = "testvalues"
        try database.update(version: 101) { (dbm) in
            let pairs: [(UInt32, String)] = []
            _ = try dbm.create(tree: treeName, pairs: pairs)
            guard let t: Tree<UInt32, String> = dbm.tree(name: treeName) else { fatalError("No such tree") }
            for k: UInt32 in 0..<16 {
                let key = k * 2
                let value = "<<\(key)>>"
                try t.add(pair: (key, value))
            }
        }

        XCTAssertEqual(database.pageCount, 4)

        database.read { (dbm) in
            guard let t: Tree<UInt32, String> = dbm.tree(name: treeName) else { fatalError("No such tree") }
            do {
                let mtime = try t.effectiveVersion(between: (0, 15))
                XCTAssertNotNil(mtime)
                XCTAssertEqual(mtime, 101)
            } catch {
                XCTFail()
            }
        }

        try database.update(version: 102) { (dbm) in
            guard let t: Tree<UInt32, String> = dbm.tree(name: treeName) else { fatalError("No such tree") }
            try t.add(pair: (13, "foo"))
        }

        database.read { (dbm) in
            guard let t: Tree<UInt32, String> = dbm.tree(name: treeName) else { fatalError("No such tree") }
            do {
                let mtimeAll = try t.effectiveVersion(between: (0, 99))
                XCTAssertNotNil(mtimeAll)
                XCTAssertEqual(mtimeAll, 102, "Effective mtime of entire tree")

                let mtimeLeft = try t.effectiveVersion(between: (0, 2))
                XCTAssertNotNil(mtimeLeft)
                XCTAssertEqual(mtimeLeft, 101, "Effective mtime of untouched leaf")

                let mtimeRight = try t.effectiveVersion(between: (13, 99))
                XCTAssertNotNil(mtimeRight)
                XCTAssertEqual(mtimeRight, 102, "Effective mtime of modified leaf")
            } catch {
                XCTFail()
            }
        }

    }

    private func assertValidTreeVersionMtime(_ mediator: RMediator, _ pid: PageId, _ message: String = "") {
        if let (node, _) : (TreeNode<UInt32, String>, PageStatus) = try? mediator.readPage(pid) {
            assertValidTreeVersionMtime(mediator, node, node.version, [])
        } else {
            XCTFail(message)
        }
    }

    private func assertValidTreeVersionMtime(_ mediator: RMediator, _ node: TreeNode<UInt32, String>, _ max: UInt64, _ versions: [UInt64], _ message: String = "") {
        XCTAssertLessThanOrEqual(node.version, max, "Tree mtimes are invalid: \(versions)")
        switch node {
        case .leafNode(_):
            return
        case .internalNode(let i):
            for (_, pid) in i.pairs {
                if let (child, _) : (TreeNode<UInt32, String>, PageStatus) = try? mediator.readPage(pid) {
                    assertValidTreeVersionMtime(mediator, child, node.version, versions + [node.version])
                } else {
                    XCTFail(message)
                }
            }
        }
    }

    private func assertTreeVersions(_ mediator: RMediator, _ pid: PageId, _ expected: [UInt64]) {
        if let (node, _) : (TreeNode<UInt32, String>, PageStatus) = try? mediator.readPage(pid) {
            let versions = walkTreeNode(mediator, node: node) { $0.version }
            XCTAssertEqual(versions, expected)
            return
        }
        XCTFail()
    }

    private func walkTreeNode<T>(_ mediator: RMediator, node: TreeNode<UInt32, String>, cb callback: (TreeNode<UInt32, String>) -> T) -> [T] {
        switch node {
        case .leafNode(_):
            return [callback(node)]
        case .internalNode(let i):
            var results = [callback(node)]
            for (_, pid) in i.pairs {
                //                print("- node walk going to page \(pid)")
                if let (child, _) : (TreeNode<UInt32, String>, PageStatus) = try? mediator.readPage(pid) {
                    results += walkTreeNode(mediator, node: child, cb: callback)
                }
            }
            return results
        }
    }
}
