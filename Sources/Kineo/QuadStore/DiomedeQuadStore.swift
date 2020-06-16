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
    public func availableOrders(matching pattern: QuadPattern) throws -> [(order: [RDFQuadPosition], fullOrder: [RDFQuadPosition])] {
        var boundPositions = Set<Int>()
        for (i, n) in pattern.enumerated() {
            if case .bound = n {
                boundPositions.insert(i)
            }
        }
        
        var results = [(order: [RDFQuadPosition], fullOrder: [RDFQuadPosition])]()
        for i in try self.indexes(matchingBoundPositions: boundPositions) {
            let order = i.order()
            let removePrefixCount = order.prefix { boundPositions.contains($0) }.count
            let unbound = order.dropFirst(removePrefixCount)
            var positions = [Int: RDFQuadPosition]()
            for (i, p) in RDFQuadPosition.allCases.enumerated() {
                positions[i] = p
            }
            var ordering = [RDFQuadPosition]()
            var fullOrdering = [RDFQuadPosition]()
            for i in unbound {
                guard let p = positions[i] else { break }
                ordering.append(p)
            }
            for i in order {
                guard let p = positions[i] else { break }
                fullOrdering.append(p)
            }
            
            results.append((order: ordering, fullOrder: fullOrdering))
        }
        return results
    }
    
    public func quadIds(matching pattern: QuadPattern, orderedBy order: [RDFQuadPosition]) throws -> [[UInt64]] {
        let chars : [String] = order.map {
            switch $0 {
            case .subject:
                return "s"
            case .predicate:
                return "p"
            case .object:
                return "o"
            case .graph:
                return "g"
            }
        }
        let name = chars.joined()
        guard let bestIndex = IndexOrder.init(rawValue: name) else {
            throw DiomedeQuadStoreError.indexError("No such index \(name)")
        }
        
        let (prefix, restrictions) = try self.prefix(for: pattern, in: bestIndex)
        let quadids = try self.quadIds(usingIndex: bestIndex, withPrefix: prefix, restrictedBy: restrictions)
        return quadids
    }
    
    //    public func resultOrder(matching pattern: QuadPattern) throws -> [RDFQuadPosition] {
    //        var boundPositions = Set<Int>()
    //        for (i, n) in pattern.enumerated() {
    //            if case .bound = n {
    //                boundPositions.insert(i)
    //            }
    //        }
    //        guard let i = try self.bestIndex(matchingBoundPositions: boundPositions) else {
    //            return []
    //        }
    //        let order = i.order()
    //        let removePrefixCount = order.prefix { boundPositions.contains($0) }.count
    //        let unbound = order.dropFirst(removePrefixCount)
    //        var positions = [Int: RDFQuadPosition]()
    //        for (i, p) in RDFQuadPosition.allCases.enumerated() {
    //            positions[i] = p
    //        }
    //        var ordering = [RDFQuadPosition]()
    //        for i in unbound {
    //            guard let p = positions[i] else { break }
    //            ordering.append(p)
    //        }
    //
    //        return ordering
    //    }
    
    public func plan(algebra: Algebra, activeGraph: Term, dataset: Dataset) throws -> QueryPlan? {
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
