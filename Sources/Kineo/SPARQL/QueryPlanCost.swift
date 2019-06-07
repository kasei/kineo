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
    func cheaperThan(lhs: QueryPlan, rhs: QueryPlan) throws -> Bool {
        let lcost = try cost(for: lhs)
        let rcost = try cost(for: rhs)
        return cheaperThan(lhs: lcost, rhs: rcost)
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
}

public struct QueryPlanSimpleCostEstimator: QueryPlanCostEstimator {
    public init() {
        
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

    public func cost(for plan: QueryPlan) throws -> QueryPlanSimpleCost {
        if let _ = plan as? NullaryQueryPlan {
            if let p = plan as? QuadPlan {
                let q = p.quad
                var cost = 1.0
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
            } else if let _ = plan as? FilterPlan {
                return QueryPlanSimpleCost(cost: 1.1 * c.cost)
            } else if let _ = plan as? HeapSortLimitPlan {
                return QueryPlanSimpleCost(cost: 1.2 * c.cost)
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
                return QueryPlanSimpleCost(cost: penalty * (lc.cost + 2.0 * rc.cost)) // value rhs more, since that is the one that is materialized
            } else if let _ = plan as? NestedLoopJoinPlan {
                return QueryPlanSimpleCost(cost: lc.cost * rc.cost)
            } else if let _ = plan as? UnionPlan {
                return QueryPlanSimpleCost(cost: lc.cost + rc.cost)
            }
        }
        throw QueryPlanCostError.unrecognizedPlan(plan)
    }
}


/**
 
DiffPlan: BinaryQueryPlan
ExtendPlan: UnaryQueryPlan
NextRowPlan: UnaryQueryPlan
MinusPlan: BinaryQueryPlan
ServicePlan: NullaryQueryPlan
ExistsPlan: UnaryQueryPlan
PathQueryPlan: NullaryQueryPlan
AggregationPlan: UnaryQueryPlan

 **/
