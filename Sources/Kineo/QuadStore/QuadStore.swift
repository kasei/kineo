//
//  QuadStore.swift
//  PageDatabase
//
//  Created by Gregory Todd Williams on 6/12/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation

public protocol QuadStoreProtocol: Sequence {
    associatedtype IDType
    var count: Int { get }
    func graphs() -> AnyIterator<Term>
    func graphIDs() -> AnyIterator<IDType>
    func graphNodeTerms() -> AnyIterator<Term>
    func graphNodeIDs() -> AnyIterator<IDType>
    func makeIterator() -> AnyIterator<Quad>
    func results(matching pattern: QuadPattern) throws -> AnyIterator<TermResult>
    func quads(matching pattern: QuadPattern) throws -> AnyIterator<Quad>
    func effectiveVersion(matching pattern: QuadPattern) throws -> Version?
}

extension QuadStoreProtocol {
    public func effectiveVersion() throws -> Version? {
        let pattern = QuadPattern(
            subject: .variable("s", binding: true),
            predicate: .variable("p", binding: true),
            object: .variable("o", binding: true),
            graph: .variable("g", binding: true)
        )
        return try effectiveVersion(matching: pattern)
    }
}

// swiftlint:disable:next type_body_length
open class QuadStore: Sequence, QuadStoreProtocol {
    public typealias IDType = UInt64
    static public let defaultIndex = "pogs"
    internal var mediator: RMediator
    public let readonly: Bool
    public var id: PersistentTermIdentityMap
    public init(mediator: RMediator, mutable: Bool = false) throws {
        self.mediator = mediator
        var readonly = !mutable
        if readonly {
            if let _ = mediator as? RWMediator {
                readonly = false
            }
        }
        self.readonly = readonly
        self.id = try PersistentTermIdentityMap(mediator: mediator, readonly: readonly)
    }

    public var count : Int {
        let pattern = QuadPattern(
            subject: .variable("s", binding: true),
            predicate: .variable("p", binding: true),
            object: .variable("o", binding: true),
            graph: .variable("g", binding: true)
        )
        return count(matching: pattern)
    }
    
    public func count(matching pattern: QuadPattern) -> Int {
        guard let idquads = try? idquads(matching: pattern) else { return 0 }
        var count = 0
        for _ in idquads {
            count += 1
        }
        return count
    }
    
    public static func create(mediator: RWMediator) throws -> QuadStore {
        do {
            _ = try PersistentTermIdentityMap(mediator: mediator)
            _ = try mediator.getRoot(named: defaultIndex)
            // all the trees seem to be set up
            return try QuadStore(mediator: mediator)
        } catch {
            // empty database; set up the trees and tables
            do {
                _ = try PersistentTermIdentityMap(mediator: mediator)
                let store = try QuadStore(mediator: mediator)
                let pairs: [(IDQuad<UInt64>, Empty)] = []
                _ = try mediator.create(tree: defaultIndex, pairs: pairs)
                return store
            } catch let e {
                warn("*** \(e)")
                throw DatabaseUpdateError.rollback
            }
        }
    }

    private func generateIDQuadsAddingTerms<S: Sequence>(quads: S) throws -> AnyIterator<IDQuad<IDType>> where S.Iterator.Element == Quad {
        var idquads = [IDQuad<IDType>]()
        for quad in quads {
            var ids = [IDType]()
            for term in quad {
                let id = try self.id.getOrSetID(for: term)
                ids.append(id)
            }
            idquads.append(IDQuad(ids[0], ids[1], ids[2], ids[3]))
        }
        return AnyIterator(idquads.makeIterator())
    }

