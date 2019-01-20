//
//  QueryPlanner.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 1/15/19.
//

import Foundation
import SPARQLSyntax

public protocol PlanningQuadStore: QuadStoreProtocol {
    func plan(algebra: Algebra, activeGraph: Term, dataset: Dataset) throws -> QueryPlan?
}

public class QueryPlanner<Q: QuadStoreProtocol> {
    public var store: Q
    public var dataset: Dataset
    public var evaluator: ExpressionEvaluator
    private var freshCounter: UnfoldSequence<Int, (Int?, Bool)>

    public init(store: Q, dataset: Dataset, base: String? = nil) {
        self.store = store
        self.dataset = dataset
        self.evaluator = ExpressionEvaluator(base: base)
        self.freshCounter = sequence(first: 1) { $0 + 1 }
    }
    
    public func freshVariable() -> Node {
        return .variable(freshVariableName(), binding: true)
    }
    
    public func freshVariableName() -> String {
        let n = freshCounter.next()!
        return ".v\(n)"
    }
    
    public func plan(query: Query, activeGraph: Term) throws -> QueryPlan {
        // The plan returned here does not fully handle the query form; it only sets up the correct query plan.
        // For CONSTRUCT and DESCRIBE queries, the production of triples must still be handled elsewhere.
        // For ASK queries, code must handle conversion of the iterator into a boolean result
        let algebra = query.algebra
        let p = try plan(algebra: algebra, activeGraph: activeGraph)
        switch query.form {
        case .select(.star):
            return p
        case .select(.variables(let proj)):
            return ProjectPlan(child: p, variables: Set(proj))
        case .ask, .construct(_), .describe(_):
            return p
        }
    }
    
    func plan(bgp: [TriplePattern], activeGraph g: Node) throws -> QueryPlan {
        // TODO: implement smarter planning here
        guard let f = bgp.first else {
            return TablePlan.joinIdentity
        }
        
        let rest = bgp.dropFirst()
        
        let q = QuadPattern(triplePattern: f, graph: g)
        let qp = QuadPlan(quad: q, store: store)
        let tuple : (QueryPlan, Set<String>) = (qp, Algebra.triple(f).inscope)
        let (plan, _) = rest.reduce(into: tuple) { (r, t) in
            let tv = Algebra.triple(t).inscope
            let i = r.1.intersection(tv)
            var plan : QueryPlan
            let q = QuadPattern(triplePattern: t, graph: g)
            let qp = QuadPlan(quad: q, store: store)
            if i.isEmpty {
                plan = NestedLoopJoinPlan(lhs: r.0, rhs: qp)
            } else {
                plan = HashJoinPlan(lhs: r.0, rhs: qp, joinVariables: i)
            }
            let u = r.1.union(tv)
            r = (plan, u)
        }
        
        return plan
    }
    
