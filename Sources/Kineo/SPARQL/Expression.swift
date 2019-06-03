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
    public func ebv() throws -> Bool {
        switch type {
        case .datatype(.boolean):
            return value == "true" || value == "1"
        case .language(_), .datatype(.string):
            return value.count > 0
        case _ where self.isNumeric:
            return self.numericValue != 0.0
        default:
            throw QueryError.typeError("EBV cannot be computed for \(self)")
        }
    }
}

public class ExpressionEvaluator {
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
        case adjust = "ADJUST"
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
    public var base: String?
    var activeGraph: Term?
    var algebraEvaluator: AlgebraEvaluator?
    
    public init(base: String? = nil) {
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
                return Term(value: f.string(from: now), type: .datatype(.dateTime))
            } else {
                throw QueryError.evaluationError("OSX 10.12 is required to use date functions")
            }
        } else if dateFunction == .adjust {
            guard terms.count == 2 else { throw QueryError.evaluationError("Wrong argument count for \(dateFunction) call") }
            guard let term = terms[0] else { throw QueryError.evaluationError("Not all arguments are bound in \(dateFunction) call") }
            guard let adjust = terms[1] else { throw QueryError.evaluationError("Not all arguments are bound in \(dateFunction) call") }
            guard let date = term.dateValue else {
                throw QueryError.typeError("Not a date value in \(dateFunction) call")
            }
            if adjust.value.isEmpty {
                return Term(dateTime: date, timeZone: nil)
            }
            guard let tzdur = adjust.duration, let toTimezone = TimeZone(secondsFromGMT: Int(tzdur.seconds)) else {
                throw QueryError.typeError("Timezone value is not a valid duration in \(dateFunction) call")
            }
            if let tz = term.timeZone {
                let fromTimezone = tz
                let offset = TimeInterval(toTimezone.secondsFromGMT() - fromTimezone.secondsFromGMT())
                let d = date.addingTimeInterval(offset)
                let t = Term(dateTime: d, timeZone: toTimezone)
                return t
            } else {
                let t = Term(dateTime: date, timeZone: toTimezone)
                return t
            }
        } else {
            guard terms.count == 1 else { throw QueryError.evaluationError("Wrong argument count for \(dateFunction) call") }
            guard let term = terms[0] else { throw QueryError.evaluationError("Not all arguments are bound in \(dateFunction) call") }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            if case .datatype(.time) = term.type {
                switch dateFunction {
                case .hours, .minutes, .seconds:
                    break
                case .timezone:
                    fatalError("TODO: implement TIMEZONE(?time)")
                default:
                    throw QueryError.evaluationError("Cannot evaluate function on xsd:time value: \(dateFunction)")
                }
            }
            
            guard let date = term.dateValue else { throw QueryError.evaluationError("Argument is not a valid xsd:dateTime value in \(dateFunction) call") }
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
                    let dt = TermDataType(stringLiteral: Term.xsd("dayTimeDuration").value)
                    return Term(value: "PT0S", type: .datatype(dt))
                } else {
                    let neg = seconds < 0 ? "-" : ""
                    let minutes = abs(seconds / 60) % 60
                    let hours = abs(seconds) / (60 * 60)
                    var string = "\(neg)PT\(hours)H"
                    if minutes > 0 {
                        string += "\(minutes)M"
                    }
                    let dt = TermDataType(stringLiteral: Term.xsd("dayTimeDuration").value)
                    return Term(value: string, type: .datatype(dt))
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
            case .adjust, .now:
                fatalError() // handled above
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
        guard case .datatype(.string) = term.type else {
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
                guard let b = IRI(string: base), let i = IRI(string: string.value, relativeTo: b) else {
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
            let dt = TermDataType(stringLiteral: datatype.value)
            return Term(value: string.value, type: .datatype(dt))
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
    
    private func throwUnlessDateType(_ term: Term) throws {
        guard term.isADateType else {
            throw QueryError.typeError("Operand must be one of: xsd:time, xsd:date, or xsd:dateTime: \(term)")
        }
    }
    
    private func throwUnlessDurationType(_ term: Term) throws {
        guard term.isDuration else {
            throw QueryError.typeError("Operand must be a duration type: xsd:duration, xsd:yearMonthDuration, or xsd:dayTimeDuration: \(term)")
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
        case (.language(_), .datatype(.string)):
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
        case .str, .strlen, .lcase, .ucase, .datatype, .encode_for_uri:
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
                return Term(value: d.value, type: .iri)
            case .encode_for_uri:
                guard let encoded = string.value.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) else {
                    throw QueryError.evaluationError("Failed to encode string as a URI")
                }
                return Term(string: encoded)
            default:
                break
            }
        case .contains, .strstarts, .strends, .strbefore, .strafter:
            try guardArity(terms.count, 2, stringFunction.rawValue)
            guard let string = terms[0], let pattern = terms[1] else { throw QueryError.evaluationError("Not all arguments are bound in \(stringFunction) call") }
            try throwUnlessArgumentCompatible(string, pattern)
            switch stringFunction {
            case .contains:
                return Term(boolean: string.value.contains(pattern.value))
            case .strstarts:
                return Term(boolean: string.value.hasPrefix(pattern.value))
            case .strends:
                return Term(boolean: string.value.hasSuffix(pattern.value))
            case .strbefore:
                guard pattern.value != "" else { return Term(value: "", type: string.type) }
                if let range = string.value.range(of: pattern.value) {
                    let prefix = String(string.value[..<range.lowerBound])
                    return Term(value: prefix, type: string.type)
                } else {
                    return Term(string: "")
                }
            case .strafter:
                guard pattern.value != "" else { return string }
                if let range = string.value.range(of: pattern.value) {
                    let suffix = String(string.value[range.upperBound...])
                    return Term(value: suffix, type: string.type)
                } else {
                    return Term(string: "")
                }
            default:
                break
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

    private func evaluateDateSub(_ l: Term, _ r: Term) throws -> Term {
        guard var ldate = l.dateValue else {
            throw QueryError.evaluationError("Failed to extract date from term: \(l)")
        }
        guard var rdate = r.dateValue else {
            throw QueryError.evaluationError("Failed to extract date from term: \(r)")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        if let tz = l.timeZone {
            let s = tz.secondsFromGMT(for: ldate)
            guard let d = calendar.date(byAdding: DateComponents(second: -s), to: ldate) else {
                throw QueryError.evaluationError("Failed to adjust for timezone offset: \(l)")
            }
            ldate = d
        }
        
        if let tz = r.timeZone {
            let s = tz.secondsFromGMT(for: rdate)
            guard let d = calendar.date(byAdding: DateComponents(second: -s), to: rdate) else {
                throw QueryError.evaluationError("Failed to adjust for timezone offset: \(r)")
            }
            rdate = d
        }

        var neg = true
        if ldate > rdate {
            (ldate, rdate) = (rdate, ldate)
            neg = false
        }
        
        let components = calendar.dateComponents([.day, .hour, .minute, .second], from: ldate, to: rdate)
        var s: String
        if neg {
            s = "-P"
        } else {
            s = "P"
        }
        if let v = components.day, v > 0 {
            s += "\(v)D"
        }
        
        var timeSet = false
        if let v = components.hour, v > 0 {
            if !timeSet {
                s += "T"
                timeSet = true
            }
            s += "\(v)H"
        }
        if let v = components.minute, v > 0 {
            if !timeSet {
                s += "T"
                timeSet = true
            }
            s += "\(v)M"
        }
        if let v = components.second, v > 0 {
            if !timeSet {
                s += "T"
            }
            s += "\(v)S"
        }
        return Term(value: s, type: .datatype(.custom("http://www.w3.org/2001/XMLSchema#dayTimeDuration")))
    }
    
    private func evaluate(time term: Term, duration: Term, withOperatorFrom expr: Expression) throws -> Term {
        try throwUnlessDurationType(duration)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let components = term.dateComponents else {
            throw QueryError.evaluationError("Failed to extract date components from term: \(term)")
        }
        guard let date = calendar.date(from: components) else {
            throw QueryError.evaluationError("Failed to construct date from xsd:time components")
        }
        guard var durationInterval = duration.duration else {
            throw QueryError.evaluationError("Failed to extract interval from duration: \(duration)")
        }
        switch expr {
        case .sub:
            durationInterval.months *= -1
            durationInterval.seconds *= -1.0
        default:
            break
        }
        guard let d = calendar.date(byAdding: .second, value: Int(durationInterval.seconds), to: date),
            let dd = calendar.date(byAdding: .month, value: durationInterval.months, to: d) else {
                throw QueryError.evaluationError("Failed to add duration to date")
        }
        let h = calendar.component(.hour, from: dd)
        let m = calendar.component(.minute, from: dd)
        let s = calendar.component(.second, from: dd)
        let ts = String(format: "%02d:%02d:%02d", h, m, s)
        return Term(value: ts, type: .datatype(.time))
    }
    
    private func evaluate(date term: Term, duration: Term, withOperatorFrom expr: Expression, truncateToDate: Bool = false) throws -> Term {
        try throwUnlessDurationType(duration)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = term.dateValue else {
            throw QueryError.evaluationError("Failed to extract date from term: \(term)")
        }
        guard var durationInterval = duration.duration else {
            throw QueryError.evaluationError("Failed to extract interval from duration: \(duration)")
        }
        switch expr {
        case .sub:
            durationInterval.months *= -1
            durationInterval.seconds *= -1.0
        default:
            break
        }
        guard let d = calendar.date(byAdding: .second, value: Int(durationInterval.seconds), to: date),
            let dd = calendar.date(byAdding: .month, value: durationInterval.months, to: d) else {
                throw QueryError.evaluationError("Failed to add duration to date")
        }
        
        if truncateToDate {
            let y = calendar.component(.year, from: dd)
            let m = calendar.component(.month, from: dd)
            let d = calendar.component(.day, from: dd)
            let ts = String(format: "%04d-%02d-%02d", y, m, d)
            return Term(value: ts, type: .datatype(.date))
        }

        return Term(dateTime: dd, timeZone: term.timeZone)
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
                throw QueryError.evaluationError("Unexpected numeric function \(numericFunction)")
            }
        }
//        throw QueryError.evaluationError("Unrecognized numeric function: \(numericFunction)")
    }

    // NOTE: this isn't really an escaping closure, but swift can't tell that
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
            throw QueryError.evaluationError("Cannot evaluate an aggregate expression without a query context: \(expression)")
        case .window(_):
            throw QueryError.evaluationError("Cannot evaluate a window expression without a query context: \(expression)")
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
                if let ld = lval.duration, let rd = rval.duration {
                    // in general, durations are not comparable, but they are equatable
                    switch expression {
                    case .eq:
                        return Term(boolean: ld.months == rd.months && ld.seconds == rd.seconds)
                    case .ne:
                        return Term(boolean: ld.months != rd.months || ld.seconds != rd.seconds)
                    default:
                        break
                    }
                }
                
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
                switch (lval, rval) {
                case _ where lval.isTime && rval.isTime:
                    guard case .sub = expression else {
                        throw QueryError.typeError("Time arithmetic is limited to subtraction: \(expression)")
                    }
                    let ll = Term(value: "2000-01-01T\(lval.value)", type: .datatype(TermDataType.dateTime))
                    let rr = Term(value: "2000-01-01T\(rval.value)", type: .datatype(TermDataType.dateTime))
                    return try evaluateDateSub(ll, rr)
                case _ where lval.isADateType && rval.isADateType:
                    guard case .sub = expression else {
                        throw QueryError.typeError("Date arithmetic is limited to subtraction: \(expression)")
                    }
                    return try evaluateDateSub(lval, rval)
                case let (date, dur) where date.isADateType && dur.isDuration:
                    var truncateToDate = false
                    if case .datatype(.custom("http://www.w3.org/2001/XMLSchema#yearMonthDuration")) = dur.type {
                        if case .datatype(.date) = date.type {
                            truncateToDate = true
                        }
                    }
                    return try evaluate(date: date, duration: dur, withOperatorFrom: expression, truncateToDate: truncateToDate)
                case let (time, dur) where time.isTime && dur.isDuration:
                    return try evaluate(time: time, duration: dur, withOperatorFrom: expression)
                case (_, _) where lval.isNumeric && rval.isNumeric:
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
                default:
                    throw QueryError.typeError("Operands to arithmetic operator are not compatible: \(expression)")
                }
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
                return Term(value: dt.value, type: .iri)
            } else if case .language(_) = val.type {
                return Term(value: Namespace.rdf.langString, type: .iri)
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
                f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
                if let _ = f.date(from: term.value) {
                    return Term(value: term.value, type: .datatype(.date))
                }
            }
            throw QueryError.typeError("Cannot coerce term to a date value")
        case .dateTimeCast(let expr):
            let term = try evaluate(expression: expr, result: result)
            if #available (OSX 10.12, *) {
                let f = ISO8601DateFormatter()
                f.formatOptions.remove(.withTimeZone)
                if let _ = f.date(from: term.value) {
                    return Term(value: term.value, type: .datatype(.dateTime))
                }
            }
            throw QueryError.typeError("Cannot coerce term to a dateTime value")
        case .timeCast(let expr):
            let term = try evaluate(expression: expr, result: result)
            let v = term.value
            if v == "24:00:00" {
                return Term(value: "00:00:00", type: .datatype(.time))
            }
            let parts = v.split(separator: ":")
            let ints = parts.compactMap { Int($0) }
            guard ints.count == 3 else {
                throw QueryError.typeError("Bad xsd:time lexical form: \(term)")
            }
            let h = ints[0]
            let m = ints[1]
            let s = ints[2] // TODO: support fractional seconds
            guard (0..<24).contains(h), (0..<60).contains(m), (0...60).contains(s) else {
                throw QueryError.typeError("Bad xsd:time lexical form: \(term)")
            }
            let tv = String(format: "%02d:%02d:%02d", h, m, s)
            return Term(value: tv, type: .datatype(.time))
        case .durationCast(let expr):
            let t = try evaluate(expression: expr, result: result)
            let term = Term(value: t.value, type: .datatype(TermDataType(stringLiteral: "http://www.w3.org/2001/XMLSchema#duration")))
            if let d = term.duration {
                var seconds = d.seconds
                var months = d.months
                var neg = ""
                if (seconds < 0 || months < 0) {
                    neg = "-"
                    seconds = abs(seconds)
                    months = abs(months)
                }
                var dv = "\(neg)P"
                if months > 0 {
                    let y = months / 12
                    let m = months % 12
                    if y > 0 {
                        dv += "\(y)Y"
                    }
                    if m > 0 {
                        dv += "\(m)M"
                    }
                }
                
                if seconds > 0 {
                    let ss = Int(seconds)
                    let d = ss / 86400
                    let h = (ss % 86400) / 3600
                    let m = (ss % 3600) / 60
                    let _s = ss % 60
                    let s = Double(_s) + (seconds - Double(ss))
                    if d > 0 {
                        dv += "\(d)D"
                    }
                    if h > 0 || m > 0 || s > 0 {
                        dv += "T"
                    }
                    if h > 0 {
                        dv += "\(h)H"
                    }
                    if m > 0 {
                        dv += "\(m)M"
                    }
                    if s > 0 {
                        if s.remainder(dividingBy: 1.0) == 0.0 {
                            dv += "\(Int(s))S"
                        } else {
                            dv += "\(s)S"
                        }
                    }
                }
                
                if let c = dv.last, c == "P" {
                    dv += "T0S"
                }
                let duration = TermDataType(stringLiteral: "http://www.w3.org/2001/XMLSchema#duration")
                return Term(value: dv, type: .datatype(duration))
            }
            throw QueryError.typeError("Cannot coerce term to a duration value")
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
            throw QueryError.evaluationError("Cannot evaluate an aggregate expression without a query context")
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
        case .language(_), .datatype(.string):
            return true
        default:
            return false
        }
    }
    
    var isSimpleLiteral: Bool {
        switch self.type {
        case .datatype(.string):
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
    
    private func _cmp<C: Comparable>(_ l: C, _ r: C) -> SPARQLComparisonResult {
        if l == r {
            return .equals
        } else if l < r {
            return .lessThan
        } else {
            return .greaterThan
        }
    }
    private func _valueCmp(_ l: Term, _ r: Term) -> SPARQLComparisonResult {
        if l.equals(r) {
            return .equals
        } else if l < r {
            return .lessThan
        } else {
            return .greaterThan
        }
    }

    func sparqlCompare(_ rval: Term) throws -> SPARQLComparisonResult {
        let lval = self
        switch (lval.type, rval.type) {
        case (.iri, .iri):
            return _cmp(lval, rval)
        case (.datatype(.dateTime), .datatype(.dateTime)), (.datatype(.date), .datatype(.date)):
            if let ld = lval.dateValue, let rd = rval.dateValue {
                return _cmp(ld, rd)
            } else {
                throw QueryError.typeError("Comparison on invalid xsd:dateTime")
            }
        case (.datatype(.time), .datatype(.time)):
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            if let ld = lval.dateValue, let rd = rval.dateValue {
                let lc = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: ld)
                let rc = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: rd)
                if lc == rc {
                    return .equals
                }
                if lc.hour != rc.hour {
                    return _cmp(lc.hour ?? 0, rc.hour ?? 0)
                } else if lc.minute != rc.minute {
                    return _cmp(lc.minute ?? 0, rc.minute ?? 0)
                } else if lc.second != rc.second {
                    return _cmp(lc.second ?? 0, rc.second ?? 0)
                } else {
                    return _cmp(lc.nanosecond ?? 0, rc.nanosecond ?? 0)
                }
            } else {
                throw QueryError.typeError("Comparison on invalid xsd:dateTime")
            }
        case (.datatype(.boolean), .datatype(.boolean)):
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
            return _valueCmp(lval, rval)
        case (_, _) where lval.isStringLiteral && rval.isStringLiteral:
            return _valueCmp(lval, rval)
        default:
            if let ld = lval.duration, let rd = rval.duration {
                if ld.seconds == 0 && rd.seconds == 0 {
                    // special case for xsd:yearMonthDuration
                    return _cmp(ld.months, rd.months)
                } else if ld.months == 0 && rd.months == 0 {
                    // special case for xsd:dayTimeDuration
                    return _cmp(ld.seconds, rd.seconds)
                }
            }
            
            throw QueryError.typeError("Comparison cannot be made on these types: \(lval) <=> \(rval)")
        }
    }
}