    public func load<S: Sequence>(quads: S) throws where S.Iterator.Element == Quad {
        let defaultIndex = QuadStore.defaultIndex
        guard let m = self.mediator as? RWMediator else { throw DatabaseError.PermissionError("Cannot load quads into a read-only quadstore") }
        do {
            print("Adding RDF terms to database...")
            let idquads = try generateIDQuadsAddingTerms(quads: quads)

            print("Adding RDF triples to database...")
            let empty = Empty()

            let toIndex = quadMapping(toOrder: defaultIndex)
            guard let defaultQuadsIndex: Tree<IDQuad<UInt64>, Empty> = m.tree(name: defaultIndex) else { throw DatabaseError.DataError("Missing default index \(defaultIndex)") }

            let spog = idquads.sorted()
            print("Loading quads into primary index \(defaultIndex)")
            for spogquad in spog {
                let indexOrder = toIndex(spogquad)
                let pair = (indexOrder, empty)
                try defaultQuadsIndex.insertIgnore(pair: pair)
            }

            for secondaryIndex in self.availableQuadIndexes.filter({ $0 != QuadStore.defaultIndex }) {
                print("Loading quads into secondary index \(secondaryIndex)")
                guard let secondaryQuadIndex: Tree<IDQuad<UInt64>, Empty> = m.tree(name: secondaryIndex) else { throw DatabaseError.DataError("Missing secondary index \(secondaryIndex)") }
                let toSecondaryIndex = quadMapping(toOrder: secondaryIndex)
                let indexOrdered = spog.map { toSecondaryIndex($0) }.sorted()
                for indexOrder in indexOrdered {
                    let pair = (indexOrder, empty)
                    try secondaryQuadIndex.insertIgnore(pair: pair)
                }
            }
        } catch let e {
            warn("*** \(e)")
            throw DatabaseUpdateError.rollback
        }
    }

    public func addQuadIndex(_ index: String) throws {
        let defaultIndex = QuadStore.defaultIndex
        guard let m = self.mediator as? RWMediator else { throw DatabaseError.PermissionError("Cannot create a quad index in a read-only quadstore") }
        guard String(index.sorted()) == "gops" else { throw DatabaseError.KeyError("Not a valid quad index name: '\(index)'") }
        guard let defaultQuadsIndex: Tree<IDQuad<UInt64>, Empty> = m.tree(name: defaultIndex) else { throw DatabaseError.DataError("Missing default index \(defaultIndex)") }

        let toSpog  = try quadMapping(fromOrder: defaultIndex)
        let toIndex = quadMapping(toOrder: index)

        let empty = Empty()
        let pairs = defaultQuadsIndex.map { $0.0 }.map { (idquad) -> IDQuad<UInt64> in
            let spog = toSpog(idquad)
            let indexOrder = toIndex(spog)
            return indexOrder
            }.sorted().map { ($0, empty) }

        _ = try m.create(tree: index, pairs: pairs)
    }

    public func graphIDs() -> AnyIterator<IDType> {
        guard let mapping = try? quadMapping(fromOrder: QuadStore.defaultIndex) else {
            warn("Failed to compute mapping for quad index order \(QuadStore.defaultIndex)")
            return AnyIterator { return nil }
        }
        guard let quadsTree: Tree<IDQuad<UInt64>, Empty> = mediator.tree(name: QuadStore.defaultIndex) else {
            warn("Failed to load default index \(QuadStore.defaultIndex)")
            return AnyIterator { return nil }
        }

        var seen = Set<UInt64>()
        let graphs = quadsTree.lazy.map {
            mapping($0.0)
            }.map { (idquad) in
                idquad[3]
            }.compactMap { $0 }.filter { (gid) -> Bool in
                let s = seen.contains(gid)
                seen.insert(gid)
                return !s
            }.compactMap { $0 }

        return AnyIterator(graphs.makeIterator())
    }

    public func graphs() -> AnyIterator<Term> {
        let idmap = self.id
        let ids = self.graphIDs()
        let graphs = ids.map { (gid) -> Term? in
            return idmap.term(for: gid)
        }.compactMap { $0 }

        return AnyIterator(graphs.makeIterator())
    }

    public func graphNodeIDs() -> AnyIterator<IDType> {
        guard let mapping = try? quadMapping(fromOrder: QuadStore.defaultIndex) else {
            warn("Failed to compute mapping for quad index order \(QuadStore.defaultIndex)")
            return AnyIterator { return nil }
        }
        guard let quadsTree: Tree<IDQuad<UInt64>, Empty> = mediator.tree(name: QuadStore.defaultIndex) else {
            warn("Failed to load default index \(QuadStore.defaultIndex)")
            return AnyIterator { return nil }
        }

        var seen = Set<UInt64>()
        let nodes = quadsTree.lazy.map {
                mapping($0.0)
            }.map { (idquad) in
                [idquad[2], idquad[0]]
            }.flatMap { $0 }.filter { (gid) -> Bool in
                let s = seen.contains(gid)
                seen.insert(gid)
                return !s
            }

        return AnyIterator(nodes.makeIterator())
    }

    public func graphNodeTerms() -> AnyIterator<Term> {
        let idmap = self.id
        let ids = graphNodeIDs()
        let nodes = ids.map { (gid) -> Term? in
                return idmap.term(for: gid)
            }.compactMap { $0 }

        return AnyIterator(nodes.makeIterator())
    }

