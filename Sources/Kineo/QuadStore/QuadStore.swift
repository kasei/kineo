//
//  QuadStore.swift
//  PageDatabase
//
//  Created by Gregory Todd Williams on 6/12/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import SPARQLSyntax

public protocol QuadStoreProtocol: Sequence {
    var count: Int { get }
    func graphs() -> AnyIterator<Term>
    func graphNodeTerms() -> AnyIterator<Term>
    func makeIterator() -> AnyIterator<Quad>
    func results(matching pattern: QuadPattern) throws -> AnyIterator<TermResult>
    func quads(matching pattern: QuadPattern) throws -> AnyIterator<Quad>
    func effectiveVersion(matching pattern: QuadPattern) throws -> Version?
}

public protocol MutableQuadStoreProtocol: QuadStoreProtocol {
    func load<S: Sequence>(version: Version, quads: S) throws where S.Iterator.Element == Quad
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
    public func serialize(to buffer: inout UnsafeMutableRawPointer, mediator: PageRWMediator?, maximumSize: Int) throws {
        if serializedSize > maximumSize { throw DatabaseError.OverflowError("Cannot serialize IDQuad in available space") }
        //        print("serializing quad \(subject) \(predicate) \(object) \(graph)")
        try self[0].serialize(to: &buffer)
        try self[1].serialize(to: &buffer)
        try self[2].serialize(to: &buffer)
        try self[3].serialize(to: &buffer)
    }

