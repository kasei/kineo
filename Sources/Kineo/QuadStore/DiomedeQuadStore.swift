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
extension DiomedeQuadStore: PlanningQuadStore {
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