    public func quad(from idquad: IDQuad<UInt64>) -> Quad? {
        let idmap = self.id
        if let s = idmap.term(for: idquad[0]), let p = idmap.term(for: idquad[1]), let o = idmap.term(for: idquad[2]), let g = idmap.term(for: idquad[3]) {
            return Quad(subject: s, predicate: p, object: o, graph: g)
        }
        return nil
    }

    public func iterator(usingIndex treeName: String) throws -> AnyIterator<Quad> {
        let mapping = try quadMapping(fromOrder: treeName)
        let idmap = self.id
        if let quadsTree: Tree<IDQuad<UInt64>, Empty> = mediator.tree(name: treeName) {
            let idquads = quadsTree.makeIterator()
            return AnyIterator {
                repeat {
                    guard let pair = idquads.next() else { return nil }
                    let indexOrderedIDQuad = pair.0
                    let idquad = mapping(indexOrderedIDQuad)
                    if let s = idmap.term(for: idquad[0]), let p = idmap.term(for: idquad[1]), let o = idmap.term(for: idquad[2]), let g = idmap.term(for: idquad[3]) {
                        return Quad(subject: s, predicate: p, object: o, graph: g)
                    }
                } while true
            }
        } else {
            throw DatabaseError.KeyError("No such index: \(treeName)")
        }
    }

    public func makeIterator() -> AnyIterator<Quad> {
        let treeName = QuadStore.defaultIndex
        do {
            return try iterator(usingIndex: treeName)
        } catch let e {
            warn("*** \(e)")
        }
        return AnyIterator { return nil }
    }

    public var availableQuadIndexes: [String] {
        return mediator.rootNames.filter { String($0.sorted()) == "gops" }
    }

    private func bestIndex(for bound: [Bool]) -> (String, Int) {
        let QUAD_POSTIONS = ["s": 0, "p": 1, "o": 2, "g": 3]
        var bestCount = 0
        let available = availableQuadIndexes
        var indexCoverage = [0: available[0]]
        for index_name in available {
            var count = 0
            for c in index_name {
                if let pos = QUAD_POSTIONS[String(c)] {
                    if bound[pos] {
                        count += 1
                    } else {
                        break
                    }
                }
            }
            indexCoverage[count] = index_name
            if count > bestCount {
                bestCount = count
            }
        }

        if let index_name = indexCoverage[bestCount] {
            return (index_name, bestCount)
        } else {
            return (available[0], 0)
        }
    }

