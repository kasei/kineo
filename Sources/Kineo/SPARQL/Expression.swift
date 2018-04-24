//
//  Expression.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 7/31/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import CryptoSwift
import SPARQLSyntax

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
    
    private func _random() -> UInt32 {
        #if os(Linux)
        return UInt32(random() % Int(UInt32.max))
        #else
        return arc4random()
        #endif
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
        
//        print("Computing hash of \(data.debugDescription)")
        
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
            let v = Double(_random()) / Double(UINT32_MAX)
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
            let v = Double(_random()) / Double(UINT32_MAX)
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
