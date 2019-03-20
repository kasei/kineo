//
//  Graph.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 3/20/19.
//

import Foundation
import SPARQLSyntax

public struct GraphVertex<QS: QuadStoreProtocol> {
    var store: QS
    var graph: Graph<QS>
    public var term: Term
    
    public func listElements() throws -> [GraphVertex]? {
        let first = Term(iri: Namespace.rdf.first)
        let rest = Term(iri: Namespace.rdf.rest)
        let _nil = Term(iri: Namespace.rdf.nil)
        
        var head = self
        var values = [GraphVertex]()
        while head.term != _nil {
            values += try head.outgoing(first)
            guard let tail = try head.outgoing(rest).first else {
                break
            }
            head = tail
        }
        return values
    }
    
    public func incoming(_ predicate: Term) throws -> [GraphVertex<QS>] {
        var qp = QuadPattern.all
        qp.predicate = .bound(predicate)
        qp.object = .bound(term)
        qp.graph = .bound(graph.term)
        let q = try store.quads(matching: qp)
        return q.map { GraphVertex(store: store, graph: graph, term: $0.subject) }
    }
    
    public func outgoing(_ predicate: Term) throws -> [GraphVertex<QS>] {
        var qp = QuadPattern.all
        qp.subject = .bound(term)
        qp.predicate = .bound(predicate)
        qp.graph = .bound(graph.term)
        let q = try store.quads(matching: qp)
        return q.map { GraphVertex(store: store, graph: graph, term: $0.object) }
    }
    
    public func edges() throws -> [(Term, GraphVertex<QS>)] {
        var qp = QuadPattern.all
        qp.graph = .bound(graph.term)
        let q = try store.quads(matching: qp)
        let pairs = q.map { ($0.predicate, GraphVertex(store: store, graph: graph, term: $0.subject)) }
        return pairs
    }

    public func graphs() throws -> [Graph<QS>] {
        var outQp = QuadPattern.all
        outQp.subject = .bound(term)
        let oq = try store.quads(matching: outQp)
        let outV = Set(oq.map { $0.graph })

        var inQp = QuadPattern.all
        inQp.object = .bound(term)
        let iq = try store.quads(matching: inQp)
        let inV = Set(iq.map { $0.graph })
        
        let vertices = outV.union(inV)
        return vertices.map { Graph(store: store, term: $0) }
    }
    
}

public struct Graph<QS: QuadStoreProtocol> {
    var store: QS
    public var term: Term

    public func instancesOf(_ type: Term) throws -> [GraphVertex<QS>] {
        var qp = QuadPattern.all
        qp.predicate = .bound(Term(iri: Namespace.rdf.type))
        qp.object = .bound(type)
        qp.graph = .bound(term)
        let q = try store.quads(matching: qp)
        let subjects = q.map { GraphVertex(store: store, graph: self, term: $0.subject) }
        return subjects
    }
    
    public func vertex(_ term: Term) -> GraphVertex<QS> {
        return GraphVertex(store: store, graph: self, term: term)
    }
    
    public func vertices() throws -> [GraphVertex<QS>] {
        var outQp = QuadPattern.all
        outQp.graph = .bound(term)
        let oq = try store.quads(matching: outQp)
        let outV = Set(oq.map { $0.object })
        
        var inQp = QuadPattern.all
        inQp.graph = .bound(term)
        let iq = try store.quads(matching: inQp)
        let inV = Set(iq.map { $0.subject })
        
        let vertices = outV.union(inV)
        return vertices.map { GraphVertex(store: store, graph: self, term: $0) }
    }
    
    public func extensionOf(_ predicate: Term) throws -> [(GraphVertex<QS>, GraphVertex<QS>)] {
        var qp = QuadPattern.all
        qp.predicate = .bound(predicate)
        qp.graph = .bound(term)
        let subjects = try store.quads(matching: qp).map { GraphVertex(store: store, graph: self, term: $0.subject) }
        let objects = try store.quads(matching: qp).map { GraphVertex(store: store, graph: self, term: $0.object) }
        let pairs = zip(subjects, objects)
        return Array(pairs)
    }
}

public extension QuadStoreProtocol {
    func graph(_ iri: Term) -> Graph<Self> {
       return Graph(store: self, term: iri)
    }
}