    private func bestIndex(for pattern: QuadPattern) -> (String, Int) {
        let QUAD_POSTIONS = ["s": 0, "p": 1, "o": 2, "g": 3]
        let s = pattern.subject
        let p = pattern.predicate
        let o = pattern.object
        let g = pattern.graph
        let nodes = [s, p, o, g]

        var bestCount = 0
        let available = availableQuadIndexes
        var indexCoverage = [0: available[0]]
        for index_name in available {
            var count = 0
            for c in index_name {
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
            if count > bestCount {
                bestCount = count
            }
        }

        if let index_name = indexCoverage[bestCount] {
            return (index_name, bestCount)
        } else {
            return (available[0], 0)
        }
    }

    private func quadMapping(fromOrder index: String) throws -> (IDQuad<UInt64>) -> (IDQuad<UInt64>) {
        let QUAD_POSTIONS = ["s": 0, "p": 1, "o": 2, "g": 3]
        var mapping = [Int:Int]()
        for (i, c) in index.enumerated() {
            guard let index = QUAD_POSTIONS[String(c)] else { throw DatabaseError.DataError("Bad quad position character \(c) found while attempting to map a quad from index order") }
            mapping[index] = i
        }

        guard let si = mapping[0], let pi = mapping[1], let oi = mapping[2], let gi = mapping[3] else { fatalError("Failed to obtain quad pattern mapping for index \(index)") }
        return { (quad) in
            return IDQuad(quad[si], quad[pi], quad[oi], quad[gi])
        }
    }

    private func quadMapping(toOrder index: String) -> (IDQuad<UInt64>) -> (IDQuad<UInt64>) {
        let QUAD_POSTIONS = ["s": 0, "p": 1, "o": 2, "g": 3]
        var mapping = [Int:Int]()
        for (i, c) in index.enumerated() {
            guard let pos = QUAD_POSTIONS[String(c)] else { fatalError("Failed to obtain quad pattern mapping for index \(index)") }
            mapping[i] = pos
        }

        guard let si = mapping[0], let pi = mapping[1], let oi = mapping[2], let gi = mapping[3] else { fatalError("Failed to obtain quad pattern mapping for index \(index)") }
        return { (quad) in
            return IDQuad(quad[si], quad[pi], quad[oi], quad[gi])
        }
    }

    public func results(matching pattern: QuadPattern) throws -> AnyIterator<TermResult> {
        let idmap = self.id
        var variables   = [Int:String]()
        var verify      = [Int:IDType]()
        for (i, node) in [pattern.subject, pattern.predicate, pattern.object, pattern.graph].enumerated() {
            switch node {
            case .variable(let name, let bind):
                if bind {
                    variables[i] = name
                }
            case .bound(let term):
                guard let id = idmap.id(for: term) else {
                    return AnyIterator { return nil }
//                    throw DatabaseError.DataError("Failed to load term ID for \(term)")
                }
                verify[i] = id
            }
        }

        let idquads = try self.idquads(matching: pattern).makeIterator()
        return AnyIterator {
            OUTER: repeat {
                guard let idquad = idquads.next() else { return nil }
                let quadIDs = [idquad[0], idquad[1], idquad[2], idquad[3]]
                for (i, term) in verify {
                    guard term == quadIDs[i] else { continue OUTER }
                }

                var idbindings = [String:IDType]()
                var bindings = [String:Term]()
                for (i, id) in [idquad[0], idquad[1], idquad[2], idquad[3]].enumerated() {
                    if let name = variables[i] {
                        if let existing = idbindings[name] {
                            guard existing == id else { continue OUTER }
                        } else {
                            let term = idmap.term(for: id)
                            bindings[name] = term
                            idbindings[name] = id
                        }
                    }
                }
                return TermResult(bindings: bindings)
            } while true
        }
    }

    public func effectiveVersion(matching pattern: QuadPattern) throws -> Version? {
        let umin = UInt64.min
        let umax = UInt64.max
        let idmap = self.id

        let (index_name, count) = bestIndex(for: pattern)
        //        print("Index '\(index_name)' is best match with \(count) prefix terms")

        let nodes = [pattern.subject, pattern.predicate, pattern.object, pattern.graph]
        var patternIds = [UInt64]()
        for i in 0..<4 {
            let node = nodes[i]
            switch node {
            case .variable(_):
                patternIds.append(0)
            case .bound(let term):
                guard let id = idmap.id(for: term) else {
                    return nil
                    //                    throw DatabaseError.DataError("Failed to load term ID for \(term)")
                }
                patternIds.append(id)
            }
        }

        let toIndexOrder        = quadMapping(toOrder: index_name)
        let spogOrdered         = IDQuad(patternIds[0], patternIds[1], patternIds[2], patternIds[3])
        var indexOrderedMin     = toIndexOrder(spogOrdered)
        var indexOrderedMax     = toIndexOrder(spogOrdered)
        for i in count..<4 {
            indexOrderedMin[i]      = umin
            indexOrderedMax[i]      = umax
        }

        if let node: Tree<IDQuad<UInt64>, Empty> = mediator.tree(name: index_name) {
            let min = indexOrderedMin
            let max = indexOrderedMax
            return try node.effectiveVersion(between: (min, max))
        } else {
            throw DatabaseError.DataError("No index named '\(index_name) found")
        }
    }

    internal func idquads(matching pattern: QuadPattern) throws -> AnyIterator<IDQuad<IDType>> {
        let idmap = self.id
        let nodes = [pattern.subject, pattern.predicate, pattern.object, pattern.graph]
        var patternIds = [IDType]()
        for i in 0..<4 {
            let node = nodes[i]
            switch node {
            case .variable(_):
                patternIds.append(0)
            case .bound(let term):
                guard let id = idmap.id(for: term) else {
                    return AnyIterator { return nil }
//                    throw DatabaseError.DataError("Failed to load term ID for \(term)")
                }
                patternIds.append(id)
            }
        }
        return try idquads(matching: patternIds)
    }

    internal func idquads(matching patternIds: [IDType]) throws -> AnyIterator<IDQuad<IDType>> {
        let umin = IDType.min
        let umax = IDType.max
        let bound = patternIds.map { $0 != 0 }
        let (index_name, count) = bestIndex(for: bound)
        //        print("Index '\(index_name)' is best match with \(count) prefix terms")

        let fromIndexOrder      = try quadMapping(fromOrder: index_name)
        let toIndexOrder        = quadMapping(toOrder: index_name)
        let spogOrdered         = IDQuad(patternIds[0], patternIds[1], patternIds[2], patternIds[3])
        var indexOrderedMin     = toIndexOrder(spogOrdered)
        var indexOrderedMax     = toIndexOrder(spogOrdered)
        let indexOrderedPattern = toIndexOrder(spogOrdered)
        for i in count..<4 {
            indexOrderedMin[i]      = umin
            indexOrderedMax[i]      = umax
        }

        if let node: Tree<IDQuad<UInt64>, Empty> = mediator.tree(name: index_name) {
            let min = indexOrderedMin
            let max = indexOrderedMax
            let iter = try node.elements(between: (min, max))
            return AnyIterator {
                repeat {
                    guard let pair = iter.next() else { return nil }
                    let (indexOrder, _) = pair
                    if indexOrder.matches(indexOrderedPattern) {
                        return fromIndexOrder(indexOrder)
                    }
                } while true
            }
        } else {
            throw DatabaseError.DataError("No index named '\(index_name) found")
        }
    }

    public func quads(matching pattern: QuadPattern) throws -> AnyIterator<Quad> {
        let idmap = self.id
        let idquads = try self.idquads(matching: pattern)
        return AnyIterator {
            repeat {
                guard let quad = idquads.next() else { return nil }
                if let s = idmap.term(for: quad[0]), let p = idmap.term(for: quad[1]), let o = idmap.term(for: quad[2]), let g = idmap.term(for: quad[3]) {
                    return Quad(subject: s, predicate: p, object: o, graph: g)
                }
            } while true
        }
    }
}

public class PersistentTermIdentityMap: PackedIdentityMap, Sequence {
    public typealias Item = Term
    public typealias Result = UInt64

