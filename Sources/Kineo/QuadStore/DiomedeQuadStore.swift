//
//  DiomedeQuadStore.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 5/26/20.
//

import Foundation
import SPARQLSyntax
import DiomedeQuadStore

extension DiomedeQuadStore: MutableQuadStoreProtocol {}
extension DiomedeQuadStore: LazyMaterializingQuadStore {}
extension DiomedeQuadStore: PlanningQuadStore {
    private func characteristicSetSatisfiableCardinality(_ algebra: Algebra, activeGraph: Term, dataset: DatasetProtocol, distinctStarSubject: Node? = nil) throws -> Int? {
        if case let .bgp(tps) = algebra, tps.allSatisfy({ (tp) in !tp.subject.isBound && !tp.object.isBound }) {
            let csDataset = try self.characteristicSets(for: activeGraph)
            let objectVariables = tps.compactMap { (tp) -> String? in if case .variable(let v, _) = tp.object { return v } else { return nil } }
            let objects = Set(objectVariables)
            
            // if these don't match, then there's at least one object variable that is used twice, meaning it's not a simple star
            guard objects.count == objectVariables.count else { return nil }

            if let v = distinctStarSubject {
                if !tps.allSatisfy({ (tp) in tp.subject == v }) {
                    return nil
                } else {
                    let acs = try csDataset.aggregatedCharacteristicSet(matching: tps, in: activeGraph, store: self)
                    return acs.count
                }
            } else {
                if let card = try? csDataset.starCardinality(matching: tps, in: activeGraph, store: self) {
                    return Int(card)
                }
            }
        } else if case let .triple(tp) = algebra, !tp.subject.isBound, !tp.object.isBound {
                return try characteristicSetSatisfiableCardinality(.bgp([tp]), activeGraph: activeGraph, dataset: dataset, distinctStarSubject: distinctStarSubject)
        } else if case let .namedGraph(child, .bound(g)) = algebra {
            guard dataset.namedGraphs.contains(g) else { return 0 }
            return try characteristicSetSatisfiableCardinality(child, activeGraph: g, dataset: dataset, distinctStarSubject: distinctStarSubject)
        }
        return nil
    }
    
    
    /// If `algebra` represents a COUNT(*) aggregation with no grouping, and the graph pattern being aggregated is a simple star
    /// (one subject variable, and all objects are non-shared variables), then compute the count statically using the database's
    /// Characteristic Sets, and return Table (static data) query plan.
    private func characteristicSetSatisfiableCountPlan(_ algebra: Algebra, activeGraph: Term, dataset: DatasetProtocol) throws -> QueryPlan? {
        // COUNT(*) with no GROUP BY over a triple pattern with unbound subject and object
        if case let .aggregate(child, [], aggs) = algebra {
            if aggs.count == 1, let a = aggs.first {
                let agg = a.aggregation
                switch agg {
                case .countAll:
                    if let card = try characteristicSetSatisfiableCardinality(child, activeGraph: activeGraph, dataset: dataset) {
                        let qp = TablePlan(columns: [.variable(a.variableName, binding: true)], rows: [[Term(integer: Int(card))]])
                        return qp
                    }
                case .count(_, false):
                    // COUNT(?v) can be answered by Characteristic Sets
                    if let card = try characteristicSetSatisfiableCardinality(child, activeGraph: activeGraph, dataset: dataset) {
                        let qp = TablePlan(columns: [.variable(a.variableName, binding: true)], rows: [[Term(integer: Int(card))]])
                        return qp
                    }
                case let .count(.node(v), true):
                    // COUNT(DISTINCT ?v) can be answered by Characteristic Sets only if ?v is the CS star subject
                    if let card = try characteristicSetSatisfiableCardinality(child, activeGraph: activeGraph, dataset: dataset, distinctStarSubject: v) {
                        let qp = TablePlan(columns: [.variable(a.variableName, binding: true)], rows: [[Term(integer: Int(card))]])
                        return qp
                    }
                default:
                    return nil
                }
            }
        }
        return nil
    }
    
    /// Returns a QueryPlan object for any algebra that can be efficiently executed by the QuadStore, nil for all others.
    public func plan(algebra: Algebra, activeGraph: Term, dataset: DatasetProtocol) throws -> QueryPlan? {
        if self.characteristicSetsAreAccurate {
            // Characteristic Sets are "accurate" is they were computed at or after the moment
            // when the last quad was inserted or deleted.
            if let qp = try self.characteristicSetSatisfiableCountPlan(algebra, activeGraph: activeGraph, dataset: dataset) {
                return qp
            }
        }
        switch algebra {
            //        case .triple(let t):
            //            return try plan(bgp: [t], activeGraph: activeGraph)
            //        case .bgp(let triples):
        //            return try plan(bgp: triples, activeGraph: activeGraph)
        default:
            return nil
        }
        return nil
    }
}

extension DiomedeQuadStore: PrefixNameStoringQuadStore {
    public var prefixes: [String : Term] {
        do {
            return try self.prefixes()
        } catch {
            return [:]
        }
    }
}
