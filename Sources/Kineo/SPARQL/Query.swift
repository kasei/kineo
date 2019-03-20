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
    associatedtype ResultSequence: Sequence where ResultSequence.Element == TermResult
    associatedtype TripleSequence: Sequence where TripleSequence.Element == Triple
    func evaluate(query: Query) throws -> QueryResult<ResultSequence, TripleSequence>
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
    public func matches(quad: Quad) -> TermResult? {
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
        return TermResult(bindings: bindings)
    }
}

public extension Query {
    func execute<Q: QuadStoreProtocol>(quadstore: Q, defaultGraph: Term, bind: [String:Term]? = nil) throws -> QueryResult<[TermResult], [Triple]> {
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