    var mediator: RMediator
    var next: (iri: UInt64, blank: UInt64, datatype: UInt64, language: UInt64)
    public static let t2iMapTreeName = "t2i_tree"
    public static let i2tMapTreeName = "i2t_tree"
    var i2tcache: LRUCache<Result, Term>
    var t2icache: LRUCache<Term, Result>

    public init (mediator: RMediator, readonly: Bool = false) throws {
        self.mediator = mediator
        var t2i: Tree<Item, Result>? = mediator.tree(name: PersistentTermIdentityMap.t2iMapTreeName)
        if t2i == nil {
            guard let m = mediator as? RWMediator else {
                throw DatabaseError.PermissionError("Cannot create new PersistentTermIdentityMap in a read-only transaction")
            }
            let t2ipairs = [(Item, Result)]()
            _ = try m.create(tree: PersistentTermIdentityMap.t2iMapTreeName, pairs: t2ipairs)
            t2i = mediator.tree(name: PersistentTermIdentityMap.t2iMapTreeName)
        }

        var i2t: Tree<Result, Item>? = mediator.tree(name: PersistentTermIdentityMap.i2tMapTreeName)
        if i2t == nil {
            guard let m = mediator as? RWMediator else {
                throw DatabaseError.PermissionError("Cannot create new PersistentTermIdentityMap in a read-only transaction")
            }
            let i2tpairs = [(Result, Item)]()
            _ = try m.create(tree: PersistentTermIdentityMap.i2tMapTreeName, pairs: i2tpairs)
            i2t = mediator.tree(name: PersistentTermIdentityMap.i2tMapTreeName)
        }

        if readonly {
            next.iri = 0
            next.blank = 0
            next.datatype = 0
            next.language = 0
        } else {
            if let i2t = i2t {
                next = PersistentTermIdentityMap.loadMaxIDs(from: i2t, mediator: mediator)
            } else {
                throw DatabaseError.PermissionError("Failed to get PersistentTermIdentityMap trees")
            }
        }

        self.i2tcache = LRUCache(capacity: 4096)
        self.t2icache = LRUCache(capacity: 4096)
    }

    private static func loadMaxIDs(from tree: Tree<Result, Item>, mediator: RMediator) -> (UInt64, UInt64, UInt64, UInt64) {
        let mask        = UInt64(0x00ffffffffffffff)
        let blankMax    = (tree.maxKey(in: PackedTermType.blank.idRange) ?? 0) & mask
        let iriMax      = (tree.maxKey(in: PackedTermType.iri.idRange) ?? 0) & mask
        let languageMax = (tree.maxKey(in: PackedTermType.language.idRange) ?? 0) & mask
        let datatypeMax = (tree.maxKey(in: PackedTermType.datatype.idRange) ?? 0) & mask
//        print("# Max term IDs: \(blankMax) \(iriMax) \(languageMax) \(datatypeMax)")
        return (iri: iriMax+1, blank: blankMax+1, datatype: datatypeMax+1, langauge: languageMax+1)
    }

