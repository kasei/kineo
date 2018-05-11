//
//  ExpressionParser.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 5/10/18.
//

import Foundation
import SPARQLSyntax

class ExpressionParser {
    static func parseExpression(_ parts: [String]) throws -> Expression? {
        var stack = [Expression]()
        var i = parts.makeIterator()
        let parser = NTriplesPatternParser(reader: "")
        while let s = i.next() {
            switch s {
            case "||":
                guard stack.count >= 2 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.or(lhs, rhs))
            case "&&":
                guard stack.count >= 2 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.and(lhs, rhs))
            case "=":
                guard stack.count >= 2 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.eq(lhs, rhs))
            case "!=":
                guard stack.count >= 2 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.ne(lhs, rhs))
            case "between":
                guard stack.count >= 3 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let upper = stack.popLast()!
                let lower = stack.popLast()!
                let value = stack.popLast()!
                stack.append(.between(value, lower, upper))
            case "<":
                guard stack.count >= 2 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.lt(lhs, rhs))
            case ">":
                guard stack.count >= 2 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.gt(lhs, rhs))
            case "<=":
                guard stack.count >= 2 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.le(lhs, rhs))
            case ">=":
                guard stack.count >= 2 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.ge(lhs, rhs))
            case "+":
                guard stack.count >= 2 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.add(lhs, rhs))
            case "-":
                guard stack.count >= 2 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.sub(lhs, rhs))
            case "neg":
                guard stack.count >= 1 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let expr = stack.popLast()!
                stack.append(.neg(expr))
            case "*":
                guard stack.count >= 2 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.mul(lhs, rhs))
            case "/":
                guard stack.count >= 2 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.div(lhs, rhs))
            case "not":
                guard stack.count >= 1 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let expr = stack.popLast()!
                stack.append(.not(expr))
            case "isiri":
                guard stack.count >= 1 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let expr = stack.popLast()!
                stack.append(.isiri(expr))
            case "isliteral":
                guard stack.count >= 1 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let expr = stack.popLast()!
                stack.append(.isliteral(expr))
            case "isblank":
                guard stack.count >= 1 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let expr = stack.popLast()!
                stack.append(.isblank(expr))
            case "isnumeric":
                guard stack.count >= 1 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let expr = stack.popLast()!
                stack.append(.isnumeric(expr))
            case "lang":
                guard stack.count >= 1 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let expr = stack.popLast()!
                stack.append(.lang(expr))
            case "datatype":
                guard stack.count >= 1 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let expr = stack.popLast()!
                stack.append(.datatype(expr))
            case "int":
                guard stack.count >= 1 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let expr = stack.popLast()!
                stack.append(.intCast(expr))
            case "float":
                guard stack.count >= 1 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let expr = stack.popLast()!
                stack.append(.floatCast(expr))
            case "double":
                guard stack.count >= 1 else { throw QueryError.parseError("Not enough expressions on the stack for \(s)") }
                let expr = stack.popLast()!
                stack.append(.doubleCast(expr))
            default:
                if let value = Double(s) {
                    stack.append(.node(.bound(Term(float: value))))
                } else {
                    guard let n = parser.parseNode(line: s) else { throw QueryError.parseError("Failed to parse expression: \(parts.joined(separator: " "))") }
                    stack.append(.node(n))
                }
            }
        }
        return stack.popLast()
    }
}

