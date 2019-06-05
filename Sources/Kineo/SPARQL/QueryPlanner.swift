//
//  QueryPlanner.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 1/15/19.
//

import Foundation
import SPARQLSyntax
import DiomedeQuadStore

public enum QueryPlannerError: Error {
    case noPlanAvailable
    case termNotFound
}

extension QuadPattern {
    var inscope: Set<String> {
        var variables = Set<String>()
        for node in [self.subject, self.predicate, self.object, self.graph] {
            if case .variable(let name, true) = node {
                variables.insert(name)
            }
        }
        return variables
    }
    
    func repeatedVariables() -> [String : Set<Int>] {
        let variableUsage = self.variablePositions()
        let dups = variableUsage.filter { (u) -> Bool in u.value.count > 1 }
        return dups
    }
    
    func variablePositions() -> [String: Set<Int>] {
        var variableUsage = [String: Set<Int>]()
        for (i, n) in self.enumerated() {
            switch n {
            case .bound(_):
                break
            case .variable(let name, binding: _):
                variableUsage[name, default: []].insert(i)
            }
        }
        return variableUsage
    }
    
    func idquad(for store: LazyMaterializingQuadStore) throws -> IDQuad {
        let s = try self.subject.idnode(for: store)
        let p = try self.predicate.idnode(for: store)
        let o = try self.object.idnode(for: store)
        let g = try self.graph.idnode(for: store)
        return IDQuad(subject: s, predicate: p, object: o, graph: g)
    }
}

extension Node {
    func idnode(for store: LazyMaterializingQuadStore) throws -> IDNode {
        switch self {
        case .bound(let term):
            guard let tid = try store.id(for: term) else {
                throw QueryPlannerError.termNotFound
            }
            return .bound(tid)
        case let .variable(name, binding: binding):
            return .variable(name, binding: binding)
        }
    }
}

extension Array where Element: Equatable {
    func sharedPrefix(with other: [Element]) -> [Element] {
        var result = [Element]()
        for (l, r) in zip(self, other) {
            if l == r {
                result.append(l)
            } else {
                break
            }
        }
        return result
    }
}

extension Quad.Position {
    func bindingVariable(in qp: QuadPattern) -> String? {
        let node = qp[self]
        if case .variable(let name, _) = node {
            return name
        } else {
            return nil
        }
    }
}
public protocol PlanningQuadStore: QuadStoreProtocol {
    func plan(algebra: Algebra, activeGraph: Term, dataset: Dataset) throws -> QueryPlan?
}

public class QueryPlanner<Q: QuadStoreProtocol> {
    public var allowStoreOptimizedPlans: Bool
    public var allowLazyIDPlans: Bool
    public var store: Q
    public var verbose: Bool
    public var dataset: Dataset
    public var evaluator: ExpressionEvaluator
    private var freshCounter: UnfoldSequence<Int, (Int?, Bool)>
    public var maxInFlightPlans: Int
    var serviceClients: [URL:SPARQLClient]

    enum PlanResult {
        case termPlan(QueryPlan)
        case idPlan(QueryPlan)
    }
    
