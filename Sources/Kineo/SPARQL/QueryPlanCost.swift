//
//  QueryPlanCost.swift
//  Kineo
//
//  Created by GWilliams on 6/6/19.
//

import Foundation
import SPARQLSyntax
import IDPPlanner

public enum QueryPlanCostError: Error {
    case unrecognizedPlan(QueryPlan)
}

public protocol QueryPlanCostEstimator {
    associatedtype QueryPlanCost
    func cost(_ cost: QueryPlanCost, isCheaperThan other: QueryPlanCost) -> Bool
    func cost(for plan: QueryPlan) throws -> QueryPlanCost
}

public extension QueryPlanCostEstimator {
    func plan(_ lhs: QueryPlan, isCheaperThan rhs: QueryPlan) -> Bool {
        do {
            let lcost = try cost(for: lhs)
            let rcost = try cost(for: rhs)
            return cost(lcost, isCheaperThan: rcost)
        } catch let e {
            print("*** Failed to compute cost for query plans: \(e)")
            return false
        }
    }
}

extension Node {
    var isBound: Bool { return !isVariable }
    var isVariable: Bool {
        switch self {
        case .bound:
            return false
        case .variable:
            return true
        }
    }
    var variableName: String? {
        switch self {
        case .bound:
            return nil
        case .variable(let v, _):
            return v
        }
    }
}

public struct QueryPlanSimpleCostEstimator: QueryPlanCostEstimator {
    var boundQuadCost: Double
    var serviceCost: Double
    
    let idPlanPriority = 0.5
    let joinRHSMaterializationPenalty = 3.0
    public init() {
        self.boundQuadCost = 1.0
        self.serviceCost = 50.0
    }
    
    public struct QueryPlanSimpleCost: Comparable, CustomStringConvertible {
        var cost: Double

        public var description: String {
            return String(format: "Cost(%.1lf)", cost)
        }
        
        public static func < (lhs: QueryPlanSimpleCostEstimator.QueryPlanSimpleCost, rhs: QueryPlanSimpleCostEstimator.QueryPlanSimpleCost) -> Bool {
            return lhs.cost < rhs.cost
        }
    }
    
    public func cost(_ lhs: QueryPlanSimpleCost, isCheaperThan rhs: QueryPlanSimpleCost) -> Bool {
        return lhs < rhs
    }

