//
//  QuadStore.swift
//  PageDatabase
//
//  Created by Gregory Todd Williams on 6/12/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation

public struct QuadPattern : CustomStringConvertible {
    public var subject : Node
    public var predicate : Node
    public var object : Node
    public var graph : Node
    public init(subject: Node, predicate: Node, object: Node, graph: Node) {
        self.subject = subject
        self.predicate = predicate
        self.object = object
        self.graph = graph
    }
    public var description : String {
        return "\(subject) \(predicate) \(object) \(graph)."
    }
}

public protocol IdentityMap {
    associatedtype Element : Hashable
    associatedtype Result : Comparable, DefinedTestable
    func id(for value: Element) -> Result?
    func getOrSetID(for value: Element) throws -> Result
}

public class PersistentTermIdentityMap : IdentityMap {
    static let blankTypeByte : UInt8       = 0x01
    static let iriTypeByte : UInt8         = 0x02
    static let languageTypeByte : UInt8    = 0x03
    static let datatypeTypeByte : UInt8    = 0x04

    public typealias Element = Term
    public typealias Result = UInt64

    var mediator : RMediator
    var next : (iri: UInt64, blank: UInt64, datatype: UInt64, language: UInt64)
    let t2iMapTreeName = "t2i_tree"
    let i2tMapTreeName = "i2t_tree"
    var i2tcache : LRUCache<Result,Term>
    var t2icache : LRUCache<Term,Result>

    public init (mediator : RMediator) throws {
        self.mediator = mediator
        var t2i : Tree<Element,Result>? = mediator.tree(name: t2iMapTreeName)
        if t2i == nil {
            guard let m = mediator as? RWMediator else {
                throw DatabaseError.PermissionError("Cannot create new PersistentTermIdentityMap in a read-only transaction")
            }
            let t2ipairs = [(Element, Result)]()
            _ = try m.create(tree: t2iMapTreeName, pairs: t2ipairs)
            t2i = mediator.tree(name: t2iMapTreeName)
        }

        var i2t : Tree<Result,Element>? = mediator.tree(name: i2tMapTreeName)
        if i2t == nil {
            guard let m = mediator as? RWMediator else {
                throw DatabaseError.PermissionError("Cannot create new PersistentTermIdentityMap in a read-only transaction")
            }
            let i2tpairs = [(Result, Element)]()
            _ = try m.create(tree: i2tMapTreeName, pairs: i2tpairs)
            i2t = mediator.tree(name: i2tMapTreeName)
        }
        
        if let i2t = i2t {
            next = PersistentTermIdentityMap.loadMaxIDs(from: i2t, mediator: mediator)
        } else {
            throw DatabaseError.PermissionError("Failed to get PersistentTermIdentityMap trees")
        }

        self.i2tcache = LRUCache(capacity: 64)
        self.t2icache = LRUCache(capacity: 64)
    }
    
    private static func idRange(for type: UInt8) -> Range<UInt64> {
        let min = (UInt64(type) << 56)
        let max = (UInt64(type+1) << 56)
        return min..<max
    }
    
    private static func loadMaxIDs(from tree : Tree<Result,Element>, mediator : RMediator) -> (UInt64, UInt64, UInt64, UInt64) {
        let mask        = UInt64(0x00ffffffffffffff)
        let blankMax    = (tree.maxKey(in: idRange(for: blankTypeByte)) ?? 0) & mask
        let iriMax      = (tree.maxKey(in: idRange(for: iriTypeByte)) ?? 0) & mask
        let languageMax = (tree.maxKey(in: idRange(for: languageTypeByte)) ?? 0) & mask
        let datatypeMax = (tree.maxKey(in: idRange(for: datatypeTypeByte)) ?? 0) & mask
//        print("# Max term IDs: \(blankMax) \(iriMax) \(languageMax) \(datatypeMax)")
        return (iri: iriMax+1, blank: blankMax+1, datatype: datatypeMax+1, langauge: languageMax+1)
    }
    
    public func term(for id: Result) -> Term? {
        if let term = self.i2tcache[id] {
            return term
        }
        if let node : Tree<Result, Element> = mediator.tree(name: i2tMapTreeName) {
            let pairs = node.get(key: id)
            if pairs.count == 0 {
                print("*** No terms found for ID \(id)")
            }
            self.i2tcache[id] = pairs.first
            return pairs.first
        } else {
            print("*** No node found for tree \(i2tMapTreeName)")
        }
        return nil
    }
    
    public func id(for value: Element) -> UInt64? {
        if let id = self.t2icache[value] {
            return id
        }
        if let node : Tree<Element, Result> = mediator.tree(name: t2iMapTreeName) {
            let pairs = node.get(key: value)
            self.t2icache[value] = pairs.first
            return pairs.first
        }
        return nil
    }

    // TODO: change this to make the identitymap a sequence type?
    public func walk(forEach cb: (Element, Result) -> ()) {
        if let node : Tree<Result, Element> = mediator.tree(name: i2tMapTreeName) {
            print("node: \(node)")
            _ = try? node.walk {(pairs) in
                for (v, k) in pairs {
                    cb(k,v)
                }
            }
        } else {
            print("No id to term map found in database")
        }
    }

