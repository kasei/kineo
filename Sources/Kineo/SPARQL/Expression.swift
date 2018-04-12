//
//  Expression.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 7/31/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import CryptoSwift

extension Term {
    func ebv() throws -> Bool {
        switch type {
        case .datatype("http://www.w3.org/2001/XMLSchema#boolean"):
            return value == "true" || value == "1"
        case .datatype(_), .language(_):
            if self.isNumeric {
                return self.numericValue != 0.0
            } else {
                return value.count > 0
            }
        default:
            throw QueryError.typeError("EBV cannot be computed for \(self)")
        }
    }
}

public enum Aggregation {
    case countAll
    case count(Expression, Bool)
    case sum(Expression, Bool)
    case avg(Expression, Bool)
    case min(Expression)
    case max(Expression)
    case sample(Expression)
    case groupConcat(Expression, String, Bool)
}

extension Aggregation: Equatable {
    public static func == (lhs: Aggregation, rhs: Aggregation) -> Bool {
        switch (lhs, rhs) {
        case (.countAll, .countAll):
            return true
        case (.count(let l), .count(let r)) where l == r:
            return true
        case (.sum(let l), .sum(let r)) where l == r:
            return true
        case (.avg(let l), .avg(let r)) where l == r:
            return true
        case (.min(let l), .min(let r)) where l == r:
            return true
        case (.max(let l), .max(let r)) where l == r:
            return true
        case (.sample(let l), .sample(let r)) where l == r:
            return true
        case (.groupConcat(let l), .groupConcat(let r)) where l == r:
            return true
        default:
            return false
        }
    }
}

extension Aggregation: CustomStringConvertible {
    public var description: String {
        switch self {
        case .countAll:
            return "COUNT(*)"
        case .count(let expr, false):
            return "COUNT(\(expr.description))"
        case .count(let expr, true):
            return "COUNT(DISTINCT \(expr.description))"
        case .sum(let expr, false):
            return "SUM(\(expr.description))"
        case .sum(let expr, true):
            return "SUM(DISTINCT \(expr.description))"
        case .avg(let expr, false):
            return "AVG(\(expr.description))"
        case .avg(let expr, true):
            return "AVG(DISTINCT \(expr.description))"
        case .min(let expr):
            return "MIN(\(expr.description))"
        case .max(let expr):
            return "MAX(\(expr.description))"
        case .sample(let expr):
            return "SAMPLE(\(expr.description))"
        case .groupConcat(let expr, let sep, let distinct):
            let e = distinct ? "DISTINCT \(expr.description)" : expr.description
            if sep == " " {
                return "GROUP_CONCAT(\(e))"
            } else {
                return "GROUP_CONCAT(\(e); SEPARATOR=\"\(sep)\")"
            }
}
    }
}

