//
//  QueryParser.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 5/10/18.
//

import Foundation
import SPARQLSyntax

// swiftlint:disable:next type_body_length
open class QueryParser<T: LineReadable> {
    let reader: T
    var stack: [Algebra]
    public init(reader: T) {
        self.reader = reader
        self.stack = []
    }
    
    // swiftlint:disable:next cyclomatic_complexity
    func parse(line: String) throws -> Algebra? {
        var parts = line.components(separatedBy: " ").filter { $0 != "" && !$0.hasPrefix("\t") }
        guard parts.count > 0 else { return nil }
        if parts[0].hasPrefix("#") { return nil }
        let rest = parts.suffix(from: 1).joined(separator: " ")
        let op = parts[0]
        if op == "project" {
            guard let child = stack.popLast() else { throw QueryError.parseError("Not enough operands for \(op)") }
            let vars = Array(parts.suffix(from: 1))
            guard vars.count > 0 else { throw QueryError.parseError("No projection variables supplied") }
            return .project(child, Set(vars))
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
        } else if op == "nps" {
            let parser = NTriplesPatternParser(reader: "")
            let view = AnyIterator(rest.unicodeScalars.makeIterator())
            var chars = PeekableIterator(generator: view)
            guard let nodes = parser.parseNodes(chars: &chars, count: 2) else { return nil }
            guard nodes.count == 2 else { return nil }
            let iriStrings = chars.elements().map { String($0) }.joined(separator: "").components(separatedBy: " ")
            let iris = iriStrings.map { Term(value: $0, type: .iri) }
            return .path(nodes[0], .nps(iris), nodes[1])
        } else if op == "path" {
            let parser = NTriplesPatternParser(reader: "")
            let view = AnyIterator(rest.unicodeScalars.makeIterator())
            var chars = PeekableIterator(generator: view)
            guard let nodes = parser.parseNodes(chars: &chars, count: 2) else { return nil }
            guard nodes.count == 2 else { return nil }
            let rest = chars.elements().map { String($0) }.joined(separator: "").components(separatedBy: " ")
            guard let pp = try parsePropertyPath(rest) else { throw QueryError.parseError("Failed to parse property path") }
            return .path(nodes[0], pp, nodes[1])
        } else if op == "agg" { // (SUM(?skey) AS ?sresult) (AVG(?akey) AS ?aresult) ... GROUP BY ?x ?y ?z --> "agg sum sresult ?skey , avg aresult ?akey ; ?x , ?y , ?z"
            let pair = parts.suffix(from: 1).split(separator: ";")
            guard pair.count >= 1 else { throw QueryError.parseError("Bad syntax for agg operation") }
            let aggs = pair[0].split(separator: ",")
            guard aggs.count > 0 else { throw QueryError.parseError("Bad syntax for agg operation") }
            let groupby = pair.count == 2 ? pair[1].split(separator: ",") : []
            
            var aggregates = [Algebra.AggregationMapping]()
            for a in aggs {
                let strings = Array(a)
                guard strings.count >= 3 else { throw QueryError.parseError("Failed to parse aggregate expression") }
                let op = strings[0]
                let name = strings[1]
                var expr: Expression!
                if op != "countall" {
                    guard let e = try ExpressionParser.parseExpression(Array(strings.suffix(from: 2))) else { throw QueryError.parseError("Failed to parse aggregate expression") }
                    expr = e
                }
                var agg: Aggregation
                switch op {
                case "avg":
                    agg = .avg(expr, false)
                case "sum":
                    agg = .sum(expr, false)
                case "count":
                    agg = .count(expr, false)
                case "countall":
                    agg = .countAll
                default:
                    throw QueryError.parseError("Unexpected aggregation operation: \(op)")
                }
                let aggMap = Algebra.AggregationMapping(aggregation: agg, variableName: name)
                aggregates.append(aggMap)
            }
            
            let groups = try groupby.map { (gstrings) -> Expression in
                guard let e = try ExpressionParser.parseExpression(Array(gstrings)) else { throw QueryError.parseError("Failed to parse aggregate expression") }
                return e
            }
            
            guard let child = stack.popLast() else { return nil }
            return .aggregate(child, groups, Set(aggregates))
        } else if op == "window" { // window row rowresult , rank rankresult ; ?x , ?y , ?z"
            let pair = parts.suffix(from: 1).split(separator: ";")
            guard pair.count >= 1 else { throw QueryError.parseError("Bad syntax for window operation") }
            let w = pair[0].split(separator: ",")
            guard w.count > 0 else { throw QueryError.parseError("Bad syntax for window operation") }
            let groupby = pair.count == 2 ? pair[1].split(separator: ",") : []

            let groups = try groupby.map { (gstrings) -> Expression in
                guard let e = try ExpressionParser.parseExpression(Array(gstrings)) else { throw QueryError.parseError("Failed to parse aggregate expression") }
                return e
            }

            var windows: [Algebra.WindowFunctionMapping] = []
            for a in w {
                let strings = Array(a)
                guard strings.count >= 2 else { throw QueryError.parseError("Failed to parse window expression") }
                let op = strings[0]
                let name = strings[1]
                //                var expr: Expression!
                var f: WindowFunction
                switch op {
                case "rank":
                    f = .rank
                case "row":
                    f = .rowNumber
                default:
                    throw QueryError.parseError("Unexpected window operation: \(op)")
                }
                let frame = WindowFrame(type: .rows, from: .unbound, to: .unbound)
                let windowApp = WindowApplication(windowFunction: f, comparators: [], partition: groups, frame: frame)
                let windowMap = Algebra.WindowFunctionMapping(windowApplication: windowApp, variableName: name)
                windows.append(windowMap)
            }
            
            guard let child = stack.popLast() else { return nil }
            return .window(child, windows)
        } else if op == "avg" { // (AVG(?key) AS ?name) ... GROUP BY ?x ?y ?z --> "avg key name x y z"
            guard parts.count > 2 else { return nil }
            let key = parts[1]
            let name = parts[2]
            let groups = parts.suffix(from: 3).map { (name) -> Expression in .node(.variable(name, binding: true)) }
            guard let child = stack.popLast() else { return nil }
            let aggMap = Algebra.AggregationMapping(aggregation: .avg(.node(.variable(key, binding: true)), false), variableName: name)
            return .aggregate(child, groups, [aggMap])
        } else if op == "sum" { // (SUM(?key) AS ?name) ... GROUP BY ?x ?y ?z --> "sum key name x y z"
            guard parts.count > 2 else { throw QueryError.parseError("Not enough arguments for \(op)") }
            let key = parts[1]
            let name = parts[2]
            let groups = parts.suffix(from: 3).map { (name) -> Expression in .node(.variable(name, binding: true)) }
            guard let child = stack.popLast() else { return nil }
            let aggMap = Algebra.AggregationMapping(aggregation: .sum(.node(.variable(key, binding: true)), false), variableName: name)
            return .aggregate(child, groups, [aggMap])
        } else if op == "count" { // (COUNT(?key) AS ?name) ... GROUP BY ?x ?y ?z --> "count key name x y z"
            guard parts.count > 2 else { throw QueryError.parseError("Not enough arguments for \(op)") }
            let key = parts[1]
            let name = parts[2]
            let groups = parts.suffix(from: 3).map { (name) -> Expression in .node(.variable(name, binding: true)) }
            guard let child = stack.popLast() else { return nil }
            let aggMap = Algebra.AggregationMapping(aggregation: .count(.node(.variable(key, binding: true)), false), variableName: name)
            return .aggregate(child, groups, [aggMap])
        } else if op == "countall" { // (COUNT(*) AS ?name) ... GROUP BY ?x ?y ?z --> "count name x y z"
            guard parts.count > 1 else { throw QueryError.parseError("Not enough arguments for \(op)") }
            let name = parts[1]
            let groups = parts.suffix(from: 2).map { (name) -> Expression in .node(.variable(name, binding: true)) }
            guard let child = stack.popLast() else { return nil }
            let aggMap = Algebra.AggregationMapping(aggregation: .countAll, variableName: name)
            return .aggregate(child, groups, [aggMap])
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
            let comparators = try parts.suffix(from: 1).split(separator: ",").map { (stack) -> Algebra.SortComparator in
                guard let expr = try ExpressionParser.parseExpression(Array(stack)) else { throw QueryError.parseError("Failed to parse ORDER expression") }
                let c = Algebra.SortComparator(ascending: true, expression: expr)
                return c
            }
            guard let child = stack.popLast() else { throw QueryError.parseError("Not enough operands for \(op)") }
            return .order(child, comparators)
        } else if op == "distinct" {
            guard let child = stack.popLast() else { throw QueryError.parseError("Not enough operands for \(op)") }
            return .distinct(child)
        }
        warn("Cannot parse query line: \(line)")
        return nil
    }
    