    public init(store: Q, dataset: Dataset, base: String? = nil) {
        self.store = store
        self.dataset = dataset
        self.evaluator = ExpressionEvaluator(base: base)
        self.freshCounter = sequence(first: 1) { $0 + 1 }
        self.allowStoreOptimizedPlans = true
        self.allowLazyIDPlans = true
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
    
    func project(plan: QueryPlan, to variables: Set<String>) throws -> QueryPlan {
        if let store = _lazyStore(), let plan = plan as? MaterializeTermsPlan {
            if let p = plan.idPlan as? IDProjectPlan {
                let child = p.child
                let vars = p.variables.intersection(variables)
                let proj = IDProjectPlan(child: child, variables: vars)
                return MaterializeTermsPlan(idPlan: proj, store: store, verbose: self.verbose)
            }

            let proj = IDProjectPlan(child: plan.idPlan, variables: variables)
            return MaterializeTermsPlan(idPlan: proj, store: store, verbose: self.verbose)
        }
        
        if let p = plan as? ProjectPlan {
            let child = p.child
            let vars = p.variables.intersection(variables)
            return ProjectPlan(child: child, variables: vars)
        }
        
        return ProjectPlan(child: plan, variables: Set(variables))
    }
    
    func wrap(plan p: QueryPlan, from algebra: Algebra, for query: Query) throws -> QueryPlan {
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
            
            let from = algebra.inscope
            let to = Set(proj)
            if from == to {
                return p
            } else {
//                print("adding final projection:")
//                print("from: \(from)")
//                print("to  : \(proj.sorted())")
                return try self.project(plan: p, to: Set(proj))
            }
        case .ask, .construct(_), .describe(_):
            return p
        }
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
        //        if verbose {
        //            warn("QueryPlanner plan: " + p.serialize(depth: 0))
        //        }
        return try wrap(plan: p, from: algebra, for: query)
    }
    
    func unionCartesians(for plans: [[QueryPlan]]) throws -> [QueryPlan] {
        guard !plans.isEmpty else { return [] }
        if plans.count == 1 {
            return plans[0]
        }
        
        guard let f = plans.first else {
            throw QueryPlannerError.noPlanAvailable
        }
        
        let rest = try unionCartesians(for: Array(plans.dropFirst()))
        var plans = [QueryPlan]()
        for lhs in f {
            for rhs in rest {
                let p = UnionPlan(lhs: lhs, rhs: rhs)
                plans.append(p)
            }
        }
        
        return plans
    }
    
