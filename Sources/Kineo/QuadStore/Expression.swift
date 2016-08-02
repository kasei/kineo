//
//  Expression.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 7/31/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation


extension Term {
    func ebv() throws -> Bool {
        switch type {
        case .datatype("http://www.w3.org/2001/XMLSchema#boolean"):
            return value == "true" || value == "1"
        case .datatype(_), .language(_):
            if self.isNumeric {
                return self.numericValue != 0.0
            } else {
                return value.characters.count > 0
            }
        default:
            throw QueryError.typeError("EBV cannot be computed for \(self)")
        }
    }
}

public indirect enum Expression : CustomStringConvertible {
    case node(Node)
    case eq(Expression, Expression)
    case ne(Expression, Expression)
    case between(Expression, Expression, Expression)
    case lt(Expression, Expression)
    case le(Expression, Expression)
    case gt(Expression, Expression)
    case ge(Expression, Expression)
    case add(Expression, Expression)
    case sub(Expression, Expression)
    case div(Expression, Expression)
    case mul(Expression, Expression)
    case neg(Expression)
    case and(Expression, Expression)
    case or(Expression, Expression)
    case not(Expression)
    case isiri(Expression)
    case isblank(Expression)
    case isliteral(Expression)
    case isnumeric(Expression)
    case call(String, [Expression])
    case lang(Expression)
    case datatype(Expression)
    case bound(Expression)
    //    case langmatches(Expression, String)
    // TODO: add other expression functions

    var isNumeric : Bool {
        switch self {
        case .node(_):
            return true
        case .neg(let expr):
            return expr.isNumeric
        case .add(let l, let r), .sub(let l, let r), .div(let l, let r), .mul(let l, let r):
            return l.isNumeric && r.isNumeric
        case .call("http://www.w3.org/2001/XMLSchema#integer", let exprs),
             .call("http://www.w3.org/2001/XMLSchema#float", let exprs),
             .call("http://www.w3.org/2001/XMLSchema#double", let exprs):
            if exprs.count == 1 {
                if exprs[0].isNumeric {
                    return true
                }
            }
        default:
            return false
        }
        return false
    }
    
    
    
    public func evaluate(result : TermResult) throws -> Term {
        switch self {
        case .node(.bound(let term)):
            return term
        case .node(.variable(let name, _)):
            if let term = result[name] {
                return term
            } else {
                throw QueryError.typeError("Variable ?\(name) is unbound in result \(result)")
            }
        case .and(let lhs, let rhs):
            let lval = try lhs.evaluate(result: result)
            if try lval.ebv() {
                let rval = try rhs.evaluate(result: result)
                if try rval.ebv() {
                    return Term.trueValue
                }
            }
            return Term.falseValue
        case .or(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), let lebv = try? lval.ebv() {
                if lebv {
                    return Term.trueValue
                }
            }
            let rval = try rhs.evaluate(result: result)
            if try rval.ebv() {
                return Term.trueValue
            }
            return Term.falseValue
        case .eq(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), let rval = try? rhs.evaluate(result: result) {
                return (lval == rval) ? Term.trueValue : Term.falseValue
            }
        case .ne(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), let rval = try? rhs.evaluate(result: result) {
                return (lval != rval) ? Term.trueValue : Term.falseValue
            }
        case .gt(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), let rval = try? rhs.evaluate(result: result) {
                return (lval > rval) ? Term.trueValue : Term.falseValue
            }
        case .between(let expr, let lower, let upper):
            if let val = try? expr.evaluate(result: result), let lval = try? lower.evaluate(result: result), let uval = try? upper.evaluate(result: result) {
                return (val <= uval && val >= lval) ? Term.trueValue : Term.falseValue
            }
        case .lt(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), let rval = try? rhs.evaluate(result: result) {
                return (lval < rval) ? Term.trueValue : Term.falseValue
            }
        case .ge(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), let rval = try? rhs.evaluate(result: result) {
                return (lval >= rval) ? Term.trueValue : Term.falseValue
            }
        case .le(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), let rval = try? rhs.evaluate(result: result) {
                return (lval <= rval) ? Term.trueValue : Term.falseValue
            }
        case .add(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), let rval = try? rhs.evaluate(result: result) {
                guard lval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                guard rval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                let value = lval.numericValue + rval.numericValue
                guard let type = lval.type.resultType(op: "+", operandType: rval.type) else { throw QueryError.typeError("Cannot determine resulting type for adding \(lval) and \(rval)") }
                guard let term = Term(numeric: value, type: type) else { throw QueryError.typeError("Cannot add \(lval) and \(rval) and produce a valid numeric term") }
                return term
            }
        case .sub(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), let rval = try? rhs.evaluate(result: result) {
                guard lval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                guard rval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                let value = lval.numericValue - rval.numericValue
                guard let type = lval.type.resultType(op: "-", operandType: rval.type) else { throw QueryError.typeError("Cannot determine resulting type for subtracting \(lval) and \(rval)") }
                guard let term = Term(numeric: value, type: type) else { throw QueryError.typeError("Cannot subtract \(lval) and \(rval) and produce a valid numeric term") }
                return term
            }
        case .mul(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), let rval = try? rhs.evaluate(result: result) {
                guard lval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                guard rval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                let value = lval.numericValue * rval.numericValue
                guard let type = lval.type.resultType(op: "*", operandType: rval.type) else { throw QueryError.typeError("Cannot determine resulting type for multiplying \(lval) and \(rval)") }
                guard let term = Term(numeric: value, type: type) else { throw QueryError.typeError("Cannot multiply \(lval) and \(rval) and produce a valid numeric term") }
                return term
            }
        case .div(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), let rval = try? rhs.evaluate(result: result) {
                guard lval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                guard rval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                let value = lval.numericValue / rval.numericValue
                guard let type = lval.type.resultType(op: "/", operandType: rval.type) else { throw QueryError.typeError("Cannot determine resulting type for dividing \(lval) and \(rval)") }
                guard let term = Term(numeric: value, type: type) else { throw QueryError.typeError("Cannot divide \(lval) and \(rval) and produce a valid numeric term") }
                return term
            }
            //        default:
            //            print("*** Cannot evaluate expression \(self)")
        //            throw QueryError.evaluationError("Cannot evaluate \(self) with result \(result)")
        case .neg(let expr):
            if let val = try? expr.evaluate(result: result) {
                guard let num = val.numeric else { throw QueryError.typeError("Value \(val) is not numeric") }
                let neg = -num
                return neg.term
            }
        case .not(let expr):
            let val = try expr.evaluate(result: result)
            let ebv = try val.ebv()
            return ebv ? Term.falseValue : Term.trueValue
        case .isiri(let expr):
            let val = try expr.evaluate(result: result)
            if case .iri = val.type {
                return Term.trueValue
            } else {
                return Term.falseValue
            }
        case .isblank(let expr):
            let val = try expr.evaluate(result: result)
            if case .blank = val.type {
                return Term.trueValue
            } else {
                return Term.falseValue
            }
        case .isliteral(let expr):
            let val = try expr.evaluate(result: result)
            if case .language(_) = val.type {
                return Term.trueValue
            } else if case .datatype(_) = val.type {
                return Term.trueValue
            } else {
                return Term.falseValue
            }
        case .isnumeric(let expr):
            let val = try expr.evaluate(result: result)
            if val.isNumeric {
                return Term.trueValue
            } else {
                return Term.falseValue
            }
        case .datatype(let expr):
            let val = try expr.evaluate(result: result)
            if case .datatype(let dt) = val.type {
                return Term(value: dt, type: .iri)
            } else if case .language(_) = val.type {
                return Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#", type: .iri)
            } else {
                throw QueryError.typeError("DATATYPE called with non-literal")
            }
        case .lang(let expr):
            let val = try expr.evaluate(result: result)
            if case .language(let l) = val.type {
                return Term(value: l, type: .datatype("http://www.w3.org/2001/XMLSchema#string"))
            } else {
                throw QueryError.typeError("LANG called with non-language-literal")
            }
        case .bound(let expr):
            if let _ = try? expr.evaluate(result: result) {
                return Term.trueValue
            } else {
                return Term.falseValue
            }
        case .call(let iri, let exprs):
            let terms = try exprs.map { try $0.evaluate(result: result) }
            switch iri {
            case "http://www.w3.org/2001/XMLSchema#integer":
                let term = terms[0]
                guard let n = term.numeric else { throw QueryError.typeError("Cannot coerce term to a numeric value") }
                return Term(integer: Int(n.value))
            case "http://www.w3.org/2001/XMLSchema#float":
                let term = terms[0]
                guard let n = term.numeric else { throw QueryError.typeError("Cannot coerce term to a numeric value") }
                return Term(float: n.value)
            case "http://www.w3.org/2001/XMLSchema#double":
                let term = terms[0]
                guard let n = term.numeric else { throw QueryError.typeError("Cannot coerce term to a numeric value") }
                return Term(double: n.value)
            default:
                throw QueryError.evaluationError("Failed to evaluate CALL(<\(iri)>(\(exprs)) with result \(result)")
            }
        }
        throw QueryError.evaluationError("Failed to evaluate \(self) with result \(result)")
    }
    
    public func numericEvaluate(result : TermResult) throws -> Numeric {
        //        print("numericEvaluate over result: \(result)")
        //        print("numericEvaluate expression: \(self)")
        //        guard self.isNumeric else { throw QueryError.evaluationError("Cannot compile expression as numeric") }
        switch self {
        case .node(.bound(let term)):
            guard term.isNumeric else { throw QueryError.typeError("Term is not numeric") }
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
            let val = try expr.numericEvaluate(result: result)
            return -val
        case .add(let lhs, let rhs):
            let lval = try lhs.numericEvaluate(result: result)
            let rval = try rhs.numericEvaluate(result: result)
            let value = lval + rval
            return value
        case .sub(let lhs, let rhs):
            let lval = try lhs.numericEvaluate(result: result)
            let rval = try rhs.numericEvaluate(result: result)
            let value = lval - rval
            return value
        case .mul(let lhs, let rhs):
            let lval = try lhs.numericEvaluate(result: result)
            let rval = try rhs.numericEvaluate(result: result)
            let value = lval * rval
            return value
        case .div(let lhs, let rhs):
            let lval = try lhs.numericEvaluate(result: result)
            let rval = try rhs.numericEvaluate(result: result)
            let value = lval / rval
            return value
        case .call("http://www.w3.org/2001/XMLSchema#integer", let exprs):
            guard exprs.count == 1 else { throw QueryError.evaluationError("Cannot numerically evaluate integer coercsion") }
            let val = try exprs[0].numericEvaluate(result: result)
            return .integer(Int(val.value))
        case .call("http://www.w3.org/2001/XMLSchema#float", let exprs):
            guard exprs.count == 1 else { throw QueryError.evaluationError("Cannot numerically evaluate float coercsion") }
            let val = try exprs[0].numericEvaluate(result: result)
            return .float(val.value)
        case .call("http://www.w3.org/2001/XMLSchema#double", let exprs):
            guard exprs.count == 1 else { throw QueryError.evaluationError("Cannot numerically evaluate double coercsion") }
            let val = try exprs[0].numericEvaluate(result: result)
            return .double(val.value)
        default:
            throw QueryError.evaluationError("Failed to numerically evaluate \(self) with result \(result)")
        }
    }
    
    public var description : String {
        switch self {
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
        case .not(let expr):
            return "NOT(\(expr))"
        case .isiri(let expr):
            return "ISIRI(\(expr))"
        case .isblank(let expr):
            return "ISBLANK(\(expr))"
        case .isliteral(let expr):
            return "ISLITERAL(\(expr))"
        case .isnumeric(let expr):
            return "ISNUMERIC(\(expr))"
        case .call(let iri, let exprs):
            let strings = exprs.map { $0.description }
            return "<\(iri)>(\(strings.joined(separator: ",")))"
        case .lang(let expr):
            return "LANG(\(expr))"
        case .datatype(let expr):
            return "DATATYPE(\(expr))"
        case .bound(let expr):
            return "BOUND(\(expr))"
        }
    }
}

