//
//  Query.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 7/8/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation

enum QueryError : ErrorProtocol {
    case evaluationError(String)
    case typeError(String)
}

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

public indirect enum Expression {
    case node(Node)
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
//    case not(Expression)
//    case call(String, [Expression])
//    case isiri(Expression)
//    case isblank(Expression)
//    case isliteral(Expression)
//    case isnumeric(Expression)
//    case lang(Expression)
//    case datatype(Expression)
//    case langmatches(Expression, String)
//    case bound(Expression)
    // TODO: add other expression functions
    
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
        case .eq(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), rval = try? rhs.evaluate(result: result) {
                return (lval == rval) ? Term.trueValue : Term.falseValue
            }
        case .ne(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), rval = try? rhs.evaluate(result: result) {
                return (lval != rval) ? Term.trueValue : Term.falseValue
            }
        case .gt(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), rval = try? rhs.evaluate(result: result) {
                return (lval > rval) ? Term.trueValue : Term.falseValue
            }
        case .lt(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), rval = try? rhs.evaluate(result: result) {
                return (lval < rval) ? Term.trueValue : Term.falseValue
            }
        case .ge(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), rval = try? rhs.evaluate(result: result) {
                return (lval >= rval) ? Term.trueValue : Term.falseValue
            }
        case .le(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), rval = try? rhs.evaluate(result: result) {
                return (lval <= rval) ? Term.trueValue : Term.falseValue
            }
        case .add(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), rval = try? rhs.evaluate(result: result) {
                guard lval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                guard rval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                let value = lval.numericValue + rval.numericValue
                guard let type = lval.type.resultType(op: "+", operandType: rval.type) else { throw QueryError.typeError("Cannot determine resulting type for adding \(lval) and \(rval)") }
                guard let term = Term(numeric: value, type: type) else { throw QueryError.typeError("Cannot add \(lval) and \(rval) and produce a valid numeric term") }
                return term
            }
        case .sub(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), rval = try? rhs.evaluate(result: result) {
                guard lval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                guard rval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                let value = lval.numericValue - rval.numericValue
                guard let type = lval.type.resultType(op: "-", operandType: rval.type) else { throw QueryError.typeError("Cannot determine resulting type for subtracting \(lval) and \(rval)") }
                guard let term = Term(numeric: value, type: type) else { throw QueryError.typeError("Cannot subtract \(lval) and \(rval) and produce a valid numeric term") }
                return term
            }
        case .mul(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), rval = try? rhs.evaluate(result: result) {
                guard lval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                guard rval.isNumeric else { throw QueryError.typeError("Value \(lval) is not numeric") }
                let value = lval.numericValue * rval.numericValue
                guard let type = lval.type.resultType(op: "*", operandType: rval.type) else { throw QueryError.typeError("Cannot determine resulting type for multiplying \(lval) and \(rval)") }
                guard let term = Term(numeric: value, type: type) else { throw QueryError.typeError("Cannot multiply \(lval) and \(rval) and produce a valid numeric term") }
                return term
            }
        case .div(let lhs, let rhs):
            if let lval = try? lhs.evaluate(result: result), rval = try? rhs.evaluate(result: result) {
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
        }
        throw QueryError.evaluationError("Failed to evaluate \(self) with result \(result)")
    }
}

public enum Aggregation {
    case countAll
    case count(Expression)
    case sum(Expression)
    case avg(Expression)
}