    public func cost(for plan: IDQueryPlan) throws -> QueryPlanSimpleCost {
        if let _ = plan as? NullaryIDQueryPlan {
            if let p = plan as? IDQuadPlan {
                let q = p.pattern
                var cost = boundQuadCost
                if q.subject.isVariable {
                    cost *= 7.5
                }
                if q.predicate.isVariable {
                    cost *= 2.5
                }
                if q.object.isVariable {
                    cost *= 5.0
                }
                if q.graph.isVariable {
                    cost *= 10.0
                }
                return QueryPlanSimpleCost(cost: idPlanPriority * cost)
            } else if let p = plan as? IDOrderedQuadPlan {
                    let q = p.quad
                    var cost = boundQuadCost
                    if q.subject.isVariable {
                        cost *= 7.5
                    }
                    if q.predicate.isVariable {
                        cost *= 2.5
                    }
                    if q.object.isVariable {
                        cost *= 5.0
                    }
                    if q.graph.isVariable {
                        cost *= 10.0
                    }
                    return QueryPlanSimpleCost(cost: idPlanPriority * cost)
            } else if let p = plan as? IDPathQueryPlan {
                var cost = boundQuadCost
                if p.subject.isVariable {
                    cost *= 7.5
                }
                if p.object.isVariable {
                    cost *= 5.0
                }
                if p.graph.isVariable {
                    cost *= 10.0
                }
                let pathPenalty = 10.0 // How much more costly is a path than a triple? We don't have a good way to know, so we just treat a path as a triple with a penalty
                return QueryPlanSimpleCost(cost: cost * pathPenalty)
            }
//            print("[1] cost for ID plan: \(plan)")
        } else if let p = plan as? UnaryIDQueryPlan {
            let c = try cost(for: p.child)
            if let _ = plan as? IDProjectPlan {
                return c
            } else if let _ = plan as? IDReducedPlan {
                return c
            } else if let _ = plan as? IDUniquePlan {
                return c
            } else if let _ = plan as? IDLimitPlan {
                return c
            } else if let _ = plan as? IDOffsetPlan {
                return c
            } else if let _ = plan as? IDSortPlan {
                return QueryPlanSimpleCost(cost: idPlanPriority * c.cost * log(c.cost))
            } else if let bindJoin = plan as? IDIndexBindQuadPlan {
                var pattern = bindJoin.pattern
//                let idQuadPlan = IDQuadPlan(
//                    pattern: pattern,
//                    repeatedVariables: [:],
//                    orderVars: [],
//                    store: bindJoin.store,
//                    metricsToken: QueryPlanEvaluationMetrics.silentToken
//                )
                
                for (_, path) in bindJoin.bindings {
                    pattern[keyPath: path] = .bound(0)
                }
                
                let boundIDQuadPlan = IDQuadPlan(
                    pattern: pattern,
                    repeatedVariables: [:],
                    orderVars: [],
                    store: bindJoin.store,
                    metricsToken: QueryPlanEvaluationMetrics.silentToken
                )
                
//                let unboundProbeCost = try self.cost(for: idQuadPlan)
                let probeCost = try self.cost(for: boundIDQuadPlan)
//                print("bind join costs: \(unboundProbeCost) ; \(probeCost)")

                // TODO: try to determine the cost of bindJoin.pattern when all of the binding substitutions have been made, and incorporate that into the final cost
                return QueryPlanSimpleCost(cost: idPlanPriority * 2.0 * probeCost.cost * c.cost)
            } else {
//                print("[2] cost for ID plan: \(plan)")
            }
        } else if let p = plan as? BinaryIDQueryPlan {
            let lhs = p.children[0]
            let rhs = p.children[1]
            let lc = try cost(for: lhs)
            let rc = try cost(for: rhs)
            var penalty = 1.0
            if let p = plan as? IDHashJoinPlan {
                let jv = p.joinVariables
                if jv.isEmpty {
                    penalty = 1000.0
                }
                let cost = idPlanPriority * penalty * (lc.cost + joinRHSMaterializationPenalty * rc.cost)
                return QueryPlanSimpleCost(cost: cost) // value rhs more, since that is the one that is materialized
            } else if let p = plan as? IDHashLeftJoinPlan {
                let jv = p.joinVariables
                if jv.isEmpty {
                    penalty = 1000.0
                }
                return QueryPlanSimpleCost(cost: penalty * (lc.cost + joinRHSMaterializationPenalty * rc.cost)) // value rhs more, since that is the one that is materialized
            } else if let p = plan as? IDHashAntiJoinPlan {
                let jv = p.joinVariables
                if jv.isEmpty {
                    penalty = 1000.0
                }
                return QueryPlanSimpleCost(cost: penalty * (lc.cost + joinRHSMaterializationPenalty * rc.cost)) // value rhs more, since that is the one that is materialized
            } else if let _ = plan as? IDMergeJoinPlan {
                var mergePlanPriority = 1.0
                
                if let _ = lhs as? IDMergeJoinPlan {
                    mergePlanPriority *= 1.5
                }
                if let _ = rhs as? IDQuadPlan {
                    mergePlanPriority *= 1.5
                }
                let cost = (1.0 / mergePlanPriority) * idPlanPriority * (lc.cost + rc.cost)
                return QueryPlanSimpleCost(cost: cost)
            } else if let _ = plan as? IDNestedLoopJoinPlan {
                return QueryPlanSimpleCost(cost: idPlanPriority * (lc.cost * joinRHSMaterializationPenalty * rc.cost))
            } else if let _ = plan as? IDNestedLoopLeftJoinPlan {
                return QueryPlanSimpleCost(cost: idPlanPriority * (lc.cost * joinRHSMaterializationPenalty * rc.cost))
            } else if let _ = plan as? IDUnionPlan {
                return QueryPlanSimpleCost(cost: idPlanPriority * (lc.cost + rc.cost))
            } else if let _ = plan as? IDMinusPlan {
                return QueryPlanSimpleCost(cost: idPlanPriority * (lc.cost + 2.0 * rc.cost)) // value rhs more, since that is the one that is materialized
            } else if let _ = plan as? IDDiffPlan {
                return QueryPlanSimpleCost(cost: idPlanPriority * (lc.cost + 2.0 * rc.cost)) // value rhs more, since that is the one that is materialized
            } else {
//                print("[3] cost for ID plan: \(plan)")
            }
        } else {
//            print("[4] cost for ID plan: \(plan)")
        }
        return QueryPlanSimpleCost(cost: idPlanPriority * 100.0)
    }
    
