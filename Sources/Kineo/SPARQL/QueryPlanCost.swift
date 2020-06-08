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
    var boundQuadCost: Double
    var serviceCost: Double
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
            }
            print("[1] cost for ID plan: \(plan)")
        } else if let p = plan as? UnaryIDQueryPlan {
            let c = try cost(for: p.child)
            if let _ = plan as? IDProjectPlan {
                return c
            } else if let _ = plan as? IDReducedPlan {
                return c
            } else if let _ = plan as? IDLimitPlan {
                return c
            } else if let _ = plan as? IDOffsetPlan {
                return c
            } else {
                print("[2] cost for ID plan: \(plan)")
            }
        } else if let p = plan as? BinaryIDQueryPlan {
            let lhs = p.children[0]
            let rhs = p.children[1]
            let lc = try cost(for: lhs)
            let rc = try cost(for: rhs)
            if let p = plan as? IDHashJoinPlan {
                var penalty = 1.0
                let jv = p.joinVariables
                if jv.isEmpty {
                    penalty = 1000.0
                }
                return QueryPlanSimpleCost(cost: penalty * (lc.cost + 2.0 * rc.cost)) // value rhs more, since that is the one that is materialized
            } else if let p = plan as? IDHashLeftJoinPlan {
                var penalty = 1.0
                let jv = p.joinVariables
                if jv.isEmpty {
                    penalty = 1000.0
                }
                return QueryPlanSimpleCost(cost: penalty * (lc.cost + 2.0 * rc.cost)) // value rhs more, since that is the one that is materialized
            } else if let _ = plan as? IDNestedLoopJoinPlan {
                return QueryPlanSimpleCost(cost: lc.cost * rc.cost)
            } else if let _ = plan as? IDNestedLoopLeftJoinPlan {
                return QueryPlanSimpleCost(cost: lc.cost * rc.cost)
            } else if let _ = plan as? IDUnionPlan {
                return QueryPlanSimpleCost(cost: lc.cost + rc.cost)
            } else if let _ = plan as? IDMinusPlan {
                return QueryPlanSimpleCost(cost: lc.cost + 2.0 * rc.cost) // value rhs more, since that is the one that is materialized
            } else {
                print("[3] cost for ID plan: \(plan)")
            }
        } else {
            print("[4] cost for ID plan: \(plan)")
        }
        return QueryPlanSimpleCost(cost: 100.0)
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
            } else if let matplan = plan as? MaterializePlan {
                return try cost(for: matplan.idPlan)
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
                return QueryPlanSimpleCost(cost: penalty * (lc.cost + 2.0 * rc.cost)) // value rhs more, since that is the one that is materialized
            } else if let _ = plan as? NestedLoopJoinPlan {
                return QueryPlanSimpleCost(cost: lc.cost * rc.cost)
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
