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

extension TriplePattern : Equatable {
    public static func == (lhs: TriplePattern, rhs: TriplePattern) -> Bool {
        guard lhs.subject == rhs.subject else { return false }
        guard lhs.predicate == rhs.predicate else { return false }
        guard lhs.object == rhs.object else { return false }
        return true
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

extension QuadPattern : Equatable {
    public static func == (lhs: QuadPattern, rhs: QuadPattern) -> Bool {
        guard lhs.subject == rhs.subject else { return false }
        guard lhs.predicate == rhs.predicate else { return false }
        guard lhs.object == rhs.object else { return false }
        guard lhs.graph == rhs.graph else { return false }
        return true
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

extension PropertyPath : Equatable {
    public static func == (lhs: PropertyPath, rhs: PropertyPath) -> Bool {
        switch (lhs, rhs) {
        case (.link(let l), .link(let r)) where l == r:
            return true
        case (.inv(let l), .inv(let r)) where l == r:
            return true
        case (.nps(let l), .nps(let r)) where l == r:
            return true
        case (.alt(let ll, let lr), .alt(let rl, let rr)) where ll == rl && lr == rr:
            return true
        case (.seq(let ll, let lr), .seq(let rl, let rr)) where ll == rl && lr == rr:
            return true
        case (.plus(let l), .plus(let r)) where l == r:
            return true
        case (.star(let l), .star(let r)) where l == r:
            return true
        case (.zeroOrOne(let l), .zeroOrOne(let r)) where l == r:
            return true
        default:
            return false
        }
    }
}

public enum SelectProjection : Equatable {
    case star
    case variables([String])
}

public enum QueryForm : Equatable {
    case select(SelectProjection)
    case ask
    case construct([TriplePattern])
    case describe([Node])
}

public struct Dataset : Equatable {
    var defaultGraphs: [Term]
    var namedGraphs: [Term]
    
    var isEmpty : Bool {
        return defaultGraphs.count == 0 && namedGraphs.count == 0
    }
}

public struct Query : Equatable {
    public var form: QueryForm
    public var algebra: Algebra
    public var dataset: Dataset?
    
    init(form: QueryForm, algebra: Algebra, dataset: Dataset? = nil) {
        self.form = form
        self.algebra = algebra
        self.dataset = dataset
    }
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
    case project(Algebra, Set<String>)
    case distinct(Algebra)
    case service(Node, Algebra, Bool)
    case slice(Algebra, Int?, Int?)
    case order(Algebra, [SortComparator])
    case path(Node, PropertyPath, Node)
    case aggregate(Algebra, [Expression], [(Aggregation, String)])
    case window(Algebra, [Expression], [(WindowFunction, [SortComparator], String)])
    case subquery(Query)
}

extension Algebra : Equatable {
    public static func == (lhs: Algebra, rhs: Algebra) -> Bool {
        switch (lhs, rhs) {
        case (.unionIdentity, .unionIdentity), (.joinIdentity, .joinIdentity):
            return true
        case (.table(let ln, let lr), .table(let rn, let rr)) where ln == rn && lr == rr:
            return true
        case (.quad(let l), .quad(let r)) where l == r:
            return true
        case (.triple(let l), .triple(let r)) where l == r:
            return true
        case (.bgp(let l), .bgp(let r)) where l == r:
            return true
        case (.innerJoin(let l), .innerJoin(let r)) where l == r:
            return true
        case (.leftOuterJoin(let l), .leftOuterJoin(let r)) where l == r:
            return true
        case (.union(let l), .union(let r)) where l == r:
            return true
        case (.minus(let l), .minus(let r)) where l == r:
            return true
        case (.distinct(let l), .distinct(let r)) where l == r:
            return true
        case (.subquery(let l), .subquery(let r)) where l == r:
            return true
        case (.filter(let la, let le), .filter(let ra, let re)) where la == ra && le == re:
            return true
        case (.namedGraph(let la, let ln), .namedGraph(let ra, let rn)) where la == ra && ln == rn:
            return true
        case (.extend(let la, let le, let ln), .extend(let ra, let re, let rn)) where la == ra && le == re && ln == rn:
            return true
        case (.project(let la, let lv), .project(let ra, let rv)) where la == ra && lv == rv:
            return true
        case (.service(let ln, let la, let ls), .service(let rn, let ra, let rs)) where la == ra && ln == rn && ls == rs:
            return true
        case (.slice(let la, let ll, let lo), .slice(let ra, let rl, let ro)) where la == ra && ll == rl && lo == ro:
            return true
        case (.order(let la, let lc), .order(let ra, let rc)) where la == ra:
            guard lc.count == rc.count else { return false }
            for (lcmp, rcmp) in zip(lc, rc) {
                guard lcmp.0 == rcmp.0 else { return false }
                guard lcmp.1 == rcmp.1 else { return false }
            }
            return true
        case (.path(let ls, let lp, let lo), .path(let rs, let rp, let ro)) where ls == rs && lp == rp && lo == ro:
            return true
        case (.aggregate(let ls, let lp, let lo), .aggregate(let rs, let rp, let ro)) where ls == rs && lp == rp:
            guard lo.count == ro.count else { return false }
            for (l, r) in zip(lo, ro) {
                guard l.0 == r.0 else { return false }
                guard l.1 == r.1 else { return false }
            }
            return true
        case (.window(let ls, let lp, let lo), .window(let rs, let rp, let ro)) where ls == rs && lp == rp:
            guard lo.count == ro.count else { return false }
            for (l, r) in zip(lo, ro) {
                guard l.0 == r.0 else { return false }
                guard l.2 == r.2 else { return false }
                guard l.1.count == r.1.count else { return false }
                for (lcmp, rcmp) in zip(l.1 ,r.1) {
                    guard lcmp.0 == rcmp.0 else { return false }
                    guard lcmp.1 == rcmp.1 else { return false }
                }
            }
            return true
        default:
            return false
        }
    }
}

public extension Query {
    public func serialize(depth: Int=0) -> String {
        let indent = String(repeating: " ", count: (depth*2))
        let algebra = self.algebra
        switch self.form {
        case .construct(let triples):
            var d = "\(indent)Construct\n"
            d += "\(indent)  Query\n"
            d += algebra.serialize(depth: depth+2)
            d += "\(indent)  Template\n"
            for t in triples {
                d += "\(indent)    \(t)\n"
            }
            return d
        case .describe(let nodes):
            let expressions = nodes.map { "\($0)" }
            var d = "\(indent)Describe { \(expressions.joined(separator: ", ")) }\n"
            d += algebra.serialize(depth: depth+1)
            return d
        case .ask:
            var d = "\(indent)Ask\n"
            d += algebra.serialize(depth: depth+1)
            return d
        case .select(.star):
            var d = "\(indent)Select { * }\n"
            d += algebra.serialize(depth: depth+1)
            return d
        case .select(.variables(let v)):
            var d = "\(indent)Select { \(v.joined(separator: ", ")) }\n"
            d += algebra.serialize(depth: depth+1)
            return d
        }
    }
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
        case .subquery(let a):
            var d = "\(indent)Sub-select\n"
            d += a.serialize(depth: depth+1)
            return d
        }
    }
}

public extension Query {
    public var inscope: Set<String> {
        return self.algebra.inscope
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
        case .subquery(let q):
            return q.inscope
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
        }
    }

    public var projectableVariables : Set<String> {
        switch self {
        case .aggregate(_, let groups, _):
            var vars = Set<String>()
            for g in groups {
                if case .node(.variable(let v, _)) = g {
                    vars.insert(v)
                }
            }
            return vars

        case .extend(let child, _, let v):
            return Set([v]).union(child.projectableVariables)
            
        default:
            return self.inscope
        }
    }
    
    public var isAggregation: Bool {
        switch self {
        case .joinIdentity, .unionIdentity, .triple(_), .quad(_), .bgp(_), .path(_), .window(_), .table(_), .subquery(_):
            return false
            
        case .project(let child, _), .minus(let child, _), .distinct(let child), .slice(let child, _, _), .namedGraph(let child, _), .order(let child, _), .service(_, let child, _):
            return child.isAggregation
            
        case .innerJoin(let lhs, let rhs), .union(let lhs, let rhs), .leftOuterJoin(let lhs, let rhs, _):
            return lhs.isAggregation || rhs.isAggregation
            
        case .aggregate(_):
            return true
        case .extend(let child, let expr, _), .filter(let child, let expr):
            if child.isAggregation {
                return true
            }
            return expr.hasAggregation
        }
    }
}

public extension Query {
    func replace(_ map: (Expression) -> Expression?) -> Query {
        let algebra = self.algebra.replace(map)
        return Query(form: self.form, algebra: algebra, dataset: self.dataset)
    }

    func replace(_ map: (Algebra) -> Algebra?) -> Query {
        let algebra = self.algebra.replace(map)
        return Query(form: self.form, algebra: algebra, dataset: self.dataset)
    }
}

public extension Algebra {
    func replace(_ map: (Expression) -> Expression?) -> Algebra {
        switch self {
        case .subquery(let q):
            return .subquery(q.replace(map))
        case .unionIdentity, .joinIdentity, .triple(_), .quad(_), .path(_), .bgp(_), .table(_):
            return self
        case .distinct(let a):
            return .distinct(a.replace(map))
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
            case .subquery(let q):
                return .subquery(q.replace(map))
            case .unionIdentity, .joinIdentity, .triple(_), .quad(_), .path(_), .bgp(_), .table(_):
                return self
            case .distinct(let a):
                return .distinct(a.replace(map))
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
        return Query(form: .select(.variables(proj)), algebra: algebra, dataset: nil)
    }
}