public indirect enum Algebra {
    case quad(QuadPattern)
    case triple(TriplePattern)
    case bgp([TriplePattern])
    case innerJoin(Algebra, Algebra)
    case leftOuterJoin(Algebra, Algebra, Expression)
    case filter(Algebra, Expression)
    case union([Algebra])
    case namedGraph(Algebra, Node)
    case extend(Algebra, Expression, String)
    case minus(Algebra, Algebra)
    case project(Algebra, [String])
    case distinct(Algebra)
    case slice(Algebra, Int?, Int?)
    case order(Algebra, [Expression])
    case aggregate(Algebra, [Expression], [(Aggregation, String)])
    // TODO: add property paths
    
    private func inscopeUnion(children : [Algebra]) -> Set<String> {
        if children.count == 0 {
            return Set()
        }
        var vars = children.map { $0.inscope }
        while vars.count > 1 {
            let l = vars.popLast()!
            let r = vars.popLast()!
            vars.append(l.union(r))
        }
        return vars.popLast()!
    }
    
    public var inscope : Set<String> {
        var variables = Set<String>()
        switch self {
        case .project(_, let vars):
            return Set(vars)
        case .innerJoin(let lhs, let rhs):
            return inscopeUnion(children: [lhs, rhs])
        case .union(let children):
            return inscopeUnion(children: children)
        case .triple(let t):
            for node in [t.subject, t.predicate, t.object] {
                if case .variable(let name, _) = node {
                    variables.insert(name)
                }
            }
            return variables
        case .quad(let q):
            for node in [q.subject, q.predicate, q.object, q.graph] {
                if case .variable(let name, _) = node {
                    variables.insert(name)
                }
            }
            return variables
        case .bgp(let triples):
            if triples.count == 0 {
                return Set()
            }
            var variables = Set<String>()
            for t in triples {
                for node in [t.subject, t.predicate, t.object] {
                    if case .variable(let name, _) = node {
                        variables.insert(name)
                    }
                }
            }
            return variables
        case .leftOuterJoin(let lhs, let rhs, _):
            return inscopeUnion(children: [lhs, rhs])
        case .extend(let child, _, let v):
            var variables = child.inscope
            variables.insert(v)
            return variables
        case .filter(let child, _), .minus(let child, _), .distinct(let child), .slice(let child, _, _), .namedGraph(let child, .bound(_)), .order(let child, _):
            return child.inscope
        case .namedGraph(let child, .variable(let v, let bind)):
            var variables = child.inscope
            if bind {
                variables.insert(v)
            }
            return variables
        case .aggregate(_, let groups, let aggs):
            for g in groups {
                if case .node(.variable(let name, true)) = g {
                    variables.insert(name)
                }
            }
            for (_, name) in aggs {
                variables.insert(name)
            }
            return variables
        }
    }
    
    public func serialize(depth : Int=0) -> String {
        let indent = String(repeating: Character(" "), count: (depth*2))
        switch self {
        case .quad(let q):
            return "\(indent)Quad(\(q))\n"
        case .triple(let t):
            return "\(indent)Triple(\(t))\n"
        case .bgp(let triples):
            var d = "\(indent)BGP\n"
            for t in triples {
                d += "  \(t)\n"
            }
            return d
        case .innerJoin(let lhs, let rhs):
            var d = "\(indent)Join\n"
            d += lhs.serialize(depth: depth+1)
            d += rhs.serialize(depth: depth+1)
            return d
        case .leftOuterJoin(let lhs, let rhs, let expr):
            var d = "\(indent)LeftJoin (\(expr))\n"
            for c in [lhs, rhs] {
                d += c.serialize(depth: depth+1)
            }
            return d
        case .union(let children):
            var d = "\(indent)Union\n"
            for c in children {
                d += c.serialize(depth: depth+1)
            }
            return d
        case .namedGraph(let child, let graph):
            var d = "\(indent)NamedGraph \(graph)\n"
            d += child.serialize(depth: depth+1)
            return d
        case .extend(let child, let expr, let name):
            var d = "\(indent)Extend \(expr) -> \(name)\n"
            d += child.serialize(depth: depth+1)
            return d
        case .project(let child, let variables):
            var d = "\(indent)Project \(variables)\n"
            d += child.serialize(depth: depth+1)
            return d
        case .distinct(let child):
            var d = "\(indent)Distinct\n"
            d += child.serialize(depth: depth+1)
            return d
        case .slice(let child, nil, .some(let limit)), .slice(let child, .some(0), .some(let limit)):
            var d = "\(indent)Limit \(limit)\n"
            d += child.serialize(depth: depth+1)
            return d
        case .slice(let child, .some(let offset), nil):
            var d = "\(indent)Offset \(offset)\n"
            d += child.serialize(depth: depth+1)
            return d
        case .slice(let child, let offset, let limit):
            var d = "\(indent)Slice offset=\(offset) limit=\(limit)\n"
            d += child.serialize(depth: depth+1)
            return d
        case .order(let child, let expressions):
            var d = "\(indent)OrderBy \(expressions)\n"
            d += child.serialize(depth: depth+1)
            return d
        case .filter(let child, let expr):
            var d = "\(indent)Filter \(expr)\n"
            d += child.serialize(depth: depth+1)
            return d
        case .minus(let lhs, let rhs):
            var d = "\(indent)Minus\n"
            d += lhs.serialize(depth: depth+1)
            d += rhs.serialize(depth: depth+1)
            return d
        case .aggregate(let child, let groups, let aggs):
            var d = "\(indent)Aggregate \(aggs) over groups \(groups)\n"
            d += child.serialize(depth: depth+1)
            return d
        }
    }
}

