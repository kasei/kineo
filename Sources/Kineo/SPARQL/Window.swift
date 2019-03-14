//
//  Window.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 3/8/19.
//

import Foundation
import SPARQLSyntax

public struct WindowRowsRange {
    var from: Int?
    var to: Int?
    
    public func indices<C>(relativeTo results: C) -> Range<Int> where C : Collection, C.Indices == Range<Int> {
        let begin = from ?? Int.min
        let end = to ?? Int.max
        let window = begin...end
        let range = window.relative(to: results)
        return range.clamped(to: results.indices)
    }
    
    public mutating func slide(by offset: Int) {
        switch (from, to) {
        case (nil, nil):
            break
        case let (nil, .some(max)):
            to = max + offset
        case let (.some(min), nil):
            from = min + offset
        case let (.some(min), .some(max)):
            from = min + offset
            to = max + offset
        }
    }
}

public extension WindowFrame {
    private func offsetValue(for bound: FrameBound, evaluator ee: ExpressionEvaluator) throws -> Int? {
        switch bound {
        case .unbound:
            return nil
        case .current:
            return 0
        case .preceding(let expr):
            let term = try ee.evaluate(expression: expr, result: TermResult(bindings: [:]))
            guard let n = term.numeric else {
                throw QueryError.typeError("Window PRECEDING range bound value is not a numeric value")
            }
            let offset = Int(n.value)
            return -offset
        case .following(let expr):
            let term = try ee.evaluate(expression: expr, result: TermResult(bindings: [:]))
            guard let n = term.numeric else {
                throw QueryError.typeError("Window FOLLOWING range bound value is not a numeric value")
            }
            let offset = Int(n.value)
            return offset
        }
    }
    
    public func startRowsRange() throws -> WindowRowsRange {
        let ee = ExpressionEvaluator(base: nil)
        let begin = try offsetValue(for: from, evaluator: ee)
        let end = try offsetValue(for: to, evaluator: ee)
        return WindowRowsRange(from: begin, to: end)
    }
}
