//
//  IDQuadPlanner.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 2/6/21.
//

import Foundation
import SPARQLSyntax
import IDPPlanner

struct IDPCostEstimatorAdaptor<E: QueryPlanCostEstimator>: IDPCostEstimator {
    typealias Cost = E.QueryPlanCost
    typealias Plan = IDQueryPlan
    
    var store: LazyMaterializingQuadStore
    var estimator: E
    init(store: LazyMaterializingQuadStore, estimator: E) {
        self.estimator = estimator
        self.store = store
    }

    func cost(for plan: Plan) throws -> Cost {
        let mat = MaterializeTermsPlan(idPlan: plan, store: store, verbose: false, metricsToken: QueryPlanEvaluationMetrics.silentToken)
        return try estimator.cost(for: mat)
    }
    
    func cost(_ cost: Cost, isCheaperThan other: Cost) -> Bool {
        return estimator.cost(cost, isCheaperThan: other)
    }
}

struct IDPlanProvider<E: QueryPlanCostEstimator>: IDPPlanProvider {
    typealias Relation = QuadPattern
    typealias Plan = IDQueryPlan
    typealias Estimator = IDPCostEstimatorAdaptor<E>
    
    var planCountThreshold: Int
    var costEstimator: IDPCostEstimatorAdaptor<E>
    var store: LazyMaterializingQuadStore
    var metrics: QueryPlanEvaluationMetrics
    init(store: LazyMaterializingQuadStore, estimator: E, metrics: QueryPlanEvaluationMetrics) {
        self.store = store
        self.costEstimator = IDPCostEstimatorAdaptor(store: store, estimator: estimator)
        self.metrics = metrics
        self.planCountThreshold = 4
    }
    
    func accessPlans(for quad: Relation) throws -> [IDQueryPlan] {
        var plans = [IDQueryPlan]()
        let availableOrders = try store.availableOrders(matching: quad)
        for (order, fullOrder) in availableOrders {
            let orderVars = order.map { quad[$0] }.compactMap { $0.variableName }
            let seedPlan = IDOrderedQuadPlan(
                quad: quad,
                order: fullOrder,
                store: store,
                orderVars: orderVars,
                metricsToken: metrics.getOperatorToken()
            )
            plans.append(seedPlan)
        }
        return plans
    }
    
    func joinPlans<C: Collection, D: Collection>(_ lhs: C, _ rhs: D) -> [IDQueryPlan] where C.Element == IDQueryPlan, D.Element == IDQueryPlan {
        var plans = [IDQueryPlan]()
        for l in lhs {
            for r in rhs {
                let lhsOrder = l.orderVars
                let rhsOrder = r.orderVars
                let availableJoinVariables : Set<String> = l.variables.intersection(r.variables)
                let sharedOrder = lhsOrder.sharedPrefix(with: rhsOrder)
                if !sharedOrder.isEmpty {
                    let mergeJoinplan = IDMergeJoinPlan(lhs: l, rhs: r, mergeVariables: sharedOrder, orderVars: sharedOrder, metricsToken: metrics.getOperatorToken())
                    plans.append(mergeJoinplan)
                }
                
                if !availableJoinVariables.isEmpty {
                    plans.append(
                        IDHashJoinPlan(
                            lhs: l,
                            rhs: r,
                            joinVariables: availableJoinVariables,
                            orderVars: l.orderVars,
                            metricsToken: metrics.getOperatorToken()
                        )
                    )
                    plans.append(
                        IDHashJoinPlan(
                            lhs: r,
                            rhs: l,
                            joinVariables: availableJoinVariables,
                            orderVars: r.orderVars,
                            metricsToken: metrics.getOperatorToken()
                        )
                    )
                }
                
                for (l, r) in [(l, r), (r, l)] {
                    if let idqp = r as? IDQuadPlan {
                        let iq : IDQuad = idqp.pattern
                        var bindings = [String: WritableKeyPath<IDQuad, IDNode>]()
                        for name in availableJoinVariables {
                            if case .variable(name, _) = iq.subject {
                                bindings[name] = \IDQuad.subject
                            }
                            if case .variable(name, _) = iq.predicate {
                                bindings[name] = \IDQuad.predicate
                            }
                            if case .variable(name, _) = iq.object {
                                bindings[name] = \IDQuad.object
                            }
                            if case .variable(name, _) = iq.graph {
                                bindings[name] = \IDQuad.graph
                            }
                        }
                        
                        
                        let rv = iq.repeatedVariables()
                        let bindPlan = IDIndexBindQuadPlan(
                            child: l,
                            pattern: idqp.pattern,
                            bindings: bindings,
                            repeatedVariables: rv,
                            orderVars: l.orderVars,
                            store: store,
                            metricsToken: metrics.getOperatorToken()
                        )
                        plans.append(bindPlan)
                    }
                }
                
                plans.append(IDNestedLoopJoinPlan(lhs: l, rhs: r, orderVars: l.orderVars, metricsToken: metrics.getOperatorToken()))
                plans.append(IDNestedLoopJoinPlan(lhs: r, rhs: l, orderVars: r.orderVars, metricsToken: metrics.getOperatorToken()))
            }
        }
        return plans
    }
    