// swiftlint:disable cyclomatic_complexity
// swiftlint:disable:next type_body_length
public indirect enum Expression: CustomStringConvertible {
    case node(Node)
    case aggregate(Aggregation)
    case neg(Expression)
    case not(Expression)
    case isiri(Expression)
    case isblank(Expression)
    case isliteral(Expression)
    case isnumeric(Expression)
    case lang(Expression)
    case langmatches(Expression, Expression)
    case datatype(Expression)
    case bound(Expression)
    case intCast(Expression)
    case floatCast(Expression)
    case doubleCast(Expression)
    case eq(Expression, Expression)
    case ne(Expression, Expression)
    case lt(Expression, Expression)
    case le(Expression, Expression)
    case gt(Expression, Expression)
    case ge(Expression, Expression)
    case add(Expression, Expression)
    case sub(Expression, Expression)
    case div(Expression, Expression)
    case mul(Expression, Expression)
    case and(Expression, Expression)
    case or(Expression, Expression)
    case between(Expression, Expression, Expression)
    case valuein(Expression, [Expression])
    case call(String, [Expression])
    case exists(Algebra)

    var hasAggregation: Bool {
        switch self {
        case .aggregate(_):
            return true
        case .node(_), .exists(_):
            return false
        case .not(let expr), .isiri(let expr), .isblank(let expr), .isliteral(let expr), .isnumeric(let expr), .lang(let expr), .datatype(let expr), .bound(let expr), .intCast(let expr), .floatCast(let expr), .doubleCast(let expr), .neg(let expr):
            return expr.hasAggregation
        case .eq(let lhs, let rhs), .ne(let lhs, let rhs), .lt(let lhs, let rhs), .le(let lhs, let rhs), .gt(let lhs, let rhs), .ge(let lhs, let rhs), .add(let lhs, let rhs), .sub(let lhs, let rhs), .div(let lhs, let rhs), .mul(let lhs, let rhs), .and(let lhs, let rhs), .or(let lhs, let rhs), .langmatches(let lhs, let rhs):
            return lhs.hasAggregation || rhs.hasAggregation
        case .between(let a, let b, let c):
            return a.hasAggregation || b.hasAggregation || c.hasAggregation
        case .call(_, let exprs):
            return exprs.reduce(false) { $0 || $1.hasAggregation }
        case .valuein(let expr, let exprs):
            return exprs.reduce(expr.hasAggregation) { $0 || $1.hasAggregation }
        }
    }

    func removeAggregations(_ counter: AnyIterator<Int>, mapping: inout [String:Aggregation]) -> Expression {
        switch self {
        case .node(_), .exists(_):
            return self
        case .neg(let expr):
            return .neg(expr.removeAggregations(counter, mapping: &mapping))
        case .not(let expr):
            return .not(expr.removeAggregations(counter, mapping: &mapping))
        case .isiri(let expr):
            return .isiri(expr.removeAggregations(counter, mapping: &mapping))
        case .isblank(let expr):
            return .isblank(expr.removeAggregations(counter, mapping: &mapping))
        case .isliteral(let expr):
            return .isliteral(expr.removeAggregations(counter, mapping: &mapping))
        case .isnumeric(let expr):
            return .isnumeric(expr.removeAggregations(counter, mapping: &mapping))
        case .lang(let expr):
            return .lang(expr.removeAggregations(counter, mapping: &mapping))
        case .langmatches(let expr, let pattern):
            return .langmatches(expr.removeAggregations(counter, mapping: &mapping), pattern.removeAggregations(counter, mapping: &mapping))
        case .datatype(let expr):
            return .datatype(expr.removeAggregations(counter, mapping: &mapping))
        case .bound(let expr):
            return .bound(expr.removeAggregations(counter, mapping: &mapping))
        case .intCast(let expr):
            return .intCast(expr.removeAggregations(counter, mapping: &mapping))
        case .floatCast(let expr):
            return .floatCast(expr.removeAggregations(counter, mapping: &mapping))
        case .doubleCast(let expr):
            return .doubleCast(expr.removeAggregations(counter, mapping: &mapping))
        case .call(let f, let exprs):
            return .call(f, exprs.map { $0.removeAggregations(counter, mapping: &mapping) })
        case .eq(let lhs, let rhs):
            return .eq(lhs.removeAggregations(counter, mapping: &mapping), rhs.removeAggregations(counter, mapping: &mapping))
        case .ne(let lhs, let rhs):
            return .ne(lhs.removeAggregations(counter, mapping: &mapping), rhs.removeAggregations(counter, mapping: &mapping))
        case .lt(let lhs, let rhs):
            return .lt(lhs.removeAggregations(counter, mapping: &mapping), rhs.removeAggregations(counter, mapping: &mapping))
        case .le(let lhs, let rhs):
            return .le(lhs.removeAggregations(counter, mapping: &mapping), rhs.removeAggregations(counter, mapping: &mapping))
        case .gt(let lhs, let rhs):
            return .gt(lhs.removeAggregations(counter, mapping: &mapping), rhs.removeAggregations(counter, mapping: &mapping))
        case .ge(let lhs, let rhs):
            return .ge(lhs.removeAggregations(counter, mapping: &mapping), rhs.removeAggregations(counter, mapping: &mapping))
        case .add(let lhs, let rhs):
            return .add(lhs.removeAggregations(counter, mapping: &mapping), rhs.removeAggregations(counter, mapping: &mapping))
        case .sub(let lhs, let rhs):
            return .sub(lhs.removeAggregations(counter, mapping: &mapping), rhs.removeAggregations(counter, mapping: &mapping))
        case .div(let lhs, let rhs):
            return .div(lhs.removeAggregations(counter, mapping: &mapping), rhs.removeAggregations(counter, mapping: &mapping))
        case .mul(let lhs, let rhs):
            return .mul(lhs.removeAggregations(counter, mapping: &mapping), rhs.removeAggregations(counter, mapping: &mapping))
        case .and(let lhs, let rhs):
            return .and(lhs.removeAggregations(counter, mapping: &mapping), rhs.removeAggregations(counter, mapping: &mapping))
        case .or(let lhs, let rhs):
            return .or(lhs.removeAggregations(counter, mapping: &mapping), rhs.removeAggregations(counter, mapping: &mapping))
        case .between(let a, let b, let c):
            return .between(a.removeAggregations(counter, mapping: &mapping), b.removeAggregations(counter, mapping: &mapping), c.removeAggregations(counter, mapping: &mapping))
        case .aggregate(let agg):
            guard let c = counter.next() else { fatalError("No fresh variable available") }
            let name = ".agg-\(c)"
            mapping[name] = agg
            let node: Node = .variable(name, binding: true)
            return .node(node)
        case .valuein(let expr, let exprs):
            return .valuein(expr.removeAggregations(counter, mapping: &mapping), exprs.map { $0.removeAggregations(counter, mapping: &mapping) })
        }
    }

    var isNumeric: Bool {
        switch self {
        case .node(.bound(let term)) where term.isNumeric:
            return true
        case .neg(let expr):
            return expr.isNumeric
        case .add(let l, let r), .sub(let l, let r), .div(let l, let r), .mul(let l, let r):
            return l.isNumeric && r.isNumeric
        case .intCast(let expr), .floatCast(let expr), .doubleCast(let expr):
            return expr.isNumeric
        default:
            return false
        }
    }

    public var description: String {
        switch self {
        case .aggregate(let a):
            return a.description
        case .node(let node):
            return node.description
        case .eq(let lhs, let rhs):
            return "(\(lhs) == \(rhs))"
        case .ne(let lhs, let rhs):
            return "(\(lhs) != \(rhs))"
        case .gt(let lhs, let rhs):
            return "(\(lhs) > \(rhs))"
        case .between(let val, let lower, let upper):
            return "(\(val) BETWEEN \(lower) AND \(upper))"
        case .lt(let lhs, let rhs):
            return "(\(lhs) < \(rhs))"
        case .ge(let lhs, let rhs):
            return "(\(lhs) >= \(rhs))"
        case .le(let lhs, let rhs):
            return "(\(lhs) <= \(rhs))"
        case .add(let lhs, let rhs):
            return "(\(lhs) + \(rhs))"
        case .sub(let lhs, let rhs):
            return "(\(lhs) - \(rhs))"
        case .mul(let lhs, let rhs):
            return "(\(lhs) * \(rhs))"
        case .div(let lhs, let rhs):
            return "(\(lhs) / \(rhs))"
        case .neg(let expr):
            return "-(\(expr))"
        case .and(let lhs, let rhs):
            return "(\(lhs) && \(rhs))"
        case .or(let lhs, let rhs):
            return "(\(lhs) || \(rhs))"
        case .isiri(let expr):
            return "ISIRI(\(expr))"
        case .isblank(let expr):
            return "ISBLANK(\(expr))"
        case .isliteral(let expr):
            return "ISLITERAL(\(expr))"
        case .isnumeric(let expr):
            return "ISNUMERIC(\(expr))"
        case .intCast(let expr):
            return "<http://www.w3.org/2001/XMLSchema#integer>(\(expr.description))"
        case .floatCast(let expr):
            return "<http://www.w3.org/2001/XMLSchema#float>(\(expr.description))"
        case .doubleCast(let expr):
            return "<http://www.w3.org/2001/XMLSchema#double>(\(expr.description))"
        case .call(let iri, let exprs):
            let strings = exprs.map { $0.description }
            return "<\(iri)>(\(strings.joined(separator: ",")))"
        case .lang(let expr):
            return "LANG(\(expr))"
        case .langmatches(let expr, let m):
            return "LANGMATCHES(\(expr), \"\(m)\")"
        case .datatype(let expr):
            return "DATATYPE(\(expr))"
        case .bound(let expr):
            return "BOUND(\(expr))"
        case .not(.valuein(let expr, let exprs)):
            let strings = exprs.map { $0.description }
            return "\(expr) NOT IN (\(strings.joined(separator: ",")))"
        case .valuein(let expr, let exprs):
            let strings = exprs.map { $0.description }
            return "\(expr) IN (\(strings.joined(separator: ",")))"
        case .not(.exists(let child)):
            return "NOT EXISTS { \(child) }"
        case .not(let expr):
            return "NOT(\(expr))"
        case .exists(let child):
            return "EXISTS { \(child) }"
        }
    }
}

