//
//  Query.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 7/8/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation

enum QueryError : Error {
    case evaluationError(String)
    case typeError(String)
    case parseError(String)
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
    case union(Algebra, Algebra)
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
        case .innerJoin(let lhs, let rhs), .union(let lhs, let rhs):
            return inscopeUnion(children: [lhs, rhs])
        case .triple(let t):
            for node in [t.subject, t.predicate, t.object] {
                if case .variable(let name, _) = node {
                    variables.insert(name)
                }
            }
            return variables
        case .quad(let q):
            for node in [q.subject, q.predicate, q.object, q.graph] {
                if case .variable(let name, true) = node {
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
                    if case .variable(let name, true) = node {
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
        case .union(let lhs, let rhs):
            var d = "\(indent)Union\n"
            for c in [lhs, rhs] {
                d += c.serialize(depth: depth+1)
            }
            return d
        case .namedGraph(let child, let graph):
            var d = "\(indent)NamedGraph \(graph)\n"
            d += child.serialize(depth: depth+1)
            return d
        case .extend(let child, let expr, let name):
            var d = "\(indent)Extend \(name) <- \(expr)\n"
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
    
    func parse(line : String) throws -> Algebra? {
        var parts = line.components(separatedBy: " ").filter { $0 != "" && !$0.hasPrefix("\t") }
        guard parts.count > 0 else { return nil }
        if parts[0].hasPrefix("#") { return nil }
        let rest = parts.suffix(from: 1).joined(separator: " ")
        let op = parts[0]
        if op == "project" {
            guard let child = stack.popLast() else { throw QueryError.parseError("Not enough operands for \(op)") }
            let vars = Array(parts.suffix(from: 1))
            guard vars.count > 0 else { throw QueryError.parseError("No projection variables supplied") }
            return .project(child, vars)
        } else if op == "join" {
            guard stack.count >= 2 else { throw QueryError.parseError("Not enough operands for \(op)") }
            guard let rhs = stack.popLast() else { return nil }
            guard let lhs = stack.popLast() else { return nil }
            return .innerJoin(lhs, rhs)
        } else if op == "union" {
            guard stack.count >= 2 else { throw QueryError.parseError("Not enough operands for \(op)") }
            guard let rhs = stack.popLast() else { return nil }
            guard let lhs = stack.popLast() else { return nil }
            return .union(lhs, rhs)
        } else if op == "leftjoin" {
            guard stack.count >= 2 else { throw QueryError.parseError("Not enough operands for \(op)") }
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
        } else if op == "avg" { // (AVG(?key) AS ?name) ... GROUP BY ?x ?y ?z --> "avg key name x y z"
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
            guard let child = stack.popLast() else { throw QueryError.parseError("Not enough operands for \(op)") }
            return .slice(child, 0, count)
        } else if op == "graph" { 
            let parser = NTriplesPatternParser(reader: "")
            guard let child = stack.popLast() else { throw QueryError.parseError("Not enough operands for \(op)") }
            guard let graph = parser.parseNode(line: rest) else { return nil }
            return .namedGraph(child, graph)
        } else if op == "extend" {
            guard let child = stack.popLast() else { throw QueryError.parseError("Not enough operands for \(op)") }
            let name = parts[1]
            guard parts.count > 2 else { return nil }
            do {
                if let expr = try ExpressionParser.parseExpression(Array(parts.suffix(from: 2))) {
                    return .extend(child, expr, name)
                }
            } catch {}
            fatalError("Failed to parse filter expression: \(parts)")
        } else if op == "filter" {
            guard let child = stack.popLast() else { throw QueryError.parseError("Not enough operands for \(op)") }
            do {
                if let expr = try ExpressionParser.parseExpression(Array(parts.suffix(from: 1))) {
                    return .filter(child, expr)
                }
            } catch {}
            fatalError("Failed to parse filter expression: \(parts)")
        } else if op == "sort" {
            // TODO: this is only parsing variable names right now
            let names = parts.suffix(from: 1).map { (name) -> Expression in .node(.variable(name, binding: true)) }
            guard let child = stack.popLast() else { throw QueryError.parseError("Not enough operands for \(op)") }
            return .order(child, names)
        }
        warn("Cannot parse query line: \(line)")
        return nil
    }
    
    public func parse() throws -> Algebra? {
        let lines = self.reader.lines()
        for line in lines {
            guard let algebra = try self.parse(line: line) else { continue }
            stack.append(algebra)
        }
        return stack.popLast()
    }
}

public class SimpleQueryEvaluator<Q : QuadStoreProtocol> {
    var store : Q
    var defaultGraph : Term
    public init(store : Q, defaultGraph : Term) {
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
//            warn("# using hash join on: \(intersection)")
//            warn("### \(lhsAlgebra)")
//            warn("### \(rhsAlgebra)")
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
    
    func evaluateCount<S : Sequence>(results : S, expression keyExpr : Expression) -> Term? where S.Iterator.Element == TermResult {
        var count = 0
        for result in results {
            if let _ = try? keyExpr.evaluate(result: result) {
                count += 1
            }
        }
        return Term(integer: count)
    }
    
    func evaluateCountAll<S : Sequence>(results : S) -> Term? where S.Iterator.Element == TermResult {
        var count = 0
        for _ in results {
            count += 1
        }
        return Term(integer: count)
    }
    
    func evaluateSum<S : Sequence>(results : S, expression keyExpr : Expression) -> Term? where S.Iterator.Element == TermResult {
        var runningSum : Numeric = .integer(0)
        var count = 0
        for result in results {
            if let term = try? keyExpr.evaluate(result: result) {
                count += 1
                if let numeric = term.numeric {
                    runningSum = runningSum + numeric
                }
            }
        }
        
        if count == 0 {
            return nil
        }
        return runningSum.term
    }
    
    //
    func evaluateSinglePipelinedAggregation(algebra child: Algebra, groups: [Expression], aggregation agg: Aggregation, variable name: String, activeGraph : Term) throws -> AnyIterator<TermResult> {
        let i = try self.evaluate(algebra: child, activeGraph: activeGraph)
        var groupValue = [String:Numeric]()
        var groupCount = [String:Int]()
        var groupBindings = [String:[String:Term]]()
        for result in i {
            let group = groups.map { (expr) -> Term? in return try? expr.evaluate(result: result) }
            let groupKey = "\(group)"
            if let value = groupValue[groupKey] {
                switch agg {
                case .countAll:
                    groupValue[groupKey] = value + .integer(1)
                case .avg(let keyExpr):
                    if let term = try? keyExpr.evaluate(result: result), let c = groupCount[groupKey] {
                        if let n = term.numeric {
                            groupValue[groupKey] = value + n
                            groupCount[groupKey] = c + 1
                        }
                    }
                case .count(let keyExpr):
                    if let _ = try? keyExpr.evaluate(result: result) {
                        groupValue[groupKey] = value + .integer(1)
                    }
                case .sum(let keyExpr):
                    if let term = try? keyExpr.evaluate(result: result) {
                        if let n = term.numeric {
                            groupValue[groupKey] = value + n
                        }
                    }
                }
            } else {
                switch agg {
                case .countAll:
                    groupValue[groupKey] = .integer(1)
                case .avg(let keyExpr):
                    if let term = try? keyExpr.evaluate(result: result) {
                        if term.isNumeric {
                            groupValue[groupKey] = term.numeric
                            groupCount[groupKey] = 1
                        }
                    }
                case .count(let keyExpr):
                    if let _ = try? keyExpr.evaluate(result: result) {
                        groupValue[groupKey] = .integer(1)
                    }
                case .sum(let keyExpr):
                    if let term = try? keyExpr.evaluate(result: result) {
                        if term.isNumeric {
                            groupValue[groupKey] = term.numeric
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
                value = v / Numeric.double(Double(count))
            }
            
            guard var bindings = groupBindings[groupKey] else { fatalError("Unexpected missing aggregation group template") }
            bindings[name] = value.term
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
        case .union(let lhs, let rhs):
            return try self.evaluateUnion([lhs, rhs], activeGraph: activeGraph)
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
            print("extend expression: \(expr)")
            
            if expr.isNumeric {
                return AnyIterator {
                    guard var result = i.next() else { return nil }
                    if let num = try? expr.numericEvaluate(result: result) {
                        result.extend(variable: name, value: num.term)
                    }
                    return result
                }
            } else {
                return AnyIterator {
                    guard var result = i.next() else { return nil }
                    if let term = try? expr.evaluate(result: result) {
                        result.extend(variable: name, value: term)
                    }
                    return result
                }
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
//    warn(">>> filling hash table")
    var count = 0
    for result in rhs {
        count += 1
        let key = result.projected(variables: joinVariables)
        if let results = table[key] {
            table[key] = results + [result]
        } else {
            table[key] = [result]
        }
    }
//    warn(">>> done (\(count) results in \(Array(table.keys).count) buckets)")
    
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
                for lhs in results {
                    if let j = lhs.join(result) {
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

