//
//  QuadStore.swift
//  PageDatabase
//
//  Created by Gregory Todd Williams on 6/12/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import SPARQLSyntax

public enum DatabaseError: Error {
    case DataError(String)
    case PermissionError(String)
}

public enum NetworkError: Error {
    case noData(String)
}

public typealias Version = UInt64
public typealias IDType = UInt64

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
        public var position: Triple.Position
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
    func results(matching pattern: QuadPattern) throws -> AnyIterator<SPARQLResultSolution<Term>>
    func quads(matching pattern: QuadPattern) throws -> AnyIterator<Quad>
    func countQuads(matching pattern: QuadPattern) throws -> Int
    func effectiveVersion(matching pattern: QuadPattern) throws -> Version?
    var graphDescriptions: [Term:GraphDescription] { get }
    var features: [QuadStoreFeature] { get }
}

public protocol PrefixNameSotringQuadStore: QuadStoreProtocol {
    var prefixes: [String: Term] { get }
}

public protocol LazyMaterializingQuadStore: QuadStoreProtocol {
//    func resultOrder(matching pattern: QuadPattern) throws -> [Quad.Position]
    func quadIds(matching pattern: QuadPattern) throws -> [[IDType]]
    func quadsIterator(fromIds ids: [[IDType]]) -> AnyIterator<Quad>
    func term(from: IDType) throws -> Term?
    func id(for: Term) throws -> IDType?
    
    // in the returned tuples,
    //  order: is the positions in the quad that results will come back ordered by
    //  fullOrder: is the full set of quad positions of the underlying index,
    //             of which some prefix will be covered by bound terms in the quad pattern
    //             (and is used in quadIds(matching:orderedBt:) to pull data from the specific index
    func availableOrders(matching pattern: QuadPattern) throws -> [(order: [Quad.Position], fullOrder: [Quad.Position])]
    func quadIds(matching pattern: QuadPattern, orderedBy: [Quad.Position]) throws -> [[IDType]]
    func quadIds(matchingIDs pattern: [UInt64]) throws -> AnyIterator<[UInt64]>
    func graphTermIDs(in graph: UInt64) -> AnyIterator<UInt64>
}

extension LazyMaterializingQuadStore {
    public func idresults(matching pattern: QuadPattern) throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        var bindings : [String: Int] = [:]
        for (node, index) in zip(pattern, 0..<4) {
            if case .variable(let name, binding: true) = node {
                bindings[name] = index
            }
        }
        let quads = try self.quadIds(matching: pattern)
        let results = quads.lazy.map { (q) -> SPARQLResultSolution<UInt64> in
            var b = [String: UInt64]()
            for (name, idx) in bindings {
                b[name] = q[idx]
            }
            return SPARQLResultSolution(bindings: b)
        }
        return AnyIterator(results.makeIterator())
    }

    public func idresults(matching pattern: QuadPattern, orderedBy order: [Quad.Position]) throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        var bindings : [String: Int] = [:]
        for (node, index) in zip(pattern, 0..<4) {
            if case .variable(let name, binding: true) = node {
                bindings[name] = index
            }
        }
        let quads = try self.quadIds(matching: pattern, orderedBy: order)
        let results = quads.lazy.map { (q) -> SPARQLResultSolution<UInt64> in
            var b = [String: UInt64]()
            for (name, idx) in bindings {
                b[name] = q[idx]
            }
            return SPARQLResultSolution(bindings: b)
        }
        return AnyIterator(results.makeIterator())
    }
}

public protocol LanguageAwareQuadStore: QuadStoreProtocol {
    var acceptLanguages: [(String, Double)] { get set }
}

public protocol BGPQuadStoreProtocol: QuadStoreProtocol {
    func results(matching bgp: [TriplePattern], in graph: Term) throws -> AnyIterator<SPARQLResultSolution<Term>>
}

public enum MutableQuadStoreProtocolError: Error {
    case missingMapping(UInt64)
    case loadingError(String)
}

