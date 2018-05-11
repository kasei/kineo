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
        case .language(_), .datatype("http://www.w3.org/2001/XMLSchema#string"):
            return value.count > 0
        case _ where self.isNumeric:
            return self.numericValue != 0.0
        default:
            throw QueryError.typeError("EBV cannot be computed for \(self)")
        }
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
        case substr = "SUBSTR"
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
  
    public typealias AlgebraEvaluator = (Algebra, Term) throws -> AnyIterator<TermResult>

    var bnodes: [String: String]
    var now: Date
    var base: String?
    var activeGraph: Term?
    var algebraEvaluator: AlgebraEvaluator?
    
    init(base: String? = nil) {
        self.base = base
        self.bnodes = [:]
        self.now = Date()
        self.activeGraph = nil
        self.algebraEvaluator = nil
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
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            
            switch dateFunction {
            case .year:
                return Term(integer: calendar.component(.year, from: date))
            case .month:
                return Term(integer: calendar.component(.month, from: date))
            case .day:
                return Term(integer: calendar.component(.day, from: date))
            case .hours:
                return Term(integer: calendar.component(.hour, from: date))
            case .minutes:
                return Term(integer: calendar.component(.minute, from: date))
            case .seconds:
                return Term(decimal: Double(calendar.component(.second, from: date)))
            case .timezone:
                guard let tz = term.timeZone else { throw QueryError.evaluationError("Argument xsd:dateTime does not have a valid timezone in \(dateFunction) call") }
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
            case .tz:
                guard let tz = term.timeZone else { return Term(string: "") }
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
            case .now:
                return Term(dateTime: now, timeZone: term.timeZone)
            }
        }
    }
    
    private func evaluateCoalesce(terms: [Term?]) throws -> Term {
        let bound = terms.compactMap { $0 }
        guard let term = bound.first else {
            throw QueryError.evaluationError("COALESCE() function invocation did not produce any bound values")
        }
        return term
    }
    
    private func guardArity(_ items: Int, _ count: Int, _ function: String) throws {
        guard items == count else {
            throw QueryError.evaluationError("\(function) function invocation must have arity of \(count)")
        }
    }
    private func evaluateIf(terms: [Term?]) throws -> Term {
        try guardArity(terms.count, 3, "IF()")
        guard let term = terms[0] else {
            throw QueryError.evaluationError("IF() function conditional not found")
        }
        if let ebv = try? term.ebv() {
            let index = ebv ? 1 : 2
            guard let term = terms[index] else {
                throw QueryError.evaluationError("IF() \(ebv ? "true" : "false") branch evaluation caused an error")
            }
            return term
        } else {
            return Term.falseValue
        }
    }
    
    private func evaluate(hashFunction: HashFunction, terms: [Term?]) throws -> Term {
        try guardArity(terms.count, 1, "Hash")
        let term = terms[0]!
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
            try guardArity(terms.count, 1, constructorFunction.rawValue)
            guard let string = terms[0] else { throw QueryError.evaluationError("Not all arguments are bound in \(constructorFunction) call") }
            return Term(string: string.value)
        case .uri, .iri:
            try guardArity(terms.count, 1, constructorFunction.rawValue)
            guard let string = terms[0] else { throw QueryError.evaluationError("Not all arguments are bound in \(constructorFunction) call") }
            if let base = self.base {
                guard let b = URL(string: base), let i = URL(string: string.value, relativeTo: b) else {
                    throw QueryError.evaluationError("Failed to resolve IRI against base IRI")
                }
                return Term(value: i.absoluteString, type: .iri)
            } else {
                return Term(value: string.value, type: .iri)
            }
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
            try guardArity(terms.count, 2, constructorFunction.rawValue)
            guard let string = terms[0], let datatype = terms[1] else { throw QueryError.evaluationError("Not all arguments are bound in \(constructorFunction) call") }
            try throwUnlessSimpleLiteral(string)
            return Term(value: string.value, type: .datatype(datatype.value))
        case .strlang:
            try guardArity(terms.count, 2, constructorFunction.rawValue)
            guard let string = terms[0], let lang = terms[1] else { throw QueryError.evaluationError("Not all arguments are bound in \(constructorFunction) call") }
            try throwUnlessSimpleLiteral(string)
            return Term(value: string.value, type: .language(lang.value))
        case .uuid:
            try guardArity(terms.count, 0, constructorFunction.rawValue)
            let id = NSUUID().uuidString.lowercased()
            return Term(value: "urn:uuid:\(id)", type: .iri)
        case .struuid:
            try guardArity(terms.count, 0, constructorFunction.rawValue)
            let id = NSUUID().uuidString.lowercased()
            return Term(string: id)
        }
    }
    
    private func throwUnlessStringLiteral(_ term: Term) throws {
        if !term.isStringLiteral {
            throw QueryError.evaluationError("Operand must be a string literal")
        }
    }
    
    private func throwUnlessSimpleLiteral(_ term: Term) throws {
        if !term.isSimpleLiteral {
            throw QueryError.evaluationError("Operand must be a simple literal")
        }
    }
    
    private func throwUnlessArgumentCompatible(_ lhs: Term, _ rhs: Term) throws {
        if lhs.isSimpleLiteral && rhs.isSimpleLiteral {
            return
        }
        
        switch (lhs.type, rhs.type) {
        case let (.language(llang), .language(rlang)) where llang == rlang:
            return
        case (.language(_), .datatype("http://www.w3.org/2001/XMLSchema#string")):
            return
        default:
            throw QueryError.evaluationError("Operands must be argument-compatible")
        }
    }
    
    private func evaluate(stringFunction: StringFunction, terms: [Term?]) throws -> Term {
        switch stringFunction {
        case .concat:
            var types = Set<TermType>()
            var string = ""
            for term in terms.compactMap({ $0 }) {
                try throwUnlessStringLiteral(term)
                types.insert(term.type)
                string.append(term.value)
            }
            if types.count == 1 {
                return Term(value: string, type: types.first!)
            } else {
                return Term(string: string)
            }
        case .str, .strlen, .lcase, .ucase, .encode_for_uri, .datatype:
            try guardArity(terms.count, 1, stringFunction.rawValue)
            guard let string = terms[0] else { throw QueryError.evaluationError("Not all arguments are bound in \(stringFunction) call") }
            switch stringFunction {
            case .str:
                return Term(string: string.value)
            case .strlen:
                return Term(integer: string.value.count)
            case .lcase:
                return Term(value: string.value.lowercased(), type: string.type)
            case .ucase:
                return Term(value: string.value.uppercased(), type: string.type)
            case .datatype:
                guard case .datatype(let d) = string.type else { throw QueryError.evaluationError("DATATYPE called on on a non-datatyped term") }
                return Term(value: d, type: .iri)
            case .encode_for_uri:
                guard let encoded = string.value.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) else {
                    throw QueryError.evaluationError("Failed to encode string as a URI")
                }
                return Term(string: encoded)
            default:
                fatalError()
            }
        case .contains, .strstarts, .strends, .strbefore, .strafter:
            try guardArity(terms.count, 2, stringFunction.rawValue)
            guard let string = terms[0], let pattern = terms[1] else { throw QueryError.evaluationError("Not all arguments are bound in \(stringFunction) call") }
            try throwUnlessArgumentCompatible(string, pattern)
            if stringFunction == .contains {
                return Term(boolean: string.value.contains(pattern.value))
            } else if stringFunction == .strstarts {
                return Term(boolean: string.value.hasPrefix(pattern.value))
            } else if stringFunction == .strends {
                return Term(boolean: string.value.hasSuffix(pattern.value))
            } else if stringFunction == .strbefore {
                guard pattern.value != "" else { return Term(value: "", type: string.type) }
                if let range = string.value.range(of: pattern.value) {
                    let prefix = String(string.value[..<range.lowerBound])
                    return Term(value: prefix, type: string.type)
                } else {
                    return Term(string: "")
                }
            } else if stringFunction == .strafter {
                guard pattern.value != "" else { return string }
                if let range = string.value.range(of: pattern.value) {
                    let suffix = String(string.value[range.upperBound...])
                    return Term(value: suffix, type: string.type)
                } else {
                    return Term(string: "")
                }
            }
        case .replace:
            guard (3...4).contains(terms.count) else { throw QueryError.evaluationError("Wrong argument count for \(stringFunction) call") }
            guard let string = terms[0], let pattern = terms[1], let replacement = terms[2] else { throw QueryError.evaluationError("Not all arguments are bound in \(stringFunction) call") }
            try throwUnlessStringLiteral(string)
            let flags = Set((terms.count == 4 ? (terms[3]?.value ?? "") : ""))
            
            let options : NSRegularExpression.Options = flags.contains("i") ? .caseInsensitive : []
            let regex = try NSRegularExpression(pattern: pattern.value, options: options)
            let s = string.value
            let range = NSRange(location: 0, length: s.utf16.count)
            let value = regex.stringByReplacingMatches(in: string.value, options: [], range: range, withTemplate: replacement.value)
            return Term(value: value, type: string.type)
        case .regex, .substr:
            guard (2...3).contains(terms.count) else { throw QueryError.evaluationError("Wrong argument count for \(stringFunction) call") }
            guard let string = terms[0] else { throw QueryError.evaluationError("Not all arguments are bound in \(stringFunction) call") }
            if stringFunction == .regex {
                guard let pattern = terms[1] else { throw QueryError.evaluationError("Not all arguments are bound in \(stringFunction) call") }
                try throwUnlessStringLiteral(string)
                try throwUnlessSimpleLiteral(pattern)
                let flags = Set((terms.count == 3 ? (terms[2]?.value ?? "") : ""))
                let options : NSRegularExpression.Options = flags.contains("i") ? .caseInsensitive : []
                let regex = try NSRegularExpression(pattern: pattern.value, options: options)
                let s = string.value
                let range = NSRange(location: 0, length: s.utf16.count)
                return Term(boolean: regex.numberOfMatches(in: s, options: [], range: range) > 0)
            } else if stringFunction == .substr {
                guard let fromTerm = terms[1] else { throw QueryError.evaluationError("Not all arguments are bound in \(stringFunction) call") }
                let from = Int(fromTerm.numericValue)
                let fromIndex = string.value.index(string.value.startIndex, offsetBy: from-1)
                if terms.count == 2 {
                    let toIndex = string.value.endIndex
                    let value = string.value[fromIndex..<toIndex]
                    return Term(value: String(value), type: string.type)
                } else {
                    let lenTerm = terms[2]!
                    let len = Int(lenTerm.numericValue)
                    let toIndex = string.value.index(fromIndex, offsetBy: len)
                    let value = string.value[fromIndex..<toIndex]
                    return Term(value: String(value), type: string.type)
                }
            }
        }
        throw QueryError.evaluationError("Unrecognized string function: \(stringFunction)")
    }
    
    private func evaluate(numericFunction: NumericFunction, terms: [Term?]) throws -> Term {
        switch numericFunction {
        case .rand:
            let v = Double(_random()) / Double(UINT32_MAX)
            return Term(double: v)
        case .abs, .round, .ceil, .floor:
            try guardArity(terms.count, 1, numericFunction.rawValue)
            guard let term = terms[0] else { throw QueryError.evaluationError("Not all arguments are bound in \(numericFunction) call") }
            guard let numeric = term.numeric else { throw QueryError.evaluationError("Argument is not numeric in \(numericFunction) call") }
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

    // TODO: this isn't really an escaping closure, but swift can't tell that
    public func evaluate(expression: Expression, result: TermResult, activeGraph: Term, existsHandler: @escaping AlgebraEvaluator) throws -> Term {
        let previousGraph = activeGraph
        self.activeGraph = activeGraph
        self.algebraEvaluator = existsHandler
        defer {
            self.activeGraph = previousGraph
            self.algebraEvaluator = nil
        }
        let term = try self.evaluate(expression: expression, result: result)
        return term
    }
    
    public func evaluate(expression: Expression, result: TermResult) throws -> Term {
        switch expression {
        case .aggregate(_):
            fatalError("cannot evaluate an aggregate expression without a query context: \(expression)")
        case .node(.bound(let term)):
            return term
        case .node(.variable(let name, _)):
            if let term = result[name] {
                return term
            } else {
                throw QueryError.typeError("Variable ?\(name) is unbound in result \(result)")
            }
        case let .and(lhs, rhs):
            let lval = try evaluate(expression: lhs, result: result)
            if try lval.ebv() {
                let rval = try evaluate(expression: rhs, result: result)
                if try rval.ebv() {
                    return Term.trueValue
                }
            }
            return Term.falseValue
        case let .or(lhs, rhs):
            let lval = try? evaluate(expression: lhs, result: result)
            if let lv = lval, let lebv = try? lv.ebv() {
                if lebv {
                    return Term.trueValue
                }
            }
            let rval = try evaluate(expression: rhs, result: result)
            if try rval.ebv() {
                return Term.trueValue
            } else if lval == nil {
                print("logical-or resulted in error||false")
                throw QueryError.typeError("logical-or resulted in error||false")
            }
            return Term.falseValue
        case let .eq(lhs, rhs), let .ne(lhs, rhs), let .gt(lhs, rhs), let .lt(lhs, rhs), let .ge(lhs, rhs), let .le(lhs, rhs):
            if let lval = try? evaluate(expression: lhs, result: result), let rval = try? evaluate(expression: rhs, result: result) {
                let c = try lval.sparqlCompare(rval)
                switch expression {
                case .eq:
                    return (c == .equals) ? Term.trueValue: Term.falseValue
                case .ne:
                    return (c != .equals) ? Term.trueValue: Term.falseValue
                case .gt:
                    return (c == .greaterThan) ? Term.trueValue: Term.falseValue
                case .lt:
                    return (c == .lessThan) ? Term.trueValue: Term.falseValue
                case .ge:
                    return (c != .lessThan) ? Term.trueValue: Term.falseValue
                case .le:
                    return (c != .greaterThan) ? Term.trueValue: Term.falseValue
                }
            }
        case .between(let expr, let lower, let upper):
            if let val = try? evaluate(expression: expr, result: result), let lval = try? evaluate(expression: lower, result: result), let uval = try? evaluate(expression: upper, result: result) {
                return (val <= uval && val >= lval) ? Term.trueValue: Term.falseValue
            }
        case .neg(let expr):
            if let val = try? evaluate(expression: expr, result: result) {
                guard let num = val.numeric else { throw QueryError.typeError("Value \(val) is not numeric") }
                let neg = -num
                return neg.term
            }
        case let .add(lhs, rhs), let .sub(lhs, rhs), let .mul(lhs, rhs), let .div(lhs, rhs):
            if let lval = try? evaluate(expression: lhs, result: result), let rval = try? evaluate(expression: rhs, result: result) {
                guard lval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                guard rval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                let value: Double
                let termType: TermType?
                switch expression {
                case .add:
                    value = lval.numericValue + rval.numericValue
                    termType = lval.type.resultType(for: "+", withOperandType: rval.type)
                case .sub:
                    value = lval.numericValue - rval.numericValue
                    termType = lval.type.resultType(for: "-", withOperandType: rval.type)
                case .mul:
                    value = lval.numericValue * rval.numericValue
                    termType = lval.type.resultType(for: "*", withOperandType: rval.type)
                case .div:
                    guard rval.numericValue != 0.0 else { throw QueryError.typeError("Cannot divide by zero") }
                    value = lval.numericValue / rval.numericValue
                    termType = lval.type.resultType(for: "/", withOperandType: rval.type)
                }
                guard let type = termType else { throw QueryError.typeError("Cannot determine resulting numeric type for combining \(lval) and \(rval)") }
                guard let term = Term(numeric: value, type: type) else { throw QueryError.typeError("Cannot combine \(lval) and \(rval) and produce a valid numeric term") }
                return term
            }
        case .not(let expr):
            let val = try evaluate(expression: expr, result: result)
            let ebv = try val.ebv()
            return Term.boolean(!ebv)
        case .isiri(let expr):
            let val = try evaluate(expression: expr, result: result)
            return Term.boolean(val.type == .iri)
        case .isblank(let expr):
            let val = try evaluate(expression: expr, result: result)
            return Term.boolean(val.type == .blank)
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
            return Term.boolean(val.isNumeric)
        case .datatype(let expr):
            let val = try evaluate(expression: expr, result: result)
            if case .datatype(let dt) = val.type {
                return Term(value: dt, type: .iri)
            } else if case .language(_) = val.type {
                return Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#langString", type: .iri)
            } else {
                throw QueryError.typeError("DATATYPE called with non-literal")
            }
        case .bound(let expr):
            if let _ = try? evaluate(expression: expr, result: result) {
                return Term.trueValue
            } else {
                return Term.falseValue
            }
        case .boolCast(let expr):
            let term = try evaluate(expression: expr, result: result)
            if let n = term.numeric {
                return Term(boolean: n.value != 0.0)
            } else if term.value == "true" {
                return Term(boolean: true)
            } else if term.value == "false" {
                return Term(boolean: false)
            } else {
                throw QueryError.typeError("Cannot coerce term to a numeric value")
            }
        case .intCast(let expr):
            let term = try evaluate(expression: expr, result: result)
            if let n = term.numeric {
                return Term(integer: Int(n.value))
            } else if let v = Int(term.value) {
                return Term(integer: v)
            } else {
                throw QueryError.typeError("Cannot coerce term to a numeric value")
            }
        case .floatCast(let expr):
            let term = try evaluate(expression: expr, result: result)
            if let n = term.numeric {
                return Term(float: n.value)
            } else if let v = Double(term.value) {
                return Term(float: v)
            } else {
                throw QueryError.typeError("Cannot coerce term to a numeric value")
            }
        case .doubleCast(let expr):
            let term = try evaluate(expression: expr, result: result)
            if let n = term.numeric {
                return Term(double: n.value)
            } else if let v = Double(term.value) {
                return Term(double: v)
            } else {
                throw QueryError.typeError("Cannot coerce term to a numeric value")
            }
        case .decimalCast(let expr):
            let term = try evaluate(expression: expr, result: result)
            if let n = term.numeric {
                return Term(decimal: n.value)
            } else if let v = Double(term.value) {
                let cs = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".+-")).inverted
                if term.value.rangeOfCharacter(from: cs) == nil {
                    return Term(decimal: v)
                }
            } else {
                throw QueryError.typeError("Cannot coerce term to a numeric value")
            }
        case .dateCast(let expr):
            let term = try evaluate(expression: expr, result: result)
            if #available (OSX 10.12, *) {
                let f = ISO8601DateFormatter()
                f.formatOptions.remove(.withTimeZone)
                if let _ = f.date(from: term.value) {
                    return Term(value: term.value, type: .datatype("http://www.w3.org/2001/XMLSchema#date"))
                }
            }
            throw QueryError.typeError("Cannot coerce term to a date value")
        case .dateTimeCast(let expr):
            let term = try evaluate(expression: expr, result: result)
            if #available (OSX 10.12, *) {
                let f = ISO8601DateFormatter()
                f.formatOptions.remove(.withTimeZone)
                if let _ = f.date(from: term.value) {
                    return Term(value: term.value, type: .datatype("http://www.w3.org/2001/XMLSchema#dateTime"))
                }
            }
            throw QueryError.typeError("Cannot coerce term to a dateTime value")
        case .stringCast(let expr):
            let term = try evaluate(expression: expr, result: result)
            return Term(string: term.value)
        case .lang(let expr):
            let val = try evaluate(expression: expr, result: result)
            if case .language(let l) = val.type {
                return Term(string: l)
            } else if case .datatype(_) = val.type {
                return Term(string: "")
            } else {
                throw QueryError.typeError("LANG called with non-language-literal")
            }
        case let .sameterm(lhs, rhs):
            let l = try evaluate(expression: lhs, result: result)
            let r = try evaluate(expression: rhs, result: result)
            return (l == r) ? Term.trueValue : Term.falseValue
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
            } else if iri == "IF" {
                return try evaluateIf(terms: terms)
            } else if iri == "COALESCE" {
                return try evaluateCoalesce(terms: terms)
            }
            switch iri {
            default:
                throw QueryError.evaluationError("Failed to evaluate CALL(<\(iri)>(\(exprs)) with result \(result)")
            }
        case .valuein(let expr, let exprs):
            let term = try evaluate(expression: expr, result: result)
            let terms = try exprs.map { try evaluate(expression: $0, result: result) }
            if let _ = terms.index(of: term) {
                return Term.trueValue
            } else {
                return Term.falseValue
            }
        case .exists(let algebra):
            if let ae = algebraEvaluator, let ag = activeGraph {
                let a = try algebra.replace(result.bindings)
                let i = try ae(a, ag)
                if let _ = i.next() {
                    return Term.trueValue
                } else {
                    return Term.falseValue
                }
            } else {
                throw QueryError.evaluationError("Failed to evaluate EXISTS in a Query Evaluator that lacks an AlgebraEvaluator")
            }
        }
        throw QueryError.evaluationError("Failed to evaluate \(expression) with result \(result)")
    }
    
    public func numericEvaluate(expression: Expression, result: TermResult) throws -> NumericValue {
        switch expression {
        case .aggregate(_):
            fatalError("cannot evaluate an aggregate expression without a query context")
        case .node(.bound(let term)):
            if let num = term.numeric {
                return num
            } else {
                throw QueryError.typeError("Term is not numeric in evaluation: \(term)")
            }
        case .node(.variable(let name, binding: _)):
            if let term = result[name] {
                if let num = term.numeric {
                    return num
                } else {
                    throw QueryError.typeError("Term is not numeric in evaluation: \(term)")
                }
            } else {
                throw QueryError.typeError("Variable ?\(name) is unbound in result \(result)")
            }
        case .neg(let expr):
            let val = try numericEvaluate(expression: expr, result: result)
            return -val
        case let .add(lhs, rhs), let .sub(lhs, rhs), let .mul(lhs, rhs), let .div(lhs, rhs):
            let lval = try numericEvaluate(expression: lhs, result: result)
            let rval = try numericEvaluate(expression: rhs, result: result)
            switch expression {
            case .add:
                return lval + rval
            case .sub:
                return lval - rval
            case .mul:
                return lval * rval
            case .div:
                return lval / rval
            }
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

extension Term {
    var isStringLiteral: Bool {
        switch self.type {
        case .language(_), .datatype("http://www.w3.org/2001/XMLSchema#string"):
            return true
        default:
            return false
        }
    }
    
    var isSimpleLiteral: Bool {
        switch self.type {
        case .datatype("http://www.w3.org/2001/XMLSchema#string"):
            return true
        default:
            return false
        }
    }
    
    enum SPARQLComparisonResult {
        case equals
        case lessThan
        case greaterThan
    }
    
    func sparqlCompare(_ rval: Term) throws -> SPARQLComparisonResult {
        let lval = self
        switch (lval.type, rval.type) {
        case (.iri, .iri):
            if lval == rval {
                return .equals
            } else if lval < rval {
                return .lessThan
            } else {
                return .greaterThan
            }
        case (.datatype("http://www.w3.org/2001/XMLSchema#dateTime"), .datatype("http://www.w3.org/2001/XMLSchema#dateTime")):
            if let ld = lval.dateValue, let rd = rval.dateValue {
                if ld == rd {
                    return .equals
                } else if ld < rd {
                    return .lessThan
                } else {
                    return .greaterThan
                }
            } else {
                throw QueryError.typeError("Comparison on invalid xsd:dateTime")
            }
        case (.datatype("http://www.w3.org/2001/XMLSchema#boolean"), .datatype("http://www.w3.org/2001/XMLSchema#boolean")):
            if let ld = lval.booleanValue, let rd = rval.booleanValue {
                if ld == rd {
                    return .equals
                } else if rd {
                    return .lessThan
                } else {
                    return .greaterThan
                }
            } else {
                throw QueryError.typeError("Equality on invalid xsd:boolean")
            }
        case (_, _) where lval.isNumeric && rval.isNumeric:
            if lval.equals(rval)  {
                return .equals
            } else if lval < rval {
                return .lessThan
            } else {
                return .greaterThan
            }
        case (_, _) where lval.isStringLiteral && rval.isStringLiteral:
            if lval.equals(rval)  {
                return .equals
            } else if lval < rval {
                return .lessThan
            } else {
                return .greaterThan
            }
        default:
            throw QueryError.typeError("Comparison cannot be made on these types: \(lval) <=> \(rval)")
        }
    }
}
