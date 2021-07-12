//
//  IDQuadPlanner.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 2/6/21.
//

import Foundation
import SPARQLSyntax
import IDPPlanner


/// Adapts a Kineo cost estimator (conforming to QueryPlanCostEstimator) to the API used by the IDPPlanner module
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

/// IDPlanProvider provides implementations of the required methods needed to use the IDPPlanner to produce query plans,
/// including access plans (using the available index orders of the underlying store), and join plans (which may be merge and
/// hash join, when allowable, or bind and nested loop joins otherwise).
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
        self.planCountThreshold = 8
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
    
    /// Returns an array of IDQueryPlan objects representing possible joins between the alternative left- and right-hand-side children plans, `lhs` and `rhs`.
    ///
    /// For each combination of left and right plans:
    /// * If the children plans have a shared ordering, a merge join is returned
    /// * If the children plans have a shared join variable, two hash joins are returned (for both orderings of left and right child plans)
    /// * Otherwise, both bind and nested-loop joins are returned (for both orderings of left and right child plans)
    ///
    /// - Parameters:
    ///   - lhs: Alternative plans for the left-child of the join
    ///   - rhs: Alternative plans for the right-child of the join
    /// - Returns: An array of alternative plans to join all combinations of `lhs` and `rhs`
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
                    continue // always prefer a merge plan
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
                    continue // prefer hash joins to bind joins and nested loop joins
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
                
                plans.append(IDNestedLoopJoinPlan(lhs: l, rhs: r, orderVars: r.orderVars, metricsToken: metrics.getOperatorToken()))
            }
        }
//        print("======================================================================")
//        for plan in plans {
//            if let cost = try? self.costEstimator.cost(for: plan) {
//                try print("[\(cost)] \(plan.serialize(depth: 0))")
//            }
////            try print("[\(self.costEstimator.cost(for: plan))] \(plan.serialize(depth: 0))")
//        }
//        print("======================================================================")
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
    
    /// Prune a list of alternative plans, returning a subset of the input
    /// - Parameter plans: Alternative query plans
    /// - Returns: A subset of `plans` representing the desirable plans with which to continue the query planning
    func prunePlans<C: Collection>(_ plans: C) -> [IDQueryPlan] where C.Element == IDQueryPlan {
        var sortedPlans = Array(plans)
        sort(plans: &sortedPlans)
        let pruned = Array(sortedPlans.prefix(self.planCountThreshold))
        return pruned
    }
    
    /// Apply any finalization to the generated query plans before returning from the planning algorithm
    /// - Parameter plans: Alternative query plans
    /// - Returns: A new array containing the alternative query plans with the finalization process applied
    func finalizePlans<C: Collection>(_ plans: C) -> [IDQueryPlan] where C.Element == IDQueryPlan {
        var sortedPlans = Array(plans)
        sort(plans: &sortedPlans)
        return sortedPlans
    }
}

// QueryPlanner extension providing planning for BGPs using the Iterative Dynamic Planning query planner module.
extension QueryPlanner {
    func idPlans<E: QueryPlanCostEstimator>(for patterns: [QuadPattern], in store: LazyMaterializingQuadStore, estimator: E) throws -> [MaterializeTermsPlan] {
        
        let provider = IDPlanProvider<E>(store: store, estimator: estimator, metrics: metrics)
        let idpplanner = IDPPlanner(provider, k: 4, blockSize: .bestRow)
        let idpplans = try idpplanner.join(patterns)

        let matplans = idpplans.map { MaterializeTermsPlan(idPlan: $0, store: store, verbose: false, metricsToken: QueryPlanEvaluationMetrics.silentToken) }
//        for plan in matplans {
//            if let cost = try? estimator.cost(for: plan) {
//                print("GENERATED JOIN: [\(cost)] \(plan.serialize(depth: 0))")
//            }
//        }
//        print("======================================================================")
        return Array(matplans.prefix(2))
    }
}
