//
//  QueryPlanner.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 1/15/19.
//

import Foundation
import SPARQLSyntax

public enum QueryPlannerError: Error {
    case noPlanAvailable
}

public protocol PlanningQuadStore: QuadStoreProtocol {
    func plan(algebra: Algebra, activeGraph: Term, dataset: Dataset) throws -> QueryPlan?
}

public class QueryPlanner<Q: QuadStoreProtocol> {
    public var allowStoreOptimizedPlans: Bool
    public var store: Q
    public var verbose: Bool
    public var dataset: Dataset
    public var evaluator: ExpressionEvaluator
    private var freshCounter: UnfoldSequence<Int, (Int?, Bool)>
    private var maxInFlightPlans: Int
    var serviceClients: [URL:SPARQLClient]

    public init(store: Q, dataset: Dataset, base: String? = nil) {
        self.store = store
        self.dataset = dataset
        self.evaluator = ExpressionEvaluator(base: base)
        self.freshCounter = sequence(first: 1) { $0 + 1 }
        self.allowStoreOptimizedPlans = true
        self.verbose = false
        self.serviceClients = [:]
        self.maxInFlightPlans = 16
    }
    
    public func addFunction(_ iri: String, _ f: @escaping ([Term]) throws -> Term) {
        self.evaluator.functions[iri] = f
    }
    
    public func freshVariable() -> Node {
        return .variable(freshVariableName(), binding: true)
    }
    
    public func freshVariableName() -> String {
        let n = freshCounter.next()!
        return ".v\(n)"
    }
    
    public func plan(query: Query, activeGraph: Term? = nil) throws -> QueryPlan {
        let costEstimator = QueryPlanSimpleCostEstimator()
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
            let ps = try plan(algebra: algebra, activeGraph: activeGraph, estimator: costEstimator)
            let p = try bestPlan(ps, estimator: costEstimator)
            plans.append(p)
        }

        guard let f = plans.first else {
            throw QueryPlannerError.noPlanAvailable
        }
        
        let p = plans.dropFirst().reduce(f) { UnionPlan(lhs: $0, rhs: $1) }
        if verbose {
            warn("QueryPlanner plan: " + p.serialize(depth: 0))
        }

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
    
    private func reduceQuadJoins<E: QueryPlanCostEstimator>(_ plan: QueryPlan, rest tail: [QuadPattern], currentVariables: Set<String>, estimator: E) throws -> [QueryPlan] {
        // TODO: this is currently doing all possible permutations of [rest]; that's going to be prohibitive on large BGPs; use heuristics or something like IDP
        guard !tail.isEmpty else {
            return [plan]
        }
        
        var plans = [QueryPlan]()
        for i in tail.indices {
            var intermediate = [QueryPlan]()
            let q = tail[i]
            var rest = tail
            rest.remove(at: i)
            let qp = QuadPlan(quad: q, store: store)
            let tv = q.variables
            let i = currentVariables.intersection(tv)
            intermediate.append(NestedLoopJoinPlan(lhs: plan, rhs: qp))
            if !i.isEmpty {
                intermediate.append(HashJoinPlan(lhs: plan, rhs: qp, joinVariables: i))
            }
            
            let u = currentVariables.union(tv)
            for p in intermediate {
                let j = try reduceQuadJoins(p, rest: rest, currentVariables: u, estimator: estimator)
                plans.append(contentsOf: j)
            }
        }
        return candidatePlans(plans, estimator: estimator)
    }
    