public class QueryParser<T : LineReadable> {
    let reader : T
    var stack : [Algebra]
    public init(reader : T) {
        self.reader = reader
        self.stack = []
    }
    
    func parse(line : String) -> Algebra? {
        var parts = line.components(separatedBy: " ").filter { $0 != "" && !$0.hasPrefix("\t") }
        guard parts.count > 0 else { return nil }
        if parts[0].hasPrefix("#") { return nil }
        let rest = parts.suffix(from: 1).joined(separator: " ")
        let op = parts[0]
        if op == "project" {
            guard let child = stack.popLast() else { return nil }
            let vars = Array(parts.suffix(from: 1))
            return .project(child, vars)
        } else if op == "join" {
            guard stack.count >= 2 else { return nil }
            guard let rhs = stack.popLast() else { return nil }
            guard let lhs = stack.popLast() else { return nil }
            return .innerJoin(lhs, rhs)
        } else if op == "union" {
            guard let count = Int(rest) else { return nil }
            var children = [Algebra]()
            for _ in 0..<count {
                guard let child = stack.popLast() else { return nil }
                children.insert(child, at: 0)
            }
            return .union(children)
        } else if op == "leftjoin" {
            guard stack.count >= 2 else { return nil }
            guard let rhs = stack.popLast() else { return nil }
            guard let lhs = stack.popLast() else { return nil }
            return .leftOuterJoin(lhs, rhs, .node(.bound(Term.trueValue)))
        } else if op == "quad" {
            let parser = NTriplesPatternParser(reader: "")
            guard let pattern = parser.parseQuadPattern(line: rest) else { return nil }
            return .quad(pattern)
        } else if op == "triple" {
            let parser = NTriplesPatternParser(reader: "")
            guard let pattern = parser.parseTriplePattern(line: rest) else { return nil }
            return .triple(pattern)
        } else if op == "avg" { // (AVG(?key) AS ?name) ... GROUP BY ?x ?y ?z --> "sum key name x y z"
            let key = parts[1]
            let name = parts[2]
            let groups = parts.suffix(from: 3).map { (name) -> Expression in .node(.variable(name, binding: true)) }
            guard let child = stack.popLast() else { return nil }
            return .aggregate(child, groups, [(.avg(.node(.variable(key, binding: true))), name)])
        } else if op == "sum" { // (SUM(?key) AS ?name) ... GROUP BY ?x ?y ?z --> "sum key name x y z"
            let key = parts[1]
            let name = parts[2]
            let groups = parts.suffix(from: 3).map { (name) -> Expression in .node(.variable(name, binding: true)) }
            guard let child = stack.popLast() else { return nil }
            return .aggregate(child, groups, [(.sum(.node(.variable(key, binding: true))), name)])
        } else if op == "count" { // (COUNT(?key) AS ?name) ... GROUP BY ?x ?y ?z --> "count key name x y z"
            let key = parts[1]
            let name = parts[2]
            let groups = parts.suffix(from: 3).map { (name) -> Expression in .node(.variable(name, binding: true)) }
            guard let child = stack.popLast() else { return nil }
            return .aggregate(child, groups, [(.count(.node(.variable(key, binding: true))), name)])
        } else if op == "countall" { // (COUNT(*) AS ?name) ... GROUP BY ?x ?y ?z --> "count name x y z"
            let name = parts[1]
            let groups = parts.suffix(from: 2).map { (name) -> Expression in .node(.variable(name, binding: true)) }
            guard let child = stack.popLast() else { return nil }
            return .aggregate(child, groups, [(.countAll, name)])
        } else if op == "limit" {
            guard let count = Int(rest) else { return nil }
            guard let child = stack.popLast() else { return nil }
            return .slice(child, 0, count)
        } else if op == "graph" { 
            let parser = NTriplesPatternParser(reader: "")
            guard let child = stack.popLast() else { return nil }
            guard let graph = parser.parseNode(line: rest) else { return nil }
            return .namedGraph(child, graph)
        } else if op == "extend" {
            let name = parts[1]
            guard let child = stack.popLast() else { return nil }
            do {
                if let expr = try parseBinaryExpression(Array(parts.suffix(from: 2))) {
                    return .extend(child, expr, name)
                }
            } catch {}
            fatalError("Failed to parse filter expression: \(parts)")
        } else if op == "filter" {
            guard let child = stack.popLast() else { return nil }
            do {
                if let expr = try parseBinaryExpression(Array(parts.suffix(from: 1))) {
                    return .filter(child, expr)
                }
            } catch {}
            fatalError("Failed to parse filter expression: \(parts)")
        } else if op == "sort" {
            // TODO: this is only parsing variable names right now
            let names = parts.suffix(from: 1).map { (name) -> Expression in .node(.variable(name, binding: true)) }
            guard let child = stack.popLast() else { return nil }
            return .order(child, names)
        }
        warn("Cannot parse query line: \(line)")
        return nil
    }
    