extension Expression: Equatable {
    public static func == (lhs: Expression, rhs: Expression) -> Bool {
        switch (lhs, rhs) {
        case (.aggregate(let l), .aggregate(let r)) where l == r:
            return true
        case (.node(let l), .node(let r)) where l == r:
            return true
        case (.eq(let ll, let lr), .eq(let rl, let rr)) where ll == rl && lr == rr:
            return true
        case (.ne(let ll, let lr), .ne(let rl, let rr)) where ll == rl && lr == rr:
            return true
        case (.gt(let ll, let lr), .gt(let rl, let rr)) where ll == rl && lr == rr:
            return true
        case (.lt(let ll, let lr), .lt(let rl, let rr)) where ll == rl && lr == rr:
            return true
        case (.ge(let ll, let lr), .ge(let rl, let rr)) where ll == rl && lr == rr:
            return true
        case (.le(let ll, let lr), .le(let rl, let rr)) where ll == rl && lr == rr:
            return true
        case (.add(let ll, let lr), .add(let rl, let rr)) where ll == rl && lr == rr:
            return true
        case (.sub(let ll, let lr), .sub(let rl, let rr)) where ll == rl && lr == rr:
            return true
        case (.mul(let ll, let lr), .mul(let rl, let rr)) where ll == rl && lr == rr:
            return true
        case (.div(let ll, let lr), .div(let rl, let rr)) where ll == rl && lr == rr:
            return true
        case (.between(let l), .between(let r)) where l == r:
            return true
        case (.neg(let l), .neg(let r)) where l == r:
            return true
        case (.and(let ll, let lr), .and(let rl, let rr)) where ll == rl && lr == rr:
            return true
        case (.or(let ll, let lr), .or(let rl, let rr)) where ll == rl && lr == rr:
            return true
        case (.not(let l), .not(let r)) where l == r:
            return true
        case (.isiri(let l), .isiri(let r)) where l == r:
            return true
        case (.isblank(let l), .isblank(let r)) where l == r:
            return true
        case (.isliteral(let l), .isliteral(let r)) where l == r:
            return true
        case (.isnumeric(let l), .isnumeric(let r)) where l == r:
            return true
        case (.intCast(let l), .intCast(let r)) where l == r:
            return true
        case (.floatCast(let l), .floatCast(let r)) where l == r:
            return true
        case (.doubleCast(let l), .doubleCast(let r)) where l == r:
            return true
        case (.call(let l, let largs), .call(let r, let rargs)) where l == r && largs == rargs:
            return true
        case (.lang(let l), .lang(let r)) where l == r:
            return true
        case (.datatype(let l), .datatype(let r)) where l == r:
            return true
        case (.bound(let l), .bound(let r)) where l == r:
            return true
        case (.exists(let l), .exists(let r)) where l == r:
            return true
        default:
            return false
        }
    }
}

