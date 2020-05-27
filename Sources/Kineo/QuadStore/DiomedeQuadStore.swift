//
//  DiomedeQuadStore.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 5/26/20.
//

import Foundation
import SPARQLSyntax
import DiomedeQuadStore

extension DiomedeQuadStore: MutableQuadStoreProtocol {
    public func results(matching pattern: QuadPattern) throws -> AnyIterator<TermResult> {
        let bindings = try self.bindings(matching: pattern)
        let results = bindings.lazy.map {
            TermResult(bindings: $0)
        }
        return AnyIterator(results.makeIterator())
    }
}