    private func sort(plans: inout [IDQueryPlan]) {
        plans.sort { (a, b) -> Bool in
            do {
                let acost = try self.costEstimator.cost(for: a)
                let bcost = try self.costEstimator.cost(for: b)
                return self.costEstimator.cost(acost, isCheaperThan: bcost)
            } catch {
                return false
            }
        }
    }
    
    func prunePlans<C: Collection>(_ plans: C) -> [IDQueryPlan] where C.Element == IDQueryPlan {
        var sortedPlans = Array(plans)
        sort(plans: &sortedPlans)
        let pruned = Array(sortedPlans.prefix(self.planCountThreshold))
        return pruned
    }
    
    func finalizePlans<C: Collection>(_ plans: C) -> [IDQueryPlan] where C.Element == IDQueryPlan {
        var sortedPlans = Array(plans)
        sort(plans: &sortedPlans)
        return sortedPlans
    }
}

extension QueryPlanner {
    func idPlans<E: QueryPlanCostEstimator>(for patterns: [QuadPattern], in store: LazyMaterializingQuadStore, estimator: E) throws -> [MaterializeTermsPlan] {
        
        let provider = IDPlanProvider<E>(store: store, estimator: estimator, metrics: metrics)
        let idpplanner = IDPPlanner(provider, k: 5, blockSize: .bestRow)
        let idpplans = try idpplanner.join(patterns)

        let matplans = idpplans.map { MaterializeTermsPlan(idPlan: $0, store: store, verbose: false, metricsToken: QueryPlanEvaluationMetrics.silentToken) }
        return matplans
//        for plan in idpplans {
//            let mat = MaterializeTermsPlan(idPlan: plan, store: store, verbose: false, metricsToken: QueryPlanEvaluationMetrics.silentToken)
//            let cost = try estimator.cost(for: mat)
//        }
//        let plans = try _idPlans(for: patterns, in: store, estimator: estimator)
//        for plan in plans {
//            let cost = try estimator.cost(for: plan)
//        }
//        return plans
    }
    
    func _idPlans<E: QueryPlanCostEstimator>(for patterns: [QuadPattern], in store: LazyMaterializingQuadStore, estimator: E) throws -> [MaterializeTermsPlan] {
        guard let store = _lazyStore() else {
            throw QueryPlannerError.noPlanAvailable
        }
        guard let firstQuad = patterns.first else {
            throw QueryPlannerError.noPlanAvailable
        }
        let restQuads = Array(patterns.dropFirst())
        
        if true {
            var idQuadCache = [QuadPattern: IDQuad]()
            for q in patterns {
                let idquad = try q.idquad(for: store)
                idQuadCache[q] = idquad
            }
            
            // this will generate many join order permutations
            var plans = [MaterializeTermsPlan]()
            // TODO: also consider "interesting" orders (e.g. idplans that have been explicityly sorted to a join variable)
            let availableOrders = try store.availableOrders(matching: firstQuad)
//            print("available orders: \(availableOrders.count)")
            for (order, fullOrder) in availableOrders {
                let orderVars = order.map { $0.bindingVariable(in: firstQuad) }.prefix { $0 != nil }.compactMap { $0 }
                let seedPlan = IDOrderedQuadPlan(quad: firstQuad, order: fullOrder, store: store, orderVars: orderVars, metricsToken: metrics.getOperatorToken())
                let alternativePlans = try reduceIDQuadJoins(seedPlan, ordered: orderVars, rest: restQuads, currentVariables: firstQuad.variables, estimator: estimator, idQuadCache: &idQuadCache)
                plans.append(contentsOf: alternativePlans)
            }
            return plans
        }
    }
    
