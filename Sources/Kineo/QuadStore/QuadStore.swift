//
//  QuadStore.swift
//  PageDatabase
//
//  Created by Gregory Todd Williams on 6/12/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import SPARQLSyntax

public enum QuadStoreFeature : String {
    case emptyGraphs = "http://www.w3.org/ns/sparql-service-description#EmptyGraphs"
}

public struct GraphDescription {
    public struct Histogram {
        public struct Bucket {
            public var term: Term
            public var count: Int
        }
        public var isComplete: Bool
        public var position: RDFTriplePosition
        public var buckets: [Bucket]
    }
    public var triplesCount: Int
    public var isComplete: Bool
    public var predicates: Set<Term>
    public var histograms: [Histogram]
}

public protocol QuadStoreProtocol {
    var count: Int { get }
    func graphs() -> AnyIterator<Term>
    func graphTerms(in: Term) -> AnyIterator<Term>
    func makeIterator() -> AnyIterator<Quad>
    func results(matching pattern: QuadPattern) throws -> AnyIterator<SPARQLResult<Term>>
    func quads(matching pattern: QuadPattern) throws -> AnyIterator<Quad>
    func countQuads(matching pattern: QuadPattern) throws -> Int
    func effectiveVersion(matching pattern: QuadPattern) throws -> Version?
    var graphDescriptions: [Term:GraphDescription] { get }
    var features: [QuadStoreFeature] { get }
}

public protocol LanguageAwareQuadStore: QuadStoreProtocol {
    var acceptLanguages: [(String, Double)] { get set }
}

public protocol BGPQuadStoreProtocol: QuadStoreProtocol {
    func results(matching bgp: [TriplePattern], in graph: Term) throws -> AnyIterator<SPARQLResult<Term>>
}

public enum MutableQuadStoreProtocolError: Error {
    case missingMapping(UInt64)
    case loadingError(String)
}

public protocol MutableQuadStoreProtocol: QuadStoreProtocol {
    func load<S: Sequence, T: Sequence>(version: Version, dictionary: S, quads: T) throws where S.Element == (UInt64, Term), T.Element == (UInt64, UInt64, UInt64, UInt64)
    func load<S: Sequence>(version: Version, quads: S) throws where S.Iterator.Element == Quad
}

extension MutableQuadStoreProtocol {
    public func load<S: Sequence, T: Sequence>(version: Version, dictionary: S, quads: T) throws where S.Element == (UInt64, Term), T.Element == (UInt64, UInt64, UInt64, UInt64) {
//        print("default MutableQuadStoreProtocol.load(version:dictionary:quads:) called")
        let d = Dictionary(uniqueKeysWithValues: dictionary)
        let materialized = try quads.map { (s,p,o,g) throws -> Quad in
            guard let st = d[s] else {
                throw MutableQuadStoreProtocolError.missingMapping(s)
            }
            guard let pt = d[p] else {
                throw MutableQuadStoreProtocolError.missingMapping(p)
            }
            guard let ot = d[o] else {
                throw MutableQuadStoreProtocolError.missingMapping(o)
            }
            guard let gt = d[g] else {
                throw MutableQuadStoreProtocolError.missingMapping(g)
            }
            return Quad(subject: st, predicate: pt, object: ot, graph: gt)
        }
        try load(version: version, quads: materialized)
    }
    
    public func load(version: Version, files: [String], graph defaultGraphTerm: Term? = nil) throws {
        for filename in files {
            #if os (OSX)
            guard let path = NSURL(fileURLWithPath: filename).absoluteString else {
                throw MutableQuadStoreProtocolError.loadingError("Not a valid graph path: \(filename)")
            }
            #else
            let path = NSURL(fileURLWithPath: filename).absoluteString
            #endif
            let graph   = defaultGraphTerm ?? Term(value: path, type: .iri)
            
            let syntax = RDFParserCombined.guessSyntax(filename: filename)
            let parser = RDFParserCombined()
            var quads = [Quad]()
            //                    print("Parsing RDF...")
            _ = try parser.parse(file: filename, syntax: syntax, defaultGraph: graph, base: graph.value) { (s, p, o, g) in
                let q = Quad(subject: s, predicate: p, object: o, graph: g)
                quads.append(q)
            }
            
            //                    print("Loading RDF...")
            try load(version: version, quads: quads)
        }
    }

}

extension Term {
    func appending(_ string: String) -> Term {
        return Term(value: "\(value)\(string)", type: type)
    }
}

extension QuadStoreProtocol {
    public func dataset(withDefault defaultGraph: Term) -> Dataset {
        var named = Set(self.graphs())
        named.remove(defaultGraph)
        let dataset = Dataset(defaultGraphs: [defaultGraph], namedGraphs: Array(named))
        return dataset
    }
    
    public func dataset() -> Dataset {
        let named = self.graphs()
        let dataset = Dataset(defaultGraphs: [], namedGraphs: Array(named))
        return dataset
    }
    
    public func effectiveVersion() throws -> Version? {
        let pattern = QuadPattern(
            subject: .variable("s", binding: true),
            predicate: .variable("p", binding: true),
            object: .variable("o", binding: true),
            graph: .variable("g", binding: true)
        )
        return try effectiveVersion(matching: pattern)
    }

    public var features: [QuadStoreFeature] {
        return []
    }
}