public protocol MutableQuadStoreProtocol: QuadStoreProtocol {
    func load<S: Sequence, T: Sequence>(version: Version, dictionary: S, quads: T) throws where S.Element == (UInt64, Term), T.Element == (UInt64, UInt64, UInt64, UInt64)
    func load<S: Sequence>(version: Version, quads: S) throws where S.Iterator.Element == Quad
}

extension URLSession {
    func synchronousDataTaskWithURL(url: URL) throws -> (Data, URLResponse?) {
        var data: Data?, response: URLResponse?, error: Error?

        let semaphore = DispatchSemaphore.init(value: 0)
        
        dataTask(with: url) {
            data = $0; response = $1; error = $2
            semaphore.signal()
        }.resume()

        semaphore.wait()
        if let e = error {
            throw e
        }
        
        if let d = data {
            return (d, response)
        } else {
            throw NetworkError.noData("No data loaded from URL \(url)")
        }
    }
}

extension MutableQuadStoreProtocol {
    public func load<S: Sequence>(quads: S) throws where S.Element == Quad {
        try self.load(version: 0, quads: quads)
    }
    
    @discardableResult
    public func load(url: URL, defaultGraph: Term, version: Version = 0) throws -> Int {
        let parser = RDFParserCombined()
        var quads = [Quad]()
        let session = URLSession.shared
        let (data, resp) = try session.synchronousDataTaskWithURL(url: url)
        var mt: String? = nil
        if let httpResponse = resp as? HTTPURLResponse {
            mt = httpResponse.value(forHTTPHeaderField: "Content-Type")
        }
        
        if mt == nil {
            // this should probably use RDFSerializationConfiguration instead of hard-coding a specific list of media types
            let ext = url.pathExtension
            switch ext {
            case "nt":
                mt = "application/n-triples"
            case "nq":
                mt = "application/n-triples"
            case "ttl":
                mt = "text/turtle"
            default:
                break
            }
        }
        
        let mediaType = mt ?? "text/plain"
        
        let count = try parser.parse(data: data, mediaType: mediaType, defaultGraph: graph, base: url.absoluteString) { (s, p, o, g) in
            let q = Quad(subject: s, predicate: p, object: o, graph: g)
            quads.append(q)
        }
        
        try self.load(version: version, quads: quads)
        return count
    }
    
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
    
    public func load(version: Version, files: [String], graph defaultGraphTerm: Term? = nil, canonicalize: Bool = true) throws {
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

public enum PushQueryResult {
    case boolean(Bool)
    case triple(Triple)
    case binding([String], SPARQLResultSolution<Term>)
}


public enum QueryResult<S, T> where S: Sequence, S.Element == SPARQLResultSolution<Term>, T: Sequence, T.Element == Triple {
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
    
    private static func splitBindingsWithBlanks(_ bindings: S) -> ([SPARQLResultSolution<Term>], [SPARQLResultSolution<Term>], [String]) {
        var withBlanks = [SPARQLResultSolution<Term>]()
        var withoutBlanks = [SPARQLResultSolution<Term>]()
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
                
                let lbMapped = lb.map { (r) -> SPARQLResultSolution<Term> in
                    let bindings = r.bindings.mapValues { (t) -> Term in
                        guard t.type == .blank else { return t }
                        let name = t.value
                        let ident = map[name] ?? name
                        return Term(value: ident, type: .blank)
                    }
                    return SPARQLResultSolution<Term>(bindings: bindings)
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
    func removing(variables: Set<String>) -> Self
}

extension SPARQLResultSolution: ResultProtocol, Comparable {
    public static func < (lhs: SPARQLResultSolution<T>, rhs: SPARQLResultSolution<T>) -> Bool {
        let keys = Set(lhs.keys + rhs.keys).sorted()
        for key in keys {
            if let l = lhs[key], let r = rhs[key] {
                if l == r {
                    continue
                }
                return l < r
            } else if let _ = lhs[key] {
                return false
            } else {
                return true
            }
        }
        return false
    }
}