    public func getOrSetID(for term: Element) throws -> UInt64 {
        if let id = id(for: term) {
            return id
        } else {
            var value : UInt64
            var type : UInt8 = 0
            switch term.type {
            case .blank:
                type = PersistentTermIdentityMap.blankTypeByte
                value = next.blank
                next.blank += 1
            case .iri:
                type = PersistentTermIdentityMap.iriTypeByte
                value = next.iri
                next.iri += 1
            case .language(_):
                type = PersistentTermIdentityMap.languageTypeByte
                value = next.language
                next.language += 1
            case .datatype(_):
                type = PersistentTermIdentityMap.datatypeTypeByte
                value = next.datatype
                next.datatype += 1
            }
            
            guard value < UInt64(0x00ffffffffffffff) else { throw DatabaseError.DataError("Term ID overflows the 56 bits available") }
            let id = (UInt64(type) << 56) + value
            
            guard let m = mediator as? RWMediator else { throw DatabaseError.PermissionError("Cannot create new term IDs in a read-only transaction") }
            guard let i2t : Tree<Result, Element> = m.tree(name: i2tMapTreeName) else { throw DatabaseError.DataError("Failed to get the ID to term tree") }
            guard let t2i : Tree<Element, Result> = m.tree(name: t2iMapTreeName) else { throw DatabaseError.DataError("Failed to get the term to ID tree") }

            try i2t.add(pair: (id, term))
            try t2i.add(pair: (term, id))
            
            return id
        }
    }
}

public protocol DefinedTestable {
    var isDefined : Bool { get }
}

extension UInt64 : DefinedTestable {
    public var isDefined : Bool {
        return self != 0
    }
}

public struct IDQuad<T : protocol<DefinedTestable, Equatable, Comparable, BufferSerializable>> : BufferSerializable, Equatable, Comparable {
    var values : [T]
    public init(_ v0 : T, _ v1 : T, _ v2 : T, _ v3 : T) {
        self.values = [v0,v1,v2,v3]
    }
    
    public subscript(i : Int) -> T {
        get {
            return self.values[i]
        }
        
        set(newValue) {
            self.values[i] = newValue
        }
    }
    
    public func matches(_ rhs : IDQuad) -> Bool {
        for (l,r) in zip(values, rhs.values) {
            if l.isDefined && r.isDefined && l != r {
                return false
            }
        }
        return true
    }
    
    public var serializedSize : Int { return 4 * sizeof(T.self) }
    public func serialize(to buffer : inout UnsafeMutablePointer<Void>, mediator: RWMediator?, maximumSize: Int) throws {
        if serializedSize > maximumSize { throw DatabaseError.OverflowError("Cannot serialize IDQuad in available space") }
        //        print("serializing quad \(subject) \(predicate) \(object) \(graph)")
        try self[0].serialize(to: &buffer)
        try self[1].serialize(to: &buffer)
        try self[2].serialize(to: &buffer)
        try self[3].serialize(to: &buffer)
    }
    
    public static func deserialize(from buffer : inout UnsafePointer<Void>, mediator : RMediator?=nil) throws -> IDQuad {
        let v0      = try T.deserialize(from: &buffer, mediator: mediator)
        let v1      = try T.deserialize(from: &buffer, mediator: mediator)
        let v2      = try T.deserialize(from: &buffer, mediator: mediator)
        let v3      = try T.deserialize(from: &buffer, mediator: mediator)
        //        print("deserializing quad \(v0) \(v1) \(v2) \(v3)")
        let q = IDQuad(v0, v1, v2, v3)
        return q
    }
}

public func ==<T>(lhs: IDQuad<T>, rhs: IDQuad<T>) -> Bool {
    if lhs[0] == rhs[0] && lhs[1] == rhs[1] && lhs[2] == rhs[2] && lhs[3] == rhs[3] {
        return true
    } else {
        return false
    }
}

public func < <T>(lhs: IDQuad<T>, rhs: IDQuad<T>) -> Bool {
    for (l,r) in zip(lhs.values, rhs.values) {
        if l < r {
            return true
        } else if l > r {
            return false
        }
    }
    return false
}

extension RWMediator {
    public func addQuadIndex(_ index : String) throws {
        guard String(index.characters.sorted()) == "gops" else { throw DatabaseError.KeyError("Not a valid quad index name: '\(index)'") }
        guard let table : Table<IDQuad<UInt64>,Empty> = table(name: "quads") else { throw DatabaseError.DataError("Failed to load quads table") }
        let mapping = quadMapping(toOrder: index)
        let empty = Empty()
        let pairs = table.map { mapping(quad: $0.0) }.sorted().map { ($0, empty) }
        let pid = try create(tree: index, pairs: pairs)
//        updateRoot(name : index, page : pid)
    }
}

extension RMediator {
    public var availableQuadIndexes : [String] {
        return self.rootNames.filter { String($0.characters.sorted()) == "gops" }
    }
    