class ExpressionParser {
    static func parseExpression(_ parts : [String]) throws -> Expression? {
        var stack = [Expression]()
        var i = parts.makeIterator()
        let parser = NTriplesPatternParser(reader: "")
        while let s = i.next() {
            switch s {
            case "||":
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.or(lhs, rhs))
            case "&&":
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.and(lhs, rhs))
            case "=":
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.eq(lhs, rhs))
            case "!=":
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.ne(lhs, rhs))
            case "between":
                let upper = stack.popLast()!
                let lower = stack.popLast()!
                let value = stack.popLast()!
                stack.append(.between(value, lower, upper))
            case "<":
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.lt(lhs, rhs))
            case ">":
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.gt(lhs, rhs))
            case "<=":
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.le(lhs, rhs))
            case ">=":
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.ge(lhs, rhs))
            case "+":
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.add(lhs, rhs))
            case "-":
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.sub(lhs, rhs))
            case "*":
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.mul(lhs, rhs))
            case "/":
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.div(lhs, rhs))
            case "not":
                let expr = stack.popLast()!
                stack.append(.not(expr))
            case "isiri":
                let expr = stack.popLast()!
                stack.append(.isiri(expr))
            case "isliteral":
                let expr = stack.popLast()!
                stack.append(.isliteral(expr))
            case "isblank":
                let expr = stack.popLast()!
                stack.append(.isblank(expr))
            case "isnumeric":
                let expr = stack.popLast()!
                stack.append(.isnumeric(expr))
            case "lang":
                let expr = stack.popLast()!
                stack.append(.lang(expr))
            case "datatype":
                let expr = stack.popLast()!
                stack.append(.datatype(expr))
            case "int":
                let expr = stack.popLast()!
                stack.append(.call("http://www.w3.org/2001/XMLSchema#integer", [expr]))
            case "float":
                let expr = stack.popLast()!
                stack.append(.call("http://www.w3.org/2001/XMLSchema#float", [expr]))
            case "double":
                let expr = stack.popLast()!
                stack.append(.call("http://www.w3.org/2001/XMLSchema#double", [expr]))
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
