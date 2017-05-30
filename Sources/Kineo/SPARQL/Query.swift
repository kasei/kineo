//
//  Query.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 7/8/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation

enum QueryError: Error {
    case evaluationError(String)
    case typeError(String)
    case parseError(String)
    case compatabilityError(String)
}

public struct TriplePattern: CustomStringConvertible {
    public var subject: Node
    public var predicate: Node
    public var object: Node
    public init(subject: Node, predicate: Node, object: Node) {
        self.subject = subject
        self.predicate = predicate
        self.object = object
    }

    public var description: String {
        return "\(subject) \(predicate) \(object) ."
    }

    func bind(_ variable: String, to replacement: Node) -> TriplePattern {
        let subject = self.subject.bind(variable, to: replacement)
        let predicate = self.predicate.bind(variable, to: replacement)
        let object = self.object.bind(variable, to: replacement)
        return TriplePattern(subject: subject, predicate: predicate, object: object)
    }
}

public struct QuadPattern: CustomStringConvertible {
    public var subject: Node
    public var predicate: Node
    public var object: Node
    public var graph: Node
    public init(subject: Node, predicate: Node, object: Node, graph: Node) {
        self.subject = subject
        self.predicate = predicate
        self.object = object
        self.graph = graph
    }
    public var description: String {
        return "\(subject) \(predicate) \(object) \(graph)."
    }

    public func matches(quad: Quad) -> TermResult? {
        let terms = [quad.subject, quad.predicate, quad.object, quad.graph]
        let nodes = [subject, predicate, object, graph]
        var bindings = [String:Term]()
        for i in 0..<4 {
            let term = terms[i]
            let node = nodes[i]
            switch node {
            case .bound(let t):
                if t != term {
                    return nil
                }
            case .variable(let name, binding: let b):
                if b {
                    bindings[name] = term
                }
            }
        }
        return TermResult(bindings: bindings)
    }

    func bind(_ variable: String, to replacement: Node) -> QuadPattern {
        let subject = self.subject.bind(variable, to: replacement)
        let predicate = self.predicate.bind(variable, to: replacement)
        let object = self.object.bind(variable, to: replacement)
        let graph = self.graph.bind(variable, to: replacement)
        return QuadPattern(subject: subject, predicate: predicate, object: object, graph: graph)
    }
}

public enum WindowFunction {
    case rowNumber
    case rank
}

public indirect enum PropertyPath {
    case link(Term)
    case inv(PropertyPath)
    case nps([Term])
    case alt(PropertyPath, PropertyPath)
    case seq(PropertyPath, PropertyPath)
    case plus(PropertyPath)
    case star(PropertyPath)
    case zeroOrOne(PropertyPath)
}

public indirect enum Algebra {
    public typealias SortComparator = (Bool, Expression)

    case unionIdentity
    case joinIdentity
    case table([Node], [TermResult])
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
    case service(Node, Algebra, Bool)
    case slice(Algebra, Int?, Int?)
    case order(Algebra, [SortComparator])
    case path(Node, PropertyPath, Node)
    case aggregate(Algebra, [Expression], [(Aggregation, String)])
    case window(Algebra, [Expression], [(WindowFunction, [SortComparator], String)])
    case construct(Algebra, [TriplePattern])
    case describe(Algebra, [Node])
    case ask(Algebra)
}