    public func quadMapping(fromOrder index : String) throws -> (quad: IDQuad<UInt64>) -> (IDQuad<UInt64>) {
        let QUAD_POSTIONS = ["s": 0, "p": 1, "o": 2, "g": 3]
        var mapping = [Int:Int]()
        for (i,c) in index.characters.enumerated() {
            guard let index = QUAD_POSTIONS[String(c)] else { throw DatabaseError.DataError("Bad quad position character \(c) found while attempting to map a quad from index order") }
            mapping[index] = i
        }
        
        guard let si = mapping[0], pi = mapping[1], oi = mapping[2], gi = mapping[3] else { fatalError() }
        return { (quad) in
            return IDQuad(quad[si], quad[pi], quad[oi], quad[gi])
        }
    }
    
    public func quadMapping(toOrder index : String) -> (quad: IDQuad<UInt64>) -> (IDQuad<UInt64>) {
        let QUAD_POSTIONS = ["s": 0, "p": 1, "o": 2, "g": 3]
        var mapping = [Int:Int]()
        for (i,c) in index.characters.enumerated() {
            guard let index = QUAD_POSTIONS[String(c)] else { fatalError() }
            mapping[i] = index
        }
        
        guard let si = mapping[0], pi = mapping[1], oi = mapping[2], gi = mapping[3] else { fatalError() }
        return { (quad) in
            return IDQuad(quad[si], quad[pi], quad[oi], quad[gi])
        }
    }
    
    public func bestIndex(for pattern : QuadPattern) -> (String, Int) {
        let QUAD_POSTIONS = ["s": 0, "p": 1, "o": 2, "g": 3]
        let s = pattern.subject
        let p = pattern.predicate
        let o = pattern.object
        let g = pattern.graph
        let nodes = [s,p,o,g]
        
        var bestCount = 0
        var indexCoverage = [0: availableQuadIndexes[0]]
        for index_name in availableQuadIndexes {
            var count = 0
            for c in index_name.characters {
                if let pos = QUAD_POSTIONS[String(c)] {
                    let node = nodes[pos]
                    if case .bound(_) = node {
                        count += 1
                    } else {
                        break
                    }
                }
            }
            indexCoverage[count] = index_name
            bestCount = max(bestCount, count)
        }
        
        if let index_name = indexCoverage[bestCount] {
            return (index_name, bestCount)
        } else {
            return (availableQuadIndexes[0], 0)
        }
    }
    
    public func quads(matching pattern: QuadPattern) throws -> AnyIterator<Quad> {
        let umin = UInt64.min
        let umax = UInt64.max
        let idmap = try PersistentTermIdentityMap(mediator: self)
        var quadids = [IDQuad<UInt64>]()
        
        let (index_name, count) = bestIndex(for: pattern)
        print("Index '\(index_name)' is best match with \(count) prefix terms")
        
        let nodes = [pattern.subject, pattern.predicate, pattern.object, pattern.graph]
        var patternIds = [UInt64]()
        for i in 0..<4 {
            let node = nodes[i]
            switch node {
            case .variable(_):
                patternIds.append(0)
            case .bound(let term):
                guard let id = idmap.id(for: term) else { throw DatabaseError.DataError("Failed to load term ID for \(term)") }
                patternIds.append(id)
            }
        }
        
        let fromIndexOrder      = try quadMapping(fromOrder: index_name)
        let toIndexOrder        = quadMapping(toOrder: index_name)
        let spogOrdered         = IDQuad(patternIds[0], patternIds[1], patternIds[2], patternIds[3])
        var indexOrderedMin     = toIndexOrder(quad: spogOrdered)
        var indexOrderedMax     = toIndexOrder(quad: spogOrdered)
        let indexOrderedPattern = toIndexOrder(quad: spogOrdered)
        for i in count..<4 {
            indexOrderedMin[i]      = umin
            indexOrderedMax[i]      = umax
        }
        //            print("pattern = \(indexOrderedPattern)")
        //            print("In index order: \(indexOrderedMin)..\(indexOrderedMax)")
        
        if let node : Tree<IDQuad<UInt64>,Empty> = tree(name: index_name) {
            let min = indexOrderedMin
            let max = indexOrderedMax
            _ = try? node.walk(between: (min, max)) { (pairs) in
                for (indexOrder, _) in pairs where indexOrder >= min && indexOrder <= max {
                    if indexOrder.matches(indexOrderedPattern) {
                        let quad = fromIndexOrder(quad: indexOrder)
                        quadids.append(quad)
                    }
                }
            }
            
            let quads = try quadids.map { (quad) throws -> Quad in
                if let s = idmap.term(for: quad[0]), p = idmap.term(for: quad[1]), o = idmap.term(for: quad[2]), g = idmap.term(for: quad[3]) {
                    let q = Quad(subject: s, predicate: p, object: o, graph: g)
                    return q
                } else {
                    throw DatabaseError.DataError("Failed to construct quad")
                }
            }
            
            return AnyIterator(quads.makeIterator())
        } else {
            throw DatabaseError.DataError("No index named '\(index_name) found")
        }
    }
}

