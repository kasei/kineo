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
    public var allowStoreOptimizedPlans: Bool
    public var store: Q
    public var dataset: Dataset
    public var evaluator: ExpressionEvaluator
    private var freshCounter: UnfoldSequence<Int, (Int?, Bool)>

    public init(store: Q, dataset: Dataset, base: String? = nil) {
        self.store = store
        self.dataset = dataset
        self.evaluator = ExpressionEvaluator(base: base)
        self.freshCounter = sequence(first: 1) { $0 + 1 }
        self.allowStoreOptimizedPlans = true
    }
    
    public func freshVariable() -> Node {
        return .variable(freshVariableName(), binding: true)
    }
    
    public func freshVariableName() -> String {
        let n = freshCounter.next()!
        return ".v\(n)"
    }
    
    public func plan(query: Query, activeGraph: Term? = nil) throws -> QueryPlan {
        // The plan returned here does not fully handle the query form; it only sets up the correct query plan.
        // For CONSTRUCT and DESCRIBE queries, the production of triples must still be handled elsewhere.
        // For ASK queries, code must handle conversion of the iterator into a boolean result
        let algebra = query.algebra
        
        let graphs : [Term]
        if let g = activeGraph {
            graphs = [g]
        } else {
            graphs = dataset.defaultGraphs
        }
        if graphs.isEmpty {
            print("*** There is no active graph during query planning:")
            print("*** \(algebra.serialize())")
        }
        
        var plans = [QueryPlan]()
        for activeGraph in graphs {
            let p = try plan(algebra: algebra, activeGraph: activeGraph)
            plans.append(p)
        }

        let f = plans.first!
        let p = plans.dropFirst().reduce(f) { UnionPlan(lhs: $0, rhs: $1) }
        
        switch query.form {
        case .select(.star):
            return p
        case .select(.variables(let proj)):
            if let pp = p as? ProjectPlan {
                if pp.variables.count == proj.count && pp.variables == Set(proj) {
                    // avoid duplicating projection
                    return p
                }
            }
            return ProjectPlan(child: p, variables: Set(proj))
        case .ask, .construct(_), .describe(_):
            return p
        }
    }
    
    func plan(bgp: [TriplePattern], activeGraph g: Node) throws -> QueryPlan {
        let proj = Algebra.bgp(bgp).inscope
        // TODO: implement smarter planning here
        guard let f = bgp.first?.bindingAllVariables else {
            return TablePlan.joinIdentity
        }
        
        let rest = bgp.dropFirst()
        
        let q = QuadPattern(triplePattern: f, graph: g).bindingAllVariables
        let qp = QuadPlan(quad: q, store: store)
        let tuple : (QueryPlan, Set<String>) = (qp, Algebra.triple(f).inscope)
        let (plan, vars) = rest.reduce(into: tuple) { (r, t) in
            let algebra = Algebra.triple(t)
            var plan : QueryPlan
            let q = QuadPattern(triplePattern: t, graph: g).bindingAllVariables
            let qp = QuadPlan(quad: q, store: store)
            let tv = q.variables
            let i = r.1.intersection(tv)
            if i.isEmpty {
                print("No intersection of in-scope variables:")
                print("- \(r.1): \(r.0)")
                print("- \(tv): \(algebra)")
                plan = NestedLoopJoinPlan(lhs: r.0, rhs: qp)
            } else {
                plan = HashJoinPlan(lhs: r.0, rhs: qp, joinVariables: i)
            }
            let u = r.1.union(tv)
            r = (plan, u)
        }
        
        if vars == proj {
            return plan
        } else {
            return ProjectPlan(child: plan, variables: Set(proj))
        }
    }

    public func plan(algebra: Algebra, activeGraph: Term) throws -> QueryPlan {
        if allowStoreOptimizedPlans {
            if let ps = store as? PlanningQuadStore {
                do {
                    if let p = try ps.plan(algebra: algebra, activeGraph: activeGraph, dataset: dataset) {
                        return p
                    }
                } catch {}
            }
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
            print("*** TODO: handle query planning of EXISTS expressions in OPTIONAL: \(e)")
            // TODO: add mapping to algebra (determine the right semantics for this with diff)
            let diff : QueryPlan = DiffPlan(lhs: l, rhs: r, expression: e, evaluator: evaluator)
            return UnionPlan(lhs: fij, rhs: diff)
        case let .union(lhs, rhs):
            return try UnionPlan(
                lhs: plan(algebra: lhs, activeGraph: activeGraph),
                rhs: plan(algebra: rhs, activeGraph: activeGraph)
            )
        case let .project(child, vars):
            let p = try plan(algebra: child, activeGraph: activeGraph)
            if child.inscope == vars {
                return p
            } else {
                return ProjectPlan(child: p, variables: vars)
            }
//        case let .slice(.order(child, orders), nil, .some(limit)):
//            // TODO: expand to cases with offsets
//            let p = try plan(algebra: child, activeGraph: activeGraph)
//            return HeapSortLimitPlan(child: p, comparators: orders, limit: limit)
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
            //NextRowPlan
        case let .extend(child, .exists(algebra), name):
            var p = try plan(algebra: child, activeGraph: activeGraph)
            if case .extend(_) = child {
            } else {
                // at the bottom of a chain of one or more extend()s, add a NextRow plan
                p = NextRowPlan(child: p, evaluator: evaluator)
            }
            let pat = try plan(algebra: algebra, activeGraph: activeGraph)
            return ExistsPlan(child: p, pattern: pat, variable: name, patternAlgebra: algebra)
        case let .extend(child, expr, name):
            var p = try plan(algebra: child, activeGraph: activeGraph)
            if case .extend(_) = child {
            } else {
                // at the bottom of a chain of one or more extend()s, add a NextRow plan
                p = NextRowPlan(child: p, evaluator: evaluator)
            }
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
            p = NextRowPlan(child: p, evaluator: evaluator)
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
            let branches = try dataset.namedGraphs.map { (g) throws -> QueryPlan in
                let p = try plan(algebra: child, activeGraph: g)
                if bind {
                    return ExtendPlan(child: p, expression: .node(.bound(g)), variable: graph, evaluator: evaluator)
                } else {
                    return p
                }
            }
            guard let first = branches.first else {
                return TablePlan(columns: [], rows: [])
            }
            return branches.dropFirst().reduce(first) { UnionPlan(lhs: $0, rhs: $1) }
        case let .triple(t):
            let quad = QuadPattern(subject: t.subject, predicate: t.predicate, object: t.object, graph: .bound(activeGraph))
            return try plan(algebra: .quad(quad), activeGraph: activeGraph)
        case let .quad(quad):
            return QuadPlan(quad: quad, store: store)
        case let .path(s, path, o):
            return try plan(subject: s, path: path, object: o, activeGraph: activeGraph)
//            switch path {
//            case .link(let predicate):
//                let pp = LinkPathPlan(predicate: predicate, store: store)
//                return PropertyPathPlan(subject: s, path: pp, object: o, graph: activeGraph)
//            case .inv(let ipath):
//                return try plan(algebra: .path(o, ipath, s), activeGraph: activeGraph)
//            case let .alt(lhs, rhs):
//                let i = try plan(algebra: .path(s, lhs, o), activeGraph: activeGraph)
//                let j = try plan(algebra: .path(s, rhs, o), activeGraph: activeGraph)
//                return UnionPlan(lhs: i, rhs: j)
//            case let .seq(lhs, rhs):
//                let jvar = freshVariable()
//                guard case .variable(_, _) = jvar else {
//                    Logger.shared.error("Unexpected variable generated during path evaluation")
//                    throw QueryError.evaluationError("Unexpected variable generated during path evaluation")
//                }
//                let j : Algebra = .innerJoin(
//                    .path(s, lhs, jvar),
//                    .path(jvar, rhs, o)
//                )
//                return try plan(algebra: j, activeGraph: activeGraph)
//            case .nps(let iris):
//                let p = freshVariable()
//                let pp = NPSPathPlan(iris: iris, store: store)
//                return PropertyPathPlan(subject: s, path: pp, object: o, graph: activeGraph)
//            case .plus(let pp):
//                let cs = freshVariable()
//                let co = freshVariable()
//                let child = try plan(algebra: .path(cs, pp, co), activeGraph: activeGraph)
//                return PlusPathPlan(
//                    child: child,
//                    subject: s,
//                    innerSubject: cs,
//                    innerObject: co,
//                    object: o,
//                    graph: activeGraph,
//                    store: store
//                )
//            case .star(_):
//                print("unimplemented")
//                fatalError()
//                throw QueryPlanError.unimplemented // TODO: implement +, *, ? path planning
//            case .zeroOrOne(_):
//                print("unimplemented")
//                fatalError()
//                throw QueryPlanError.unimplemented // TODO: implement +, *, ? path planning
//            default:
//                fatalError("TODO: unimplemented switch case for \(self)")
//            }
        }
    }

    public func plan(subject s: Node, path: PropertyPath, object o: Node, activeGraph: Term) throws -> PathPlan {
        switch path {
        case .link(let predicate):
            return LinkPathPlan(subject: s, predicate: predicate, object: o, graph: activeGraph, store: store)
        case .inv(let ipath):
            return try plan(subject: o, path: ipath, object: s, activeGraph: activeGraph)
        case let .alt(lhs, rhs):
            let l = try plan(subject: s, path: lhs, object: o, activeGraph: activeGraph)
            let r = try plan(subject: s, path: rhs, object: o, activeGraph: activeGraph)
            return UnionPathPlan(subject: s, lhs: l, rhs: r, object: o)
        case let .seq(lhs, rhs):
            let j = freshVariable()
            let l = try plan(subject: s, path: lhs, object: j, activeGraph: activeGraph)
            let r = try plan(subject: j, path: rhs, object: o, activeGraph: activeGraph)
            return SequencePathPlan(subject: s, lhs: l, joinNode: j, rhs: r, object: o)
        case .nps(let iris):
            return NPSPathPlan(subject: s, iris: iris, object: o, graph: activeGraph, store: store)
        case .plus(let pp):
            switch (s, o) {
            case (.bound(_), .variable(_)):
                let j = freshVariable()
                let p = try plan(subject: s, path: pp, object: j, activeGraph: activeGraph)
                print("planning Plus path with frontier node: \(j)")
                return PlusPathPlan(subject: s, child: p, object: o, graph: activeGraph, store: store, frontierNode: j)
            default:
                fatalError()
            }
        case .star(_):
            print("unimplemented")
            fatalError()
            throw QueryPlanError.unimplemented // TODO: implement +, *, ? path planning
        case .zeroOrOne(_):
            print("unimplemented")
            fatalError()
            throw QueryPlanError.unimplemented // TODO: implement +, *, ? path planning
        default:
            fatalError("TODO: unimplemented switch case for \(self)")
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
    public var planner: QueryPlanner<Q>
    
    public init(dataset: Dataset, store: Q, base: String? = nil) {
        self.dataset = dataset
        self.planner = QueryPlanner(store: store, dataset: dataset, base: base)
    }
    
    public func evaluate(query: Query, defaultGraph graph: Term? = nil) throws -> QueryResult<AnySequence<TermResult>, [Triple]> {
        let rewriter = SPARQLQueryRewriter()
        let q = try rewriter.simplify(query: query)
        let plan = try planner.plan(query: q, activeGraph: graph)
        print("Query Plan:")
        print(plan.serialize())
        
        let seq = AnySequence { () -> AnyIterator<TermResult> in
            do {
                let i = try plan.evaluate()
                return i
//                let a = Array(i)
//                print(">>> \(a)")
//                return AnyIterator(a.makeIterator())
            } catch let error {
                print("*** Failed to evaluate query plan in Sequence construction: \(error)")
                return AnyIterator([].makeIterator())
                //                throw error
            }
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
            print("unimplemented")
        throw QueryPlanError.unimplemented // TODO: implement
        case .describe(let nodes):
            print("unimplemented")
        throw QueryPlanError.unimplemented // TODO: implement
        }
    }
}



// TODO This should be removed once this extension is available in SPARQLSyntax.TermPattern
extension QuadPattern {
    public var variables: Set<String> {
        let vars = self.makeIterator().compactMap { (n) -> String? in
            switch n {
            case .variable(let name, binding: _):
                return name
            default:
                return nil
            }
        }
        return Set(vars)
    }
}