    func parseBinaryExpression(_ parts : [String]) throws -> Expression? {
        let parser = NTriplesPatternParser(reader: "")
        let op = parts[0]
        guard let node = parser.parseNode(line: parts[1]) else { return nil }
        var vexpr : Expression
        if let value = Double(parts[2]) {
            vexpr = .node(.bound(Term(float: value)))
        } else {
            guard let node = parser.parseNode(line: parts[2]) else { return nil }
            vexpr = .node(node)
        }
        switch op {
        case "=":
            return .eq(.node(node), vexpr)
        case "!=":
            return .ne(.node(node), vexpr)
        case "<":
            return .lt(.node(node), vexpr)
        case ">":
            return .gt(.node(node), vexpr)
        case "<=":
            return .le(.node(node), vexpr)
        case ">=":
            return .ge(.node(node), vexpr)
        case "+":
            return .add(.node(node), vexpr)
        case "-":
            return .sub(.node(node), vexpr)
        case "*":
            return .mul(.node(node), vexpr)
        case "/":
            return .div(.node(node), vexpr)
        default:
            fatalError("Failed to parse binary expression: \(parts)")
        }
    }
    public func parse() -> Algebra? {
        let lines = self.reader.lines()
        for line in lines {
            guard let algebra = self.parse(line: line) else { continue }
            stack.append(algebra)
        }
        return stack.popLast()
    }
}

public class SimpleQueryEvaluator {
    var store : QuadStore
    var defaultGraph : Term
    public init(store : QuadStore, defaultGraph : Term) {
        self.store = store
        self.defaultGraph = defaultGraph
    }
    
