//
//  Query.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 7/8/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import SPARQLSyntax

enum QueryError: Error {
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

extension Query {
    func execute<Q: QuadStoreProtocol>(quadstore: Q, defaultGraph: Term) throws -> QueryResult<[TermResult], [Triple]> {
        let dataset = quadstore.dataset(withDefault: defaultGraph)
        let e       = SimpleQueryEvaluator(store: quadstore, dataset: dataset, verbose: false)
        let result = try e.evaluate(query: self)
        return result
    }
}