    func plan<E: QueryPlanCostEstimator>(bgp: [TriplePattern], activeGraph g: Node, estimator: E) throws -> [QueryPlan] {
        let proj = Algebra.bgp(bgp).inscope
        let quadPatterns = bgp.map { (t) in
            return QuadPattern(triplePattern: t, graph: g).bindingAllVariables
        }

        guard let firstQuad = quadPatterns.first else {
            throw QueryPlannerError.noPlanAvailable
        }
        let restQuads = Array(quadPatterns.dropFirst())
        var vars = firstQuad.variables
        for qp in restQuads {
            vars.formUnion(qp.variables)
        }

        let qp = QuadPlan(quad: firstQuad, store: store)
        let plans = try reduceQuadJoins(qp, rest: restQuads, currentVariables: firstQuad.variables, estimator: estimator)
//        print("Got \(plans.count) possible BGP join plans...")
        if vars == proj {
            return plans
        } else {
            // binding variables were introduced to allow the join to be performed,
            // but they shouldn't escape the BGP evaluation, so introduce an extra projection
            return plans.map { ProjectPlan(child: $0, variables: Set(proj)) }
        }
    }

    private func candidatePlans<E: QueryPlanCostEstimator>(_ plans: [QueryPlan], estimator: E) -> [QueryPlan] {
        if plans.count > self.maxInFlightPlans {
            let sorted = plans.sorted { (lhs, rhs) -> Bool in
                return estimator.cheaperThan(lhs: lhs, rhs: rhs)
            }
            return Array(sorted.prefix(self.maxInFlightPlans))
        } else {
            return plans
        }
    }
    
    private func bestPlan<E: QueryPlanCostEstimator>(_ plans: [QueryPlan], estimator: E) throws -> QueryPlan {
        guard let p = plans.min(by: { estimator.cheaperThan(lhs: $0, rhs: $1) }) else {
            throw QueryPlannerError.noPlanAvailable
        }
        return p
    }
    