    public func plans(query: Query, activeGraph: Term? = nil) throws -> [QueryPlan] {
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
        
        var planOptions = [[QueryPlan]]()
        for activeGraph in graphs {
            let ps = try plan(algebra: algebra, activeGraph: activeGraph, estimator: costEstimator)
            planOptions.append(ps)
        }
        
        let plans = try unionCartesians(for: planOptions)
        //        if verbose {
        //            warn("QueryPlanner plan: " + p.serialize(depth: 0))
        //        }
        return try plans.sorted(by: { costEstimator.cheaperThan(lhs: $0, rhs: $1) }).map {
            try wrap(plan: $0, from: algebra, for: query)
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

    private func reduceIDQuadJoins<E: QueryPlanCostEstimator>(_ plan: IDQueryPlan, ordered orderVars: [String], rest tail: [QuadPattern], currentVariables: Set<String>, estimator: E) throws -> [MaterializeTermsPlan] {
        guard let store = _lazyStore() else {
            throw QueryPlannerError.noPlanAvailable
        }
        
        // TODO: this is currently doing all possible permutations of [rest]; that's going to be prohibitive on large BGPs; use heuristics or something like IDP
        guard !tail.isEmpty else {
            let matplan = MaterializeTermsPlan(idPlan: plan, store: store, verbose: verbose)
            return [matplan]
        }
        
        var plans = [QueryPlan]()
        for i in tail.indices {
            var intermediate = [(IDQueryPlan, [String])]()
            let q = tail[i]
            var rest = tail
            rest.remove(at: i)

            // TODO: also consider "interesting" orders (e.g. idplans that have been explicityly sorted to a join variable)
            for (nextOrder, fullOrder) in try store.availableOrders(matching: q) {
                let qp = IDOrderedQuadPlan(quad: q, order: fullOrder, store: store)
                let nextOrderVars = nextOrder.map { $0.bindingVariable(in: q) }.prefix { $0 != nil }.compactMap { $0 }
                let sharedOrder = nextOrderVars.sharedPrefix(with: orderVars)

                if !sharedOrder.isEmpty {
                    let plan = IDMergeJoinPlan(lhs: plan, rhs: qp, variables: sharedOrder)
                    intermediate.append((plan, sharedOrder))
                }
            }
            
            let rv = q.repeatedVariables()
            let idquad = try q.idquad(for: store)
            let qp : IDQueryPlan = IDQuadPlan(pattern: idquad, repeatedVariables: rv, store: store)
            let tv = q.variables
            let i = currentVariables.intersection(tv)
            intermediate.append((IDNestedLoopJoinPlan(lhs: plan, rhs: qp), []))
            if !i.isEmpty {
                let hashJoinPlan = IDHashJoinPlan(lhs: plan, rhs: qp, joinVariables: i)
                intermediate.append((hashJoinPlan, orderVars)) // hashjoin keeps the order of the LHS
                
                var bindings = [String: WritableKeyPath<IDQuad, IDNode>]()
                for name in i {
                    if case .variable(name, _) = q.subject {
                        bindings[name] = \IDQuad.subject
                    }
                    if case .variable(name, _) = q.predicate {
                        bindings[name] = \IDQuad.predicate
                    }
                    if case .variable(name, _) = q.object {
                        bindings[name] = \IDQuad.object
                    }
                    if case .variable(name, _) = q.graph {
                        bindings[name] = \IDQuad.graph
                    }
                }
                
                let bindPlan = IDIndexBindQuadPlan(child: plan, pattern: idquad, bindings: bindings, repeatedVariables: rv, store: store)
                intermediate.append((bindPlan, orderVars)) // bind join keeps the order of the LHS
            }
            
            let u = currentVariables.union(tv)
            for (p, sharedOrder) in intermediate {
                let matplans = try reduceIDQuadJoins(p, ordered: sharedOrder, rest: rest, currentVariables: u, estimator: estimator)
                plans.append(contentsOf: matplans)
            }
        }
        
        let candidates = candidatePlans(plans, estimator: estimator)
        return candidates as! [MaterializeTermsPlan]
    }
    
    internal func _lazyStore() -> LazyMaterializingQuadStore? {
        guard self.allowLazyIDPlans else { return nil }
        
        // if we can do partial query evaluation using just term IDs, and delay materialization of term values,
        // return the LazyMaterializingQuadStore store object to be used for such purposes here.
        if let s = store as? LazyMaterializingQuadStore {
            return s
        } else if let aqs = store as? AnyQuadStore {
            if let s = aqs._store as? LazyMaterializingQuadStore {
                return s
            }
        } else if let ams = store as? AnyMutableQuadStore {
            if let s = ams._store as? LazyMaterializingQuadStore {
                return s
            }
        }
        return nil
    }
    
    struct OrderedIDQuadPlan {
        var plan: IDQuadPlan
        var order: [Quad.Position]
    }
    
    func idPlans<E: QueryPlanCostEstimator>(for patterns: [QuadPattern], in store: LazyMaterializingQuadStore, estimator: E) throws -> [MaterializeTermsPlan] {
        guard let store = _lazyStore() else {
            throw QueryPlannerError.noPlanAvailable
        }
        guard let firstQuad = patterns.first else {
            throw QueryPlannerError.noPlanAvailable
        }
        let restQuads = Array(patterns.dropFirst())
        
        if true {
            // this will generate many join order permutations
            var plans = [MaterializeTermsPlan]()
            // TODO: also consider "interesting" orders (e.g. idplans that have been explicityly sorted to a join variable)
            for (order, fullOrder) in try store.availableOrders(matching: firstQuad) {
                let orderVars = order.map { $0.bindingVariable(in: firstQuad) }.prefix { $0 != nil }.compactMap { $0 }
                let idplan = IDOrderedQuadPlan(quad: firstQuad, order: fullOrder, store: store)
                try plans.append(contentsOf: reduceIDQuadJoins(idplan, ordered: orderVars, rest: restQuads, currentVariables: firstQuad.variables, estimator: estimator))
            }
            return plans
        }
    }
    
    func plan<E: QueryPlanCostEstimator>(bgp: [TriplePattern], activeGraph g: Node, estimator: E) throws -> [QueryPlan] {
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

        var plans = [QueryPlan]()
        if let s = _lazyStore() {
            do {
                let idplans = try idPlans(for: quadPatterns, in: s, estimator: estimator)
                plans.append(contentsOf: idplans)
            } catch QueryPlannerError.termNotFound {
                // in cases where we can tell during planning that no data will match
                plans.append(TablePlan.unionIdentity)
            }
        }
        
        let qp = QuadPlan(quad: firstQuad, store: store)
        try plans.append(contentsOf: reduceQuadJoins(qp, rest: restQuads, currentVariables: firstQuad.variables, estimator: estimator))
        
//        print("Got \(plans.count) possible BGP join plans...")
        let proj = Algebra.bgp(bgp).inscope
        if vars == proj {
            return plans
        } else {
            // binding variables were introduced to allow the join to be performed,
            // but they shouldn't escape the BGP evaluation, so introduce an extra projection
            let variables = Set(proj)
            return try plans.map { try self.project(plan: $0, to: variables) }
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
    
    public func allAvailableJoins(lhs l: QueryPlan, rhs r: QueryPlan, intersection i: Set<String>) -> [QueryPlan] {
        var plans = [QueryPlan]()
        if let store = _lazyStore(), let lhs = l as? MaterializeTermsPlan, let rhs = r as? MaterializeTermsPlan {
            // id plans
            let l = lhs.idPlan
            let r = rhs.idPlan

            var idplans = [IDQueryPlan]()
            idplans.append(IDNestedLoopJoinPlan(lhs: l, rhs: r))
            idplans.append(IDNestedLoopJoinPlan(lhs: r, rhs: l))
            if !i.isEmpty {
                idplans.append(IDHashJoinPlan(lhs: l, rhs: r, joinVariables: i))
                idplans.append(IDHashJoinPlan(lhs: r, rhs: l, joinVariables: i))
            }
            plans.append(contentsOf: idplans.map {
                MaterializeTermsPlan(idPlan: $0, store: store, verbose: verbose)
            })
        }
        
        // materialized plans
        plans.append(NestedLoopJoinPlan(lhs: l, rhs: r))
        plans.append(NestedLoopJoinPlan(lhs: r, rhs: l))
        if !i.isEmpty {
            plans.append(HashJoinPlan(lhs: l, rhs: r, joinVariables: i))
            plans.append(HashJoinPlan(lhs: r, rhs: l, joinVariables: i))
        }

        return plans
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
                    plans.append(contentsOf: self.allAvailableJoins(lhs: l, rhs: r, intersection: i))
                }
            }
            return candidatePlans(plans, estimator: estimator)
        case let .leftOuterJoin(lhs, rhs, expr):
            let lplans = try plan(algebra: lhs, activeGraph: activeGraph, estimator: estimator)
            let rplans = try plan(algebra: rhs, activeGraph: activeGraph, estimator: estimator)
            let i = lhs.inscope.intersection(rhs.inscope)
            var plans = [QueryPlan]()

            let fijplans: [QueryPlan]
            if case .node(.bound(Term.trueValue)) = expr {
                // there is no top-level filter in the RHS of the OPTIONAL
                fijplans = try plan(algebra: .innerJoin(lhs, rhs), activeGraph: activeGraph, estimator: estimator)
            } else {
                fijplans = try plan(algebra: .filter(.innerJoin(lhs, rhs), expr), activeGraph: activeGraph, estimator: estimator)
            }

            if let store = self._lazyStore(),
                case .node(.bound(Term.trueValue)) = expr {
                for l in lplans {
                    for r in rplans {
                        if let lhs = l as? MaterializeTermsPlan, let rhs = r as? MaterializeTermsPlan {
                            if !i.isEmpty {
                                let lhjoin = IDHashLeftJoinPlan(lhs: lhs.idPlan, rhs: rhs.idPlan, joinVariables: i)
                                plans.append(MaterializeTermsPlan(idPlan: lhjoin, store: store, verbose: verbose))
                            }
                            
                            let lnljoin = IDNestedLoopJoinPlan(lhs: lhs.idPlan, rhs: rhs.idPlan)
                            let diff : IDQueryPlan = IDDiffPlan(lhs: lhs.idPlan, rhs: rhs.idPlan)
                            let union = IDUnionPlan(lhs: lnljoin, rhs: diff)
                            plans.append(MaterializeTermsPlan(idPlan: union, store: store, verbose: verbose))
                        } else {
                            for fij in fijplans {
                                let diff : QueryPlan = DiffPlan(lhs: l, rhs: r, expression: expr, evaluator: evaluator)
                                plans.append(UnionPlan(lhs: fij, rhs: diff))
                            }
                        }
                    }
                }
            } else {
                let (e, mapping) = try expr.removingExistsExpressions(namingVariables: &freshCounter)
                if !mapping.isEmpty {
                    print("*** TODO: handle query planning of EXISTS expressions in OPTIONAL: \(e) with mapping \(mapping)")
                }
                for fij in fijplans {
                    for l in lplans {
                        for r in rplans {
                            // TODO: add mapping to algebra (determine the right semantics for this with diff)
                            let diff : QueryPlan = DiffPlan(lhs: l, rhs: r, expression: e, evaluator: evaluator)
                            plans.append(UnionPlan(lhs: fij, rhs: diff))
                        }
                    }
                }
            }
            return candidatePlans(plans, estimator: estimator)
        case .union:
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
                return try p.map { try self.project(plan: $0, to: vars) }
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
                return plans.map { (child) -> QueryPlan in
                    if let store = self._lazyStore(), let c = child as? MaterializeTermsPlan {
                        return MaterializeTermsPlan(idPlan: IDLimitPlan(child: IDOffsetPlan(child: c.idPlan, offset: offset), limit: limit), store: store, verbose: verbose)
                    } else {
                        return LimitPlan(child: OffsetPlan(child: child, offset: offset), limit: limit)
                    }
                }
            case (.some(let offset), _):
                return plans.map { (child) -> QueryPlan in
                    if let store = self._lazyStore(), let c = child as? MaterializeTermsPlan {
                        return MaterializeTermsPlan(idPlan: IDOffsetPlan(child: c.idPlan, offset: offset), store: store, verbose: verbose)
                    } else {
                        return OffsetPlan(child: child, offset: offset)
                    }
                }
            case (_, .some(let limit)):
                return plans.map { (child) -> QueryPlan in
                    if let store = self._lazyStore(), let c = child as? MaterializeTermsPlan {
                        return MaterializeTermsPlan(idPlan: IDLimitPlan(child: c.idPlan, limit: limit), store: store, verbose: verbose)
                    } else {
                        return LimitPlan(child: child, limit: limit)
                    }
                }
            default:
                return plans
            }
            //NextRowPlan
        case let .extend(child, .exists(algebra), name):
            var pplans = try plan(algebra: child, activeGraph: activeGraph, estimator: estimator)
            if case .extend = child {
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
            // TODO: handle multiple query plans from child
            let pplans = try plan(algebra: child, activeGraph: activeGraph, estimator: estimator)
            guard var p = pplans.first else {
                throw QueryPlannerError.noPlanAvailable
            }
            if case .extend = child {
            } else {
                // at the bottom of a chain of one or more extend()s, add a NextRow plan
                p = NextRowPlan(child: p, evaluator: evaluator)
            }
            let (e, mapping) = try expr.removingExistsExpressions(namingVariables: &freshCounter)
            try mapping.forEach { (name, algebra) throws in
                let patplans = try plan(algebra: algebra, activeGraph: activeGraph, estimator: estimator)
                guard let pat = patplans.first else {
                    throw QueryPlannerError.noPlanAvailable
                }
                p = ExistsPlan(child: p, pattern: pat, variable: name, patternAlgebra: algebra)
            }
            
            if mapping.isEmpty {
                return [ExtendPlan(child: p, expression: e, variable: name, evaluator: evaluator)]
            } else {
                let extend = ExtendPlan(child: p, expression: e, variable: name, evaluator: evaluator)
                let vars = child.inscope
                let variables = vars.union([name])
                return try [self.project(plan: extend, to: variables)]
            }
        case let .order(child, orders):
            let p = try plan(algebra: child, activeGraph: activeGraph, estimator: estimator)
            return p.map { OrderPlan(child: $0, comparators: orders, evaluator: evaluator) }
        case let .aggregate(child, groups, aggs):
            let p = try plan(algebra: child, activeGraph: activeGraph, estimator: estimator)
            return p.map { AggregationPlan(child: $0, groups: groups, aggregates: aggs) }
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
            // TODO: handle multiple query plans from child
            let pplans = try plan(algebra: child, activeGraph: activeGraph, estimator: estimator)
            guard var p = pplans.first else {
                throw QueryPlannerError.noPlanAvailable
            }
            let (e, mapping) = try expr.removingExistsExpressions(namingVariables: &freshCounter)
            try mapping.forEach { (name, algebra) throws in
                let patplans = try plan(algebra: algebra, activeGraph: activeGraph, estimator: estimator)
                guard let pat = patplans.first else {
                    throw QueryPlannerError.noPlanAvailable
                }
                p = ExistsPlan(child: p, pattern: pat, variable: name, patternAlgebra: algebra)
            }
            p = NextRowPlan(child: p, evaluator: evaluator)
            
            if mapping.isEmpty {
                return [FilterPlan(child: p, expression: e, evaluator: evaluator)]
            } else {
                let filter = FilterPlan(child: p, expression: e, evaluator: evaluator)
                let variables = child.inscope
                return try [self.project(plan: filter, to: variables)]
            }
        case let .distinct(child):
            let plans = try plan(algebra: child, activeGraph: activeGraph, estimator: estimator)
            return plans.map { (plan) -> [QueryPlan] in
                var plans = [QueryPlan]()
                if let store = _lazyStore(), let plan = plan as? MaterializeTermsPlan {
                    // TODO: check if the data is already fully sorted
                    let uniq1 = IDUniquePlan(child: plan.idPlan) // this should be relatively cheap, but might save a lot of work in the IDSortPlan that happens next
                    let ordered = IDSortPlan(child: uniq1, orderVariables: Array(child.inscope))
                    let uniq2 = IDUniquePlan(child: ordered)
                    plans.append(MaterializeTermsPlan(idPlan: uniq2, store: store, verbose: self.verbose))
                }
                plans.append(DistinctPlan(child: plan))
                return plans
            }.flatMap { $0 }
        case let .reduced(child):
            // remove duplicated adjacent results 
            let plans = try plan(algebra: child, activeGraph: activeGraph, estimator: estimator)
            return plans.map { (plan) -> QueryPlan in
                if let store = _lazyStore(), let plan = plan as? MaterializeTermsPlan {
                    let uniq = IDUniquePlan(child: plan.idPlan)
                    return MaterializeTermsPlan(idPlan: uniq, store: store, verbose: self.verbose)
                }
                return ReducedPlan(child: plan)
            }
        case .bgp(let patterns):
            let plans = try plan(bgp: patterns, activeGraph: .bound(activeGraph), estimator: estimator)
            return candidatePlans(plans, estimator: estimator)
        case let .minus(lhs, rhs):
            var plans = [QueryPlan]()
            let lplans = try plan(algebra: lhs, activeGraph: activeGraph, estimator: estimator)
            let rplans = try plan(algebra: rhs, activeGraph: activeGraph, estimator: estimator)

            let i = lhs.inscope.intersection(rhs.inscope)
            let ni = lhs.necessarilyBound.intersection(rhs.necessarilyBound)
            for l in lplans {
                for r in rplans {
                    if let store = _lazyStore(), let lhs = l as? MaterializeTermsPlan, let rhs = r as? MaterializeTermsPlan {
                        if !ni.isEmpty {
                            // there is an intersection of necessarily-bound variables in the two branches,
                            // so we can use an anti-join to produce the results
                            let hplan = IDHashAntiJoinPlan(lhs: lhs.idPlan, rhs: rhs.idPlan, joinVariables: i)
                            plans.append(MaterializeTermsPlan(idPlan: hplan, store: store, verbose: verbose))
                        } else {
                            let mplan = IDMinusPlan(lhs: lhs.idPlan, rhs: rhs.idPlan)
                            plans.append(MaterializeTermsPlan(idPlan: mplan, store: store, verbose: verbose))
                        }
                    }
                    
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
            var plans = [QueryPlan]()
            if let store = self._lazyStore() {
                let rv = quad.repeatedVariables()
                do {
                    let idquad = try quad.idquad(for: store)
                    let idplan = IDQuadPlan(pattern: idquad, repeatedVariables: rv, store: store)
                    plans.append(MaterializeTermsPlan(idPlan: idplan, store: store, verbose: verbose))
                } catch QueryPlannerError.termNotFound {
                    plans.append(TablePlan.unionIdentity)
                }
            } else {
                plans.append(QuadPlan(quad: quad, store: store))
            }
            
            // get rid of any variables that are non-projected (e.g. using the `[]` syntax)
            let proj = quad.inscope
            if quad.variables == proj {
                return plans
            } else {
                // binding variables were introduced to allow the join to be performed,
                // but they shouldn't escape the BGP evaluation, so introduce an extra projection
                let variables = Set(proj)
                return try plans.map { try self.project(plan: $0, to: variables) }
            }
        case let .path(s, path, o):
            var plans = [QueryPlan]()
            if let store = _lazyStore() {
                let subject = try s.idnode(for: store)
                let object = try o.idnode(for: store)
                guard let graph = try store.id(for: activeGraph) else {
                    throw QueryPlannerError.termNotFound
                }
                let pathPlan = try idplan(subject: subject, path: path, object: object, activeGraph: activeGraph, estimator: estimator)
                let qp = IDPathQueryPlan(subject: subject, path: pathPlan, object: object, graph: graph)
                plans.append(MaterializeTermsPlan(idPlan: qp, store: store, verbose: self.verbose))
            }
            let pathPlan = try plan(subject: s, path: path, object: o, activeGraph: activeGraph, estimator: estimator)
            plans.append(PathQueryPlan(subject: s, path: pathPlan, object: o, graph: activeGraph))
            return plans
        case .matchStatement(_, _):
            fatalError("TODO: implement plan(algebra: .matchStatement)")
        }
    }

    func planBushyUnionProduct<E: QueryPlanCostEstimator>(branches: [[QueryPlan]], estimator: E) throws -> [QueryPlan] {
        guard !branches.isEmpty else {
            return [TablePlan.unionIdentity]
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

    public func idplan<E: QueryPlanCostEstimator>(subject s: IDNode, path: PropertyPath, object o: IDNode, activeGraph: Term, estimator: E) throws -> IDPathPlan {
        guard let store = _lazyStore() else {
            throw QueryPlannerError.noPlanAvailable
        }

        switch path {
        case .link(let predicate):
            guard let p = try store.id(for: predicate) else {
                throw QueryPlannerError.termNotFound
            }
            return IDLinkPathPlan(predicate: p, store: store)
        case .inv(let ipath):
            let p = try idplan(subject: o, path: ipath, object: s, activeGraph: activeGraph, estimator: estimator)
            return IDInversePathPlan(child: p)
        case let .alt(lhs, rhs):
            let l = try idplan(subject: s, path: lhs, object: o, activeGraph: activeGraph, estimator: estimator)
            let r = try idplan(subject: s, path: rhs, object: o, activeGraph: activeGraph, estimator: estimator)
            return IDUnionPathPlan(lhs: l, rhs: r)
        case let .seq(lhs, rhs):
            let j = try freshVariable().idnode(for: store)
            let l = try idplan(subject: s, path: lhs, object: j, activeGraph: activeGraph, estimator: estimator)
            let r = try idplan(subject: j, path: rhs, object: o, activeGraph: activeGraph, estimator: estimator)
            return IDSequencePathPlan(lhs: l, joinNode: j, rhs: r)
        case .nps(let iris):
            let ids = try iris.map { try store.id(for: $0) }.compactMap { $0 }
            return IDNPSPathPlan(iris: ids, store: store)
        case .plus(let pp):
            let p = try idplan(subject: s, path: pp, object: o, activeGraph: activeGraph, estimator: estimator)
            return IDPlusPathPlan(child: p, store: store)
        case .star(let pp):
            let p = try idplan(subject: s, path: pp, object: o, activeGraph: activeGraph, estimator: estimator)
            return IDStarPathPlan(child: p, store: store)
        case .zeroOrOne(let pp):
            let p = try idplan(subject: s, path: pp, object: o, activeGraph: activeGraph, estimator: estimator)
            return IDZeroOrOnePathPlan(child: p, store: store)
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

extension QueryPlanEvaluator: CustomStringConvertible {
    public var description: String {
        return "QueryPlanEvaluator<\(Q.self)>"
    }
}

public struct QueryPlanEvaluator<Q: QuadStoreProtocol>: QueryEvaluatorProtocol {
    public typealias ResultSequence = AnySequence<SPARQLResultSolution<Term>>
    public typealias TripleSequence = [Triple]

    public let supportedLanguages: [QueryLanguage] = [.sparqlQuery10, .sparqlQuery11]
    public let supportedFeatures: [QueryEngineFeature] = [.basicFederatedQuery]

    var verbose: Bool
    var dataset: Dataset
    public var planner: QueryPlanner<Q>
    
    public init(planner: QueryPlanner<Q>) {
        self.verbose = false
        self.dataset = planner.dataset
        self.planner = planner
    }
    
    public init(store: Q, dataset: Dataset, base: String? = nil, verbose: Bool = false) {
        self.verbose = verbose
        self.dataset = dataset
        self.planner = QueryPlanner(store: store, dataset: dataset, base: base)
        planner.verbose = verbose
    }
    
    public func evaluate(query: Query) throws -> QueryResult<AnySequence<SPARQLResultSolution<Term>>, [Triple]> {
        return try evaluate(query: query, activeGraph: nil)
    }
    
    public func evaluate(algebra: Algebra, activeGraph: Term?) throws -> AnyIterator<SPARQLResultSolution<Term>> {
        let rewriter = SPARQLQueryRewriter()
        let a = try rewriter.simplify(algebra: algebra)
        let ce = QueryPlanSimpleCostEstimator()
        let plans = try planner.plan(algebra: a, activeGraph: activeGraph!, estimator: ce)
        guard let plan = plans.first else {
            throw QueryPlannerError.noPlanAvailable
        }
        if self.verbose {
            print("Query Plan:")
            print(plan.serialize(depth: 0))
        }
        
        let seq = AnySequence { () -> AnyIterator<SPARQLResultSolution<Term>> in
            do {
                let i = try plan.evaluate()
                return i
            } catch let error {
                print("*** Failed to evaluate query plan in Sequence construction: \(error)")
                return AnyIterator([].makeIterator())
                //                throw error
            }
        }
        
        return AnyIterator(seq.makeIterator())
    }
    
    public func evaluate(query: Query, activeGraph graph: Term? = nil) throws -> QueryResult<AnySequence<SPARQLResultSolution<Term>>, [Triple]> {
        let rewriter = SPARQLQueryRewriter()
        let q = try rewriter.simplify(query: query)
        let plan = try planner.plan(query: q, activeGraph: graph)
        if self.verbose {
            print("Query Plan:")
            print(plan.serialize(depth: 0))
            
//            if let store = planner.store as? DiomedeQuadStore {
//                print("Store Terms:")
//                try store.iterateTerms { (id, term) in
//                    print("[\(id)] \(term)")
//                }
//            }
        }

        let seq = AnySequence { () -> AnyIterator<SPARQLResultSolution<Term>> in
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