    public func cost(for plan: QueryPlan) throws -> QueryPlanSimpleCost {
        if let _ = plan as? NullaryQueryPlan {
            if let p = plan as? QuadPlan {
                let q = p.quad
                var cost = boundQuadCost
                if q.subject.isVariable {
                    cost *= 7.5
                }
                if q.predicate.isVariable {
                    cost *= 2.5
                }
                if q.object.isVariable {
                    cost *= 5.0
                }
                if q.graph.isVariable {
                    cost *= 10.0
                }
                return QueryPlanSimpleCost(cost: cost)
            } else if let p = plan as? TablePlan {
                return QueryPlanSimpleCost(cost: Double(p.rows.count))
            } else if let _ = plan as? ServicePlan {
                return QueryPlanSimpleCost(cost: self.serviceCost)
            } else if let p = plan as? PathQueryPlan {
                var cost = boundQuadCost
                if p.subject.isVariable {
                    cost *= 7.5
                }
                if p.object.isVariable {
                    cost *= 5.0
                }
                if p.graph.isVariable {
                    cost *= 10.0
                }
                let pathPenalty = 10.0 // How much more costly is a path than a triple? We don't have a good way to know, so we just treat a path as a triple with a penalty
                return QueryPlanSimpleCost(cost: cost * pathPenalty)
            } else if let matplan = plan as? MaterializeTermsPlan {
                // cost to covert ID results to materialized results
                // with the priority we give to id plans (n = 1/2), we give the inverse penalty (0.9/n = 1.8 ~ 1/n)
                // to materialization so that using a trivial ID plan (e.g. MaterializeTermsPlan(IDQuadPlan())) is
                // roughly the same cost as doing it directly (QuadPlan()).
                // we don't want it to be exactly 1/n because some non-trivial plans that we would prefer might
                // end up having indistinguishable costs from a fully-materialized version (e.g. a hash join which
                // is composed of a sum of sub-costs).
                let idCost = try cost(for: matplan.idPlan)
                let penalty = (0.9 / idPlanPriority)
                let cost = QueryPlanSimpleCost(cost: penalty * idCost.cost)
                return cost
            } else {
                // TODO: store-provided query plans will appear here, but we don't know how to cost them
                return QueryPlanSimpleCost(cost: 1.0)
            }
        } else if let p = plan as? UnaryQueryPlan {
            let c = try cost(for: p.child)
            if let _ = plan as? ProjectPlan {
                return c
            } else if let _ = plan as? NextRowPlan {
                return c
            } else if let _ = plan as? DistinctPlan {
                return QueryPlanSimpleCost(cost: 2.0 * c.cost)
            } else if let _ = plan as? ReducedPlan {
                return c
            } else if let _ = plan as? LimitPlan {
                return c
            } else if let _ = plan as? OffsetPlan {
                return c
            } else if let _ = plan as? ReducedPlan {
                return c
            } else if let _ = plan as? OrderPlan {
                return QueryPlanSimpleCost(cost: c.cost * log(c.cost))
            } else if let _ = plan as? WindowPlan {
                return QueryPlanSimpleCost(cost: 2.0 * c.cost)
            } else if let _ = plan as? ExtendPlan {
                return QueryPlanSimpleCost(cost: 1.1 * c.cost)
            } else if let _ = plan as? FilterPlan {
                return QueryPlanSimpleCost(cost: 1.1 * c.cost)
            } else if let _ = plan as? HeapSortLimitPlan {
                return QueryPlanSimpleCost(cost: 1.2 * c.cost)
            } else if let _ = plan as? AggregationPlan {
                return QueryPlanSimpleCost(cost: 2.0 * c.cost)
            } else if let p = plan as? ExistsPlan {
                let patternCost = try cost(for: p.pattern)
                return QueryPlanSimpleCost(cost: c.cost + sqrt(patternCost.cost))
            } else if let p = plan as? UnaryQueryPlan, plan.selfDescription.contains("RestrictToNamedGraphsPlan") {
                // this is a string-based comparison because we don't know the generic type Q to test for RestrictToNamedGraphsPlan<Q>
                return try cost(for: p.child)
            }
        } else if let p = plan as? BinaryQueryPlan {
            let lhs = p.children[0]
            let rhs = p.children[1]
            let lc = try cost(for: lhs)
            let rc = try cost(for: rhs)
            if let p = plan as? HashJoinPlan {
                var penalty = 1.0
                let jv = p.joinVariables
                if jv.isEmpty {
                    penalty = 1000.0
                }
                return QueryPlanSimpleCost(cost: penalty * (lc.cost + joinRHSMaterializationPenalty * rc.cost)) // value rhs more, since that is the one that is materialized
            } else if let _ = plan as? NestedLoopJoinPlan {
                return QueryPlanSimpleCost(cost: lc.cost * joinRHSMaterializationPenalty * rc.cost)
            } else if let _ = plan as? DiffPlan {
                return QueryPlanSimpleCost(cost: lc.cost + 2.0 * rc.cost) // value rhs more, since that is the one that is materialized
            } else if let _ = plan as? UnionPlan {
                return QueryPlanSimpleCost(cost: lc.cost + rc.cost)
            } else if let _ = plan as? MinusPlan {
                return QueryPlanSimpleCost(cost: lc.cost + 2.0 * rc.cost) // value rhs more, since that is the one that is materialized
            }
        }
        
        print("Unrecognized query plan \(plan)")
        throw QueryPlanCostError.unrecognizedPlan(plan)
    }
}