    public func plan<E: QueryPlanCostEstimator>(algebra: Algebra, activeGraph: Term, estimator: E) throws -> [QueryPlan] {
        if allowStoreOptimizedPlans {
            if let ps = store as? PlanningQuadStore {
                do {
                    if let p = try ps.plan(algebra: algebra, activeGraph: activeGraph, dataset: dataset) {
                        return [p]
                    }
                } catch {}
            }
        }
        
        switch algebra {
        // don't require access to the underlying store:
        case let .subquery(q):
            return try [plan(query: q, activeGraph: activeGraph)]
        case .unionIdentity:
            return [TablePlan.unionIdentity]
        case .joinIdentity:
            return [TablePlan.joinIdentity]
        case let .table(names, rows):
            return [TablePlan(columns: names, rows: rows)]
        case let .innerJoin(lhs, rhs):
            let i = lhs.inscope.intersection(rhs.inscope)
            let lplans = try plan(algebra: lhs, activeGraph: activeGraph, estimator: estimator)
            let rplans = try plan(algebra: rhs, activeGraph: activeGraph, estimator: estimator)
            var plans = [QueryPlan]()
            for l in lplans {
                for r in rplans {
                    plans.append(NestedLoopJoinPlan(lhs: l, rhs: r))
                    plans.append(NestedLoopJoinPlan(lhs: r, rhs: l))
                    if !i.isEmpty {
                        plans.append(HashJoinPlan(lhs: l, rhs: r, joinVariables: i))
                        plans.append(HashJoinPlan(lhs: r, rhs: l, joinVariables: i))
                    }
                }
            }
            return candidatePlans(plans, estimator: estimator)
        case let .leftOuterJoin(lhs, rhs, expr):
            let fijplans = try plan(algebra: .filter(.innerJoin(lhs, rhs), expr), activeGraph: activeGraph, estimator: estimator)
            let lplans = try plan(algebra: lhs, activeGraph: activeGraph, estimator: estimator)
            let rplans = try plan(algebra: rhs, activeGraph: activeGraph, estimator: estimator)
            var plans = [QueryPlan]()
            let (e, mapping) = try expr.removingExistsExpressions(namingVariables: &freshCounter)
            print("*** TODO: handle query planning of EXISTS expressions in OPTIONAL: \(e)")
            for fij in fijplans {
                for l in lplans {
                    for r in rplans {
                        // TODO: add mapping to algebra (determine the right semantics for this with diff)
                        let diff : QueryPlan = DiffPlan(lhs: l, rhs: r, expression: e, evaluator: evaluator)
                        plans.append(UnionPlan(lhs: fij, rhs: diff))
                    }
                }
            }
            return candidatePlans(plans, estimator: estimator)
        case let .union(lhs, rhs):
            let branches = algebra.unionBranches()
            let branchPlans = try branches.map { try plan(algebra: $0, activeGraph: activeGraph, estimator: estimator) }
            let plans = try self.planBushyUnionProduct(branches: branchPlans, estimator: estimator)
            
//            let lplans = try plan(algebra: lhs, activeGraph: activeGraph, estimator: estimator)
//            let rplans = try plan(algebra: rhs, activeGraph: activeGraph, estimator: estimator)
//            var plans = [QueryPlan]()
//            for l in lplans {
//                for r in rplans {
//                    plans.append(UnionPlan(lhs: l, rhs: r))
//                }
//            }
            return candidatePlans(plans, estimator: estimator)
        case let .project(child, vars):
            let p = try plan(algebra: child, activeGraph: activeGraph, estimator: estimator)
            if child.inscope == vars {
                return p
            } else {
                return p.map { ProjectPlan(child: $0, variables: vars) }
            }
        case let .slice(.order(child, orders), nil, .some(limit)):
            let p = try plan(algebra: child, activeGraph: activeGraph, estimator: estimator)
            return p.map { HeapSortLimitPlan(child: $0, comparators: orders, limit: limit, evaluator: self.evaluator) }
        case let .slice(.order(child, orders), .some(offset), .some(limit)):
            let p = try plan(algebra: child, activeGraph: activeGraph, estimator: estimator)
            return p.map { (p) -> QueryPlan in
                let hs = HeapSortLimitPlan(child: p, comparators: orders, limit: limit+offset, evaluator: self.evaluator)
                return OffsetPlan(child: hs, offset: offset)
            }
        case let .slice(child, offset, limit):
            let plans = try plan(algebra: child, activeGraph: activeGraph, estimator: estimator)
            switch (offset, limit) {
            case let (.some(offset), .some(limit)):
                return plans.map { LimitPlan(child: OffsetPlan(child: $0, offset: offset), limit: limit) }
            case (.some(let offset), _):
                return plans.map { OffsetPlan(child: $0, offset: offset) }
            case (_, .some(let limit)):
                return plans.map { LimitPlan(child: $0, limit: limit) }
            default:
                return plans
            }
            //NextRowPlan
        case let .extend(child, .exists(algebra), name):
            var pplans = try plan(algebra: child, activeGraph: activeGraph, estimator: estimator)
            if case .extend(_) = child {
            } else {
                // at the bottom of a chain of one or more extend()s, add a NextRow plan
                pplans = pplans.map { NextRowPlan(child: $0, evaluator: evaluator) }
            }
            let patplans = try plan(algebra: algebra, activeGraph: activeGraph, estimator: estimator)
            var plans = [QueryPlan]()
            for p in pplans {
                for pat in patplans {
                    plans.append(ExistsPlan(child: p, pattern: pat, variable: name, patternAlgebra: algebra))
                }
            }
            return candidatePlans(plans, estimator: estimator)
        case let .extend(child, expr, name):
            let (e, mapping) = try expr.removingExistsExpressions(namingVariables: &freshCounter)
            let pplans = try plan(algebra: child, activeGraph: activeGraph, estimator: estimator).map { (pp) -> QueryPlan in
                var p = pp
                switch child {
                case .extend:
                    // we're in the middle of several extend()s
                    break
                default:
                    // at the bottom of a chain of one or more extend()s, add a NextRow plan
                    p = NextRowPlan(child: p, evaluator: evaluator)
                }
                try mapping.forEach { (name, algebra) throws in
                    let patplans = try plan(algebra: algebra, activeGraph: activeGraph, estimator: estimator)
                    guard let pat = patplans.first else {
                        throw QueryPlannerError.noPlanAvailable
                    }
                    p = ExistsPlan(child: p, pattern: pat, variable: name, patternAlgebra: algebra)
                }
                return p
            }
            
            if mapping.isEmpty {
                return pplans.map { ExtendPlan(child: $0, expression: e, variable: name, evaluator: evaluator) }
            } else {
                let vars = child.inscope
                return pplans.map { (p) -> QueryPlan in
                    let extend = ExtendPlan(child: p, expression: e, variable: name, evaluator: evaluator)
                    return ProjectPlan(child: extend, variables: vars.union([name]))
                }
            }
        case let .order(child, orders):
            let p = try plan(algebra: child, activeGraph: activeGraph, estimator: estimator)
            return p.map { OrderPlan(child: $0, comparators: orders, evaluator: evaluator) }
        case let .aggregate(child, groups, aggs):
            let p = try plan(algebra: child, activeGraph: activeGraph, estimator: estimator)
            return try p.map { try AggregationPlan(child: $0, groups: groups, aggregates: aggs) }
        case let .window(child, funcs):
            guard funcs.count == 1, let f = funcs.first else {
                let pp = funcs.reduce(child) { Algebra.window($0, [$1]) }
                return try plan(algebra: pp, activeGraph: activeGraph, estimator: estimator)
            }
            let pplans = try plan(algebra: child, activeGraph: activeGraph, estimator: estimator)
            
            let app = f.windowApplication
            let partitionComparators = app.partition.map { Algebra.SortComparator(ascending: true, expression: $0) }
            let orderComparators = app.comparators
            
            var plans = [QueryPlan]()
            for p in pplans {
                let sorted = OrderPlan(
                    child: p,
                    comparators: partitionComparators + orderComparators,
                    evaluator: evaluator
                )
                plans.append(WindowPlan(child: sorted, function: f, evaluator: evaluator))
            }
            return candidatePlans(plans, estimator: estimator)
        case let .filter(child, expr):
            let (e, mapping) = try expr.removingExistsExpressions(namingVariables: &freshCounter)
            let pplans = try plan(algebra: child, activeGraph: activeGraph, estimator: estimator).map { (pp) -> QueryPlan in
                var p = pp
                try mapping.forEach { (name, algebra) throws in
                    let patplans = try plan(algebra: algebra, activeGraph: activeGraph, estimator: estimator)
                    guard let pat = patplans.first else {
                        throw QueryPlannerError.noPlanAvailable
                    }
                    p = ExistsPlan(child: p, pattern: pat, variable: name, patternAlgebra: algebra)
                }
                p = NextRowPlan(child: p, evaluator: evaluator)
                return p
            }
            
            if mapping.isEmpty {
                return pplans.map { FilterPlan(child: $0, expression: e, evaluator: evaluator) }
            } else {
                return pplans.map { (p) -> QueryPlan in
                    let filter = FilterPlan(child: p, expression: e, evaluator: evaluator)
                    return ProjectPlan(child: filter, variables: child.inscope)
                }
            }
        case let .distinct(child):
            let p = try plan(algebra: child, activeGraph: activeGraph, estimator: estimator)
            return p.map { DistinctPlan(child: $0) }
        case let .reduced(child):
            let p = try plan(algebra: child, activeGraph: activeGraph, estimator: estimator)
            return p.map { ReducedPlan(child: $0) }
        case .bgp(let patterns):
            let plans = try plan(bgp: patterns, activeGraph: .bound(activeGraph), estimator: estimator)
            return candidatePlans(plans, estimator: estimator)
        case let .minus(lhs, rhs):
            let lplans = try plan(algebra: lhs, activeGraph: activeGraph, estimator: estimator)
            let rplans = try plan(algebra: rhs, activeGraph: activeGraph, estimator: estimator)
            var plans = [QueryPlan]()
            for l in lplans {
                for r in rplans {
                    plans.append(MinusPlan(lhs: l, rhs: r))
                }
            }
            return candidatePlans(plans, estimator: estimator)
        case let .service(endpoint, algebra, silent):
            let s = SPARQLSerializer(prettyPrint: true)
            guard let q = try? Query(form: .select(.star), algebra: algebra) else {
                throw QueryError.evaluationError("Failed to serialize SERVICE algebra into SPARQL string")
            }
            let tokens = try q.sparqlTokens()
            let query = s.serialize(tokens)
            let client: SPARQLClient
            if let c = serviceClients[endpoint] {
                client = c
            } else {
                client = SPARQLClient(endpoint: endpoint, silent: silent)
                serviceClients[endpoint] = client
            }
            return [ServicePlan(endpoint: endpoint, query: query, silent: silent, client: client)]
        case let .namedGraph(child, .bound(g)):
            return try plan(algebra: child, activeGraph: g, estimator: estimator)
        case let .namedGraph(child, .variable(graph, binding: _)):
            // TODO: handle multiple query plans from child
            if case .joinIdentity = child {
                let rows = dataset.namedGraphs.map { [$0] }
                let table = TablePlan(columns: [.variable(graph, binding: true)], rows: rows)
                return [table]
            }
            
            let branches = try dataset.namedGraphs.map { (g) throws -> QueryPlan in
                let pplans = try plan(algebra: child, activeGraph: g, estimator: estimator)
                guard let p = pplans.first else {
                    throw QueryPlannerError.noPlanAvailable
                }
                if p.isJoinIdentity {
                    return p
                } else {
                    let table = TablePlan(columns: [.variable(graph, binding: true)], rows: [[g]])
                    if child.inscope.contains(graph) {
                        return HashJoinPlan(lhs: p, rhs: table, joinVariables: [graph])
                    } else {
                        return NestedLoopJoinPlan(lhs: p, rhs: table)
                    }
                }
            }
            let branchPlans = branches.map { [$0] }
            let plans = try self.planBushyUnionProduct(branches: branchPlans, estimator: estimator)
            return candidatePlans(plans, estimator: estimator)


//            guard let first = branches.first else {
//                return [TablePlan(columns: [], rows: [])]
//            }
//            let p = branches.dropFirst().reduce(first) { UnionPlan(lhs: $0, rhs: $1) }
//            return [p]
        case let .triple(t):
            let quad = QuadPattern(subject: t.subject, predicate: t.predicate, object: t.object, graph: .bound(activeGraph))
            let plans = try plan(algebra: .quad(quad), activeGraph: activeGraph, estimator: estimator)
            return plans
        case let .quad(quad):
            return [QuadPlan(quad: quad, store: store)]
        case let .path(s, path, o):
            let pathPlan = try plan(subject: s, path: path, object: o, activeGraph: activeGraph, estimator: estimator)
            return [PathQueryPlan(subject: s, path: pathPlan, object: o, graph: activeGraph)]
        }
    }