    public func plan(algebra: Algebra, activeGraph: Term) throws -> QueryPlan {
        if let ps = store as? PlanningQuadStore {
            print("QuadStore is a query planner")
            do {
                if let p = try ps.plan(algebra: algebra, activeGraph: activeGraph, dataset: dataset) {
                    return p
                }
            } catch {}
        }
        
        switch algebra {
        // don't require access to the underlying store:
        case let .subquery(q):
            return try plan(query: q, activeGraph: activeGraph)
        case .unionIdentity:
            return TablePlan.unionIdentity
        case .joinIdentity:
            return TablePlan.joinIdentity
        case let .table(names, rows):
            return TablePlan(columns: names, rows: rows)
        case let .innerJoin(lhs, rhs):
            let i = lhs.inscope.intersection(rhs.inscope)
            let l = try plan(algebra: lhs, activeGraph: activeGraph)
            let r = try plan(algebra: rhs, activeGraph: activeGraph)
            if i.isEmpty {
                return NestedLoopJoinPlan(lhs: l, rhs: r)
            } else {
                return HashJoinPlan(lhs: l, rhs: r, joinVariables: i)
            }
        case let .leftOuterJoin(lhs, rhs, expr):
            let fij = try plan(algebra: .filter(.innerJoin(lhs, rhs), expr), activeGraph: activeGraph)
            let l : QueryPlan = try plan(algebra: lhs, activeGraph: activeGraph)
            let r : QueryPlan = try plan(algebra: rhs, activeGraph: activeGraph)
            let (e, mapping) = try expr.removingExistsExpressions(namingVariables: &freshCounter)
            print("*** TODO: handle query planning of EXISTS expressions in OPTIONAL")
            // TODO: add mapping to algebra (determine the right semantics for this with diff)
            let diff : QueryPlan = DiffPlan(lhs: l, rhs: r, expression: e, evaluator: evaluator)
            return UnionPlan(lhs: fij, rhs: diff)
        case let .union(lhs, rhs):
            return try UnionPlan(
                lhs: plan(algebra: lhs, activeGraph: activeGraph),
                rhs: plan(algebra: rhs, activeGraph: activeGraph)
            )
        case let .project(child, vars):
            return try ProjectPlan(child: plan(algebra: child, activeGraph: activeGraph), variables: vars)
        case let .slice(.order(child, orders), nil, .some(limit)):
            // TODO: expand to cases with offsets
            let p = try plan(algebra: child, activeGraph: activeGraph)
            return HeapSortLimitPlan(child: p, comparators: orders, limit: limit)
        case let .slice(child, offset, limit):
            let p = try plan(algebra: child, activeGraph: activeGraph)
            switch (offset, limit) {
            case let (.some(offset), .some(limit)):
                return LimitPlan(child: OffsetPlan(child: p, offset: offset), limit: limit)
            case (.some(let offset), _):
                return OffsetPlan(child: p, offset: offset)
            case (_, .some(let limit)):
                return LimitPlan(child: p, limit: limit)
            default:
                return p
            }
        case let .extend(child, .exists(algebra), name):
            let p = try plan(algebra: child, activeGraph: activeGraph)
            let pat = try plan(algebra: algebra, activeGraph: activeGraph)
            return ExistsPlan(child: p, pattern: pat, variable: name, patternAlgebra: algebra)
        case let .extend(child, expr, name):
            var p = try plan(algebra: child, activeGraph: activeGraph)
            let (e, mapping) = try expr.removingExistsExpressions(namingVariables: &freshCounter)
            try mapping.forEach { (name, algebra) throws in
                let pat = try plan(algebra: algebra, activeGraph: activeGraph)
                p = ExistsPlan(child: p, pattern: pat, variable: name, patternAlgebra: algebra)
            }
            return ExtendPlan(child: p, expression: e, variable: name, evaluator: evaluator)
        case let .order(child, orders):
            let p = try plan(algebra: child, activeGraph: activeGraph)
            return OrderPlan(child: p, comparators: orders, evaluator: evaluator)
        case let .aggregate(child, groups, aggs):
            let p = try plan(algebra: child, activeGraph: activeGraph)
            return AggregationPlan(child: p, groups: groups, aggregates: aggs)
        case let .window(child, groups, funcs):
            let p = try plan(algebra: child, activeGraph: activeGraph)
            return WindowPlan(child: p, groups: groups, functions: Set(funcs))
        case let .filter(child, expr):
            var p = try plan(algebra: child, activeGraph: activeGraph)
            let (e, mapping) = try expr.removingExistsExpressions(namingVariables: &freshCounter)
            try mapping.forEach { (name, algebra) throws in
                let pat = try plan(algebra: algebra, activeGraph: activeGraph)
                p = ExistsPlan(child: p, pattern: pat, variable: name, patternAlgebra: algebra)
            }
            return FilterPlan(child: p, expression: e, evaluator: evaluator)
        case let .distinct(child):
            let p = try plan(algebra: child, activeGraph: activeGraph)
            return DistinctPlan(child: p)
        case .bgp(let patterns):
            return try plan(bgp: patterns, activeGraph: .bound(activeGraph))
        case let .minus(lhs, rhs):
            return try MinusPlan(
                lhs: plan(algebra: lhs, activeGraph: activeGraph),
                rhs: plan(algebra: rhs, activeGraph: activeGraph)
            )
        case let .service(endpoint, algebra, silent):
            let s = SPARQLSerializer(prettyPrint: true)
            guard let q = try? Query(form: .select(.star), algebra: algebra) else {
                throw QueryError.evaluationError("Failed to serialize SERVICE algebra into SPARQL string")
            }
            let tokens = try q.sparqlTokens()
            let query = s.serialize(tokens)
            return ServicePlan(endpoint: endpoint, query: query, silent: silent)
        case let .namedGraph(child, .bound(g)):
            return try plan(algebra: child, activeGraph: g)
        case let .namedGraph(child, .variable(graph, binding: bind)):
            let branches = try dataset.namedGraphs.lazy.map { (g) -> QueryPlan in
                let p = try plan(algebra: child, activeGraph: g)
                if bind {
                    return ExtendPlan(child: p, expression: .node(.bound(g)), variable: graph, evaluator: evaluator)
                } else {
                    return p
                }
            }
            let first = branches.first!
            return branches.dropFirst().reduce(first) { UnionPlan(lhs: $0, rhs: $1) }
        case let .triple(t):
            let quad = QuadPattern(subject: t.subject, predicate: t.predicate, object: t.object, graph: .bound(activeGraph))
            return try plan(algebra: .quad(quad), activeGraph: activeGraph)
        case let .quad(quad):
            return QuadPlan(quad: quad, store: store)
        case let .path(s, path, o):
            switch path {
            case .link(let predicate):
                let quad = QuadPattern(subject: s, predicate: .bound(predicate), object: o, graph: .bound(activeGraph))
                return QuadPlan(quad: quad, store: store)
            case .inv(let ipath):
                return try plan(algebra: .path(o, ipath, s), activeGraph: activeGraph)
            case let .alt(lhs, rhs):
                let i = try plan(algebra: .path(s, lhs, o), activeGraph: activeGraph)
                let j = try plan(algebra: .path(s, rhs, o), activeGraph: activeGraph)
                return UnionPlan(lhs: i, rhs: j)
            case let .seq(lhs, rhs):
                let jvar = freshVariable()
                guard case .variable(_, _) = jvar else {
                    Logger.shared.error("Unexpected variable generated during path evaluation")
                    throw QueryError.evaluationError("Unexpected variable generated during path evaluation")
                }
                let j : Algebra = .innerJoin(
                    .path(s, lhs, jvar),
                    .path(jvar, rhs, o)
                )
                return try plan(algebra: j, activeGraph: activeGraph)
            case .nps(let iris):
                let p = freshVariable()
                return NPSPathPlan(iris: iris, subject: s, predicate: p, object: o, graph: activeGraph, store: store)
            case .plus(let pp):
                switch (s, o) {
                case (.bound(_), .variable(_, binding: _)):
                    let pvar = freshVariableName()
                    let child = try plan(algebra: .path(s, pp, .variable(pvar, binding: true)), activeGraph: activeGraph)
                    return PartiallyBoundPlusPathPlan(child: child, subject: s, object: o, graph: activeGraph, objectVariable: pvar)
                case (.variable(_), .bound(_)):
                    let ipath: PropertyPath = .plus(.inv(pp))
                    return try plan(algebra: .path(o, ipath, s), activeGraph: activeGraph)
                case (.bound(_), .bound(_)):
                    let child = try plan(algebra: .path(s, pp, o), activeGraph: activeGraph)
                    return FullyBoundPlusPathPlan(child: child, subject: s, object: o, graph: activeGraph)
                case (.variable(_), .variable(_)):
                    let pvar = freshVariableName()
                    let qvar = freshVariableName()
                    let child = try plan(algebra: .path(.variable(pvar, binding: true), pp, .variable(qvar, binding: true)), activeGraph: activeGraph)
                    return UnboundPlusPathPlan(child: child, subject: s, object: o, graph: activeGraph, subjectVariable: pvar, objectVariable: qvar)
                }
            case .star(let pp):
                switch (s, o) {
                case (.bound(_), .variable(_)):
                    let pvar = freshVariableName()
                    let child = try plan(algebra: .path(s, pp, .variable(pvar, binding: true)), activeGraph: activeGraph)
                    return PartiallyBoundStarPathPlan(child: child, subject: s, object: o, graph: activeGraph, objectVariable: pvar)
                case (.variable(_), .bound(_)):
                    let ipath: PropertyPath = .star(.inv(pp))
                    return try plan(algebra: .path(o, ipath, s), activeGraph: activeGraph)
                case (.bound(_), .bound(_)):
                    let child = try plan(algebra: .path(s, pp, o), activeGraph: activeGraph)
                    return FullyBoundStarPathPlan(child: child, subject: s, object: o, graph: activeGraph)
                case (.variable(_), .variable(_)):
                    let pvar = freshVariableName()
                    let qvar = freshVariableName()
                    let child = try plan(algebra: .path(.variable(pvar, binding: true), pp, .variable(qvar, binding: true)), activeGraph: activeGraph)
                    return UnboundStarPathPlan(child: child, subject: s, object: o, graph: activeGraph, subjectVariable: pvar, objectVariable: qvar)
                }
            case .zeroOrOne(let pp):
                switch (s, o) {
                case (.bound(_), .variable(_)):
                    let pvar = freshVariableName()
                    let child = try plan(algebra: .path(s, pp, .variable(pvar, binding: true)), activeGraph: activeGraph)
                    return PartiallyBoundZeroOrOnePathPlan(child: child, subject: s, object: o, graph: activeGraph, objectVariable: pvar)
                case (.variable(_), .bound(_)):
                    let ipath: PropertyPath = .star(.inv(pp))
                    return try plan(algebra: .path(o, ipath, s), activeGraph: activeGraph)
                case (.bound(let s), .bound(let o)) where s == o:
                    return TablePlan.joinIdentity
                case (.bound(_), .bound(_)):
                    let child = try plan(algebra: .path(s, pp, o), activeGraph: activeGraph)
                    return FullyBoundZeroOrOnePathPlan(child: child, subject: s, object: o, graph: activeGraph)
                case (.variable(_), .variable(_)):
                    let pvar = freshVariableName()
                    let qvar = freshVariableName()
                    let child = try plan(algebra: .path(.variable(pvar, binding: true), pp, .variable(qvar, binding: true)), activeGraph: activeGraph)
                    return UnboundZeroOrOnePathPlan(child: child, subject: s, object: o, graph: activeGraph, subjectVariable: pvar, objectVariable: qvar)
                }
            default:
                fatalError("TODO: unimplemented switch case for \(self)")
            }
        }
    }
}

