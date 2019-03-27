//
//  Graph.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 3/20/19.
//

import Foundation
import SPARQLSyntax

public protocol GraphProtocol {
    associatedtype VertexType
    var term: Term { get }
    
    func instancesOf(_ type: Term) throws -> [VertexType]
    func vertex(_ term: Term) -> VertexType
    func vertices() throws -> [VertexType]
    func extensionOf(_ predicate: Term) throws -> [(VertexType, VertexType)]
}

public protocol GraphVertexProtocol {
    associatedtype VertexType
    associatedtype GraphType
    var term: Term { get }
    var graph: GraphType { get }

    func listElements() throws -> [VertexType]
    func incoming(_ predicate: Term) throws -> [VertexType]
    func outgoing(_ predicate: Term) throws -> [VertexType]
    func incoming() throws -> Set<Term>
    func outgoing() throws -> Set<Term>
    func edges() throws -> [(Term, VertexType)]
    func graphs() throws -> [GraphType]
}

public enum GraphAPI {
    public struct GraphVertex<QS: QuadStoreProtocol>: GraphVertexProtocol {
        public typealias VertexType = GraphVertex<QS>
        public typealias GraphType = Graph<QS>

        var store: QS
        public var graph: Graph<QS>
        public var term: Term
        
        public func listElements() throws -> [GraphVertex<QS>] {
            let first = Term(iri: Namespace.rdf.first)
            let rest = Term(iri: Namespace.rdf.rest)
            let _nil = Term(iri: Namespace.rdf.nil)
            
            var head = self
            var values = [GraphVertex<QS>]()
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
        
        public func incoming() throws -> Set<Term> {
            var qp = QuadPattern.all
            qp.object = .bound(term)
            qp.graph = .bound(graph.term)
            let q = try store.quads(matching: qp)
            let props = Set(q.map { $0.predicate })
            return props
        }
        
        public func outgoing() throws -> Set<Term> {
            var qp = QuadPattern.all
            qp.subject = .bound(term)
            qp.graph = .bound(graph.term)
            let q = try store.quads(matching: qp)
            let props = Set(q.map { $0.predicate })
            return props
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

    public struct Graph<QS: QuadStoreProtocol>: GraphProtocol {
        public typealias VertexType = GraphVertex<QS>
        
        var store: QS
        public var term: Term
        
        public func instancesOf(_ type: Term) throws -> [VertexType] {
            var qp = QuadPattern.all
            qp.predicate = .bound(Term(iri: Namespace.rdf.type))
            qp.object = .bound(type)
            qp.graph = .bound(term)
            let q = try store.quads(matching: qp)
            let subjects = q.map { GraphVertex(store: store, graph: self, term: $0.subject) }
            return subjects
        }
        
        public func vertex(_ term: Term) -> VertexType {
            return GraphVertex(store: store, graph: self, term: term)
        }
        
        public func vertices() throws -> [VertexType] {
            let vertices = store.graphTerms(in: term)
            return vertices.map { GraphVertex(store: store, graph: self, term: $0) }
        }
        
        public func extensionOf(_ predicate: Term) throws -> [(VertexType, VertexType)] {
            var qp = QuadPattern.all
            qp.predicate = .bound(predicate)
            qp.graph = .bound(term)
            let subjects = try store.quads(matching: qp).map { GraphVertex(store: store, graph: self, term: $0.subject) }
            let objects = try store.quads(matching: qp).map { GraphVertex(store: store, graph: self, term: $0.object) }
            let pairs = zip(subjects, objects)
            return Array(pairs)
        }
    }
}

extension GraphAPI.GraphVertex: Hashable {
    public static func == (lhs: GraphAPI.GraphVertex<QS>, rhs: GraphAPI.GraphVertex<QS>) -> Bool {
        return lhs.term == rhs.term && lhs.graph == rhs.graph
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(term)
        hasher.combine(graph)
    }
}

extension GraphAPI.Graph: Hashable {
    public static func == (lhs: GraphAPI.Graph<QS>, rhs: GraphAPI.Graph<QS>) -> Bool {
        return lhs.term == rhs.term
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(term)
    }
}

extension QuadStoreProtocol {
    public func graph(_ iri: Term) -> GraphAPI.Graph<Self> {
       return GraphAPI.Graph(store: self, term: iri)
    }
}