public extension Algebra {
    // swiftlint:disable:next cyclomatic_complexity
    public func serialize(depth: Int=0) -> String {
        let indent = String(repeating: " ", count: (depth*2))

        switch self {
        case .unionIdentity:
            return "\(indent)Empty\n"
        case .joinIdentity:
            return "\(indent)Join Identity\n"
        case .quad(let q):
            return "\(indent)Quad(\(q))\n"
        case .triple(let t):
            return "\(indent)Triple(\(t))\n"
        case .bgp(let triples):
            var d = "\(indent)BGP\n"
            for t in triples {
                d += "\(indent)  \(t)\n"
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
        case .service(let endpoint, let child, let silent):
            let modifier = silent ? " (Silent)" : ""
            var d = "\(indent)Service\(modifier) \(endpoint)\n"
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
            var d = "\(indent)Slice offset=\(String(describing: offset)) limit=\(String(describing: limit))\n"
            d += child.serialize(depth: depth+1)
            return d
        case .order(let child, let orders):
            let expressions = orders.map { $0.0 ? "\($0.1)" : "DESC(\($0.1))" }
            var d = "\(indent)OrderBy { \(expressions.joined(separator: ", ")) }\n"
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
        case .path(let subject, let pp, let object):
            return "\(indent)Path(\(subject), \(pp), \(object))\n"
        case .aggregate(let child, let groups, let aggs):
            var d = "\(indent)Aggregate \(aggs) over groups \(groups)\n"
            d += child.serialize(depth: depth+1)
            return d
        case .window(let child, let groups, let funcs):
            let orders = funcs.flatMap { $0.1 }
            let expressions = orders.map { $0.0 ? "\($0.1)" : "DESC(\($0.1))" }
            let f = funcs.map { ($0.0, $0.2) }
            var d = "\(indent)Window \(f) over groups \(groups) ordered by { \(expressions.joined(separator: ", ")) }\n"
            d += child.serialize(depth: depth+1)
            return d
        case .table(let nodes, let results):
            let vars = nodes.map { $0.description }
            var d = "\(indent)Table { \(vars.joined(separator: ", ")) }\n"
            for result in results {
                d += "\(indent)  \(result)\n"
            }
            return d
        case .construct(let child, let triples):
            var d = "\(indent)Construct\n"
            d += "\(indent)  Query\n"
            d += child.serialize(depth: depth+2)
            d += "\(indent)  Template\n"
            for t in triples {
                d += "\(indent)    \(t)\n"
            }
            return d
        case .describe(let child, let nodes):
            let expressions = nodes.map { "\($0)" }
            var d = "\(indent)Describe { \(expressions.joined(separator: ", ")) }\n"
            d += child.serialize(depth: depth+1)
            return d
        case .ask(let child):
            var d = "\(indent)Ask\n"
            d += child.serialize(depth: depth+1)
            return d
        }
    }
}

public extension Algebra {
    private func inscopeUnion(children: [Algebra]) -> Set<String> {
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

    public var inscope: Set<String> {
        var variables = Set<String>()
        switch self {
        case .joinIdentity, .unionIdentity:
            return Set()
        case .project(_, let vars):
            return Set(vars)
        case .innerJoin(let lhs, let rhs), .union(let lhs, let rhs):
            return inscopeUnion(children: [lhs, rhs])
        case .triple(let t):
            for node in [t.subject, t.predicate, t.object] {
                if case .variable(let name, true) = node {
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
        case .bgp(let triples), .construct(_, let triples):
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
        case .filter(let child, _), .minus(let child, _), .distinct(let child), .slice(let child, _, _), .namedGraph(let child, .bound(_)), .order(let child, _), .service(_, let child, _):
            return child.inscope
        case .namedGraph(let child, .variable(let v, let bind)):
            var variables = child.inscope
            if bind {
                variables.insert(v)
            }
            return variables
        case .path(let subject, _, let object):
            var variables = Set<String>()
            for node in [subject, object] {
                if case .variable(let name, true) = node {
                    variables.insert(name)
                }
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
        case .window(let child, _, let funcs):
            var variables = child.inscope
            for (_, _, name) in funcs {
                variables.insert(name)
            }
            return variables
        case .table(let nodes, _):
            for node in nodes {
                if case .variable(let name, _) = node {
                    variables.insert(name)
                }
            }
            return variables
        case .describe(_), .ask(_):
            return variables
        }
    }
}

public extension Algebra {
    func replace(_ map: (Expression) -> Expression?) -> Algebra {
        switch self {
        case .unionIdentity, .joinIdentity, .triple(_), .quad(_), .path(_), .bgp(_), .table(_):
            return self
        case .distinct(let a):
            return .distinct(a.replace(map))
        case .ask(let a):
            return .ask(a.replace(map))
        case .describe(let a, let nodes):
            return .describe(a.replace(map), nodes)
        case .construct(let a, let triples):
            return .construct(a.replace(map), triples)
        case .project(let a, let p):
            return .project(a.replace(map), p)
        case .minus(let a, let b):
            return .minus(a.replace(map), b.replace(map))
        case .union(let a, let b):
            return .union(a.replace(map), b.replace(map))
        case .innerJoin(let a, let b):
            return .innerJoin(a.replace(map), b.replace(map))
        case .namedGraph(let a, let node):
            return .namedGraph(a.replace(map), node)
        case .slice(let a, let offset, let limit):
            return .slice(a.replace(map), offset, limit)
        case .service(let endpoint, let a, let silent):
            return .service(endpoint, a.replace(map), silent)
        case .filter(let a, let expr):
            return .filter(a.replace(map), expr.replace(map))
        case .leftOuterJoin(let a, let b, let expr):
            return .leftOuterJoin(a.replace(map), b.replace(map), expr.replace(map))
        case .extend(let a, let expr, let v):
            return .extend(a.replace(map), expr.replace(map), v)
        case .order(let a, let cmps):
            return .order(a.replace(map), cmps.map { (asc, expr) in (asc, expr.replace(map)) })
        case .aggregate(let a, let exprs, let aggs):
            // case aggregate(Algebra, [Expression], [(Aggregation, String)])
            let exprs = exprs.map { (expr) in
                return expr.replace(map)
            }
            let aggs = aggs.map { (agg, name) in
                return (agg.replace(map), name)
            }
            return .aggregate(a.replace(map), exprs, aggs)
        case .window(let a, let exprs, let funcs):
            //     case window(Algebra, [Expression], [(WindowFunction, [SortComparator], String)])
            let exprs = exprs.map { (expr) in
                return expr.replace(map)
            }
            let funcs = funcs.map { (f, cmps, name) -> (WindowFunction, [SortComparator], String) in
                let e = cmps.map { (asc, expr) in (asc, expr.replace(map)) }
                return (f, e, name)
            }
            return .window(a.replace(map), exprs, funcs)
        }
    }

    func replace(_ map: (Algebra) -> Algebra?) -> Algebra {
        if let r = map(self) {
            return r
        } else {
            switch self {
            case .unionIdentity, .joinIdentity, .triple(_), .quad(_), .path(_), .bgp(_), .table(_):
                return self
            case .distinct(let a):
                return .distinct(a.replace(map))
            case .ask(let a):
                return .ask(a.replace(map))
            case .describe(let a, let nodes):
                return .describe(a.replace(map), nodes)
            case .construct(let a, let triples):
                return .construct(a.replace(map), triples)
            case .project(let a, let p):
                return .project(a.replace(map), p)
            case .order(let a, let cmps):
                return .order(a.replace(map), cmps)
            case .minus(let a, let b):
                return .minus(a.replace(map), b.replace(map))
            case .union(let a, let b):
                return .union(a.replace(map), b.replace(map))
            case .innerJoin(let a, let b):
                return .innerJoin(a.replace(map), b.replace(map))
            case .leftOuterJoin(let a, let b, let expr):
                return .leftOuterJoin(a.replace(map), b.replace(map), expr)
            case .extend(let a, let expr, let v):
                return .extend(a.replace(map), expr, v)
            case .filter(let a, let expr):
                return .filter(a.replace(map), expr)
            case .namedGraph(let a, let node):
                return .namedGraph(a.replace(map), node)
            case .slice(let a, let offset, let limit):
                return .slice(a.replace(map), offset, limit)
            case .service(let endpoint, let a, let silent):
                return .service(endpoint, a.replace(map), silent)
            case .aggregate(let a, let exprs, let aggs):
                return .aggregate(a.replace(map), exprs, aggs)
            case .window(let a, let exprs, let funcs):
                return .window(a.replace(map), exprs, funcs)
            }
        }
    }

    func bind(_ variable: String, to replacement: Node, preservingProjection: Bool = false) -> Algebra {
        var r = self
        r = r.replace { (expr: Expression) in
            if case .node(.variable(let name, _)) = expr {
                if name == variable {
                    return .node(replacement)
                }
            }
            return nil
        }

        r = r.replace { (algebra: Algebra) in
            switch algebra {
            case .triple(let t):
                return .triple(t.bind(variable, to: replacement))
            case .quad(let q):
                return .quad(q.bind(variable, to: replacement))
            case .path(let subj, let pp, let obj):
                let subj = subj.bind(variable, to: replacement)
                let obj = obj.bind(variable, to: replacement)
                return .path(subj, pp, obj)
            case .bgp(let triples):
                return .bgp(triples.map { $0.bind(variable, to: replacement) })
            case .table(_):
                fatalError("TODO: semantics of binding a variable for a values table are unclear")
            case .describe(let a, let nodes):
                return .describe(a, nodes.map { $0.bind(variable, to: replacement) })
            case .construct(let a, let triples):
                return .construct(a, triples.map { $0.bind(variable, to: replacement) })
            case .project(let a, let p):
                let child = a.bind(variable, to: replacement)
                if preservingProjection {
                    let extend: Algebra = .extend(child, .node(replacement), variable)
                    return .project(extend, p)
                } else {
                    return .project(child, p.filter { $0 != variable })
                }
            case .namedGraph(let a, let node):
                return .namedGraph(
                    a.bind(variable, to: replacement),
                    node.bind(variable, to: replacement)
                )
            default:
                break
            }
            return nil
        }
        return r
    }
}

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

            var aggregates = [(Aggregation, String)]()
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
                aggregates.append((agg, name))
            }

            let groups = try groupby.map { (gstrings) -> Expression in
                guard let e = try ExpressionParser.parseExpression(Array(gstrings)) else { throw QueryError.parseError("Failed to parse aggregate expression") }
                return e
            }

            guard let child = stack.popLast() else { return nil }
            return .aggregate(child, groups, aggregates)
        } else if op == "window" { // window row rowresult , rank rankresult ; ?x , ?y , ?z"
            let pair = parts.suffix(from: 1).split(separator: ";")
            guard pair.count >= 1 else { throw QueryError.parseError("Bad syntax for window operation") }
            let w = pair[0].split(separator: ",")
            guard w.count > 0 else { throw QueryError.parseError("Bad syntax for window operation") }
            let groupby = pair.count == 2 ? pair[1].split(separator: ",") : []

            var windows: [(WindowFunction, [Algebra.SortComparator], String)] = []
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
                windows.append((f, [], name))
            }

            let groups = try groupby.map { (gstrings) -> Expression in
                guard let e = try ExpressionParser.parseExpression(Array(gstrings)) else { throw QueryError.parseError("Failed to parse aggregate expression") }
                return e
            }

            guard let child = stack.popLast() else { return nil }
            return .window(child, groups, windows)
        } else if op == "avg" { // (AVG(?key) AS ?name) ... GROUP BY ?x ?y ?z --> "avg key name x y z"
            guard parts.count > 2 else { return nil }
            let key = parts[1]
            let name = parts[2]
            let groups = parts.suffix(from: 3).map { (name) -> Expression in .node(.variable(name, binding: true)) }
            guard let child = stack.popLast() else { return nil }
            return .aggregate(child, groups, [(.avg(.node(.variable(key, binding: true)), false), name)])
        } else if op == "sum" { // (SUM(?key) AS ?name) ... GROUP BY ?x ?y ?z --> "sum key name x y z"
            guard parts.count > 2 else { throw QueryError.parseError("Not enough arguments for \(op)") }
            let key = parts[1]
            let name = parts[2]
            let groups = parts.suffix(from: 3).map { (name) -> Expression in .node(.variable(name, binding: true)) }
            guard let child = stack.popLast() else { return nil }
            return .aggregate(child, groups, [(.sum(.node(.variable(key, binding: true)), false), name)])
        } else if op == "count" { // (COUNT(?key) AS ?name) ... GROUP BY ?x ?y ?z --> "count key name x y z"
            guard parts.count > 2 else { throw QueryError.parseError("Not enough arguments for \(op)") }
            let key = parts[1]
            let name = parts[2]
            let groups = parts.suffix(from: 3).map { (name) -> Expression in .node(.variable(name, binding: true)) }
            guard let child = stack.popLast() else { return nil }
            return .aggregate(child, groups, [(.count(.node(.variable(key, binding: true)), false), name)])
        } else if op == "countall" { // (COUNT(*) AS ?name) ... GROUP BY ?x ?y ?z --> "count name x y z"
            guard parts.count > 1 else { throw QueryError.parseError("Not enough arguments for \(op)") }
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
            let comparators = try parts.suffix(from: 1).split(separator: ",").map { (stack) -> Algebra.SortComparator in
                guard let expr = try ExpressionParser.parseExpression(Array(stack)) else { throw QueryError.parseError("Failed to parse ORDER expression") }
                let c: Algebra.SortComparator = (true, expr)
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

    public func parse() throws -> Algebra? {
        let lines = self.reader.lines()
        for line in lines {
            guard let algebra = try self.parse(line: line) else { continue }
            stack.append(algebra)
        }
        return stack.popLast()
    }
}

extension TriplePattern {
    public var sparqlTokens: AnySequence<SPARQLToken> {
        var tokens = [SPARQLToken]()
        tokens.append(contentsOf: self.subject.sparqlTokens)

        if self.predicate == .bound(Term.rdf("type")) {
            tokens.append(.keyword("A"))
        } else {
            tokens.append(contentsOf: self.predicate.sparqlTokens)
        }
        tokens.append(contentsOf: self.object.sparqlTokens)
        tokens.append(.dot)
        return AnySequence(tokens)
    }
}

extension QuadPattern {
    public var sparqlTokens: AnySequence<SPARQLToken> {
        var tokens = [SPARQLToken]()
        tokens.append(.keyword("GRAPH"))
        tokens.append(contentsOf: self.graph.sparqlTokens)
        tokens.append(.lbrace)
        tokens.append(contentsOf: self.subject.sparqlTokens)
        if self.predicate == .bound(Term.xsd("type")) {
            tokens.append(.keyword("A"))
        } else {
            tokens.append(contentsOf: self.predicate.sparqlTokens)
        }
        tokens.append(contentsOf: self.object.sparqlTokens)
        tokens.append(.dot)
        tokens.append(.rbrace)
        return AnySequence(tokens)
    }
}

extension Algebra {
    var serializableEquivalent: Algebra {
        switch self {
        case .project(let lhs, let names):
            return .project(lhs.serializableEquivalent, names)
        case .aggregate(let lhs, let groups, let aggs):
            switch lhs {
            case .project(_):
                return .aggregate(lhs.serializableEquivalent, groups, aggs)
            default:
                fatalError()
            }
        case .order(let lhs, let cmps):
            switch lhs {
            case .aggregate(_), .project(_):
                return .order(lhs.serializableEquivalent, cmps)
            default:
                return .order(.project(lhs.serializableEquivalent, lhs.inscope.sorted()), cmps)
            }
        case .slice(let lhs, let offset, let limit):
            switch lhs {
            case .order(_), .aggregate(_), .project(_):
                return .slice(lhs.serializableEquivalent, offset, limit)
            default:
                return .slice(.project(lhs.serializableEquivalent, lhs.inscope.sorted()), offset, limit)
            }
        case .distinct(let lhs):
            switch lhs {
            case .slice(_), .order(_), .aggregate(_), .project(_):
                return .distinct(lhs.serializableEquivalent)
            default:
                return .distinct(.project(lhs.serializableEquivalent, lhs.inscope.sorted()))
            }

        case .unionIdentity:
            fatalError("cannot serialize the union identity in SPARQL")
        case .joinIdentity:
            return self
        case .quad(_), .triple(_), .table(_), .bgp(_):
            return self
        case .innerJoin(let lhs, let rhs):
            return .innerJoin(lhs.serializableEquivalent, rhs.serializableEquivalent)
        case .leftOuterJoin(let lhs, let rhs, let expr):
            return .leftOuterJoin(lhs.serializableEquivalent, rhs.serializableEquivalent, expr)
        case .minus(let lhs, let rhs):
            return .minus(lhs.serializableEquivalent, rhs.serializableEquivalent)
        case .union(let lhs, let rhs):
            return .union(lhs.serializableEquivalent, rhs.serializableEquivalent)
        case .filter(let lhs, let expr):
            return .filter(lhs.serializableEquivalent, expr)
        case .namedGraph(let lhs, let graph):
            return .namedGraph(lhs.serializableEquivalent, graph)
        case .service(let endpoint, let lhs, let silent):
            return .service(endpoint, lhs.serializableEquivalent, silent)

            /**
    case .path(Node, PropertyPath, Node)
    case .aggregate(Algebra, [Expression], [(Aggregation, String)])
    case .window(Algebra, [Expression], [(WindowFunction, [SortComparator], String)])
    case .construct(Algebra, [TriplePattern])
    case .describe(Algebra, [Node])
    case .ask(Algebra)
**/
        default:
            fatalError("Implement Algebra.sparqlTokens for \(self)")
        }
    }

    public func sparqlQueryTokens() -> AnySequence<SPARQLToken> {
        let a = self.serializableEquivalent

        switch a {
        case .project(_), .aggregate(_), .order(.project(_), _), .slice(.project(_), _, _), .slice(.order(.project(_), _), _, _), .distinct(_):
            return a.sparqlTokens(depth: 0)
        default:
            let wrapped: Algebra = .project(a, a.inscope.sorted())
            return wrapped.sparqlTokens(depth: 0)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    public func sparqlTokens(depth: Int) -> AnySequence<SPARQLToken> {
        switch self {
        case .unionIdentity:
            fatalError("cannot serialize the union identity as a SPARQL token sequence")
        case .joinIdentity:
            return AnySequence([.lbrace, .rbrace])
        case .quad(let q):
            return q.sparqlTokens
        case .triple(let t):
            return t.sparqlTokens
        case .bgp(let triples):
            let tokens = triples.map { $0.sparqlTokens }.flatMap { $0 }
            return AnySequence(tokens)
        case .innerJoin(let rhs, let lhs):
            let tokens = [rhs, lhs].map { $0.sparqlTokens(depth: depth) }.flatMap { $0 }
            return AnySequence(tokens)
        case .leftOuterJoin(let lhs, let rhs, let expr):
            var tokens = [SPARQLToken]()
            tokens.append(.lbrace)
            tokens.append(contentsOf: lhs.sparqlTokens(depth: depth+1))
            tokens.append(.rbrace)
            tokens.append(.keyword("OPTIONAL"))
            tokens.append(.lbrace)
            tokens.append(contentsOf: rhs.sparqlTokens(depth: depth+1))
            if expr != .node(.bound(Term.trueValue)) {
                tokens.append(.keyword("FILTER"))
                tokens.append(contentsOf: expr.sparqlTokens())
            }
            tokens.append(.rbrace)
            return AnySequence(tokens)
        case .minus(let lhs, let rhs):
            var tokens = [SPARQLToken]()
            tokens.append(.lbrace)
            tokens.append(contentsOf: lhs.sparqlTokens(depth: depth+1))
            tokens.append(.rbrace)
            tokens.append(.keyword("MINUS"))
            tokens.append(.lbrace)
            tokens.append(contentsOf: rhs.sparqlTokens(depth: depth+1))
            tokens.append(.rbrace)
            return AnySequence(tokens)
        case .filter(let lhs, let expr):
            var tokens = [SPARQLToken]()
            tokens.append(contentsOf: lhs.sparqlTokens(depth: depth))
            tokens.append(.keyword("FILTER"))
            tokens.append(contentsOf: expr.sparqlTokens())
            return AnySequence(tokens)
        case .union(let lhs, let rhs):
            var tokens = [SPARQLToken]()
            tokens.append(.lbrace)
            tokens.append(contentsOf: lhs.sparqlTokens(depth: depth+1))
            tokens.append(.rbrace)
            tokens.append(.keyword("UNION"))
            tokens.append(.lbrace)
            tokens.append(contentsOf: rhs.sparqlTokens(depth: depth+1))
            tokens.append(.rbrace)
            return AnySequence(tokens)
        case .namedGraph(let lhs, let graph):
            var tokens = [SPARQLToken]()
            tokens.append(.keyword("GRAPH"))
            tokens.append(contentsOf: graph.sparqlTokens)
            tokens.append(.lbrace)
            tokens.append(contentsOf: lhs.sparqlTokens(depth: depth+1))
            tokens.append(.rbrace)
            return AnySequence(tokens)
        case .service(let endpoint, let lhs, let silent):
            var tokens = [SPARQLToken]()
            tokens.append(.keyword("SERVICE"))
            if silent {
                tokens.append(.keyword("SILENT"))
            }
            tokens.append(contentsOf: endpoint.sparqlTokens)
            tokens.append(.lbrace)
            tokens.append(contentsOf: lhs.sparqlTokens(depth: depth+1))
            tokens.append(.rbrace)
            return AnySequence(tokens)
        case .extend(let lhs, let expr, let name):
            var tokens = [SPARQLToken]()
            tokens.append(contentsOf: lhs.sparqlTokens(depth: depth))
            tokens.append(.keyword("BIND"))
            tokens.append(.lparen)
            tokens.append(contentsOf: expr.sparqlTokens())
            tokens.append(.keyword("AS"))
            tokens.append(._var(name))
            tokens.append(.rparen)
            return AnySequence(tokens)
        case .slice(let lhs, let offset, let limit):
            var tokens = [SPARQLToken]()
            tokens.append(contentsOf: lhs.sparqlTokens(depth: depth))
            var append = [SPARQLToken]()
            if depth > 0 {
                if let t = tokens.popLast() {
                    guard case .rbrace = t else { fatalError("Expected closing brace but found \(t)") }
                    append.append(t)
                }
            }
            if let offset = offset {
                tokens.append(.keyword("OFFSET"))
                tokens.append(.integer("\(offset)"))
            }
            if let limit = limit {
                tokens.append(.keyword("LIMIT"))
                tokens.append(.integer("\(limit)"))
            }
            tokens.append(contentsOf: append)
            return AnySequence(tokens)
        case .table(let nodes, let results):
            var tokens = [SPARQLToken]()
            tokens.append(.keyword("VALUES"))
            tokens.append(.lparen)
            var names = [String]()
            for n in nodes {
                guard case .variable(let name, _) = n else { fatalError() }
                tokens.append(contentsOf: n.sparqlTokens)
                names.append(name)
            }
            tokens.append(contentsOf: nodes.map { $0.sparqlTokens }.flatMap { $0 })
            tokens.append(.rparen)
            tokens.append(.lbrace)
            for result in results {
                tokens.append(.lparen)
                for n in names {
                    if let term = result[n] {
                        tokens.append(contentsOf: term.sparqlTokens)
                    } else {
                        tokens.append(.keyword("UNDEF"))
                    }
                }
                tokens.append(.rparen)
            }
            tokens.append(.rbrace)
            return AnySequence(tokens)
        case .project(let lhs, let names):
            var tokens = [SPARQLToken]()
            if depth > 0 {
                tokens.append(.lbrace)
            }
            tokens.append(.keyword("SELECT"))
            /**
            if Set(names) == lhs.inscope {
                tokens.append(.star)
            } else {
                tokens.append(contentsOf: names.map { ._var($0) })
            }
             **/
            tokens.append(contentsOf: names.map { ._var($0) })
            tokens.append(.keyword("WHERE"))
            tokens.append(.lbrace)
            tokens.append(contentsOf: lhs.sparqlTokens(depth: depth+1))
            tokens.append(.rbrace)
            if depth > 0 {
                tokens.append(.rbrace)
            }
            return AnySequence(tokens)
        case .distinct(.project(let lhs, let names)):
            var tokens = [SPARQLToken]()
            if depth > 0 {
                tokens.append(.lbrace)
            }
            tokens.append(.keyword("SELECT"))
            tokens.append(.keyword("DISTINCT"))
            tokens.append(contentsOf: names.map { ._var($0) })
            tokens.append(.keyword("WHERE"))
            tokens.append(.lbrace)
            tokens.append(contentsOf: lhs.sparqlTokens(depth: depth+1))
            tokens.append(.rbrace)
            if depth > 0 {
                tokens.append(.rbrace)
            }
            return AnySequence(tokens)
        case .distinct(let lhs):
            var tokens = [SPARQLToken]()
            if depth > 0 {
                tokens.append(.lbrace)
            }
            tokens.append(.keyword("SELECT"))
            tokens.append(.keyword("DISTINCT"))
            tokens.append(.star)
            tokens.append(.keyword("WHERE"))
            tokens.append(.lbrace)
            tokens.append(contentsOf: lhs.sparqlTokens(depth: depth+1))
            tokens.append(.rbrace)
            if depth > 0 {
                tokens.append(.rbrace)
            }
            return AnySequence(tokens)
        case .order(let lhs, let cmps):
            //(Bool, Expression)
            var tokens = Array(lhs.sparqlTokens(depth: depth))
            var append = [SPARQLToken]()
            if depth > 0 {
                if let t = tokens.popLast() {
                    guard case .rbrace = t else { fatalError("Expected closing brace but found \(t)") }
                    append.append(t)
                }
            }
            tokens.append(.keyword("ORDER"))
            tokens.append(.keyword("BY"))
            for (asc, expr) in cmps {
                if asc {
                    tokens.append(contentsOf: expr.sparqlTokens())
                } else {
                    tokens.append(.keyword("DESC"))
                    tokens.append(.lparen)
                    tokens.append(contentsOf: expr.sparqlTokens())
                    tokens.append(.rparen)
                }
            }
            tokens.append(contentsOf: append)
            return AnySequence(tokens)
        case .aggregate(let lhs, let groups, let aggs):
            fatalError("implement")

            /**
    case .path(Node, PropertyPath, Node)
    case .aggregate(Algebra, [Expression], [(Aggregation, String)])
    case .window(Algebra, [Expression], [(WindowFunction, [SortComparator], String)])
    case .construct(Algebra, [TriplePattern])
    case .describe(Algebra, [Node])
    case .ask(Algebra)
**/
        default:
            fatalError("implement Algebra.sparqlTokens for \(self)")
        }
    }
}