    public static func deserialize(from buffer: inout UnsafeRawPointer, mediator: PageRMediator?=nil) throws -> IDQuad {
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

public enum QueryResult<S, T> where S: Sequence, S.Element == TermResult, T: Sequence, T.Element == Triple {
    case boolean(Bool)
    case triples(T)
    case bindings([String], S)
}

extension QueryResult: CustomStringConvertible {
    public var description: String {
        var s = ""
        switch self {
        case .boolean(let v):
            s += "\(v)"
        case let .bindings(proj, seq):
            s += "Bindings \(proj) {\n"
            for r in seq {
                s += "    \(r)\n"
            }
            s += "}\n"
        case .triples(let seq):
            s += "Triples {\n"
            for t in seq {
                s += "    \(t)\n"
            }
            s += "}\n"
        }
        
        return s
    }
}
extension QueryResult: Equatable {
    private static func splitTriplesWithBlanks(_ triples: T) -> ([Triple], [Triple], [String]) {
        var withBlanks = [Triple]()
        var withoutBlanks = [Triple]()
        var blanks = Set<String>()
        for t in triples {
            var hasBlanks = false
            for term in t {
                if term.type == .blank {
                    hasBlanks = true
                    blanks.insert(term.value)
                }
            }
            
            
            if hasBlanks {
                withBlanks.append(t)
            } else {
                withoutBlanks.append(t)
            }
        }
        return (withBlanks, withoutBlanks, Array(blanks))
    }
    
    private static func splitBindingsWithBlanks(_ bindings: S) -> ([TermResult], [TermResult], [String]) {
        var withBlanks = [TermResult]()
        var withoutBlanks = [TermResult]()
        var blanks = Set<String>()
        for r in bindings {
            var hasBlanks = false
            for v in r.keys {
                guard let term = r[v] else { continue }
                if term.type == .blank {
                    hasBlanks = true
                    blanks.insert(term.value)
                }
            }
            
            
            if hasBlanks {
                withBlanks.append(r)
            } else {
                withoutBlanks.append(r)
            }
        }
        return (withBlanks, withoutBlanks, Array(blanks))
    }
    
    private static func permute<T>(_ a: [T], _ n: Int) -> [[T]] {
        if n == 0 {
            return [a]
        } else {
            var a = a
            var results = permute(a, n - 1)
            for i in 0..<n {
                a.swapAt(i, n)
                results += permute(a, n - 1)
                a.swapAt(i, n)
            }
            return results
        }
    }
    
    private static func triplesAreIsomorphic(_ lhs: T, _ rhs: T) -> Bool {
        let (lb, lnb, lblanks) = splitTriplesWithBlanks(lhs)
        let (rb, rnb, rblanks) = splitTriplesWithBlanks(rhs)
        
        guard lb.count == rb.count else {
            return false
        }
        guard lnb.count == rnb.count else {
            return false
        }
        guard lblanks.count == rblanks.count else {
            return false
        }
        
        let lset = Set(lnb)
        let rset = Set(rnb)
        guard lset == rset else {
            return false
        }
        
        if lb.count > 1 {
            let indexes = Array(0..<lb.count)
            for permutation in permute(indexes, indexes.count-1) {
                let map = Dictionary(uniqueKeysWithValues: permutation.enumerated().map { (i, j) in
                    (lblanks[i], rblanks[j])
                })
                print("blank node map: \(map)")
            }
            print("*** TRIPLE ISOMORPHISM NOT FULLY IMPLEMENTED") // TODO
            return false
        }
        return true
    }
    
    private static func bindingsAreIsomorphic(_ lhs: S, _ rhs: S) -> Bool {
        let (lb, lnb, lblanks) = splitBindingsWithBlanks(lhs)
        let (rb, rnb, rblanks) = splitBindingsWithBlanks(rhs)
        
        guard lb.count == rb.count else {
            print("bindings are not isomorphic: bindings with blanks counts don't match")
            return false
        }
        guard lnb.count == rnb.count else {
            print("bindings are not isomorphic: bindings without blanks counts don't match")
            return false
        }
        guard lblanks.count == rblanks.count else {
            print("bindings are not isomorphic: blank identifier counts don't match")
            return false
        }
        
        let lset = Set(lnb)
        let rset = Set(rnb)
        //        print("lhs-non-blank bindings: \(lnb)")
        //        print("rhs-non-blank bindings: \(rnb)")
        guard lset == rset else {
            print("bindings are not isomorphic: set of non-blank bindings don't match")
            return false
        }
        
        if lb.count > 1 {
            let indexes = Array(0..<lblanks.count)
            for permutation in permute(indexes, indexes.count-1) {
                print("--> \(permutation)")
                let map = Dictionary(uniqueKeysWithValues: permutation.enumerated().map { (i, j) in
                    (lblanks[i], rblanks[j])
                })
                print("blank node map: \(map)")
            }
            print("*** BINDING ISOMORPHISM NOT FULLY IMPLEMENTED") // TODO
            return false
        }
        return true
    }
    
    public static func == (lhs: QueryResult, rhs: QueryResult) -> Bool {
//        print("*** Comparing QueryResults: \(lhs) <=> \(rhs)")
        switch (lhs, rhs) {
        case let (.boolean(l), .boolean(r)):
            return l == r
        case let (.triples(l), .triples(r)):
            return QueryResult.triplesAreIsomorphic(l, r)
        case let (.bindings(lproj, lseq), .bindings(rproj, rseq)) where Set(lproj) == Set(rproj):
//            print("*** comparing binding query results")
            return QueryResult.bindingsAreIsomorphic(lseq, rseq)
        default:
            return false
        }
    }
}
public protocol ResultProtocol: Hashable, Sequence {
    associatedtype TermType: Hashable
    init(bindings: [String:TermType])
    var keys: [String] { get }
    func join(_ rhs: Self) -> Self?
    subscript(key: String) -> TermType? { get }
    mutating func extend(variable: String, value: TermType) throws
    func extended(variable: String, value: TermType) -> Self?
    func projected(variables: Set<String>) -> Self
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
    public typealias TermType = Term
    private var bindings: [String:TermType]
    public var keys: [String] { return Array(bindings.keys) }

    public init(bindings: [String:TermType]) {
        self.bindings = bindings
    }

    public func makeIterator() -> DictionaryIterator<String, TermType> {
        let i = bindings.makeIterator()
        return i
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

    public func projected(variables: Set<String>) -> TermResult {
        var bindings = [String:TermType]()
        for name in variables {
            if let term = self[name] {
                bindings[name] = term
            }
        }
        return TermResult(bindings: bindings)
    }
    
    public func removing(variables: Set<String>) -> TermResult {
        var bindings = [String:TermType]()
        for (k, v) in self.bindings {
            if !variables.contains(k) {
                bindings[k] = v
            }
        }
        return TermResult(bindings: bindings)
    }
    
    public subscript(key: Node) -> TermType? {
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

    public subscript(key: String) -> TermType? {
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

    public mutating func extend(variable: String, value: TermType) throws {
        if let existing = self.bindings[variable] {
            if existing != value {
                throw QueryError.compatabilityError("Cannot extend solution mapping due to existing incompatible term value")
            }
        }
        self.bindings[variable] = value
    }

    public func extended(variable: String, value: TermType) -> TermResult? {
        var b = bindings
        if let existing = b[variable] {
            if existing != value {
                print("*** cannot extend result with new term: (\(variable) <- \(value); \(self)")
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
    public typealias TermType = UInt64
    var bindings: [String:TermType]
    public var keys: [String] { return Array(bindings.keys) }
    public init(bindings: [String:TermType]) {
        self.bindings = bindings
    }
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

    public func makeIterator() -> DictionaryIterator<String, TermType> {
        let i = bindings.makeIterator()
        return i
    }

    public func projected(variables: Set<String>) -> IDResult {
        var bindings = [String:TermType]()
        for name in variables {
            if let term = self[name] {
                bindings[name] = term
            }
        }
        return IDResult(bindings: bindings)
    }

    public subscript(key: String) -> TermType? {
        return bindings[key]
    }

    public var description: String {
        return "Result\(bindings.description)"
    }

    public mutating func extend(variable: String, value: TermType) throws {
        if let existing = self.bindings[variable] {
            if existing != value {
                throw QueryError.compatabilityError("Cannot extend solution mapping due to existing incompatible term value")
            }
        }
        self.bindings[variable] = value
    }

    public func extended(variable: String, value: TermType) -> IDResult? {
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