public extension Expression {
    func replace(_ map: (Expression) -> Expression?) -> Expression {
        if let e = map(self) {
            return e
        } else {
            switch self {
            case .node(_):
                return self
            case .aggregate(let a):
                return .aggregate(a.replace(map))
            case .neg(let expr):
                return .neg(expr.replace(map))
            case .eq(let lhs, let rhs):
                return .eq(lhs.replace(map), rhs.replace(map))
            case .ne(let lhs, let rhs):
                return .ne(lhs.replace(map), rhs.replace(map))
            case .gt(let lhs, let rhs):
                return .gt(lhs.replace(map), rhs.replace(map))
            case .lt(let lhs, let rhs):
                return .lt(lhs.replace(map), rhs.replace(map))
            case .ge(let lhs, let rhs):
                return .ge(lhs.replace(map), rhs.replace(map))
            case .le(let lhs, let rhs):
                return .le(lhs.replace(map), rhs.replace(map))
            case .add(let lhs, let rhs):
                return .add(lhs.replace(map), rhs.replace(map))
            case .sub(let lhs, let rhs):
                return .sub(lhs.replace(map), rhs.replace(map))
            case .mul(let lhs, let rhs):
                return .mul(lhs.replace(map), rhs.replace(map))
            case .div(let lhs, let rhs):
                return .div(lhs.replace(map), rhs.replace(map))
            case .between(let val, let lower, let upper):
                return .between(val.replace(map), lower.replace(map), upper.replace(map))
            case .and(let lhs, let rhs):
                return .and(lhs.replace(map), rhs.replace(map))
            case .or(let lhs, let rhs):
                return .or(lhs.replace(map), rhs.replace(map))
            case .isiri(let expr):
                return .isiri(expr.replace(map))
            case .isblank(let expr):
                return .isblank(expr.replace(map))
            case .isliteral(let expr):
                return .isliteral(expr.replace(map))
            case .isnumeric(let expr):
                return .isnumeric(expr.replace(map))
            case .intCast(let expr):
                return .intCast(expr.replace(map))
            case .floatCast(let expr):
                return .floatCast(expr.replace(map))
            case .doubleCast(let expr):
                return .doubleCast(expr.replace(map))
            case .call(let iri, let exprs):
                return .call(iri, exprs.map { $0.replace(map) })
            case .lang(let expr):
                return .lang(expr.replace(map))
            case .langmatches(let expr, let m):
                return .langmatches(expr.replace(map), m)
            case .datatype(let expr):
                return .datatype(expr.replace(map))
            case .bound(let expr):
                return .bound(expr.replace(map))
            case .valuein(let expr, let exprs):
                return .valuein(expr.replace(map), exprs.map { $0.replace(map) })
            case .not(let expr):
                return .not(expr.replace(map))
            case .exists(_):
                return self
            }
        }
    }
}

public extension Aggregation {
    func replace(_ map: (Expression) -> Expression?) -> Aggregation {
        switch self {
        case .countAll:
            return self
        case .count(let expr, let distinct):
            return .count(expr.replace(map), distinct)
        case .sum(let expr, let distinct):
            return .sum(expr.replace(map), distinct)
        case .avg(let expr, let distinct):
            return .avg(expr.replace(map), distinct)
        case .min(let expr):
            return .min(expr.replace(map))
        case .max(let expr):
            return .max(expr.replace(map))
        case .sample(let expr):
            return .sample(expr.replace(map))
        case .groupConcat(let expr, let sep, let distinct):
            return .groupConcat(expr.replace(map), sep, distinct)
        }
    }
}

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

class ExpressionEvaluator {
    public enum ConstructorFunction : String {
        case str = "STR"
        case uri = "URI"
        case iri = "IRI"
        case bnode = "BNODE"
        case strdt = "STRDT"
        case strlang = "STRLANG"
        case uuid = "UUID"
        case struuid = "STRUUID"
    }
    public enum StringFunction : String {
        case concat = "CONCAT"
        case str = "STR"
        case strlen = "STRLEN"
        case lcase = "LCASE"
        case ucase = "UCASE"
        case encode_for_uri = "ENCODE_FOR_URI"
        case datatype = "DATATYPE"
        case contains = "CONTAINS"
        case strstarts = "STRSTARTS"
        case strends = "STRENDS"
        case strbefore = "STRBEFORE"
        case strafter = "STRAFTER"
        case replace = "REPLACE"
        case regex = "REGEX"
    }

    public enum HashFunction : String {
        case md5 = "MD5"
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha384 = "SHA384"
        case sha512 = "SHA512"
    }
    
    public enum DateFunction : String {
        case now = "NOW"
        case year = "YEAR"
        case month = "MONTH"
        case day = "DAY"
        case hours = "HOURS"
        case minutes = "MINUTES"
        case seconds = "SECONDS"
        case timezone = "TIMEZONE"
        case tz = "TZ"
    }
    
    public enum NumericFunction : String {
        case rand = "RAND"
        case abs = "ABS"
        case round = "ROUND"
        case ceil = "CEIL"
        case floor = "FLOOR"
    }
    
    var bnodes: [String: String]
    var now: Date
    
    init() {
        self.bnodes = [:]
        self.now = Date()
    }
    
    public func nextResult() {
        self.bnodes = [:]
    }
    