    func evaluateUnion(_ patterns : [Algebra], activeGraph : Term) throws -> AnyIterator<TermResult> {
        var iters = try patterns.map { try self.evaluate(algebra: $0, activeGraph: activeGraph) }
        return AnyIterator {
            repeat {
                if iters.count == 0 {
                    return nil
                }
                let i = iters[0]
                guard let item = i.next() else { iters.remove(at: 0); continue }
                return item
            } while true
        }
    }
    
    func evaluateJoin(lhs lhsAlgebra: Algebra, rhs rhsAlgebra: Algebra, left : Bool, activeGraph : Term) throws -> AnyIterator<TermResult> {
        var seen = [Set<String>]()
        for pattern in [lhsAlgebra, rhsAlgebra] {
            seen.append(pattern.inscope)
        }
        
        while seen.count > 1 {
            let first   = seen.popLast()!
            let next    = seen.popLast()!
            let inter   = first.intersection(next)
            seen.append(inter)
        }
        
        let intersection = seen.popLast()!
        if intersection.count > 0 {
//                warn("# using hash join on: \(intersection)")
            let joinVariables = Array(intersection)
            let lhs = try self.evaluate(algebra: lhsAlgebra, activeGraph: activeGraph)
            let rhs = try self.evaluate(algebra: rhsAlgebra, activeGraph: activeGraph)
            return pipelinedHashJoin(joinVariables: joinVariables, lhs: lhs, rhs: rhs, left: left)
        }
        
        var patternResults = [[TermResult]]()
        for pattern in [lhsAlgebra, rhsAlgebra] {
            let results     = try self.evaluate(algebra: pattern, activeGraph: activeGraph)
            patternResults.append(Array(results))
        }
        
        var results = [TermResult]()
        nestedLoopJoin(patternResults, left: left) { (result) in
            results.append(result)
        }
        return AnyIterator(results.makeIterator())
    }
    
    func evaluateLeftJoin(lhs : Algebra, rhs : Algebra, expression expr: Expression, activeGraph : Term) throws -> AnyIterator<TermResult> {
        let i = try evaluateJoin(lhs: lhs, rhs: rhs, left: true, activeGraph: activeGraph)
        return AnyIterator {
            repeat {
                guard let result = i.next() else { return nil }
                if let term = try? expr.evaluate(result: result) {
                    if case .some(true) = try? term.ebv() {
                        return result
                    }
                }
            } while true
        }
    }
    
    func evaluateCount<S : Sequence where S.Iterator.Element == TermResult>(results : S, expression keyExpr : Expression) -> Term? {
        var count = 0
        for result in results {
            if let _ = try? keyExpr.evaluate(result: result) {
                count += 1
            }
        }
        return Term(integer: count)
    }
    
    func evaluateCountAll<S : Sequence where S.Iterator.Element == TermResult>(results : S) -> Term? {
        var count = 0
        for _ in results {
            count += 1
        }
        return Term(integer: count)
    }
    
    func evaluateSum<S : Sequence where S.Iterator.Element == TermResult>(results : S, expression keyExpr : Expression) -> Term? {
        var doubleSum : Double = 0.0
        let integer = TermType.datatype("http://www.w3.org/2001/XMLSchema#integer")
        var resultingType : TermType? = integer
        var count = 0
        for result in results {
            if let term = try? keyExpr.evaluate(result: result) {
                count += 1
                if term.isNumeric {
                    resultingType = resultingType?.resultType(op: "+", operandType: term.type)
                    doubleSum += term.numericValue
                }
            }
        }
        
        if let type = resultingType {
            if let n = Term(numeric: doubleSum, type: type) {
                return n
            } else {
                // cannot create a numeric term with this combination of value and type
                return nil
            }
        } else {
            warn("*** Cannot determine resulting numeric datatype for SUM operation")
            return nil
        }
    }
    
