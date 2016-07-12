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

public indirect enum Expression {
    case node(Node)
    case add(Expression, Expression)
    case sub(Expression, Expression)
    case div(Expression, Expression)
    case mul(Expression, Expression)
    case not(Expression)
    case eq(Expression, Expression)
    case ne(Expression, Expression)
    case lt(Expression, Expression)
    case le(Expression, Expression)
    case gt(Expression, Expression)
    case ge(Expression, Expression)
    case call(String, [Expression])
    case isiri(Expression)
    case isblank(Expression)
    case isliteral(Expression)
    case isnumeric(Expression)
    case lang(Expression)
    case datatype(Expression)
    case langmatches(Expression, String)
    case bound(Expression)
    // TODO: add other expression functions
    
    public func evaluate(result : Result) throws -> Term {
        switch self {
        case .node(.bound(let term)):
            return term
        case .node(.variable(let name)):
            if let term = result[name] {
                return term
            } else {
                throw QueryError.typeError("Variable ?\(name) is unbound in result \(result)")
            }
        default:
            throw QueryError.evaluationError("Cannot evaluate \(self) with result \(result)")
        }
    }
    
//    public func ebv(result : Result) -> Bool {
//        
//    }
}

public enum Aggregation {
    case countAll
    case count(Expression)
    case sum(Expression)
}