    func reduceIDQuadJoins<E: QueryPlanCostEstimator>(_ plan: IDQueryPlan, ordered orderVars: [String], rest tail: [QuadPattern], currentVariables: Set<String>, estimator: E, idQuadCache: inout [QuadPattern: IDQuad]) throws -> [MaterializeTermsPlan] {
        guard let store = _lazyStore() else {
            throw QueryPlannerError.noPlanAvailable
        }
        
        // TODO: this is currently doing all possible permutations of [rest]; that's going to be prohibitive on large BGPs; use heuristics or something like IDP
        guard !tail.isEmpty else {
            let matplan = MaterializeTermsPlan(idPlan: plan, store: store, verbose: verbose, metricsToken: metrics.getOperatorToken())
            return [matplan]
        }
        
        var plans = [QueryPlan]()
        var costCutoff : E.QueryPlanCost? = nil
        let tooExpensive : (IDQueryPlan) -> Bool = { (plan) -> Bool in
            // for each intermediate idplan generated, we check the cost and do not conintue with it if it has a higher cost than the minimum cost seen so far
            // this approximates a greedy algorithm, but leaves some room for finding better plans with the alternatives
            do {
                let matplan = MaterializeTermsPlan(idPlan: plan, store: store, verbose: self.verbose, metricsToken: self.metrics.getOperatorToken())
                let cost = try estimator.cost(for: matplan)
                if let cutoff = costCutoff {
                    if estimator.cost(cutoff, isCheaperThan: cost) {
                        return true
                    } else {
                        costCutoff = cost
                    }
                } else {
                    costCutoff = cost
                }
            } catch {
            }
            return false
        }
        
        for i in tail.indices {
            var intermediate = [(IDQueryPlan, [String])]()
            let q = tail[i]
            var rest = tail
            rest.remove(at: i)

            // TODO: also consider "interesting" orders (e.g. idplans that have been explicityly sorted to a join variable)
            for (nextOrder, fullOrder) in try store.availableOrders(matching: q) {
                let orderVars = nextOrder.map { q[$0] }.compactMap { $0.variableName }
                let qp = IDOrderedQuadPlan(quad: q, order: fullOrder, store: store, orderVars: orderVars, metricsToken: metrics.getOperatorToken())
                let nextOrderVars = nextOrder.map { $0.bindingVariable(in: q) }.prefix { $0 != nil }.compactMap { $0 }
                let sharedOrder = nextOrderVars.sharedPrefix(with: plan.orderVars)

                if !sharedOrder.isEmpty {
                    let plan = IDMergeJoinPlan(
                        lhs: plan,
                        rhs: qp,
                        mergeVariables: sharedOrder,
                        orderVars: sharedOrder,
                        metricsToken: metrics.getOperatorToken()
                    )
                    if tooExpensive(plan) { continue }
                    intermediate.append((plan, sharedOrder))
                }
            }
            
            let rv = q.repeatedVariables()
            
            let idquad: IDQuad
            if let i = idQuadCache[q] {
                idquad = i
            } else {
                idquad = try q.idquad(for: store)
                idQuadCache[q] = idquad
            }
            let qp : IDQueryPlan = IDQuadPlan(
                pattern: idquad,
                repeatedVariables: rv,
                orderVars: [],
                store: store,
                metricsToken: metrics.getOperatorToken()
            )
            let tv = q.variables
            let i = currentVariables.intersection(tv)
            
            let idnlplan = IDNestedLoopJoinPlan(lhs: plan, rhs: qp, orderVars: plan.orderVars, metricsToken: metrics.getOperatorToken())
            if !tooExpensive(idnlplan) {
                intermediate.append((idnlplan, []))
            }
            if !i.isEmpty {
                let hashJoinPlan = IDHashJoinPlan(lhs: plan, rhs: qp, joinVariables: i, orderVars: [], metricsToken: metrics.getOperatorToken()) // TODO: improve orderVars
                if !tooExpensive(hashJoinPlan) {
                    intermediate.append((hashJoinPlan, orderVars)) // hashjoin keeps the order of the LHS
                }
                
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
                
                let bindPlan = IDIndexBindQuadPlan(child: plan, pattern: idquad, bindings: bindings, repeatedVariables: rv, orderVars: plan.orderVars, store: store, metricsToken: metrics.getOperatorToken())
                if !tooExpensive(bindPlan) {
                    intermediate.append((bindPlan, orderVars)) // bind join keeps the order of the LHS
                }
            }
            
            let u = currentVariables.union(tv)
            for (p, sharedOrder) in intermediate {
                let matplans = try reduceIDQuadJoins(p, ordered: sharedOrder, rest: rest, currentVariables: u, estimator: estimator, idQuadCache: &idQuadCache)
                plans.append(contentsOf: matplans)
            }
        }
        
//        print("  - alternative plans: \(plans.count)")
//        if plans.count > 50 {
//            for (i, p) in plans.enumerated() {
//                print("\(i) \(p.serialize(depth: 0))")
//            }
//        }
        let candidates = candidatePlans(plans, estimator: estimator)
        return candidates as! [MaterializeTermsPlan]
    }
}