    //
    func evaluateSinglePipelinedAggregation(algebra child: Algebra, groups: [Expression], aggregation agg: Aggregation, variable name: String, activeGraph : Term) throws -> AnyIterator<TermResult> {
        let i = try self.evaluate(algebra: child, activeGraph: activeGraph)
        var groupValue = [String:Double]()
        var groupCount = [String:Int]()
        var groupBindings = [String:[String:Term]]()
        let integer = TermType.datatype("http://www.w3.org/2001/XMLSchema#integer")
        var resultingType : TermType? = integer
        for result in i {
            let group = groups.map { (expr) -> Term? in return try? expr.evaluate(result: result) }
            let groupKey = "\(group)"
            if let value = groupValue[groupKey] {
                switch agg {
                case .countAll:
                    groupValue[groupKey] = value + 1.0
                case .avg(let keyExpr):
                    if let _ = try? keyExpr.evaluate(result: result), let c = groupCount[groupKey] {
                        groupValue[groupKey] = value + 1.0
                        groupCount[groupKey] = c + 1
                    }
                case .count(let keyExpr):
                    if let _ = try? keyExpr.evaluate(result: result) {
                        groupValue[groupKey] = value + 1.0
                    }
                case .sum(let keyExpr):
                    if let term = try? keyExpr.evaluate(result: result) {
                        if term.isNumeric {
                            resultingType = resultingType?.resultType(op: "+", operandType: term.type)
                            groupValue[groupKey] = value + term.numericValue
                        }
                    }
                }
            } else {
                switch agg {
                case .countAll:
                    groupValue[groupKey] = 1.0
                case .avg(let keyExpr):
                    if let _ = try? keyExpr.evaluate(result: result) {
                        groupValue[groupKey] = 1.0
                        groupCount[groupKey] = 1
                    }
                case .count(let keyExpr):
                    if let _ = try? keyExpr.evaluate(result: result) {
                        groupValue[groupKey] = 1.0
                    }
                case .sum(let keyExpr):
                    if let term = try? keyExpr.evaluate(result: result) {
                        if term.isNumeric {
                            groupValue[groupKey] = term.numericValue
                            resultingType = term.type
                        }
                    }
                }
                var bindings = [String:Term]()
                for (g, term) in zip(groups, group) {
                    if case .node(.variable(let name, true)) = g {
                        if let term = term {
                            bindings[name] = term
                        }
                    }
                }
                groupBindings[groupKey] = bindings
            }
        }
        // TODO: handle special case where there are no groups (no input rows led to no groups being created);
        //       in this case, counts should return a single result with { $name=0 }
        var a = groupValue.makeIterator()
        return AnyIterator {
            guard let pair = a.next() else { return nil }
            let (groupKey, v) = pair
            var value = v
            if case .avg(_) = agg {
                guard let count = groupCount[groupKey] else { fatalError() }
                value /= Double(count)
                resultingType = resultingType?.resultType(op: "/", operandType: integer)
            }
            
            guard var bindings = groupBindings[groupKey] else { fatalError("Unexpected missing aggregation group template") }
            if let type = resultingType {
                if let n = Term(numeric: value, type: type) {
                    bindings[name] = n
                } else {
                    // cannot create a numeric term with this combination of value and type
                }
            } else {
                warn("*** Cannot determine resulting numeric datatype for \(agg) operation")
            }
            return TermResult(bindings: bindings)
        }
    }
    