    func planBushyUnionProduct<E: QueryPlanCostEstimator>(branches: [[QueryPlan]], estimator: E) throws -> [QueryPlan] {
        guard !branches.isEmpty else {
            throw QueryPlannerError.noPlanAvailable
        }
        guard branches.count > 1 else {
            return branches[0]
        }
        
        var branches = branches
        if !branches.count.isMultiple(of: 2) {
            branches.append([TablePlan.unionIdentity])
        }
        let pairs = stride(from: 0, to: branches.endIndex, by: 2).map {
            (branches[$0], branches[$0.advanced(by: 1)])
        }
        
        var reduced = [[QueryPlan]]()
        for (lplans, rplans) in pairs {
            var plans = [QueryPlan]()
            for l in lplans {
                for r in rplans {
                    if l.isUnionIdentity {
                        plans.append(r)
                    } else if r.isUnionIdentity {
                        plans.append(l)
                    } else {
                        let plan = UnionPlan(lhs: l, rhs: r)
    //                    print(plan.serialize())
                        plans.append(plan)
                    }
                }
            }
            if plans.isEmpty {
                plans.append(TablePlan.unionIdentity)
            }
            reduced.append(plans)
        }
        
        return try self.planBushyUnionProduct(branches: reduced, estimator: estimator)
    }
    