    public func term(for id: Result) -> Term? {
        if let term = self.i2tcache[id] {
            return term
        } else if let term = self.unpack(id: id) {
            return term
        }
        if let node: Tree<Result, Item> = mediator.tree(name: PersistentTermIdentityMap.i2tMapTreeName) {
            let term = node.getAny(key: id)
            self.i2tcache[id] = term
            return term
        } else {
            warn("*** No node found for tree \(PersistentTermIdentityMap.i2tMapTreeName)")
        }
        return nil
    }

    public func id(for value: Item) -> Result? {
        if let id = self.t2icache[value] {
            return id
        } else if let id = self.pack(value: value) {
            return id
        }
        if let node: Tree<Item, Result> = mediator.tree(name: PersistentTermIdentityMap.t2iMapTreeName) {
            guard let id = node.getAny(key: value) else { return nil }
            self.t2icache[value] = id
            return id
        }
        return nil
    }

    public func makeIterator() -> AnyIterator<(Result, Item)> {
        if let node: Tree<Result, Item> = mediator.tree(name: PersistentTermIdentityMap.i2tMapTreeName) {
            return node.makeIterator()
        } else {
            return AnyIterator { return nil }
        }
    }

    public func getOrSetID(for term: Item) throws -> UInt64 {
        if let id = id(for: term) {
            return id
        } else {
            var value: UInt64
            var type: UInt64 = 0
            switch term.type {
            case .blank:
                type = PackedTermType.blank.typedEmptyValue
                value = next.blank
                next.blank += 1
            case .iri:
                type = PackedTermType.iri.typedEmptyValue
                value = next.iri
                next.iri += 1
            case .language(_):
                type = PackedTermType.language.typedEmptyValue
                value = next.language
                next.language += 1
            case .datatype(_):
                type = PackedTermType.datatype.typedEmptyValue
                value = next.datatype
                next.datatype += 1
            }

            guard value < UInt64(0x00ffffffffffffff) else { throw DatabaseError.DataError("Term ID overflows the 56 bits available") }
            let id = type + value

            guard let m = mediator as? RWMediator else { throw DatabaseError.PermissionError("Cannot create new term IDs in a read-only transaction") }
            guard let i2t: Tree<Result, Item> = m.tree(name: PersistentTermIdentityMap.i2tMapTreeName) else { throw DatabaseError.DataError("Failed to get the ID to term tree") }
            guard let t2i: Tree<Item, Result> = m.tree(name: PersistentTermIdentityMap.t2iMapTreeName) else { throw DatabaseError.DataError("Failed to get the term to ID tree") }

            try i2t.add(pair: (id, term))
            try t2i.add(pair: (term, id))

            return id
        }
    }
}

public protocol DefinedTestable {
    var isDefined: Bool { get }
}

extension UInt64: DefinedTestable {
    public var isDefined: Bool {
        return self != 0
    }
}

public struct IDQuad<T: DefinedTestable & Equatable & Comparable & BufferSerializable> : BufferSerializable, Equatable, Comparable, Sequence, Collection {
    public let startIndex = 0
    public let endIndex = 4
    public func index(after: Int) -> Int {
        return after+1
    }

    public var values: [T]
    public init(_ value0: T, _ value1: T, _ value2: T, _ value3: T) {
        self.values = [value0, value1, value2, value3]
    }

    public subscript(index: Int) -> T {
        get {
            return self.values[index]
        }

        set(newValue) {
            self.values[index] = newValue
        }
    }

    public func matches(_ rhs: IDQuad) -> Bool {
        for (l, r) in zip(values, rhs.values) {
            if l.isDefined && r.isDefined && l != r {
                return false
            }
        }
        return true
    }

    public var serializedSize: Int { return 4 * _sizeof(T.self) }
    public func serialize(to buffer: inout UnsafeMutableRawPointer, mediator: RWMediator?, maximumSize: Int) throws {
        if serializedSize > maximumSize { throw DatabaseError.OverflowError("Cannot serialize IDQuad in available space") }
        //        print("serializing quad \(subject) \(predicate) \(object) \(graph)")
        try self[0].serialize(to: &buffer)
        try self[1].serialize(to: &buffer)
        try self[2].serialize(to: &buffer)
        try self[3].serialize(to: &buffer)
    }

