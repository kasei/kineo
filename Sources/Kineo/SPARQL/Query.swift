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
        let e       = SimpleQueryEvaluator(store: quadstore, defaultGraph: defaultGraph, verbose: false)
        let result = try e.evaluate(query: self, activeGraph: defaultGraph)
        return result
    }
    
    func execute<D : PageDatabase>(_ database: D, defaultGraph: Term) throws -> AnyIterator<TermResult> {
        var results = [TermResult]()
        try self.execute(database, defaultGraph: defaultGraph) { (r) in
            results.append(r)
        }
        return AnyIterator(results.makeIterator())
    }
    
    // TODO: is this necessary?
    func execute<D : PageDatabase>(_ database: D, defaultGraph: Term, _ cb: (TermResult) throws -> ()) throws {
        let query = self
        try database.read { (m) in
            let store       = try MediatedPageQuadStore(mediator: m)
            let e       = SimpleQueryEvaluator(store: store, defaultGraph: defaultGraph, verbose: false)
            let results = try e.evaluate(query: query, activeGraph: defaultGraph)
            guard case let .bindings(_, iter) = results else { fatalError() }
            for result in iter {
                try cb(result)
            }
        }
    }
}
