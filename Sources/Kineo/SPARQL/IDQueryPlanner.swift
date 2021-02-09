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
        let idpplanner = IDPPlanner(provider, k: 6, blockSize: .bestRow)
        let idpplans = try idpplanner.join(patterns)

        let matplans = idpplans.map { MaterializeTermsPlan(idPlan: $0, store: store, verbose: false, metricsToken: QueryPlanEvaluationMetrics.silentToken) }
        return matplans
    }
}