extension Expression {
    /**
     *  This variable indicates whether constant-folding can be performed
     *  on the Expression.
     *
     */
    var isConstant : Bool {
        switch self {
        case .node(.bound(_)):
            return true
        case let .and(lhs, rhs) where lhs.isConstant && rhs.isConstant,
             let .or(lhs, rhs) where lhs.isConstant && rhs.isConstant:
            return true
        case let .eq(lhs, rhs) where lhs.isConstant && rhs.isConstant,
             let .ne(lhs, rhs) where lhs.isConstant && rhs.isConstant,
             let .lt(lhs, rhs) where lhs.isConstant && rhs.isConstant,
             let .gt(lhs, rhs) where lhs.isConstant && rhs.isConstant,
             let .le(lhs, rhs) where lhs.isConstant && rhs.isConstant,
             let .ge(lhs, rhs) where lhs.isConstant && rhs.isConstant:
            return true
        case let .add(lhs, rhs) where lhs.isConstant && rhs.isConstant,
             let .sub(lhs, rhs) where lhs.isConstant && rhs.isConstant,
             let .mul(lhs, rhs) where lhs.isConstant && rhs.isConstant:
            // we avoid asserting that div is constant because of the possibility
            // that it raises an error during constant propogation
            return true
        case let .neg(lhs) where lhs.isConstant,
             let .not(lhs) where lhs.isConstant:
            return true
        case .stringCast(let lhs) where lhs.isConstant:
            // we avoid asserting that the numeric and date casts are constant
            // because of the possibility that they raise a type error during
            // constant propogation
            return true
        default:
            // TODO: expand recognition of constant expressions
            return false
        }
    }
}
