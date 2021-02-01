//
//  Query.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 7/8/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import SPARQLSyntax

public protocol QueryEvaluatorProtocol {
    associatedtype ResultSequence: Sequence where ResultSequence.Element == SPARQLResultSolution<Term>
    associatedtype TripleSequence: Sequence where TripleSequence.Element == Triple
    func evaluate(query: Query) throws -> QueryResult<ResultSequence, TripleSequence>
    func evaluate(algebra: Algebra, activeGraph: Term?) throws -> AnyIterator<SPARQLResultSolution<Term>>
    func evaluate(query: Query, activeGraph: Term?) throws -> QueryResult<ResultSequence, TripleSequence>
    var supportedLanguages: [QueryLanguage] { get }
    var supportedFeatures: [QueryEngineFeature] { get }
}

public enum QueryLanguage : String {
    case sparqlQuery10 = "http://www.w3.org/ns/sparql-service-description#SPARQL10Query"
    case sparqlQuery11 = "http://www.w3.org/ns/sparql-service-description#SPARQL11Query"
    case sparqlUpdate11 = "http://www.w3.org/ns/sparql-service-description#SPARQL11Update"
}

public enum QueryEngineFeature : String {
    case dereferencesURIs = "http://www.w3.org/ns/sparql-service-description#DereferencesURIs"
    case unionDefaultGraph = "http://www.w3.org/ns/sparql-service-description#UnionDefaultGraph"
    case requiresDataset = "http://www.w3.org/ns/sparql-service-description#RequiresDataset"
    case basicFederatedQuery = "http://www.w3.org/ns/sparql-service-description#BasicFederatedQuery"
}

public enum QueryError: Error {
    case evaluationError(String)
    case typeError(String)
    case parseError(String)
    case compatabilityError(String)
}

extension QuadPattern {
    public func matches(quad: Quad) -> SPARQLResultSolution<Term>? {
        let terms = [quad.subject, quad.predicate, quad.object, quad.graph]
        let nodes = [subject, predicate, object, graph]
        var bindings = [String:Term]()
        for i in 0..<4 {
            let term = terms[i]
            let node = nodes[i]
            switch node {
            case .bound(let t):
                if t != term {
                    return nil
                }
            case .variable(let name, binding: let b):
                if b {
                    bindings[name] = term
                }
            }
        }
        return SPARQLResultSolution<Term>(bindings: bindings)
    }
}

public extension Query {
    func execute<Q: QuadStoreProtocol>(quadstore: Q, defaultGraph: Term, bind: [String:Term]? = nil) throws -> QueryResult<[SPARQLResultSolution<Term>], [Triple]> {
        let dataset = quadstore.dataset(withDefault: defaultGraph)
        let e       = SimpleQueryEvaluator(store: quadstore, dataset: dataset, verbose: false)
        var q = self
        if let bind = bind {
            q = try q.replace(bind)
        }
        let result = try e.evaluate(query: q)
        return result
    }
}

extension Algebra {
    func unionBranches() -> [Algebra] {
        switch self {
        case let .union(lhs, rhs):
            return lhs.unionBranches() + rhs.unionBranches()
        default:
            return [self]
        }
    }
    
    var canEvaluateWithoutMaterialization: Bool {
        switch self {
        case .unionIdentity, .joinIdentity:
            return true
        case .quad(_):
            return true
        case .triple(_):
            return true
        case .bgp(_):
            return true
        case .path(_, _, _):
            return true
        case let .innerJoin(l, r):
            return l.canEvaluateWithoutMaterialization && r.canEvaluateWithoutMaterialization
        case let .union(l, r):
            return l.canEvaluateWithoutMaterialization && r.canEvaluateWithoutMaterialization
        case let .namedGraph(l, _):
            return l.canEvaluateWithoutMaterialization
        case let .minus(l, r):
            return l.canEvaluateWithoutMaterialization && r.canEvaluateWithoutMaterialization
        case let .project(l, _):
            return l.canEvaluateWithoutMaterialization
        case .reduced(let l):
            return l.canEvaluateWithoutMaterialization
        case .slice(let l, _, _):
            return l.canEvaluateWithoutMaterialization


        case .leftOuterJoin(_, _, _): // TODO: can special-case OPTIONAL without a filter clause
            return false
        case .filter:
            return false
        case .extend(_, _, _):
            return false
        case .distinct(_):
            return false
        case .service(_, _, _):
            return false
        case .order(_, _):
            return false
        case .aggregate(_, _, _):
            return false
        case .window(_, _):
            return false
        case .subquery(_):
            return false
        case .table(_, _):
            return false
        }
    }

    
    /// Returns true if the algebra pattern will always bind a graph variable inside of a `GRAPH ?g` pattern.
    /// This is used to determine whether to evaluate the pattern directly and use the bound graph variable,
    /// or if the pattern needs to be evaluated once per named graph (e.g. `GRAPH ?g { VALUES ?x { 1 } }`)
    var willBindGraph: Bool {
        switch self {
        case .unionIdentity, .joinIdentity:
            return false
        case .quad(_):
            return true
        case .triple(_):
            return true
        case .bgp(_):
            return true
        case .path(_, _, _):
            return true
        case let .innerJoin(l, r):
            return l.willBindGraph || r.willBindGraph
        case let .union(l, r):
            return l.willBindGraph && r.willBindGraph
        case let .namedGraph(_, _):
            return false
        case let .minus(l, _):
            return l.willBindGraph
        case let .project(l, v):
            // This might actually bind a graph variable, but we don't have insight into whether the projection will preseve it, so we conservatively assume it won't
            return false
        case .reduced(let l):
            return l.willBindGraph
        case .slice(let l, _, _):
            return l.willBindGraph


        case .leftOuterJoin(let l, _, _): // TODO: can special-case OPTIONAL without a filter clause
            return l.willBindGraph
        case .filter(let l, _):
            return l.willBindGraph
        case .extend(let l, _, _):
            return l.willBindGraph
        case .distinct(let l):
            return l.willBindGraph
        case .service(_, _, _):
            return false
        case .order(let l, _):
            return l.willBindGraph
        case .aggregate(_, _, _):
            return false
        case .window(_, _):
            return false
        case .subquery(_):
            return false
        case .table(_, _):
            return false
        }
    }
}

public struct StoreDefaultDataset<Q: QuadStoreProtocol> : DatasetProtocol {
    public var store: Q
    public var defaultGraphs: [Term]
    
    public init(store: Q, graph: Term?) {
        self.store = store
        if let g = graph {
            defaultGraphs = [g]
        } else {
            // if there are no graphs in the database, it doesn't matter what the default graph is.
            defaultGraphs = [store.graphs().next() ?? Term(iri: "tag:kasei.us,2018:default-graph")]
        }
    }
  
    public var namedGraphs: [Term] {
        var named = Set(store.graphs())
        named.subtract(defaultGraphs)
        return Array(named)
    }

    public var isEmpty : Bool {
        return store.count == 0
    }
}

public extension DatasetProtocol {
    func isGraphNamed<Q : QuadStoreProtocol>(_ graph: Term, in store: Q) throws -> Bool {
        if let _ = self as? StoreDefaultDataset<Q> {
            // we know that the named graphs in the dataset are equal to all graphs minus the default graphs
            return !defaultGraphs.contains(graph)
        } else {
            return namedGraphs.contains(graph)
        }
    }
}