    public static func deserialize(from buffer: inout UnsafeRawPointer, mediator: RMediator?=nil) throws -> IDQuad {
        let v0      = try T.deserialize(from: &buffer, mediator: mediator)
        let v1      = try T.deserialize(from: &buffer, mediator: mediator)
        let v2      = try T.deserialize(from: &buffer, mediator: mediator)
        let v3      = try T.deserialize(from: &buffer, mediator: mediator)
        //        print("deserializing quad \(v0) \(v1) \(v2) \(v3)")
        let q = IDQuad(v0, v1, v2, v3)
        return q
    }

    public static func == <T>(lhs: IDQuad<T>, rhs: IDQuad<T>) -> Bool {
        if lhs[0] == rhs[0] && lhs[1] == rhs[1] && lhs[2] == rhs[2] && lhs[3] == rhs[3] {
            return true
        } else {
            return false
        }
    }

    public static func < <T>(lhs: IDQuad<T>, rhs: IDQuad<T>) -> Bool {
        for i in 0..<4 {
            let l = lhs.values[i]
            let r = rhs.values[i]
            if l < r {
                return true
            } else if l > r {
                return false
            }
        }
        return false
    }

    public func makeIterator() -> IndexingIterator<Array<T>> {
        return values.makeIterator()
    }
}

public protocol ResultProtocol: Hashable {
    associatedtype Element: Hashable
    var keys: [String] { get }
    func join(_ rhs: Self) -> Self?
    subscript(key: String) -> Element? { get }
    mutating func extend(variable: String, value: Element) throws
    func extended(variable: String, value: Element) -> Self?
    func projected(variables: [String]) -> Self
    var hashValue: Int { get }
}

extension ResultProtocol {
    public var hashValue: Int {
        let ints = keys.map { self[$0]?.hashValue ?? 0 }
        let hash = ints.reduce(0) { $0 ^ $1 }
        return hash
    }
}

public struct TermResult: CustomStringConvertible, ResultProtocol {
    public typealias Element = Term
    private var bindings: [String:Element]
    public var keys: [String] { return Array(bindings.keys) }

    public init(bindings: [String:Element]) {
        self.bindings = bindings
    }

    public func join(_ rhs: TermResult) -> TermResult? {
        let lvars = Set(bindings.keys)
        let rvars = Set(rhs.bindings.keys)
        let shared = lvars.intersection(rvars)
        for key in shared {
            guard bindings[key] == rhs.bindings[key] else { return nil }
        }
        var b = bindings
        for (k, v) in rhs.bindings {
            b[k] = v
        }

        let result = TermResult(bindings: b)
//        print("]]]] \(self) |><| \(rhs) ==> \(result)")
        return result
    }

    public func projected(variables: [String]) -> TermResult {
        var bindings = [String:Element]()
        for name in variables {
            if let term = self[name] {
                bindings[name] = term
            }
        }
        return TermResult(bindings: bindings)
    }

    public subscript(key: Node) -> Element? {
        get {
            switch key {
            case .variable(let name, _):
                return bindings[name]
            default:
                return nil
            }
        }

        set(value) {
            if case .variable(let name, _) = key {
                bindings[name] = value
            }
        }
    }

    public subscript(key: String) -> Element? {
        get {
            return bindings[key]
        }

        set(value) {
            bindings[key] = value
        }
    }

    public var description: String {
        return "Result\(bindings.description)"
    }

    public mutating func extend(variable: String, value: Element) throws {
        if let existing = self.bindings[variable] {
            if existing != value {
                throw QueryError.compatabilityError("Cannot extend solution mapping due to existing incompatible term value")
            }
        }
        self.bindings[variable] = value
    }

    public func extended(variable: String, value: Element) -> TermResult? {
        var b = bindings
        if let existing = b[variable] {
            if existing != value {
                return nil
            }
        }
        b[variable] = value
        return TermResult(bindings: b)
    }

    public static func == (lhs: TermResult, rhs: TermResult) -> Bool {
        let lkeys = Array(lhs.keys).sorted()
        let rkeys = Array(rhs.keys).sorted()
        guard lkeys == rkeys else { return false }
        for key in lkeys {
            let lvalue = lhs[key]
            let rvalue = rhs[key]
            guard lvalue == rvalue else { return false }
        }
        //    print("EQUAL-TO ==> \(lhs) === \(rhs)")
        return true
    }
}

public struct IDResult: CustomStringConvertible, ResultProtocol {
    public typealias Element = UInt64
    var bindings: [String:Element]
    public var keys: [String] { return Array(bindings.keys) }
    public func join(_ rhs: IDResult) -> IDResult? {
        let lvars = Set(bindings.keys)
        let rvars = Set(rhs.bindings.keys)
        let shared = lvars.intersection(rvars)
        for key in shared {
            guard bindings[key] == rhs.bindings[key] else { return nil }
        }
        var b = bindings
        for (k, v) in rhs.bindings {
            b[k] = v
        }
        return IDResult(bindings: b)
    }

