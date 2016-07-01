//
//  Trees.swift
//  PageDatabase
//
//  Created by Gregory Todd Williams on 5/15/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation

private enum TreeError : ErrorProtocol {
    case stopWalk
}

private let cookieHeaderSize = 32

internal struct TreePath<T : protocol<BufferSerializable,Comparable>, U : BufferSerializable> : CustomStringConvertible {
    private var internalPath : [(node: TreeNode<T,U>, index: Int)]
    internal var leaf : TreeLeaf<T,U>?
    private var mediator: RMediator
    internal static func minPath(tree: Tree<T,U>, mediator: RMediator) throws -> TreePath<T,U> {
        let (node, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(tree.root)
        var path = [(node: TreeNode<T,U>, index: Int)]()
        var current = node
        while case .internalNode(let i) = current {
            let index = 0
            path.append((node: current, index: index))
            let (_, pid) = i.pairs.first!
            let (node, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(pid)
            current = node
        }
        guard case .leafNode(let currentLeaf) = current else { fatalError() }
        return TreePath(internalPath: path, leaf: currentLeaf, mediator: mediator)
    }
    
    internal static func maxPath(tree: Tree<T,U>, mediator: RMediator) throws -> TreePath<T,U> {
        let (node, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(tree.root)
        var path = [(node: TreeNode<T,U>, index: Int)]()
        var current = node
        while case .internalNode(let i) = current {
            let index = i.pairs.count - 1
            path.append((node: current, index: index))
            let (_, pid) = i.pairs.last!
            let (node, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(pid)
            current = node
        }
        guard case .leafNode(let currentLeaf) = current else { fatalError() }
        return TreePath(internalPath: path, leaf: currentLeaf, mediator: mediator)
    }

    internal static func path(for key: T, tree: Tree<T,U>, mediator: RMediator) throws -> TreePath<T,U> {
        let (node, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(tree.root)
        var path = [(node: TreeNode<T,U>, index: Int)]()
        var current = node
        DESCENT: while case .internalNode(let i) = current {
            var lastMax : T? = nil
            for (index, (max, pid)) in i.pairs.enumerated() {
                if let min = lastMax {
                    if key >= min && key <= max {
                        do {
                            let (node, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(pid)
                            if node.contains(key: key, mediator: mediator) {
                                path.append((node: current, index: index))
                                current = node
                                continue DESCENT
                            }
                        } catch {}
                    }
                } else {
                    if key <= max {
                        do {
                            let (node, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(pid)
                            if node.contains(key: key, mediator: mediator) {
                                path.append((node: current, index: index))
                                current = node
                                continue DESCENT
                            }
                        } catch {}
                    }
                }
                lastMax = max
            }
            
            path = []
            return TreePath(internalPath: path, leaf: nil, mediator: mediator)
        }
        guard case .leafNode(let currentLeaf) = current else { fatalError() }
        return TreePath(internalPath: path, leaf: currentLeaf, mediator: mediator)
    }
    
    internal mutating func advanceLeaf() -> Bool {
        if internalPath.count == 0 {
            leaf = nil
            return false
        }
        
        do {
            while let (current, currentIndex) = internalPath.popLast() {
                guard case .internalNode(let i) = current else { fatalError() }
                if currentIndex < (i.pairs.count-1) {
                    // can go back down here
                    let index = currentIndex + 1
                    let (_, pid) = i.pairs[index]
                    internalPath.append((node: current, index: index))
                    let (child, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(pid)
                    var current = child
                    while case .internalNode(let i) = current {
                        let index = 0
                        internalPath.append((node: current, index: index))
                        let (_, pid) = i.pairs.first!
                        let (node, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(pid)
                        current = node
                    }
                    guard case .leafNode(let currentLeaf) = current else { fatalError() }
                    leaf = currentLeaf
                    return true
                }
            }
        } catch {}
        internalPath = []
        leaf = nil
        return false
    }
    
    internal var description : String {
        var s = "TreePath(Root."
        for (_, index) in internalPath {
            s += "\(index)."
        }
        s += "leaf)"
        return s
    }
}

public class Tree<T : protocol<BufferSerializable,Comparable>, U : BufferSerializable> {
    var root : PageId
    var name : String
    var mediator : RMediator
    
    init(name : String, root : PageId, mediator : RMediator) {
        self.name = name
        self.root = root
        self.mediator = mediator
    }
    
    init?(name : String, mediator : RMediator) {
        if let root = try? mediator.getRoot(named: name) {
            self.name = name
            self.root = root
            self.mediator = mediator
        } else {
            return nil
        }
    }
    
    public func elements(between: (T,T)) throws -> AnyIterator<(T,U)> {
        // TODO: convert this to pipeline the iterator results
        var pairs = [(T,U)]()
        let (node, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(root)
        _ = try? node.walk(mediator: mediator, between: between) { (leaf) in
            for (k,v) in leaf.pairs where k >= between.0 && k <= between.1 {
                pairs.append((k,v))
            }
        }
        let i = pairs.makeIterator()
        return AnyIterator(i)
    }
    
    public func makeIterator() -> AnyIterator<(T,U)> {
        var pairs = [(T,U)]()
        do {
            var path = try TreePath.minPath(tree: self, mediator: mediator)
            return AnyIterator {
                repeat {
                    if pairs.count > 0 {
                        return pairs.remove(at: 0)
                    } else {
                        guard path.leaf != nil else { return nil }
                        pairs.append(contentsOf: path.leaf!.pairs)
                        _ = path.advanceLeaf()
                    }
                } while true
            }
        } catch let e {
            print("*** \(e)")
            return AnyIterator(pairs.makeIterator())
        }
    }
    
    public func walk(between: (T,T), onPairs: @noescape ([(T,U)]) throws -> ()) throws {
        let (node, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(root)
        var elements = [(T,U)]()
        _ = try? node.walk(mediator: mediator, between: between) { (leaf) in
            for (k,v) in leaf.pairs where k >= between.0 && k <= between.1 {
                elements.append((k,v))
            }
        }
        try onPairs(elements)
    }
    
    public func contains(key : T) -> Bool {
        do {
            let (node, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(root)
            return node.contains(key: key, mediator: mediator)
        } catch {}
        return false
    }
    
    public func get(key : T) -> [U] {
        do {
            let (node, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(root)
            return node.get(key: key, mediator: mediator)
        } catch {}
        print("*** No tree node found for root '\(root)'")
        return []
    }
    
    public func maxKey(in range: Range<T>) -> T? {
        do {
            let (node, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(root)
            return node.maxKey(in: range, mediator: mediator)
        } catch {}
        return nil
    }
    
    public func add(pair : (T, U)) throws {
//        print("==================================================================")
//        print("TREE add: \(pair)")
        let (node, rootStatus) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(root)
        guard let m = mediator as? RWMediator else { throw DatabaseError.PermissionError("Cannot modify a tree in a read-only transaction") }
        
        // find leaf for pair (and its path from the root)
        var (path, leaf, leafStatus) = try node.pathToLeaf(for: pair.0, mediator: m, currentStatus: rootStatus)
        var newPairs = [(T,PageId)]()
        // if leaf can add pair:
        if leaf.spaceForPair(pair, pageSize: m.pageSize) {
//            print("- there is space in the \(leafStatus) leaf for the add")
            try leaf.addPair(pair)
            let max = leaf.max!
            
            let leafNode : TreeNode<T,U> = .leafNode(leaf)
            if case .dirty(let pid) = leafStatus {
                try m.update(page: pid, with: leafNode)
                newPairs.append((max, pid))
            } else {
                let pid = try m.createPage(for: leafNode)
                newPairs.append((max, pid))
            }
        } else {
//            print("- there is NOT space in the \(leafStatus) leaf for the add; split required")
            var pairs = leaf.pairs
            pairs.insertSorted(pair) { (l,r) in return l.0 < r.0 }
            let lcount = pairs.count / 2
            let rcount = pairs.count - lcount
            
            let lpairs = Array(pairs.prefix(lcount))
            let rpairs = Array(pairs.suffix(rcount))
            
            for pairs in [lpairs, rpairs] {
                let leaf        = try TreeLeaf(version: m.version, pageSize: m.pageSize, pairs: pairs)
                let leafNode : TreeNode<T,U> = .leafNode(leaf)
                let max         = leaf.max!
                if case .dirty(let pid) = leafStatus {
                    try m.update(page: pid, with: leafNode)
                    newPairs.append((max, pid))
                    leafStatus = .unassigned
                } else {
                    let pid = try m.createPage(for: leafNode)
                    newPairs.append((max, pid))
                }
            }
        }
        
        while let x = path.popLast() {
//            print("- adding \(newPairs.count) pairs to internal node")
            let node = x.node
            let index = x.childIndex
            let status = x.status
            
            let totalCount = node.totalCount + 1
            if node.spaceForPairs(newPairs, replacingIndex: index, pageSize: m.pageSize) {
//                print("- there is space in the \(status) internal for the add")
                
                try node.addPairs(newPairs, replacingIndex: index, totalCount: totalCount)
                let max         = node.max!
                
                let internalNode : TreeNode<T,U> = .internalNode(node)
                if case .dirty(let pid) = status {
                    try m.update(page: pid, with: internalNode)
                    newPairs = [(max,pid)]
                } else {
                    let pid = try m.createPage(for: internalNode)
                    newPairs = [(max,pid)]
                }
            } else {
//                print("- there is NOT space in the \(status) internal for the add; split required")
                var pairs = node.pairs
                pairs.replaceSubrange(index...index, with: newPairs)
                let lcount = pairs.count / 2
                let rcount = pairs.count - lcount
                
                let lpairs = Array(pairs.prefix(lcount))
                let rpairs = Array(pairs.suffix(rcount))
                newPairs = []
                
                var availablePageForReuse = [PageId]()
                if case .dirty(let pid) = status {
                    availablePageForReuse.append(pid)
                }
                
                for pairs in [lpairs, rpairs] {
                    let total = try pairs.map { (pair) -> UInt64 in
                        let pid = pair.1
                        let (node, _) : (TreeNode<T,U>, PageStatus) = try m.readPage(pid)
                        return node.totalCount
                        }.reduce(UInt64(0), combine: +)
                    
                    let node    = try TreeInternal(version: m.version, pageSize: m.pageSize, totalCount: total, pairs: pairs)
                    let internalNode : TreeNode<T,U> = .internalNode(node)
                    let max     = node.max!
                    
                    if let pid = availablePageForReuse.popLast() {
                        try m.update(page: pid, with: internalNode)
                        newPairs.append((max, pid))
                    } else {
                        let pid = try m.createPage(for: internalNode)
                        newPairs.append((max, pid))
                    }
                }
            }
        }
        
        guard path.count == 0 else { fatalError("update of tree ancestors failed") }
        
        var rootPid : PageId
//        print("finished walk to tree root with \(newPairs.count) pairs")
        if newPairs.count > 1 {
//            print("- old root was split; creating new root")
            var totalCount : UInt64 = 0
            for (_,pid) in newPairs {
                let (node, _) : (TreeNode<T,U>, PageStatus) = try m.readPage(pid)
                totalCount += node.totalCount
            }
            let newRoot     = try TreeInternal(version: m.version, pageSize: m.pageSize, totalCount: totalCount, pairs: newPairs)
            let newRootNode : TreeNode<T,U> = .internalNode(newRoot)
            let pid = try m.createPage(for: newRootNode)
            //                print("--  new root node \(pid)")
            rootPid = pid
        } else {
            rootPid = newPairs.first!.1
        }
        
//        print("linking root '\(name)' to root node \(rootPid)")
        self.root = rootPid
        m.updateRoot(name: name, page: rootPid)
        return
    }
}

/**
 
 Tree Header:
 0  4   Cookie
 4  8   Version
 12 4   Config1 (type code)
 16 4   Config2 (Unused)
 20 8   Sub-tree count
 28 4   Pair count
 32 -   Payload
 
 **/

public final class TreeLeaf<T : protocol<BufferSerializable,Comparable>, U : BufferSerializable> {
    internal var typeCode : UInt32
    public var version : UInt64
    public var pairs : [(T,U)]
    public var serializedSize : Int
    public var max : T?
    
    init(version : UInt64, pageSize: Int, typeCode : UInt32, pairs : [(T,U)]) throws {
        self.version = version
        self.pairs = pairs
        self.typeCode = typeCode
        self.max = pairs.count == 0 ? nil : pairs.last!.0
        self.serializedSize = cookieHeaderSize
        for (k,v) in pairs {
            self.serializedSize += k.serializedSize
            self.serializedSize += v.serializedSize
        }
    }
    
    convenience init<V : IteratorProtocol where V.Element == (T,U)>(version : UInt64, pageSize: Int, pairs iter: inout PeekableIterator<V>) {
        var remainingBytes = pageSize - cookieHeaderSize
        var pairs = [(T,U)]()
        
        var next = iter.peek()
        while next != nil {
            let serializedSize = next!.0.serializedSize + next!.1.serializedSize
            if remainingBytes < serializedSize {
                break
            }
            let pair = iter.next()!
            pairs.append(pair)
            remainingBytes -= serializedSize
            next    = iter.peek()
        }
        try! self.init(version: version, pageSize: pageSize, typeCode: serializationCode(T.self, U.self), pairs: pairs)
    }
    
    convenience init(version : UInt64, pageSize: Int, pairs: [(T,U)]) throws {
        var remainingBytes = pageSize - cookieHeaderSize
        for (key, value) in pairs {
            let serializedSize = key.serializedSize + value.serializedSize
            if remainingBytes < serializedSize {
                throw DatabaseError.SerializationError("Tree leaf node overflow")
            }
            remainingBytes -= serializedSize
        }
        try self.init(version: version, pageSize: pageSize, typeCode: serializationCode(T.self, U.self), pairs: pairs)
    }
    
    convenience init?(mediator : RMediator, buffer : UnsafePointer<Void>, status: PageStatus) {
        guard let (_, version, typeCode, _, _, gen) = try? buffer.deserializeTree(mediator: mediator, type: .leafTreeNode, pageSize: mediator.pageSize, keyType: T.self, valueType: U.self) else { return nil }
        let pairs = Array(gen)
        do {
            try self.init(version: version, pageSize: mediator.pageSize, typeCode: typeCode, pairs: pairs)
        } catch {
            return nil
        }
    }
    
    public var totalCount : UInt64 { return UInt64(pairs.count) }
    
    @inline(__always) func spaceForPair(_ pair : (T,U), pageSize : Int) -> Bool {
        return self.serializedSize + pair.0.serializedSize + pair.1.serializedSize <= pageSize
    }
    
    func addPair(_ pair : (T,U)) throws {
        pairs.insertSorted(pair) { (l,r) in return l.0 < r.0 }
        self.serializedSize += pair.0.serializedSize
        self.serializedSize += pair.1.serializedSize
        self.max = self.pairs.last!.0
    }
    
    func serialize(to buffer: UnsafeMutablePointer<Void>, pageSize : Int) throws {
        let cookie      = DatabaseInfo.Cookie.leafTreeNode
        let config1     = serializationCode(T.self, U.self)
        let config2     = UInt32(0)
        let count       = UInt32(self.pairs.count)
        let totalCount  = UInt64(count)
        
        let byteCount   = try buffer.writeTreeHeader(type: cookie, version: self.version, config1: config1, config2: config2, totalCount: totalCount, count: count)
        assert(byteCount == cookieHeaderSize)
        let end         = buffer + pageSize
        
        var successful  = 0
        var ptr         = buffer + byteCount
        
        for (k,v) in self.pairs {
            let ks = k.serializedSize
            let vs = v.serializedSize
            let q = ptr+ks+vs
            guard q <= end else {
                throw DatabaseError.PageOverflow(successfulItems: successful)
            }
            try k.serialize(to: &ptr)
            try v.serialize(to: &ptr)
            successful += 1
        }
    }
}

public final class TreeInternal<T : protocol<BufferSerializable,Comparable>> {
    internal var typeCode : UInt32
    public var version : UInt64
    public var pairs : [(T,PageId)]
    public var totalCount : UInt64
    public var serializedSize : Int
    public var max : T?
    
    init(version : UInt64, pageSize : Int, totalCount : UInt64, typeCode : UInt32, pairs : [(T,PageId)]) throws {
        self.version = version
        self.pairs = pairs
        self.totalCount = totalCount
        self.typeCode = typeCode
        self.max = pairs.count == 0 ? nil : pairs.last!.0
        self.serializedSize = cookieHeaderSize
        for (k,v) in pairs {
            self.serializedSize += k.serializedSize
            self.serializedSize += v.serializedSize
        }
    }
    
    convenience init(version : UInt64, pageSize: Int, totalCount : UInt64, pairs: [(T,PageId)]) throws {
        var remainingBytes = pageSize - cookieHeaderSize
        for (key, value) in pairs {
            let serializedSize  = key.serializedSize + value.serializedSize
            if remainingBytes < serializedSize {
                throw DatabaseError.SerializationError("Tree internal node overflow")
            }
            remainingBytes -= serializedSize
        }
        try self.init(version: version, pageSize: pageSize, totalCount: totalCount, typeCode: serializationCode(T.self, PageId.self), pairs: pairs)
    }
    
    convenience init<V : IteratorProtocol where V.Element == (T,PageId)>(version : UInt64, pageSize: Int, totalCount : UInt64, pairs iter: inout PeekableIterator<V>) {
        var remainingBytes = pageSize - cookieHeaderSize
        var pairs = [(T,PageId)]()
        
        var next = iter.peek()
        while next != nil {
            let serializedSize  = next!.0.serializedSize + next!.1.serializedSize
            if remainingBytes < serializedSize {
                break
            }
            let pair = iter.next()!
            pairs.append(pair)
            remainingBytes -= serializedSize
            next    = iter.peek()
        }
        try! self.init(version: version, pageSize: pageSize, totalCount: totalCount, typeCode: serializationCode(T.self, PageId.self), pairs: pairs)
    }
    
    convenience init?(mediator : RMediator, buffer : UnsafePointer<Void>, status: PageStatus) {
        guard let (_, version, typeCode, _, totalCount, gen) = try? buffer.deserializeTree(mediator: mediator, type: .internalTreeNode, pageSize: mediator.pageSize, keyType: T.self, valueType: PageId.self) else { return nil }
        //        myprintf("# deserializing internal type %x \(pairName(typeCode))\n", typeCode)
        let pairs = Array(gen)
        do {
            try self.init(version: version, pageSize: mediator.pageSize, totalCount: totalCount, typeCode: typeCode, pairs: pairs)
        } catch {
            return nil
        }
    }
    
    @inline(__always) func spaceForPairs(_ pairs : [(T,PageId)], replacingIndex index : Int, pageSize : Int) -> Bool {
        let remove = self.pairs[index]
        let removeSize = remove.0.serializedSize + remove.1.serializedSize
        let addSize = pairs.map { $0.0.serializedSize + $0.1.serializedSize }.reduce(0, combine: +)
        return self.serializedSize + addSize - removeSize <= pageSize
    }
    
    func addPairs(_ newPairs : [(T,PageId)], replacingIndex index : Int, totalCount newTotal: UInt64) throws {
        self.totalCount = newTotal
        
        let replacing = self.pairs[index]
        self.serializedSize -= replacing.0.serializedSize + replacing.1.serializedSize
        for (k,v) in newPairs {
            self.serializedSize += k.serializedSize
            self.serializedSize += v.serializedSize
        }
        
        self.pairs.replaceSubrange(index...index, with: newPairs)
        self.max = self.pairs.last!.0
    }
    
    func serialize(to buffer : UnsafeMutablePointer<Void>, pageSize : Int) throws {
        let cookie      = DatabaseInfo.Cookie.internalTreeNode
        let config1     = serializationCode(T.self, PageId.self)
        let config2     = UInt32(0)
        let totalCount  = self.totalCount;
        let count       = UInt32(self.pairs.count)
        
        let byteCount   = try buffer.writeTreeHeader(type: cookie, version: self.version, config1: config1, config2: config2, totalCount: totalCount, count: count)
        assert(byteCount == cookieHeaderSize)
        let end         = buffer + pageSize
        
        var successful  = 0
        var ptr         = buffer + byteCount
        for (k,v) in self.pairs {
            let ks = k.serializedSize
            let vs = v.serializedSize
            let q = ptr+ks+vs
            guard q <= end else {
                throw DatabaseError.PageOverflow(successfulItems: successful)
            }
            try k.serialize(to: &ptr)
            try v.serialize(to: &ptr)
            successful += 1
        }
    }
}

private enum TreeNode<T : protocol<BufferSerializable,Comparable>, U : BufferSerializable> : PageMarshalled {
    case leafNode(TreeLeaf<T,U>)
    case internalNode(TreeInternal<T>)
    
    var maxKey : T? {
        switch self {
        case .leafNode(let l):
            return l.max
        case .internalNode(let i):
            return i.max
        }
    }
    
    var totalCount : UInt64 {
        switch self {
        case .leafNode(let l):
            return UInt64(l.pairs.count)
        case .internalNode(let i):
            return i.totalCount
        }
    }
    
    // TODO: make an Iterator version of this method
    func walk(mediator : RMediator, between: (T,T), onEachLeaf cb: @noescape (TreeLeaf<T,U>) throws -> ()) throws {
        switch self {
        case .leafNode(let l):
            try cb(l)
        case .internalNode(let i):
            var lastMax : T? = nil
            for (max, pid) in i.pairs {
                if let min = lastMax {
                    if between.1 >= min && between.0 <= max {
                        let (node, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(pid)
                        try node.walk(mediator: mediator, between: between, onEachLeaf: cb)
                    }
                } else {
                    if between.0 <= max {
                        let (node, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(pid)
                        try node.walk(mediator: mediator, between: between, onEachLeaf: cb)
                    }
                }
                lastMax = max
            }
        }
    }
    
    // TODO: make an Iterator version of this method
    func walk(mediator : RMediator, in range: Range<T>, onEachLeaf cb: @noescape (TreeLeaf<T,U>) throws -> ()) throws {
        switch self {
        case .leafNode(let l):
            try cb(l)
        case .internalNode(let i):
            var lastMax : T? = nil
            for (max, pid) in i.pairs {
                if let min = lastMax {
                    if range.upperBound > min && range.lowerBound <= max {
                        let (node, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(pid)
                        try node.walk(mediator: mediator, in: range, onEachLeaf: cb)
                    }
                } else {
                    if range.lowerBound <= max {
                        let (node, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(pid)
                        try node.walk(mediator: mediator, in: range, onEachLeaf: cb)
                    }
                }
                lastMax = max
            }
        }
    }
    
    // TODO: make an Iterator version of this method
    func walk(mediator : RMediator, onEachLeaf cb: @noescape (TreeLeaf<T,U>) throws -> ()) throws {
        switch self {
        case .leafNode(let l):
            try cb(l)
        case .internalNode(let i):
            for (_,pid) in i.pairs {
                //                print("- node walk going to page \(pid)")
                let (node, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(pid)
                try node.walk(mediator: mediator, onEachLeaf: cb)
            }
        }
    }
    func contains(key : T, mediator : RMediator) -> Bool {
        switch self {
        case .leafNode(let l):
            for (k,_) in l.pairs where k == key {
                return true
            }
            return false
        case .internalNode(let i):
            var lastMax : T? = nil
            for (max, pid) in i.pairs {
                if let min = lastMax {
                    if key >= min && key <= max {
                        do {
                            let (node, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(pid)
                            if node.contains(key: key, mediator: mediator) {
                                return true
                            }
                        } catch {}
                    }
                } else {
                    if key <= max {
                        do {
                            let (node, _) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(pid)
                            if node.contains(key: key, mediator: mediator) {
                                return true
                            }
                        } catch {}
                    }
                }
                lastMax = max
            }
            return false
        }
    }
    func get(key : T, mediator : RMediator) -> [U] {
        var elements = [U]()
        _ = try? self.walk(mediator: mediator, between: (key, key)) { (leaf) in
            for (k,v) in leaf.pairs {
                if k == key {
                    elements.append(v)
                }
            }
        }
        return elements
    }
    
    func pathToLeaf(for key: T, mediator : RMediator, currentStatus : PageStatus) throws -> ([(node: TreeInternal<T>, childPage : PageId, childIndex: Int, status: PageStatus)], TreeLeaf<T,U>, PageStatus) {
        switch self {
        case .leafNode(let l):
            return ([], l, currentStatus)
        case .internalNode(let i):
            for (index, (max, pid)) in i.pairs.enumerated() {
                if key <= max {
                    let (node, status) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(pid)
                    let (p, leaf, leafstatus) = try node.pathToLeaf(for: key, mediator: mediator, currentStatus: status)
                    let path = [(node: i, childPage: pid, childIndex: index, status: currentStatus)] + p
                    return (path, leaf, leafstatus)
                }
            }
            if let (_, pid) = i.pairs.last {
                let (node, status) : (TreeNode<T,U>, PageStatus) = try mediator.readPage(pid)
                let index = max(i.pairs.count - 1, 0)
                let (p, leaf, leafstatus) = try node.pathToLeaf(for: key, mediator: mediator, currentStatus: status)
                let path = [(node: i, childPage: pid, childIndex: index, status: currentStatus)] + p
                return (path, leaf, leafstatus)
            } else {
                throw DatabaseError.DataError("Failed to find leaf node for key \(key)")
            }
        }
    }
    
    func maxKey(in range: Range<T>, mediator : RMediator) -> T? {
        var maxKey : T? = nil
        _ = try? self.walk(mediator: mediator, in: range) { (leaf) in
            let matchingKeys = leaf.pairs.map({$0.0}).filter { range.contains($0) }
            if let m = matchingKeys.last {
                maxKey = m
            } else if maxKey != nil {
                throw TreeError.stopWalk
            }
        }
        return maxKey
    }
    
    static func deserialize(from buffer: UnsafePointer<Void>, status: PageStatus, mediator : RMediator) throws -> TreeNode<T,U> {
        var ptr = buffer
        guard let cookie = DatabaseInfo.Cookie(rawValue: try UInt32.deserialize(from: &ptr)) else { throw DatabaseError.DataError("Bad tree node cookie") }
        if cookie == .leafTreeNode {
            if let leaf : TreeLeaf<T,U> = TreeLeaf(mediator: mediator, buffer: buffer, status: status) {
                return TreeNode.leafNode(leaf)
            } else {
                throw DatabaseError.DataError("Bad leaf tree node data")
            }
        } else if cookie == .internalTreeNode {
            if let i : TreeInternal<T> = TreeInternal(mediator: mediator, buffer: buffer, status: status) {
                return TreeNode.internalNode(i)
            } else {
                throw DatabaseError.DataError("Bad internal tree node data")
            }
        } else {
            throw DatabaseError.DataError("Unexpected tree node cookie")
        }
    }
    
    func serialize(to buffer: UnsafeMutablePointer<Void>, status: PageStatus, mediator : RWMediator) throws {
        switch self {
        case .leafNode(let l):
            try l.serialize(to: buffer, pageSize: mediator.pageSize)
        case .internalNode(let i):
            try i.serialize(to: buffer, pageSize: mediator.pageSize)
        }
    }
}

private extension UnsafePointer {
    func deserialize<T : protocol<BufferSerializable,Comparable>, U : BufferSerializable>(mediator : RMediator, type : DatabaseInfo.Cookie, status: PageStatus, pageSize : Int, keyType : T.Type, valueType : U.Type) throws -> TreeNode<T,U> {
        var ptr = UnsafePointer<Void>(self)
        guard let cookie = DatabaseInfo.Cookie(rawValue: try UInt32.deserialize(from: &ptr)) else { throw DatabaseError.DataError("Bad tree node cookie") }
        if cookie == .leafTreeNode {
            if let leaf : TreeLeaf<T,U> = TreeLeaf(mediator: mediator, buffer: self, status: status) {
                return TreeNode.leafNode(leaf)
            }
            throw DatabaseError.DataError("Failed to construct tree leaf node from buffer")
        } else {
            if let i : TreeInternal<T> = TreeInternal(mediator: mediator, buffer: self, status: status) {
                return TreeNode.internalNode(i)
            }
            throw DatabaseError.DataError("Failed to construct tree internal node from buffer")
        }
    }
    
    func deserializeTree<T : protocol<BufferSerializable,Comparable>, U : BufferSerializable>(mediator : RMediator, type : DatabaseInfo.Cookie, pageSize : Int, keyType : T.Type, valueType : U.Type) throws -> (UInt32, UInt64, UInt32, UInt32, UInt64, AnyIterator<(T,U)>) {
        let rawMemory   = UnsafePointer<Void>(self)
        var ptr         = rawMemory
        let cookie      = try UInt32.deserialize(from: &ptr)
        let version     = try UInt64.deserialize(from: &ptr)
        let config1     = try UInt32.deserialize(from: &ptr)
        let config2     = try UInt32.deserialize(from: &ptr)
        let totalCount  = try UInt64.deserialize(from: &ptr)
        let count       = try UInt32.deserialize(from: &ptr)
        var payloadPtr  = ptr
        assert(ptr == rawMemory.advanced(by: 32))
        
        var i : UInt32 = 0
        let gen = AnyIterator { () -> (T,U)? in
            i += 1
            if i > count {
                return nil
            }
            
            guard let id = try? keyType.deserialize(from: &payloadPtr, mediator: mediator) else { return nil }
            guard let string = try? valueType.deserialize(from: &payloadPtr, mediator: mediator) else { return nil }
            return (id, string)
        }
        return (cookie, version, config1, config2, totalCount, gen)
    }
    
    private func treeNode<T : protocol<BufferSerializable, Comparable>, U: BufferSerializable>(mediator : RMediator, status : PageStatus) throws -> TreeNode<T, U> {
        let buffer = UnsafePointer<Void>(self)
        var ptr = buffer
        guard let cookie = DatabaseInfo.Cookie(rawValue: try UInt32.deserialize(from: &ptr)) else { throw DatabaseError.DataError("Bad tree node cookie") }
        if cookie == .leafTreeNode {
            if let leaf : TreeLeaf<T,U> = TreeLeaf(mediator: mediator, buffer: buffer, status: status) {
                return TreeNode.leafNode(leaf)
            } else {
                throw DatabaseError.DataError("Bad leaf tree node data")
            }
        } else if cookie == .internalTreeNode {
            if let i : TreeInternal<T> = TreeInternal(mediator: mediator, buffer: buffer, status: status) {
                return TreeNode.internalNode(i)
            } else {
                throw DatabaseError.DataError("Bad internal tree node data")
            }
        } else {
            throw DatabaseError.DataError("Unexpected tree node cookie")
        }
    }
    
}

extension UnsafeMutablePointer {
    @inline(__always) private func writeTreeHeader(type : DatabaseInfo.Cookie, version : UInt64, config1 : UInt32, config2 : UInt32, totalCount : UInt64, count : UInt32) throws -> Int {
        let buffer = UnsafeMutablePointer<Void>(self)
        var ptr = buffer
        try type.rawValue.serialize(to: &ptr)
        try version.serialize(to: &ptr)
        try config1.serialize(to: &ptr)
        try config2.serialize(to: &ptr)
        try totalCount.serialize(to: &ptr)
        try count.serialize(to: &ptr)
        return ptr - buffer
    }
}

extension RMediator {
    public func tree<T : protocol<BufferSerializable, Comparable>, U: BufferSerializable>(name: String) -> Tree<T,U>? {
        return Tree(name: name, mediator : self)
    }
    
    public func printTreeDOT(name : String) {
        var buffer = [PageId]()
        if let pid = try? self.getRoot(named: name) {
            buffer.append(pid)
        }
        
        print("digraph graphname {")
        var seen = Set<PageId>()
        while buffer.count > 0 {
            if let pid = buffer.popLast() {
                if seen.contains(pid) {
                    continue
                } else if let children = self.printTreeDOT(page: pid) {
                    buffer += children
                    seen.insert(pid)
                }
            }
        }
        for name in self.rootNames {
            if let pid = try? self.getRoot(named: name) {
                if seen.contains(pid) {
                    print("r\(pid) [label=\"\(name)\", style=bold, shape=diamond]")
                    print("r\(pid) -> p\(pid)")
                }
            }
        }
        print("}")
    }
    
    public func printTreeDOT(pages : [PageId]) {
        print("digraph graphname {")
        var seen = Set<PageId>()
        for pid in pages {
            if let _ = self.printTreeDOT(page: pid) {
                seen.insert(pid)
            }
        }
        for name in self.rootNames {
            if let pid = try? self.getRoot(named: name) {
                if seen.contains(pid) {
                    print("r\(pid) [label=\"\(name)\", style=bold, shape=diamond]")
                    print("r\(pid) -> p\(pid)")
                }
            }
        }
        print("}")
    }
    
    private func printTreeDOT(page pid : PageId) -> [PageId]? {
        do {
            let (node, _) : (TreeNode<Empty,Empty>, PageStatus) = try self.readPage(pid)
            let nodeName = "p\(pid)"
            var attributes = [String]()
            var label : String
            switch node {
            case .leafNode(let l):
                let type = pairName(l.typeCode)
                label = "[\(pid)] \(type) leaf (\(l.pairs.count) pairs)"
                attributes.append("label=\"\(label)\"")
                attributes.append("shape=box")
                print("\(nodeName) [\(attributes.joined(separator: ", "))]")
                return []
            case .internalNode(let i):
                let type = pairName(i.typeCode)
                label = "[\(pid)] \(type) internal (\(i.pairs.count) children, \(i.totalCount) total)"
                attributes.append("label=\"\(label)\"")
                print("\(nodeName) [\(attributes.joined(separator: ", "))]")
                var children = [PageId]()
                if i.typeCode == termIntType {
                    let (typed, _) : (TreeNode<Term,PageId>, PageStatus) = try self.readPage(pid)
                    if case .internalNode(let typedi) = typed {
                        for (k,cpid) in typedi.pairs {
                            children.append(cpid)
                            let esc = String("\(k)".characters.map { $0 == "\"" ? "'" : $0 })
                            let child = "p\(cpid)"
                            print("\(nodeName) -> \(child) [label=\"\(esc)\"]")
                        }
                    }
                } else if i.typeCode == intIntType {
                    let (typed, _) : (TreeNode<UInt64,PageId>, PageStatus) = try self.readPage(pid)
                    if case .internalNode(let typedi) = typed {
                        for (k,cpid) in typedi.pairs {
                            children.append(cpid)
                            let esc = String("\(k)".characters.map { $0 == "\"" ? "'" : $0 })
                            let child = "p\(cpid)"
                            print("\(nodeName) -> \(child) [label=\"\(esc)\"]")
                        }
                    }
                } else if i.typeCode == quadIntType {
                    let (typed, _) : (TreeNode<IDQuad<UInt64>,PageId>, PageStatus) = try self.readPage(pid)
                    if case .internalNode(let typedi) = typed {
                        for (k,cpid) in typedi.pairs {
                            children.append(cpid)
                            let esc = String("\(k)".characters.map { $0 == "\"" ? "'" : $0 })
                            let child = "p\(cpid)"
                            print("\(nodeName) -> \(child) [label=\"\(esc)\"]")
                        }
                    }
                }
                return children
            }
        } catch {}
        return nil
    }
    
    public func debugTreePage(_ pid : PageId) {
        do {
            let (node, _) : (TreeNode<Empty,Empty>, PageStatus) = try self.readPage(pid)
            switch node {
            case .leafNode(let l):
                let date = getDateString(seconds: l.version)
                print("Tree node on page \(pid)")
                print("    Type          : LEAF")
                print("    Modified      : \(date)")
                print("    Pair count    : \(l.pairs.count)")
                if l.typeCode == intEmptyType {
                    let (typed, _) : (TreeNode<UInt64,Empty>, PageStatus) = try self.readPage(pid)
                    if case .leafNode(let typedl) = typed {
                        for (k,_) in typedl.pairs {
                            print("        - \(k)")
                        }
                    }
                } else if l.typeCode == termIntType {
                    let (typed, _) : (TreeNode<Term,PageId>, PageStatus) = try self.readPage(pid)
                    if case .leafNode(let typedl) = typed {
                        for (k,v) in typedl.pairs {
                            print("        - \(k): \(v)")
                        }
                    }
                } else if l.typeCode == intTermType {
                    let (typed, _) : (TreeNode<PageId,Term>, PageStatus) = try self.readPage(pid)
                    if case .leafNode(let typedl) = typed {
                        for (k,v) in typedl.pairs {
                            print("        - \(k): \(v)")
                        }
                    }
                } else if l.typeCode == intIntType {
                    let (typed, _) : (TreeNode<UInt64,PageId>, PageStatus) = try self.readPage(pid)
                    if case .leafNode(let typedl) = typed {
                        for (k,v) in typedl.pairs {
                            print("        - \(k): \(v)")
                        }
                    }
                } else if l.typeCode == quadIntType {
                    let (typed, _) : (TreeNode<IDQuad<UInt64>,PageId>, PageStatus) = try self.readPage(pid)
                    if case .leafNode(let typedl) = typed {
                        for (k,v) in typedl.pairs {
                            print("        - \(k): \(v)")
                        }
                    }
                }
            case .internalNode(let i):
                let date = getDateString(seconds: i.version)
                print("Tree node on page \(pid)")
                print("    Type          : INTERNAL")
                print("    Modified      : \(date)")
                print("    Pointer count : \(i.pairs.count)")
                if i.typeCode == termIntType {
                    let (typed, _) : (TreeNode<Term,PageId>, PageStatus) = try self.readPage(pid)
                    if case .internalNode(let typedi) = typed {
                        for (k,cpid) in typedi.pairs {
                            print("        - \(k): Page \(cpid)")
                        }
                    }
                } else if i.typeCode == intIntType {
                    let (typed, _) : (TreeNode<UInt64,PageId>, PageStatus) = try self.readPage(pid)
                    if case .internalNode(let typedi) = typed {
                        for (k,cpid) in typedi.pairs {
                            print("        - \(k): Page \(cpid)")
                        }
                    }
                } else if i.typeCode == quadIntType {
                    let (typed, _) : (TreeNode<IDQuad<UInt64>,PageId>, PageStatus) = try self.readPage(pid)
                    if case .internalNode(let typedi) = typed {
                        for (k,cpid) in typedi.pairs {
                            print("        - \(k): Page \(cpid)")
                        }
                    }
                }
            }
        } catch {}
    }
}

extension RWMediator {
    private func createTreeInternals<C : Sequence, T : protocol<BufferSerializable, Comparable>, U : BufferSerializable where C.Iterator.Element == (TreeNode<T,U>, PageId)>(pairs adding: C, keyType : T.Type, valueType : U.Type) throws -> [(TreeNode<T,U>, PageId)] {
        var lastKey : T? = nil
        let counts  = adding.map { $0.0.totalCount }
        let pairs   = adding.map { ($0.0.maxKey!, $0.1) }
        for (node, pid) in adding {
            let currentKey = node.maxKey
            if let last = lastKey {
                if last > currentKey {
                    throw DatabaseError.DataError("Cannot add page \(pid) to internal node and preserve tree ordering (the max key \(currentKey) is less than the previous max key \(last))")
                }
            }
            lastKey = currentKey
        }
        
        var iter = PeekableIterator(generator: pairs.makeIterator())
        //        var pages = [PageId]()
        var newPairs = [(TreeNode<T,U>, PageId)]()
        while iter.peek() != nil {
            let node = TreeInternal(version: version, pageSize: pageSize, totalCount: UInt64(0), pairs: &iter)
            let filled = node.pairs.count
            //            print("filled internal node with \(filled) pairs")
            let sum = counts.prefix(filled).reduce(0, combine: { $0 + $1 })
            node.totalCount = sum
            let internalNode : TreeNode<T,U> = .internalNode(node)
            
            let pid = try self.createPage(for: internalNode)
            newPairs.append((internalNode, pid))
        }
        return newPairs
    }
    
    private func createTreeLeaves<C : Sequence, T : protocol<BufferSerializable, Comparable>, U : BufferSerializable where C.Iterator.Element == (T,U)>(pairs: C) throws -> [(TreeNode<T,U>, PageId)] {
        var iter = PeekableIterator(generator: pairs.makeIterator())
        var leaves = [(TreeNode<T,U>, PageId)]()
        var lastKey : T? = nil
        while let next = iter.peek() {
            if let lastKey = lastKey {
                if lastKey > next.0 {
                    throw DatabaseError.DataError("Found keys that are not sorted during tree construction")
                }
            }
            lastKey = next.0
            
            let node = TreeLeaf(version: version, pageSize: pageSize, pairs: &iter)
            let leafNode : TreeNode<T,U> = .leafNode(node)
            
            let pid = try self.createPage(for: leafNode)
            leaves.append((leafNode, pid))
            //            print("filled leaf node with \(node.pairs.count) pairs")
        }
        if lastKey == nil {
            let node = TreeLeaf(version: version, pageSize: pageSize, pairs: &iter)
            let leafNode : TreeNode<T,U> = .leafNode(node)
            
            let pid = try self.createPage(for: leafNode)
            leaves.append((leafNode, pid))
        }
        return leaves
    }
    
    public func create<C : Sequence, T : protocol<BufferSerializable, Comparable>, U : BufferSerializable where C.Iterator.Element == (T,U)>(tree name: String, pairs: C) throws -> PageId {
        let pid = try self.createTree(pairs: pairs)
        self.updateRoot(name: name, page: pid)
        return pid
    }
    
    public func createTree<C : Sequence, T : protocol<BufferSerializable, Comparable>, U : BufferSerializable where C.Iterator.Element == (T,U)>(pairs: C) throws -> PageId {
        let newPairs  = try createTreeLeaves(pairs: pairs)
        if newPairs.count == 0 {
            throw DatabaseError.DataError("Failed to create tree leaves")
        } else if newPairs.count == 1 {
            return newPairs[0].1
        } else {
            var pairs = newPairs
            while pairs.count > 1 {
                pairs   = try createTreeInternals(pairs: pairs, keyType: T.self, valueType: U.self)
            }
            return pairs[0].1
        }
    }
}