    private func evaluate(dateFunction: DateFunction, terms: [Term?]) throws -> Term {
        if dateFunction == .now {
            if #available (OSX 10.12, *) {
                let f = W3CDTFLocatedDateFormatter()
                return Term(value: f.string(from: now), type: .datatype(Term.xsd("dateTime").value))
            } else {
                throw QueryError.evaluationError("OSX 10.12 is required to use date functions")
            }
        } else {
            guard terms.count == 1 else { throw QueryError.evaluationError("Wrong argument count for \(dateFunction) call") }
            guard let term = terms[0] else { throw QueryError.evaluationError("Not all arguments are bound in \(dateFunction) call") }
            guard let date = term.dateValue else { throw QueryError.evaluationError("Argument is not a valid xsd:dateTime value in \(dateFunction) call") }
            guard let tz = term.timeZone else { throw QueryError.evaluationError("Argument is not a valid xsd:dateTime value in \(dateFunction) call") }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = tz
            if dateFunction == .year {
                let value = calendar.component(.year, from: date)
                return Term(integer: value)
            } else if dateFunction == .month {
                let value = calendar.component(.month, from: date)
                return Term(integer: value)
            } else if dateFunction == .day {
                let value = calendar.component(.day, from: date)
                return Term(integer: value)
            } else if dateFunction == .hours {
                let value = calendar.component(.hour, from: date)
                return Term(integer: value)
            } else if dateFunction == .minutes {
                let value = calendar.component(.minute, from: date)
                return Term(integer: value)
            } else if dateFunction == .seconds {
                let value = calendar.component(.second, from: date)
                return Term(integer: value)
            } else if dateFunction == .timezone {
                let seconds = tz.secondsFromGMT()
                if seconds == 0 {
                    return Term(value: "PT0S", type: .datatype(Term.xsd("dayTimeDuration").value))
                } else {
                    let neg = seconds < 0 ? "-" : ""
                    let minutes = abs(seconds / 60) % 60
                    let hours = abs(seconds) / (60 * 60)
                    var string = "\(neg)PT\(hours)H"
                    if minutes > 0 {
                        string += "\(minutes)M"
                    }
                    return Term(value: string, type: .datatype(Term.xsd("dayTimeDuration").value))
                }
            } else if dateFunction == .tz {
                let seconds = tz.secondsFromGMT()
                if seconds == 0 {
                    return Term(string: "Z")
                } else {
                    let neg = seconds < 0 ? "-" : ""
                    let minutes = abs(seconds / 60) % 60
                    let hours = abs(seconds) / (60 * 60)
                    let string = String(format: "\(neg)%02d:%02d", hours, minutes)
                    return Term(string: string)
                }
            }
        }
        fatalError("unrecognized date function: \(dateFunction)")
    }
    
    private func evaluate(hashFunction: HashFunction, terms: [Term?]) throws -> Term {
        guard terms.count == 1 else {
            throw QueryError.evaluationError("Hash function invocation must be unary")
        }
        guard let term = terms[0] else {
            throw QueryError.evaluationError("Hash function invocation must be unary")
        }
        guard case .datatype("http://www.w3.org/2001/XMLSchema#string") = term.type else {
            throw QueryError.evaluationError("Hash function invocation must have simple literal operand")
        }
        let value = term.value
        guard let data = value.data(using: .utf8) else {
            throw QueryError.evaluationError("Hash function operand not valid utf8 data")
        }
        
        print("Computing hash of \(data.debugDescription)")
        
        let hashData : Data!
        switch hashFunction {
        case .md5:
            hashData = data.md5()
        case .sha1:
            hashData = data.sha1()
        case .sha256:
            hashData = data.sha256()
        case .sha384:
            hashData = data.sha384()
        case .sha512:
            hashData = data.sha512()
        }
        
        let hex = hashData.bytes.toHexString()
        return Term(string: hex)
    }
    
    private func evaluate(constructor constructorFunction: ConstructorFunction, terms: [Term?]) throws -> Term {
        switch constructorFunction {
        case .str:
            guard terms.count == 1 else { throw QueryError.evaluationError("Wrong argument count for \(constructorFunction) call") }
            guard let string = terms[0] else { throw QueryError.evaluationError("Not all arguments are bound in \(constructorFunction) call") }
            return Term(string: string.value)
        case .uri, .iri:
            guard terms.count == 1 else { throw QueryError.evaluationError("Wrong argument count for \(constructorFunction) call") }
            guard let string = terms[0] else { throw QueryError.evaluationError("Not all arguments are bound in \(constructorFunction) call") }
            return Term(value: string.value, type: .iri)
        case .bnode:
            guard terms.count <= 1 else { throw QueryError.evaluationError("Wrong argument count for \(constructorFunction) call") }
            if terms.count == 1 {
                guard let string = terms[0] else { throw QueryError.evaluationError("Not all arguments are bound in \(constructorFunction) call") }
                let name = string.value
                let id = self.bnodes[name] ?? NSUUID().uuidString
                self.bnodes[name] = id
                return Term(value: id, type: .blank)
            } else {
                let id = NSUUID().uuidString
                return Term(value: id, type: .blank)
            }
        case .strdt:
            guard terms.count == 2 else { throw QueryError.evaluationError("Wrong argument count for \(constructorFunction) call") }
            guard let string = terms[0], let datatype = terms[1] else { throw QueryError.evaluationError("Not all arguments are bound in \(constructorFunction) call") }
            return Term(value: string.value, type: .datatype(datatype.value))
        case .strlang:
            guard terms.count == 2 else { throw QueryError.evaluationError("Wrong argument count for \(constructorFunction) call") }
            guard let string = terms[0], let lang = terms[1] else { throw QueryError.evaluationError("Not all arguments are bound in \(constructorFunction) call") }
            return Term(value: string.value, type: .language(lang.value))
        case .uuid:
            guard terms.count == 0 else { throw QueryError.evaluationError("Wrong argument count for \(constructorFunction) call") }
            let id = NSUUID().uuidString.lowercased()
            return Term(value: "urn:uuid:\(id)", type: .iri)
        case .struuid:
            guard terms.count == 0 else { throw QueryError.evaluationError("Wrong argument count for \(constructorFunction) call") }
            let id = NSUUID().uuidString.lowercased()
            return Term(string: id)
        }
    }
    
    private func evaluate(stringFunction: StringFunction, terms: [Term?]) throws -> Term {
        switch stringFunction {
        case .concat:
            var types = Set<TermType>()
            var string = ""
            for term in terms.compactMap({ $0 }) {
                types.insert(term.type)
                string.append(term.value)
            }
            if types.count == 1 {
                return Term(value: string, type: types.first!)
            } else {
                return Term(string: string)
            }
        case .str, .strlen, .lcase, .ucase, .encode_for_uri, .datatype:
            guard terms.count == 1 else { throw QueryError.evaluationError("Wrong argument count for \(stringFunction) call") }
            guard let string = terms[0] else { throw QueryError.evaluationError("Not all arguments are bound in \(stringFunction) call") }
            if stringFunction == .str {
                return Term(string: string.value)
            } else if stringFunction == .strlen {
                return Term(integer: string.value.count)
            } else if stringFunction == .lcase {
                return Term(value: string.value.lowercased(), type: string.type)
            } else if stringFunction == .ucase {
                return Term(value: string.value.uppercased(), type: string.type)
            } else if stringFunction == .datatype {
                if case .datatype(let d) = string.type {
                    return Term(value: d, type: .iri)
                } else {
                    throw QueryError.evaluationError("DATATYPE called on on a non-datatyped term")
                }
            } else if stringFunction == .encode_for_uri {
                guard let encoded = string.value.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) else {
                    throw QueryError.evaluationError("Failed to encode string as a URI")
                }
                return Term(string: encoded)
            }
        case .contains, .strstarts, .strends, .strbefore, .strafter:
            guard terms.count == 2 else { throw QueryError.evaluationError("Wrong argument count for \(stringFunction) call") }
            guard let string = terms[0], let pattern = terms[1] else { throw QueryError.evaluationError("Not all arguments are bound in \(stringFunction) call") }
            if stringFunction == .contains {
                return Term(boolean: string.value.contains(pattern.value))
            } else if stringFunction == .strstarts {
                return Term(boolean: string.value.hasPrefix(pattern.value))
            } else if stringFunction == .strends {
                return Term(boolean: string.value.hasSuffix(pattern.value))
            } else if stringFunction == .strbefore {
                if let range = string.value.range(of: pattern.value) {
                    let index = range.lowerBound
                    let prefix = String(string.value[..<index])
                    return Term(value: prefix, type: string.type)
                } else {
                    return Term(string: "")
                }
            } else if stringFunction == .strafter {
                if let range = string.value.range(of: pattern.value) {
                    let index = range.upperBound
                    let suffix = String(string.value[index...])
                    return Term(value: suffix, type: string.type)
                } else {
                    return Term(string: "")
                }
            }
        case .replace:
            guard (3...4).contains(terms.count) else { throw QueryError.evaluationError("Wrong argument count for \(stringFunction) call") }
            guard let string = terms[0], let pattern = terms[1], let replacement = terms[2] else { throw QueryError.evaluationError("Not all arguments are bound in \(stringFunction) call") }
            let flags = Set((terms.count == 4 ? (terms[3]?.value ?? "") : ""))
            let options : String.CompareOptions = flags.contains("i") ? .caseInsensitive : .literal
            let value = string.value.replacingOccurrences(of: pattern.value, with: replacement.value, options: options)
            return Term(value: value, type: string.type)
        case .regex:
            guard (2...3).contains(terms.count) else { throw QueryError.evaluationError("Wrong argument count for \(stringFunction) call") }
            guard let string = terms[0], let pattern = terms[1] else { throw QueryError.evaluationError("Not all arguments are bound in \(stringFunction) call") }
            let flags = Set((terms.count == 3 ? (terms[2]?.value ?? "") : ""))
            let options : NSRegularExpression.Options = flags.contains("i") ? .caseInsensitive : []
            let regex = try NSRegularExpression(pattern: pattern.value, options: options)
            let s = string.value
            let range = NSRange(location: 0, length: s.utf16.count)
            return Term(boolean: regex.numberOfMatches(in: s, options: [], range: range) > 0)
        }
        throw QueryError.evaluationError("Unrecognized string function: \(stringFunction)")
    }
    
    private func evaluate(expression: Expression, numericFunction: NumericFunction, terms: [Term?]) throws -> Term {
        switch numericFunction {
        case .rand:
            let v = Double(arc4random()) / Double(UINT32_MAX)
            return Term(double: v)
        case .abs, .round, .ceil, .floor:
            guard terms.count == 1 else { throw QueryError.evaluationError("Wrong argument count for \(numericFunction) call") }
            guard let term = terms[0] else { throw QueryError.evaluationError("Not all arguments are bound in \(numericFunction) call") }
            guard term.isNumeric else { throw QueryError.evaluationError("Arguments is not numeric in \(numericFunction) call") }
            guard let numeric = term.numeric else { throw QueryError.evaluationError("Arguments is not numeric in \(numericFunction) call") }
            switch numericFunction {
            case .abs:
                return numeric.absoluteValue.term
            case .round:
                return numeric.round.term
            case .ceil:
                return numeric.ceil.term
            case .floor:
                return numeric.floor.term
            default:
                fatalError()
            }
        }
        throw QueryError.evaluationError("Unrecognized numeric function: \(numericFunction)")
    }
    
    private func evaluate(numericFunction: NumericFunction, terms: [Term?]) throws -> Term {
        switch numericFunction {
        case .rand:
            let v = Double(arc4random()) / Double(UINT32_MAX)
            return Term(double: v)
        case .abs, .round, .ceil, .floor:
            guard terms.count == 1 else { throw QueryError.evaluationError("Wrong argument count for \(numericFunction) call") }
            guard let term = terms[0] else { throw QueryError.evaluationError("Not all arguments are bound in \(numericFunction) call") }
            guard term.isNumeric else { throw QueryError.evaluationError("Arguments is not numeric in \(numericFunction) call") }
            guard let numeric = term.numeric else { throw QueryError.evaluationError("Arguments is not numeric in \(numericFunction) call") }
            switch numericFunction {
            case .abs:
                return numeric.absoluteValue.term
            case .round:
                return numeric.round.term
            case .ceil:
                return numeric.ceil.term
            case .floor:
                return numeric.floor.term
            default:
                fatalError()
            }
        }
        throw QueryError.evaluationError("Unrecognized numeric function: \(numericFunction)")
    }

    public func evaluate(expression: Expression, result: TermResult) throws -> Term {
        switch expression {
        case .aggregate(_):
            fatalError("cannot evaluate an aggregate expression without a query context")
        case .node(.bound(let term)):
            return term
        case .node(.variable(let name, _)):
            if let term = result[name] {
                return term
            } else {
                throw QueryError.typeError("Variable ?\(name) is unbound in result \(result)")
            }
        case .and(let lhs, let rhs):
            let lval = try evaluate(expression: lhs, result: result)
            if try lval.ebv() {
                let rval = try evaluate(expression: rhs, result: result)
                if try rval.ebv() {
                    return Term.trueValue
                }
            }
            return Term.falseValue
        case .or(let lhs, let rhs):
            if let lval = try? evaluate(expression: lhs, result: result), let lebv = try? lval.ebv() {
                if lebv {
                    return Term.trueValue
                }
            }
            let rval = try evaluate(expression: rhs, result: result)
            if try rval.ebv() {
                return Term.trueValue
            }
            return Term.falseValue
        case .eq(let lhs, let rhs):
            if let lval = try? evaluate(expression: lhs, result: result), let rval = try? evaluate(expression: rhs, result: result) {
                return (lval == rval) ? Term.trueValue: Term.falseValue
            }
        case .ne(let lhs, let rhs):
            if let lval = try? evaluate(expression: lhs, result: result), let rval = try? evaluate(expression: rhs, result: result) {
                return (lval != rval) ? Term.trueValue: Term.falseValue
            }
        case .gt(let lhs, let rhs):
            if let lval = try? evaluate(expression: lhs, result: result), let rval = try? evaluate(expression: rhs, result: result) {
                return (lval > rval) ? Term.trueValue: Term.falseValue
            }
        case .between(let expr, let lower, let upper):
            if let val = try? evaluate(expression: expr, result: result), let lval = try? evaluate(expression: lower, result: result), let uval = try? evaluate(expression: upper, result: result) {
                return (val <= uval && val >= lval) ? Term.trueValue: Term.falseValue
            }
        case .lt(let lhs, let rhs):
            if let lval = try? evaluate(expression: lhs, result: result), let rval = try? evaluate(expression: rhs, result: result) {
                return (lval < rval) ? Term.trueValue: Term.falseValue
            }
        case .ge(let lhs, let rhs):
            if let lval = try? evaluate(expression: lhs, result: result), let rval = try? evaluate(expression: rhs, result: result) {
                return (lval >= rval) ? Term.trueValue: Term.falseValue
            }
        case .le(let lhs, let rhs):
            if let lval = try? evaluate(expression: lhs, result: result), let rval = try? evaluate(expression: rhs, result: result) {
                return (lval <= rval) ? Term.trueValue: Term.falseValue
            }
        case .add(let lhs, let rhs):
            if let lval = try? evaluate(expression: lhs, result: result), let rval = try? evaluate(expression: rhs, result: result) {
                guard lval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                guard rval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                let value = lval.numericValue + rval.numericValue
                guard let type = lval.type.resultType(for: "+", withOperandType: rval.type) else { throw QueryError.typeError("Cannot determine resulting type for adding \(lval) and \(rval)") }
                guard let term = Term(numeric: value, type: type) else { throw QueryError.typeError("Cannot add \(lval) and \(rval) and produce a valid numeric term") }
                return term
            }
        case .sub(let lhs, let rhs):
            if let lval = try? evaluate(expression: lhs, result: result), let rval = try? evaluate(expression: rhs, result: result) {
                guard lval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                guard rval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                let value = lval.numericValue - rval.numericValue
                guard let type = lval.type.resultType(for: "-", withOperandType: rval.type) else { throw QueryError.typeError("Cannot determine resulting type for subtracting \(lval) and \(rval)") }
                guard let term = Term(numeric: value, type: type) else { throw QueryError.typeError("Cannot subtract \(lval) and \(rval) and produce a valid numeric term") }
                return term
            }
        case .mul(let lhs, let rhs):
            if let lval = try? evaluate(expression: lhs, result: result), let rval = try? evaluate(expression: rhs, result: result) {
                guard lval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                guard rval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                let value = lval.numericValue * rval.numericValue
                guard let type = lval.type.resultType(for: "*", withOperandType: rval.type) else { throw QueryError.typeError("Cannot determine resulting type for multiplying \(lval) and \(rval)") }
                guard let term = Term(numeric: value, type: type) else { throw QueryError.typeError("Cannot multiply \(lval) and \(rval) and produce a valid numeric term") }
                return term
            }
        case .div(let lhs, let rhs):
            if let lval = try? evaluate(expression: lhs, result: result), let rval = try? evaluate(expression: rhs, result: result) {
                guard lval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                guard rval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                let value = lval.numericValue / rval.numericValue
                guard let type = lval.type.resultType(for: "/", withOperandType: rval.type) else { throw QueryError.typeError("Cannot determine resulting type for dividing \(lval) and \(rval)") }
                guard let term = Term(numeric: value, type: type) else { throw QueryError.typeError("Cannot divide \(lval) and \(rval) and produce a valid numeric term") }
                return term
            }
            //        default:
            //            print("*** Cannot evaluate expression \(self)")
        //            throw QueryError.evaluationError("Cannot evaluate \(self) with result \(result)")
        case .neg(let expr):
            if let val = try? evaluate(expression: expr, result: result) {
                guard let num = val.numeric else { throw QueryError.typeError("Value \(val) is not numeric") }
                let neg = -num
                return neg.term
            }
        case .not(let expr):
            let val = try evaluate(expression: expr, result: result)
            let ebv = try val.ebv()
            return ebv ? Term.falseValue: Term.trueValue
        case .isiri(let expr):
            let val = try evaluate(expression: expr, result: result)
            if case .iri = val.type {
                return Term.trueValue
            } else {
                return Term.falseValue
            }
        case .isblank(let expr):
            let val = try evaluate(expression: expr, result: result)
            if case .blank = val.type {
                return Term.trueValue
            } else {
                return Term.falseValue
            }
        case .isliteral(let expr):
            let val = try evaluate(expression: expr, result: result)
            if case .language(_) = val.type {
                return Term.trueValue
            } else if case .datatype(_) = val.type {
                return Term.trueValue
            } else {
                return Term.falseValue
            }
        case .isnumeric(let expr):
            let val = try evaluate(expression: expr, result: result)
            if val.isNumeric {
                return Term.trueValue
            } else {
                return Term.falseValue
            }
        case .datatype(let expr):
            let val = try evaluate(expression: expr, result: result)
            if case .datatype(let dt) = val.type {
                return Term(value: dt, type: .iri)
            } else if case .language(_) = val.type {
                return Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#", type: .iri)
            } else {
                throw QueryError.typeError("DATATYPE called with non-literal")
            }
        case .bound(let expr):
            if let _ = try? evaluate(expression: expr, result: result) {
                return Term.trueValue
            } else {
                return Term.falseValue
            }
        case .intCast(let expr):
            let term = try evaluate(expression: expr, result: result)
            guard let n = term.numeric else { throw QueryError.typeError("Cannot coerce term to a numeric value") }
            return Term(integer: Int(n.value))
        case .floatCast(let expr):
            let term = try evaluate(expression: expr, result: result)
            guard let n = term.numeric else { throw QueryError.typeError("Cannot coerce term to a numeric value") }
            return Term(float: n.value)
        case .doubleCast(let expr):
            let term = try evaluate(expression: expr, result: result)
            guard let n = term.numeric else { throw QueryError.typeError("Cannot coerce term to a numeric value") }
            return Term(float: n.value)
        case .lang(let expr):
            let val = try evaluate(expression: expr, result: result)
            if case .language(let l) = val.type {
                return Term(value: l, type: .datatype("http://www.w3.org/2001/XMLSchema#string"))
            } else if case .datatype("http://www.w3.org/2001/XMLSchema#string") = val.type {
                return Term(string: "")
            } else {
                throw QueryError.typeError("LANG called with non-language-literal")
            }
        case .langmatches(let expr, let m):
            let string = try evaluate(expression: expr, result: result)
            let pattern = try evaluate(expression: m, result: result)
            if pattern.value == "*" {
                return Term(boolean: string.value.count > 0 ? true : false)
            } else {
                return Term(boolean: string.value.lowercased().hasPrefix(pattern.value.lowercased()))
            }
        case .call(let iri, let exprs):
            let terms = exprs.map { try? evaluate(expression: $0, result: result) }
            if let strFunc = StringFunction(rawValue: iri) {
                return try evaluate(stringFunction: strFunc, terms: terms)
            } else if let numericFunction = NumericFunction(rawValue: iri) {
                return try evaluate(numericFunction: numericFunction, terms: terms)
            } else if let constructorFunction = ConstructorFunction(rawValue: iri) {
                return try evaluate(constructor: constructorFunction, terms: terms)
            } else if let dateFunction = DateFunction(rawValue: iri) {
                return try evaluate(dateFunction: dateFunction, terms: terms)
            } else if let hash = HashFunction(rawValue: iri) {
                return try evaluate(hashFunction: hash, terms: terms)
            }
            switch iri {
            default:
                throw QueryError.evaluationError("Failed to evaluate CALL(<\(iri)>(\(exprs)) with result \(result)")
            }
        case .valuein(let expr, let exprs):
            let term = try evaluate(expression: expr, result: result)
            let terms = try exprs.map { try evaluate(expression: $0, result: result) }
            let contains = terms.index(of: term) == terms.startIndex
            return contains ? Term.trueValue: Term.falseValue
        case .exists(let lhs):
            print("*** Implement evaluation of EXISTS expression: \(lhs)")
        }
        throw QueryError.evaluationError("Failed to evaluate \(self) with result \(result)")
    }
    
    public func numericEvaluate(expression: Expression, result: TermResult) throws -> NumericValue {
        //        print("numericEvaluate over result: \(result)")
        //        print("numericEvaluate expression: \(self)")
        //        guard self.isNumeric else { throw QueryError.evaluationError("Cannot compile expression as numeric") }
        switch expression {
        case .aggregate(_):
            fatalError("cannot evaluate an aggregate expression without a query context")
        case .node(.bound(let term)):
            guard term.isNumeric else {
                throw QueryError.typeError("Term is not numeric in evaluation: \(term)")
            }
            if let num = term.numeric {
                return num
            } else {
                throw QueryError.typeError("Term is not numeric")
            }
        case .node(.variable(let name, binding: _)):
            if let term = result[name] {
                if let num = term.numeric {
                    return num
                } else {
                    throw QueryError.typeError("Term is not numeric")
                }
            } else {
                throw QueryError.typeError("Variable ?\(name) is unbound in result \(result)")
            }
        case .neg(let expr):
            let val = try numericEvaluate(expression: expr, result: result)
            return -val
        case .add(let lhs, let rhs):
            let lval = try numericEvaluate(expression: lhs, result: result)
            let rval = try numericEvaluate(expression: rhs, result: result)
            let value = lval + rval
            return value
        case .sub(let lhs, let rhs):
            let lval = try numericEvaluate(expression: lhs, result: result)
            let rval = try numericEvaluate(expression: rhs, result: result)
            let value = lval - rval
            return value
        case .mul(let lhs, let rhs):
            let lval = try numericEvaluate(expression: lhs, result: result)
            let rval = try numericEvaluate(expression: rhs, result: result)
            let value = lval * rval
            return value
        case .div(let lhs, let rhs):
            let lval = try numericEvaluate(expression: lhs, result: result)
            let rval = try numericEvaluate(expression: rhs, result: result)
            let value = lval / rval
            return value
        case .intCast(let expr):
            let val = try numericEvaluate(expression: expr, result: result)
            return .integer(Int(val.value))
        case .floatCast(let expr):
            let val = try numericEvaluate(expression: expr, result: result)
            return .float(mantissa: val.value, exponent: 0)
        case .doubleCast(let expr):
            let val = try numericEvaluate(expression: expr, result: result)
            return .double(mantissa: val.value, exponent: 0)
        default:
            throw QueryError.evaluationError("Failed to numerically evaluate \(self) with result \(result)")
        }
    }
}