    public func projected(variables: [String]) -> IDResult {
        var bindings = [String:Element]()
        for name in variables {
            if let term = self[name] {
                bindings[name] = term
            }
        }
        return IDResult(bindings: bindings)
    }

    public subscript(key: String) -> Element? {
        return bindings[key]
    }

    public var description: String {
        return "Result\(bindings.description)"
    }

    public mutating func extend(variable: String, value: Element) throws {
        if let existing = self.bindings[variable] {
            if existing != value {
                throw QueryError.compatabilityError("Cannot extend solution mapping due to existing incompatible term value")
            }
        }
        self.bindings[variable] = value
    }

    public func extended(variable: String, value: Element) -> IDResult? {
        var b = bindings
        if let existing = b[variable] {
            if existing != value {
                return nil
            }
        }
        b[variable] = value
        return IDResult(bindings: b)
    }

    public static func == (lhs: IDResult, rhs: IDResult) -> Bool {
        let lkeys = Array(lhs.keys).sorted()
        let rkeys = Array(rhs.keys).sorted()
        guard lkeys == rkeys else { return false }
        for key in lkeys {
            let lvalue = lhs[key]
            let rvalue = rhs[key]
            guard lvalue == rvalue else { return false }
        }
        return true
    }
}

open class LanguageQuadStore: QuadStore {
    var acceptLanguages: [(String, Double)]
    public init(mediator: RMediator, acceptLanguages: [(String, Double)], mutable: Bool = false) throws {
        self.acceptLanguages = acceptLanguages
        try super.init(mediator: mediator, mutable: mutable)
    }

    override internal func idquads(matching pattern: QuadPattern) throws -> AnyIterator<IDQuad<IDType>> {
        let i = try super.idquads(matching: pattern)
        return AnyIterator {
            repeat {
                guard let idquad = i.next() else { return nil }
                let oid = idquad[3]
                let languageQuad = PersistentTermIdentityMap.isLanguageLiteral(id: oid)
                if languageQuad {
                    return idquad
                } else {
                    guard let quad = self.quad(from: idquad) else { return nil }
                    if self.accept(quad: quad, languages: self.acceptLanguages) {
                        return idquad
                    }
                }
            } while true
        }
    }

    /**
    override public func quads(matching pattern: QuadPattern) throws -> AnyIterator<Quad> {
        let i = try super.quads(matching: pattern)
        return AnyIterator {
            repeat {
                guard let quad = i.next() else { return nil }
                if self.accept(quad: quad, languages: self.acceptLanguages) {
                    return quad
                }
            } while true
        }
    }
    **/

    internal func qValue(_ language: String, qualityValues: [(String, Double)]) -> Double {
        for (lang, value) in qualityValues {
            if language.hasPrefix(lang) {
                return value
            }
        }
        return 0.0
    }

    func siteLanguageQuality(language: String) -> Double {
        // Site-defined quality for specific languages.
        return 1.0
    }

    private func accept(quad: Quad, languages: [(String, Double)]) -> Bool {
        let object = quad.object
        switch object.type {
        case .language(let l):
            let pattern = QuadPattern(subject: .bound(quad.subject), predicate: .bound(quad.predicate), object: .variable(".o", binding: true), graph: .bound(quad.graph))
            guard let quads = try? super.idquads(matching: pattern) else { return false }
            let langs = quads.compactMap { (idquad) -> String? in
                guard let object = self.id.term(for: idquad[2]) else { return nil }
                if case .language(let lang) = object.type {
                    return lang
                }
                return nil
            }
            let pairs = langs.map { (lang) -> (String, Double) in
                let value = self.qValue(lang, qualityValues: languages) * siteLanguageQuality(language: lang)
                return (lang, value)
            }

            guard var (_, maxvalue) = pairs.first else { return true }
            for (_, value) in pairs {
                if value > maxvalue {
                    maxvalue = value
                }
            }

            let acceptable = Set(pairs.filter { $0.1 == maxvalue }.map { $0.0 })
            return acceptable.contains(l)
        default:
            return true
        }
    }

}