    func evaluateAggregation(algebra child: Algebra, groups: [Expression], aggregations aggs: [(Aggregation, String)], activeGraph : Term) throws -> AnyIterator<TermResult> {
        let i = try self.evaluate(algebra: child, activeGraph: activeGraph)
        var groupBuckets = [String:[TermResult]]()
        var groupBindings = [String:[String:Term]]()
        for result in i {
            let group = groups.map { (expr) -> Term? in return try? expr.evaluate(result: result) }
            let groupKey = "\(group)"
            if groupBuckets[groupKey] == nil {
                groupBuckets[groupKey] = [result]
                var bindings = [String:Term]()
                for (g, term) in zip(groups, group) {
                    if case .node(.variable(let name, true)) = g {
                        if let term = term {
                            bindings[name] = term
                        }
                    }
                }
                groupBindings[groupKey] = bindings
            } else {
                groupBuckets[groupKey]?.append(result)
            }
        }
        var a = groupBuckets.makeIterator()
        return AnyIterator {
            guard let pair = a.next() else { return nil }
            let (groupKey, results) = pair
            guard var bindings = groupBindings[groupKey] else { fatalError("Unexpected missing aggregation group template") }
            for (agg, name) in aggs {
                switch agg {
                case .countAll:
                    if let n = self.evaluateCountAll(results: results) {
                        bindings[name] = n
                    }
                case .count(let keyExpr):
                    if let n = self.evaluateCount(results: results, expression: keyExpr) {
                        bindings[name] = n
                    }
                case .sum(let keyExpr):
                    if let n = self.evaluateSum(results: results, expression: keyExpr) {
                        bindings[name] = n
                    }
                case .avg(let keyExpr):
                    var doubleSum : Double = 0.0
                    let integer = TermType.datatype("http://www.w3.org/2001/XMLSchema#integer")
                    var resultingType : TermType? = integer
                    var count = 0
                    for result in results {
                        if let term = try? keyExpr.evaluate(result: result) {
                            count += 1
                            if term.isNumeric {
                                resultingType = resultingType?.resultType(op: "+", operandType: term.type)
                                doubleSum += term.numericValue
                            }
                        }
                    }
                    
                    doubleSum /= Double(count)
                    resultingType = resultingType?.resultType(op: "/", operandType: integer)
                    if let type = resultingType {
                        if let n = Term(numeric: doubleSum, type: type) {
                            bindings[name] = n
                        } else {
                            // cannot create a numeric term with this combination of value and type
                        }
                    } else {
                        warn("*** Cannot determine resulting numeric datatype for AVG operation")
                    }
                    //                    default:
                    //                        fatalError("Unimplemented aggregate: \(agg)")
                }
            }
            return TermResult(bindings: bindings)
        }
    }
    