    func parsePropertyPath(_ parts: [String]) throws -> PropertyPath? {
        var stack = [PropertyPath]()
        var i = parts.makeIterator()
        let parser = NTriplesPatternParser(reader: "")
        while let s = i.next() {
            switch s {
            case "|":
                guard stack.count >= 2 else { throw QueryError.parseError("Not enough property paths on the stack for \(s)") }
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.alt(lhs, rhs))
            case "/":
                guard stack.count >= 2 else { throw QueryError.parseError("Not enough property paths on the stack for \(s)") }
                let rhs = stack.popLast()!
                let lhs = stack.popLast()!
                stack.append(.seq(lhs, rhs))
            case "^":
                guard stack.count >= 1 else { throw QueryError.parseError("Not enough property paths on the stack for \(s)") }
                let lhs = stack.popLast()!
                stack.append(.inv(lhs))
            case "+":
                guard stack.count >= 1 else { throw QueryError.parseError("Not enough property paths on the stack for \(s)") }
                let lhs = stack.popLast()!
                stack.append(.plus(lhs))
            case "*":
                guard stack.count >= 1 else { throw QueryError.parseError("Not enough property paths on the stack for \(s)") }
                let lhs = stack.popLast()!
                stack.append(.star(lhs))
            case "nps":
                guard let c = i.next() else { throw QueryError.parseError("No count argument given for property path operation: \(s)") }
                guard let count = Int(c) else { throw QueryError.parseError("Failed to parse count argument for property path operation: \(s)") }
                guard stack.count >= count else { throw QueryError.parseError("Not enough property paths on the stack for \(s)") }
                var iris = [Term]()
                for _ in 0..<count {
                    let link = stack.popLast()!
                    guard case .link(let term) = link else { throw QueryError.parseError("Not an IRI for \(s)") }
                    iris.append(term)
                }
                stack.append(.nps(iris))
            default:
                guard let n = parser.parseNode(line: s) else { throw QueryError.parseError("Failed to parse property path: \(parts.joined(separator: " "))") }
                guard case .bound(let term) = n else { throw QueryError.parseError("Failed to parse property path: \(parts.joined(separator: " "))") }
                stack.append(.link(term))
            }
        }
        return stack.popLast()
    }
    
    public func parse() throws -> Query? {
        let lines = self.reader.lines()
        for line in lines {
            guard let algebra = try self.parse(line: line) else { continue }
            stack.append(algebra)
        }
        guard let algebra = stack.popLast() else {
            return nil
        }
        let proj = Array(algebra.projectableVariables)
        return try Query(form: .select(.variables(proj)), algebra: algebra, dataset: nil)
    }
}