    public func plan<E: QueryPlanCostEstimator>(subject s: Node, path: PropertyPath, object o: Node, activeGraph: Term, estimator: E) throws -> PathPlan {
        switch path {
        case .link(let predicate):
            return LinkPathPlan(predicate: predicate, store: store)
        case .inv(let ipath):
            let p = try plan(subject: o, path: ipath, object: s, activeGraph: activeGraph, estimator: estimator)
            return InversePathPlan(child: p)
        case let .alt(lhs, rhs):
            let l = try plan(subject: s, path: lhs, object: o, activeGraph: activeGraph, estimator: estimator)
            let r = try plan(subject: s, path: rhs, object: o, activeGraph: activeGraph, estimator: estimator)
            return UnionPathPlan(lhs: l, rhs: r)
        case let .seq(lhs, rhs):
            let j = freshVariable()
            let l = try plan(subject: s, path: lhs, object: j, activeGraph: activeGraph, estimator: estimator)
            let r = try plan(subject: j, path: rhs, object: o, activeGraph: activeGraph, estimator: estimator)
            return SequencePathPlan(lhs: l, joinNode: j, rhs: r)
        case .nps(let iris):
            return NPSPathPlan(iris: iris, store: store)
        case .plus(let pp):
            let p = try plan(subject: s, path: pp, object: o, activeGraph: activeGraph, estimator: estimator)
            return PlusPathPlan(child: p, store: store)
        case .star(let pp):
            let p = try plan(subject: s, path: pp, object: o, activeGraph: activeGraph, estimator: estimator)
            return StarPathPlan(child: p, store: store)
        case .zeroOrOne(let pp):
            let p = try plan(subject: s, path: pp, object: o, activeGraph: activeGraph, estimator: estimator)
            return ZeroOrOnePathPlan(child: p, store: store)
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

public struct QueryPlanEvaluator<Q: QuadStoreProtocol>: QueryEvaluatorProtocol {
    public typealias ResultSequence = AnySequence<TermResult>
    public typealias TripleSequence = [Triple]

    public let supportedLanguages: [QueryLanguage] = [.sparqlQuery10, .sparqlQuery11]
    public let supportedFeatures: [QueryEngineFeature] = [.basicFederatedQuery]

    var dataset: Dataset
    public var planner: QueryPlanner<Q>
    
    public init(planner: QueryPlanner<Q>) {
        self.dataset = planner.dataset
        self.planner = planner
    }
    
    public init(store: Q, dataset: Dataset, base: String? = nil) {
        self.dataset = dataset
        self.planner = QueryPlanner(store: store, dataset: dataset, base: base)
    }
    
    public func evaluate(query: Query) throws -> QueryResult<AnySequence<TermResult>, [Triple]> {
        return try evaluate(query: query, activeGraph: nil)
    }
    
    public func evaluate(query: Query, activeGraph graph: Term? = nil) throws -> QueryResult<AnySequence<TermResult>, [Triple]> {
        let rewriter = SPARQLQueryRewriter()
        let q = try rewriter.simplify(query: query)
        let plan = try planner.plan(query: q, activeGraph: graph)
//        print("Query Plan:")
//        print(plan.serialize())
        
        let seq = AnySequence { () -> AnyIterator<TermResult> in
            do {
                let i = try plan.evaluate()
                return i
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
        case .construct(let template):
            var triples = Set<Triple>()
            for r in seq {
                for tp in template {
                    do {
                        let replaced = try tp.replace { (n) -> Node? in
                            guard case .variable(let name, _) = n else { return nil }
                            if let t = r[name] {
                                return .bound(t)
                            }
                            return nil
                        }
                        if let ground = replaced.ground {
                            triples.insert(ground)
                        }
                    } catch {}
                }
            }
            return QueryResult.triples(Array(triples))
        case .describe(_):
            throw QueryPlanError.unimplemented("DESCRIBE")
        }
    }
}