extension Expression {
    public func removingExistsExpressions<I: IteratorProtocol>(namingVariables counter: inout I) throws -> (Expression, [String:Algebra]) where I.Element == Int {
        var mapping = [String:Algebra]()
        let expr = try self.replace { (e) -> Expression? in
            switch e {
            case .exists(let a):
                let n = counter.next()!
                let name = ".exists-\(n)"
                mapping[name] = a
                return .node(.variable(name, binding: true))
            default:
                return nil
            }
        }
        return (expr, mapping)
    }
}

public struct QueryPlanEvaluator<Q: QuadStoreProtocol> {
    var dataset: Dataset
    var planner: QueryPlanner<Q>
    
    public init(dataset: Dataset, store: Q) {
        self.dataset = dataset
        self.planner = QueryPlanner(store: store, dataset: dataset)
    }
    
    public func evaluate(query q: Query) throws -> QueryResult<AnySequence<TermResult>, [Triple]> {
        let plan = try planner.plan(query: q, activeGraph: dataset.defaultGraphs.first!)
        print(plan.serialize())
        
        let seq = AnySequence { () -> AnyIterator<TermResult> in
            let i = try? plan.evaluate()
            return i ?? AnyIterator([].makeIterator())
        }
        switch q.form {
        case .ask:
            let i = seq.makeIterator()
            if let _ = i.next() {
                return QueryResult.boolean(true)
            } else {
                return QueryResult.boolean(false)
            }
        case .select(.star):
            return QueryResult.bindings(Array(q.inscope), seq)
        case .select(.variables(let vars)):
            return QueryResult.bindings(vars, seq)
        case .construct(let pattern):
            fatalError("unimplemented") // TODO: implement
        case .describe(let nodes):
            fatalError("unimplemented") // TODO: implement
        }
    }
}