    public func evaluate(algebra : Algebra, activeGraph : Term) throws -> AnyIterator<TermResult> {
        switch algebra {
        case .triple(let t):
            let quad = QuadPattern(subject: t.subject, predicate: t.predicate, object: t.object, graph: .bound(activeGraph))
            return try store.results(matching: quad)
        case .quad(let quad):
            return try store.results(matching: quad)
        case .innerJoin(let lhs, let rhs):
            return try self.evaluateJoin(lhs: lhs, rhs: rhs, left: false, activeGraph: activeGraph)
        case .leftOuterJoin(let lhs, let rhs, let expr):
            return try self.evaluateLeftJoin(lhs: lhs, rhs: rhs, expression: expr, activeGraph: activeGraph)
        case .union(let patterns):
            return try self.evaluateUnion(patterns, activeGraph: activeGraph)
        case .project(let child, let vars):
            let i = try self.evaluate(algebra: child, activeGraph: activeGraph)
            return AnyIterator {
                guard let result = i.next() else { return nil }
                return result.projected(variables: vars)
            }
        case .namedGraph(let child, let graph):
            if case .bound(let g) = graph {
                return try evaluate(algebra: child, activeGraph: g)
            } else {
                guard case .variable(let gv, let bind) = graph else { fatalError() }
                var iters = try store.graphs().filter { $0 != defaultGraph }.map { ($0, try evaluate(algebra: child, activeGraph: $0)) }
                return AnyIterator {
                    repeat {
                        if iters.count == 0 {
                            return nil
                        }
                        let (graph, i) = iters[0]
                        guard var result = i.next() else { iters.remove(at: 0); continue }
                        if bind {
                            result.extend(variable: gv, value: graph)
                        }
                        return result
                    } while true
                }
            }
        case .slice(let child, let offset, let limit):
            let i = try self.evaluate(algebra: child, activeGraph: activeGraph)
            if let offset = offset {
                for _ in 0..<offset {
                    _ = i.next()
                }
            }
            
            if let limit = limit {
                var seen = 0
                return AnyIterator {
                    guard seen < limit else { return nil }
                    guard let item = i.next() else { return nil }
                    seen += 1
                    return item
                }
            } else {
                return i
            }
        case .extend(let child, let expr, let name):
            let i = try self.evaluate(algebra: child, activeGraph: activeGraph)
            return AnyIterator {
                guard var result = i.next() else { return nil }
                if let term = try? expr.evaluate(result: result) {
                    result.extend(variable: name, value: term)
                }
                return result
            }
        case .order(let child, let expressions):
            let results = try Array(self.evaluate(algebra: child, activeGraph: activeGraph))
            let s = results.sorted { (a,b) -> Bool in
                for expr in expressions {
                    guard let lhs = try? expr.evaluate(result: a) else { return true }
                    guard let rhs = try? expr.evaluate(result: b) else { return false }
                    if lhs < rhs {
                        return true
                    } else if lhs > rhs {
                        return false
                    }
                }
                return false
            }
            return AnyIterator(s.makeIterator())
        case .aggregate(let child, let groups, let aggs):
            if aggs.count == 1 {
                let (agg, name) = aggs[0]
                switch agg {
                case .sum(_), .count(_), .countAll, .avg(_):
                    return try evaluateSinglePipelinedAggregation(algebra: child, groups: groups, aggregation: agg, variable: name, activeGraph: activeGraph)
                }
            }
            return try evaluateAggregation(algebra: child, groups: groups, aggregations: aggs, activeGraph: activeGraph)
        case .filter(let child, let expr):
            let i = try self.evaluate(algebra: child, activeGraph: activeGraph)
            return AnyIterator {
                repeat {
                    guard let result = i.next() else { return nil }
                    if let term = try? expr.evaluate(result: result) {
                        if case .some(true) = try? term.ebv() {
                            return result
                        }
                    }
                } while true
            }
        case .bgp(_):
            fatalError("Unimplemented: \(algebra)")
        case .minus(_, _):
            fatalError("Unimplemented: \(algebra)")
        case .distinct(_):
            fatalError("Unimplemented: \(algebra)")
        }
    }
}

public func pipelinedHashJoin<R : ResultProtocol>(joinVariables : [String], lhs : AnyIterator<R>, rhs : AnyIterator<R>, left : Bool = false) -> AnyIterator<R> {
    var table = [R:[R]]()
    for result in rhs {
        let key = result.projected(variables: joinVariables)
        if let results = table[key] {
            table[key] = results + [result]
        } else {
            table[key] = [result]
        }
    }
    
    var buffer = [R]()
    return AnyIterator {
        repeat {
            if buffer.count > 0 {
                return buffer.remove(at: 0)
            }
            guard let result = lhs.next() else { return nil }
            var joined = false
            let key = result.projected(variables: joinVariables)
            if let results = table[key] {
                for rhs in results {
                    if let j = rhs.join(result) {
                        joined = true
                        buffer.append(j)
                    }
                }
            }
            if left && !joined {
                buffer.append(result)
            }
        } while true
    }
}

public func nestedLoopJoin<R : ResultProtocol>(_ results : [[R]], left : Bool = false, cb : @noescape (R) -> ()) {
    var patternResults = results
    while patternResults.count > 1 {
        let rhs = patternResults.popLast()!
        let lhs = patternResults.popLast()!
        let finalPass = patternResults.count == 0
        var joinedResults = [R]()
        for lresult in lhs {
            var joined = false
            for rresult in rhs {
                if let j = lresult.join(rresult) {
                    joined = true
                    if finalPass {
                        cb(j)
                    } else {
                        joinedResults.append(j)
                    }
                }
            }
            if left && !joined {
                if finalPass {
                    cb(lresult)
                } else {
                    joinedResults.append(lresult)
                }
            }
        }
        patternResults.append(joinedResults)
    }
}

