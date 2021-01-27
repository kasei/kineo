//
//  QueryPlanCost.swift
//  Kineo
//
//  Created by GWilliams on 6/6/19.
//

import Foundation
import SPARQLSyntax

public enum QueryPlanCostError: Error {
    case unrecognizedPlan(QueryPlan)
}

public protocol QueryPlanCostEstimator {
    associatedtype QueryPlanCost
    func cheaperThan(lhs: QueryPlanCost, rhs: QueryPlanCost) -> Bool
    func cost(for plan: QueryPlan) throws -> QueryPlanCost
}

public extension QueryPlanCostEstimator {
    func cheaperThan(lhs: QueryPlan, rhs: QueryPlan) -> Bool {
        do {
            let lcost = try cost(for: lhs)
            let rcost = try cost(for: rhs)
            return cheaperThan(lhs: lcost, rhs: rcost)
        } catch let e {
            print("*** Failed to compute cost for query plans: \(e)")
            return false
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
    
    public func cheaperThan(lhs: QueryPlanSimpleCost, rhs: QueryPlanSimpleCost) -> Bool {
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
                print("TODO: improve cost estimation for path queries")
                return QueryPlanSimpleCost(cost: idPlanPriority * 20.0)
            }
            print("[1] cost for ID plan: \(plan)")
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
                let idQuadPlan = IDQuadPlan(pattern: pattern, repeatedVariables: [:], store: bindJoin.store)
                for (_, path) in bindJoin.bindings {
                    pattern[keyPath: path] = .bound(0)
                }
                let boundIDQuadPlan = IDQuadPlan(pattern: pattern, repeatedVariables: [:], store: bindJoin.store)
                let unboundProbeCost = try self.cost(for: idQuadPlan)
                let probeCost = try self.cost(for: boundIDQuadPlan)
//                print("bind join costs: \(unboundProbeCost) ; \(probeCost)")

                // TODO: try to determine the cost of bindJoin.pattern when all of the binding substitutions have been made, and incorporate that into the final cost
                return QueryPlanSimpleCost(cost: idPlanPriority * 2.0 * probeCost.cost * c.cost)
            } else {
                print("[2] cost for ID plan: \(plan)")
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
                return QueryPlanSimpleCost(cost: idPlanPriority * penalty * (lc.cost + joinRHSMaterializationPenalty * rc.cost)) // value rhs more, since that is the one that is materialized
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
                return QueryPlanSimpleCost(cost: (1.0 / mergePlanPriority) * idPlanPriority * (lc.cost + rc.cost))
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
                print("[3] cost for ID plan: \(plan)")
            }
        } else {
            print("[4] cost for ID plan: \(plan)")
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
            } else if let _ = plan as? PathQueryPlan {
                print("TODO: improve cost estimation for path queries")
                return QueryPlanSimpleCost(cost: 20.0)
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