extension QuadStoreProtocol {
    private func _generate_service_description(graph: Term) throws -> (Int, [Term: Int], [Term: Int]) {
        var preds = [Term: Int]()
        var classes = [Term: Int]()
        var qp = QuadPattern.all
        qp.graph = .bound(graph)
        var count = 0
        for q in try quads(matching: qp) {
            count += 1
            let p = q.predicate
            preds[p, default: 0] += 1
            
            if p == Term(iri: Namespace.rdf.type) {
                let c = q.object
                classes[c, default: 0] += 1
            }
        }
        
        return (count, preds, classes)
    }
    
    public func graphDescription(_ graph: Term, limit topK: Int) throws -> GraphDescription {
        let (count, preds, _) = try _generate_service_description(graph: graph)
        let topPreds = preds.sorted(by: { $0.value < $1.value }).prefix(topK)
        let predsSet = Set(topPreds.map { $0.key })
        let predBuckets = topPreds.map {
            GraphDescription.Histogram.Bucket(term: $0.key, count: $0.value)
        }
        
        let predHistogram = GraphDescription.Histogram(
            isComplete: false,
            position: .predicate,
            buckets: predBuckets
        )
        
        return GraphDescription(
            triplesCount: count,
            isComplete: false,
            predicates: predsSet,
            histograms: [predHistogram]
        )
    }
    
    public var graphDescriptions: [Term:GraphDescription] {
        var descriptions = [Term:GraphDescription]()
        for g in graphs() {
            do {
                let topK = Int.max
                descriptions[g] = try graphDescription(g, limit: topK)
            } catch {}
        }
        return descriptions
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

public enum PushQueryResult {
    case boolean(Bool)
    case triple(Triple)
    case binding([String], SPARQLResult<Term>)
}


public enum QueryResult<S, T> where S: Sequence, S.Element == SPARQLResult<Term>, T: Sequence, T.Element == Triple {
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
            s += "Bindings \(proj) |\(Array(seq).count)| {\n"
            for r in seq {
                s += "    \(r)\n"
            }
            s += "}\n"
        case .triples(let seq):
            s += "Triples |\(Array(seq).count)| {\n"
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
    
    private static func splitBindingsWithBlanks(_ bindings: S) -> ([SPARQLResult<Term>], [SPARQLResult<Term>], [String]) {
        var withBlanks = [SPARQLResult<Term>]()
        var withoutBlanks = [SPARQLResult<Term>]()
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
                let lbMapped = lb.map { (triple) -> Triple in
                    do {
                        return try triple.replace { (t) -> Term? in
                            guard t.type == .blank else { return t }
                            let name = t.value
                            let ident = map[name] ?? name
                            return Term(value: ident, type: .blank)
                        }
                    } catch {
                        return triple
                    }
                }
                if Set(lbMapped) == Set(rb) {
                    return true
                }
            }
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
                let map = Dictionary(uniqueKeysWithValues: permutation.enumerated().map { (i, j) in
                    (lblanks[i], rblanks[j])
                })
                
                let lbMapped = lb.map { (r) -> SPARQLResult<Term> in
                    let bindings = r.bindings.mapValues { (t) -> Term in
                        guard t.type == .blank else { return t }
                        let name = t.value
                        let ident = map[name] ?? name
                        return Term(value: ident, type: .blank)
                    }
                    return SPARQLResult<Term>(bindings: bindings)
                }
                if Set(lbMapped) == Set(rb) {
                    return true
                }
            }
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

public struct SPARQLResult<T: Hashable>: ResultProtocol, Hashable, CustomStringConvertible {
    public typealias TermType = T
    var bindings: [String: T]
    
    public init(bindings: [String: T]) {
        self.bindings = bindings
    }
    
    public var keys: [String] { return Array(self.bindings.keys) }
    
    public func join(_ rhs: SPARQLResult<T>) -> SPARQLResult<T>? {
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
        
        let result = SPARQLResult(bindings: b)
        //        print("]]]] \(self) |><| \(rhs) ==> \(result)")
        return result
    }
    
    public func projected(variables: Set<String>) -> SPARQLResult<T> {
        var bindings = [String:TermType]()
        for name in variables {
            if let term = self[name] {
                bindings[name] = term
            }
        }
        return SPARQLResult(bindings: bindings)
    }

    public subscript(key: Node) -> TermType? {
        get {
            switch key {
            case .variable(let name, _):
                return self.bindings[name]
            default:
                return nil
            }
        }

        set(value) {
            if case .variable(let name, _) = key {
                self.bindings[name] = value
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

    public mutating func extend(variable: String, value: TermType) throws {
        if let existing = self.bindings[variable] {
            if existing != value {
                throw QueryError.compatabilityError("Cannot extend solution mapping due to existing incompatible term value")
            }
        }
        self.bindings[variable] = value
    }

    public func extended(variable: String, value: TermType) -> SPARQLResult<T>? {
        var b = bindings
        if let existing = b[variable] {
            if existing != value {
                print("*** cannot extend result with new term: (\(variable) <- \(value); \(self)")
                return nil
            }
        }
        b[variable] = value
        return SPARQLResult(bindings: b)
    }

    public var description: String {
        let pairs = bindings.sorted { $0.0 < $1.0 }.map { "\($0): \($1)" }.joined(separator: ", ")
        return "Result[\(pairs)]"
    }

    public func makeIterator() -> DictionaryIterator<String, TermType> {
        let i = bindings.makeIterator()
        return i
    }

    public func removing(variables: Set<String>) -> SPARQLResult<T> {
        var bindings = [String: T]()
        for (k, v) in self.bindings {
            if !variables.contains(k) {
                bindings[k] = v
            }
        }
        return SPARQLResult(bindings: bindings)
    }
}

extension ResultProtocol {
    public func hash(into hasher: inout Hasher) {
        for k in keys.sorted() {
            hasher.combine(self[k])
        }
    }
}
