//
//  SPARQLClientQuadStore.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 6/6/18.
//

import Foundation
import SPARQLSyntax

// swiftlint:disable:next type_body_length
open class SPARQLClientQuadStore: Sequence, QuadStoreProtocol {
    var client: SPARQLClient
    var defaultGraph: Term
    
    public init(endpoint: URL, defaultGraph: Term) {
        self.client = SPARQLClient(endpoint: endpoint)
        self.defaultGraph = defaultGraph
    }
    
    public var count: Int {
        if let r = try? client.execute("SELECT (COUNT(*) AS ?count) WHERE { { GRAPH ?g { ?s ?p ?o} } UNION { ?s ?p ?o } }") {
            if case .bindings(_, let rows) = r {
                return rows.count
            }
        }
        return 0
    }
    
    public func graphs() -> AnyIterator<Term> {
        if let r = try? client.execute("SELECT ?g WHERE { GRAPH ?g {} }") {
            if case .bindings(_, let rows) = r {
                let graphs = rows.compactMap { $0["g"] }
                return AnyIterator(graphs.makeIterator())
            }
        }
        return AnyIterator([].makeIterator())
    }
    
    public func graphTerms(in graph: Term) -> AnyIterator<Term> {
        if let r = try? client.execute("SELECT DISTINCT ?t WHERE { GRAPH \(graph) { { ?t ?p ?o } UNION { ?s ?p ?t } }") {
            if case .bindings(_, let rows) = r {
                let graphs = rows.compactMap { $0["t"] }
                return AnyIterator(graphs.makeIterator())
            }
        }
        return AnyIterator([].makeIterator())
    }
    
    public func makeIterator() -> AnyIterator<Quad> {
        if let r = try? client.execute("SELECT * WHERE { { GRAPH ?g { ?s ?p ?o } } UNION { ?s ?p ?o } }") {
            if case .bindings(_, let rows) = r {
                let quads = rows.compactMap { (row) -> Quad? in
                    if let s = row["s"], let p = row["p"], let o = row["o"] {
                        if let g = row["g"] {
                            return Quad(subject: s, predicate: p, object: o, graph: g)
                        } else {
                            return Quad(subject: s, predicate: p, object: o, graph: defaultGraph)
                        }
                    }
                    return nil
                }
                return AnyIterator(quads.makeIterator())
            }
        }
        return AnyIterator([].makeIterator())
    }
    
    public func results(matching pattern: QuadPattern) throws -> AnyIterator<TermResult> {
        let query : String
        if pattern.graph == .bound(defaultGraph) {
            query = "SELECT * WHERE { \(pattern.subject) \(pattern.predicate) \(pattern.object) }"
        } else {
            query = "SELECT * WHERE { GRAPH \(pattern.graph) { \(pattern.subject) \(pattern.predicate) \(pattern.object) } }"
        }
        if let r = try? client.execute(query) {
            if case .bindings(_, let rows) = r {
                return AnyIterator(rows.makeIterator())
            }
        }
        return AnyIterator([].makeIterator())
    }
    
    public func quads(matching pattern: QuadPattern) throws -> AnyIterator<Quad> {
        var s = pattern.subject
        var p = pattern.predicate
        var o = pattern.object
        var g = pattern.graph
        if case .variable(_) = s { s = .variable("s", binding: true) }
        if case .variable(_) = p { p = .variable("p", binding: true) }
        if case .variable(_) = o { o = .variable("o", binding: true) }
        if case .variable(_) = g { g = .variable("g", binding: true) }
        let query: String
        
        if case .bound(defaultGraph) = g {
            query = "SELECT * WHERE { \(s) \(p) \(o) }"
        } else if case .bound(_) = g {
            query = "SELECT * WHERE { GRAPH \(g) { \(s) \(p) \(o) } }" // TODO: pull default graph also
        } else {
            query = """
                SELECT * WHERE {
                    {
                        GRAPH \(g) { \(s) \(p) \(o) }
                    } UNION {
                        \(s) \(p) \(o)
                    }
                }
            """
        }
        if let r = try? client.execute(query) {
            if case .bindings(_, let rows) = r {
                let quads = rows.compactMap { (row) -> Quad? in
                    var subj: Term
                    var pred: Term
                    var obj: Term
                    var graph: Term
                    if case .bound(let t) = s {
                        subj = t
                    } else if let s = row["s"] {
                        subj = s
                    } else {
                        return nil
                    }
                    if case .bound(let t) = p {
                        pred = t
                    } else if let p = row["p"] {
                        pred = p
                    } else {
                        return nil
                    }
                    if case .bound(let t) = o {
                        obj = t
                    } else if let o = row["o"] {
                        obj = o
                    } else {
                        return nil
                    }
                    if case .bound(let t) = g {
                        graph = t
                    } else {
                        graph = row["g"] ?? defaultGraph
                    }
                    return Quad(subject: subj, predicate: pred, object: obj, graph: graph)
                }
                return AnyIterator(quads.makeIterator())
            }
        }
        return AnyIterator([].makeIterator())
    }
    
    public func effectiveVersion(matching pattern: QuadPattern) throws -> Version? {
        return nil
    }
}

extension SPARQLClientQuadStore : BGPQuadStoreProtocol {
    public func results(matching triples: [TriplePattern], in graph: Term) throws -> AnyIterator<TermResult> {
        let ser = SPARQLSerializer(prettyPrint: true)
        let bgp = try ser.serialize(.bgp(triples))
        let query = "SELECT * WHERE { \(bgp) }"
        print("Evaluating BGP against \(client):\n\(query)")
        if let r = try? client.execute(query) {
            if case .bindings(_, let rows) = r {
                return AnyIterator(rows.makeIterator())
            }
        }
        return AnyIterator([].makeIterator())
    }
}

extension SPARQLClientQuadStore: CustomStringConvertible {
    public var description: String {
        return "SPARQLClientQuadStore <\(client.endpoint)>\n"
    }
}
