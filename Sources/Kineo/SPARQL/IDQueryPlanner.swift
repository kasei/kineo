//
//  IDQuadPlanner.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 2/6/21.
//

import Foundation
import SPARQLSyntax

extension QueryPlanner {
    func idPlans<E: QueryPlanCostEstimator>(for patterns: [QuadPattern], in store: LazyMaterializingQuadStore, estimator: E) throws -> [MaterializeTermsPlan] {
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
                let seedPlan = IDOrderedQuadPlan(quad: firstQuad, order: fullOrder, store: store, metricsToken: metrics.getOperatorToken())
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
                    if estimator.cheaperThan(lhs: cutoff, rhs: cost) {
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
                let qp = IDOrderedQuadPlan(quad: q, order: fullOrder, store: store, metricsToken: metrics.getOperatorToken())
                let nextOrderVars = nextOrder.map { $0.bindingVariable(in: q) }.prefix { $0 != nil }.compactMap { $0 }
                let sharedOrder = nextOrderVars.sharedPrefix(with: orderVars)

                if !sharedOrder.isEmpty {
                    let plan = IDMergeJoinPlan(lhs: plan, rhs: qp, variables: sharedOrder, metricsToken: metrics.getOperatorToken())
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
            let qp : IDQueryPlan = IDQuadPlan(pattern: idquad, repeatedVariables: rv, store: store, metricsToken: metrics.getOperatorToken())
            let tv = q.variables
            let i = currentVariables.intersection(tv)
            
            let idnlplan = IDNestedLoopJoinPlan(lhs: plan, rhs: qp, metricsToken: metrics.getOperatorToken())
            if !tooExpensive(idnlplan) {
                intermediate.append((idnlplan, []))
            }
            if !i.isEmpty {
                let hashJoinPlan = IDHashJoinPlan(lhs: plan, rhs: qp, joinVariables: i, metricsToken: metrics.getOperatorToken())
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
                
                let bindPlan = IDIndexBindQuadPlan(child: plan, pattern: idquad, bindings: bindings, repeatedVariables: rv, store: store, metricsToken: metrics.getOperatorToken())
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