public indirect enum Algebra {
    case quad(QuadPattern)
    case triple(TriplePattern)
    case bgp([TriplePattern])
    case innerJoin([Algebra])
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
        case .innerJoin(let children), .union(let children):
            return inscopeUnion(children: children)
        case .triple(let t):
            for node in [t.subject, t.predicate, t.object] {
                if case .variable(let name) = node {
                    variables.insert(name)
                }
            }
            return variables
        case .quad(let q):
            for node in [q.subject, q.predicate, q.object, q.graph] {
                if case .variable(let name) = node {
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
                    if case .variable(let name) = node {
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
        case .namedGraph(let child, .variable(let v)):
            var variables = child.inscope
            variables.insert(v)
            return variables
        case .aggregate(_, let groups, let aggs):
            for g in groups {
                if case .node(.variable(let name)) = g {
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
        case .innerJoin(let children):
            var d = "\(indent)Join\n"
            for c in children {
                d += c.serialize(depth: depth+1)
            }
            return d
        case .leftOuterJoin(let l, let r, _):
            var d = "\(indent)LeftJoin\n"
            for c in [l, r] {
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
        } else if op == "join" || op == "union" {
            guard let count = Int(rest) else { return nil }
            var children = [Algebra]()
            for _ in 0..<count {
                guard let child = stack.popLast() else { return nil }
                children.insert(child, at: 0)
            }
            if op == "join" {
                return .innerJoin(children)
            } else if op == "union" {
                return .union(children)
            }
        } else if op == "quad" {
            let parser = NTriplesPatternParser(reader: "")
            guard let pattern = parser.parseQuadPattern(line: rest) else { return nil }
            return .quad(pattern)
        } else if op == "triple" {
            let parser = NTriplesPatternParser(reader: "")
            guard let pattern = parser.parseTriplePattern(line: rest) else { return nil }
            return .triple(pattern)
        } else if op == "countall" {
            let name = parts[1]
            let groups = parts.suffix(from: 2).map { (name) -> Expression in .node(.variable(name)) }
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
        } else if op == "sort" {
            // TODO: this is only parsing variable names right now
            let names = parts.suffix(from: 1).map { (name) -> Expression in .node(.variable(name)) }
            guard let child = stack.popLast() else { return nil }
            return .order(child, names)
        }
        warn("Cannot parse query line: \(line)")
        return nil
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
    
    func evaluateUnion(_ patterns : [Algebra], activeGraph : Term) throws -> AnyIterator<Result> {
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
    
    func evaluateJoin(_ patterns : [Algebra], activeGraph : Term) throws -> AnyIterator<Result> {
        if patterns.count == 2 {
            var seen = [Set<String>]()
            for pattern in patterns {
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
                let lhsAlgebra = patterns[0]
                let rhsAlgebra = patterns[1]
                let lhs = Array(try self.evaluate(algebra: lhsAlgebra, activeGraph: activeGraph))
                let rhs = Array(try self.evaluate(algebra: rhsAlgebra, activeGraph: activeGraph))
                var results = [Result]()
                hashJoin(joinVariables: joinVariables, lhs: lhs, rhs: rhs) { (result) in
                    results.append(result)
                }
                return AnyIterator(results.makeIterator())
            }
        }
        
//        warn("# resorting to nested loop join")
        if patterns.count > 0 {
            var patternResults = [[Result]]()
            for pattern in patterns {
                let results     = try self.evaluate(algebra: pattern, activeGraph: activeGraph)
                patternResults.append(Array(results))
            }
            
            var results = [Result]()
            nestedLoopJoin(patternResults) { (result) in
                results.append(result)
            }
            return AnyIterator(results.makeIterator())
        }
        
        return AnyIterator { return nil }
    }
    
    public func evaluate(algebra : Algebra, activeGraph : Term) throws -> AnyIterator<Result> {
        switch algebra {
        case .triple(let t):
            let quad = QuadPattern(subject: t.subject, predicate: t.predicate, object: t.object, graph: .bound(activeGraph))
            return try store.results(matching: quad)
        case .quad(let quad):
            return try store.results(matching: quad)
        case .innerJoin(let patterns):
            return try self.evaluateJoin(patterns, activeGraph: activeGraph)
        case .union(let patterns):
            return try self.evaluateUnion(patterns, activeGraph: activeGraph)
        case .project(let child, let vars):
            let i = try self.evaluate(algebra: child, activeGraph: activeGraph)
            return AnyIterator {
                guard let result = i.next() else { return nil }
                return result.project(variables: vars)
            }
        case .namedGraph(let child, let graph):
            if case .bound(let g) = graph {
                return try evaluate(algebra: child, activeGraph: g)
            } else {
                guard case .variable(let gv) = graph else { fatalError() }
                var iters = try store.graphs().filter { $0 != defaultGraph }.map { ($0, try evaluate(algebra: child, activeGraph: $0)) }
                return AnyIterator {
                    repeat {
                        if iters.count == 0 {
                            return nil
                        }
                        let (graph, i) = iters[0]
                        guard var result = i.next() else { iters.remove(at: 0); continue }
                        result.extend(variable: gv, value: graph)
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
            let i = try self.evaluate(algebra: child, activeGraph: activeGraph)
            var groupBuckets = [String:[Result]]()
            var groupBindings = [String:[String:Term]]()
            for result in i {
                let group = groups.map { (expr) -> Term? in return try? expr.evaluate(result: result) }
                let groupKey = "\(group)"
                if groupBuckets[groupKey] == nil {
                    groupBuckets[groupKey] = [result]
                    var bindings = [String:Term]()
                    for (g, term) in zip(groups, group) {
                        if case .node(.variable(let name)) = g {
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
                        let count = results.count
                        bindings[name] = Term(value: "\(count)", type: .datatype("http://www.w3.org/2001/XMLSchema#integer"))
                    default:
                        fatalError("Unimplemented aggregate: \(agg)")
                    }
                }
                return Result(bindings: bindings)
            }
        case .bgp(_):
            fatalError("Unimplemented: \(algebra)")
        case .leftOuterJoin(_, _, _):
            fatalError("Unimplemented: \(algebra)")
        case .filter(_, _):
            fatalError("Unimplemented: \(algebra)")
        case .minus(_, _):
            fatalError("Unimplemented: \(algebra)")
        case .distinct(_):
            fatalError("Unimplemented: \(algebra)")
        }
    }
}

public func hashJoin(joinVariables : [String], lhs : [Result], rhs : [Result], cb : @noescape (Result) -> ()) {
    var table = [Int:[Result]]()
    for result in lhs {
        let hashes = joinVariables.map { result[$0]?.hashValue ?? 0 }
        let hash = hashes.reduce(0, combine: { $0 ^ $1 })
        if let results = table[hash] {
            table[hash] = results + [result]
        } else {
            table[hash] = [result]
        }
    }
    
    for result in rhs {
        let hashes = joinVariables.map { result[$0]?.hashValue ?? 0 }
        let hash = hashes.reduce(0, combine: { $0 ^ $1 })
        if let results = table[hash] {
            for lhs in results {
                if let j = lhs.join(result) {
                    cb(j)
                }
            }
        }
    }
}


public func nestedLoopJoin(_ results : [[Result]], cb : @noescape (Result) -> ()) {
    var patternResults = results
    while patternResults.count > 1 {
        let rhs = patternResults.popLast()!
        let lhs = patternResults.popLast()!
        let finalPass = patternResults.count == 0
        var joined = [Result]()
        for lresult in lhs {
            for rresult in rhs {
                if let j = lresult.join(rresult) {
                    if finalPass {
                        cb(j)
                    } else {
                        joined.append(j)
                    }
                }
            }
        }
        patternResults.append(joined)
    }
}

