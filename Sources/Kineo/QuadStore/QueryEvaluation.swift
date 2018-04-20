//
//  Query.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 7/8/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation

// swiftlint:disable cyclomatic_complexity
// swiftlint:disable:next type_body_length
open class SimpleQueryEvaluator<Q: QuadStoreProtocol> {
    var store: Q
    var defaultGraph: Term
    var freshVarNumber: Int
    var verbose: Bool
    var ee: ExpressionEvaluator
    
    public init(store: Q, defaultGraph: Term, verbose: Bool = false) {
        self.store = store
        self.defaultGraph = defaultGraph
        self.freshVarNumber = 1
        self.verbose = verbose
        self.ee = ExpressionEvaluator()
    }

    private func freshVariable() -> Node {
        let n = freshVarNumber
        freshVarNumber += 1
        return .variable(".v\(n)", binding: true)
    }
    

    public func evaluate(query: Query, activeGraph: Term) throws -> AnyIterator<TermResult> {
        let algebra = query.algebra
        return try self.evaluate(algebra: algebra, activeGraph: activeGraph)
    }
    
    public func evaluate(algebra: Algebra, activeGraph: Term) throws -> AnyIterator<TermResult> {
        switch algebra {
        // don't require access to the underlying store:
        case let .subquery(q):
            return try evaluate(query: q, activeGraph: activeGraph)
        case .unionIdentity:
            let results = [TermResult]()
            return AnyIterator(results.makeIterator())
        case .joinIdentity:
            let results = [TermResult(bindings: [:])]
            return AnyIterator(results.makeIterator())
        case let .table(_, results):
            return AnyIterator(results.makeIterator())
        case let .innerJoin(lhs, rhs):
            return try self.evaluateJoin(lhs: lhs, rhs: rhs, left: false, activeGraph: activeGraph)
        case let .leftOuterJoin(lhs, rhs, expr):
            return try self.evaluateLeftJoin(lhs: lhs, rhs: rhs, expression: expr, activeGraph: activeGraph)
        case let .union(lhs, rhs):
            return try self.evaluateUnion([lhs, rhs], activeGraph: activeGraph)
        case let .project(child, vars):
            let i = try self.evaluate(algebra: child, activeGraph: activeGraph)
            return AnyIterator {
                guard let result = i.next() else { return nil }
                return result.projected(variables: vars)
            }
        case let .slice(child, offset, limit):
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
        case let .extend(child, expr, name):
            let i = try self.evaluate(algebra: child, activeGraph: activeGraph)
            if expr.isNumeric {
                return AnyIterator {
                    guard var result = i.next() else { return nil }
                    do {
                        let num = try self.ee.numericEvaluate(expression: expr, result: result)
                        try? result.extend(variable: name, value: num.term)
                    } catch let err {
                        if self.verbose {
                            print(err)
                        }
                    }
                    return result
                }
            } else {
                return AnyIterator {
                    guard var result = i.next() else { return nil }
                    do {
                        let term = try self.ee.evaluate(expression: expr, result: result)
                        try? result.extend(variable: name, value: term)
                    } catch let err {
                        if self.verbose {
                            print(err)
                        }
                    }
                    return result
                }
            }
        case let .order(child, orders):
            let results = try Array(self.evaluate(algebra: child, activeGraph: activeGraph))
            let s = _sortResults(results, comparators: orders)
            return AnyIterator(s.makeIterator())
        case let .aggregate(child, groups, aggs):
            if aggs.count == 1 {
                let (agg, name) = aggs[0]
                switch agg {
                case .sum(_, false), .count(_, false), .countAll, .avg(_, false), .min(_), .max(_), .groupConcat(_, _, false), .sample(_):
                    return try evaluateSinglePipelinedAggregation(algebra: child, groups: groups, aggregation: agg, variable: name, activeGraph: activeGraph)
                default:
                    break
                }
            }
            return try evaluateAggregation(algebra: child, groups: groups, aggregations: aggs, activeGraph: activeGraph)
        case let .window(child, groups, funcs):
            return try evaluateWindow(algebra: child, groups: groups, functions: funcs, activeGraph: activeGraph)
        case let .filter(child, expr):
            let i = try self.evaluate(algebra: child, activeGraph: activeGraph)
            return AnyIterator {
                repeat {
                    guard let result = i.next() else { return nil }
                    do {
                        let term = try self.ee.evaluate(expression: expr, result: result)
                        if case .some(true) = try? term.ebv() {
                            return result
                        }
                    } catch let err {
                        if self.verbose {
                            print(err)
                        }
                    }
                } while true
            }
        case let .distinct(child):
            let i = try self.evaluate(algebra: child, activeGraph: activeGraph)
            var seen = Set<TermResult>()
            return AnyIterator {
                repeat {
                    guard let result = i.next() else { return nil }
                    guard !seen.contains(result) else { continue }
                    seen.insert(result)
                    return result
                } while true
            }
        case .bgp(_), .minus(_, _), .service(_):
            fatalError("Unimplemented: \(algebra)")
        case let .namedGraph(child, .bound(g)):
            return try evaluate(algebra: child, activeGraph: g)
        case let .triple(t):
            let quad = QuadPattern(subject: t.subject, predicate: t.predicate, object: t.object, graph: .bound(activeGraph))
            return try evaluate(algebra: .quad(quad), activeGraph: activeGraph)

            
        // requires access to the underlying store:
        case let .quad(quad):
            return try store.results(matching: quad)
        case let .path(s, path, o):
            return try evaluatePath(subject: s, object: o, graph: .bound(activeGraph), path: path)
        case let .namedGraph(child, graph):
            guard case .variable(let gv, let bind) = graph else { fatalError("Unexpected node found where variable required") }
            var iters = try store.graphs().filter { $0 != defaultGraph }.map { ($0, try evaluate(algebra: child, activeGraph: $0)) }
            return AnyIterator {
                repeat {
                    if iters.count == 0 {
                        return nil
                    }
                    let (graph, i) = iters[0]
                    guard var result = i.next() else { iters.remove(at: 0); continue }
                    if bind {
                        do {
                            try result.extend(variable: gv, value: graph)
                        } catch {
                            continue
                        }
                    }
                    return result
                } while true
            }
        }
    }

    public func effectiveVersion(matching query: Query, activeGraph: Term) throws -> Version? {
        let algebra = query.algebra
        guard var mtime = try effectiveVersion(matching: algebra, activeGraph: activeGraph) else { return nil }
        if case .describe(let nodes) = query.form {
            for node in nodes {
                let quad = QuadPattern(subject: node, predicate: .variable("p", binding: true), object: .variable("o", binding: true), graph: .bound(activeGraph))
                guard let qmtime = try store.effectiveVersion(matching: quad) else { return nil }
                mtime = max(mtime, qmtime)
            }
        }
        return mtime
    }
    
    public func effectiveVersion(matching algebra: Algebra, activeGraph: Term) throws -> Version? {
        switch algebra {
        // don't require access to the underlying store:
        case .joinIdentity, .unionIdentity:
            return 0
        case .table(_, _):
            return 0
        case let .innerJoin(lhs, rhs), let .leftOuterJoin(lhs, rhs, _), let .union(lhs, rhs), let .minus(lhs, rhs):
            guard let lhsmtime = try effectiveVersion(matching: lhs, activeGraph: activeGraph) else { return nil }
            guard let rhsmtime = try effectiveVersion(matching: rhs, activeGraph: activeGraph) else { return lhsmtime }
            return max(lhsmtime, rhsmtime)
        case let .namedGraph(child, graph):
            if case .bound(let g) = graph {
                return try effectiveVersion(matching: child, activeGraph: g)
            } else {
                fatalError("Unimplemented: effectiveVersion(.namedGraph(_), )")
            }
        case .distinct(let child), .project(let child, _), .slice(let child, _, _), .extend(let child, _, _), .order(let child, _), .filter(let child, _):
            return try effectiveVersion(matching: child, activeGraph: activeGraph)
        case .aggregate(let child, _, _):
            return try effectiveVersion(matching: child, activeGraph: activeGraph)
        case .window(let child, _, _):
            return try effectiveVersion(matching: child, activeGraph: activeGraph)
        case .service(_):
            return nil
        case .triple(let t):
            let quad = QuadPattern(subject: t.subject, predicate: t.predicate, object: t.object, graph: .bound(activeGraph))
            return try effectiveVersion(matching: .quad(quad), activeGraph: activeGraph)
            
            
        // requires access to the underlying store:
        case .path(_, _, _):
            let s: Node = .variable("s", binding: true)
            let p: Node = .variable("p", binding: true)
            let o: Node = .variable("o", binding: true)
            let quad = QuadPattern(subject: s, predicate: p, object: o, graph: .bound(activeGraph))
            return try store.effectiveVersion(matching: quad)
        case .quad(let quad):
            return try store.effectiveVersion(matching: quad)
        case .bgp(let children):
            guard children.count > 0 else { return nil }
            var mtime: Version = 0
            for t in children {
                let quad = QuadPattern(subject: t.subject, predicate: t.predicate, object: t.object, graph: .bound(activeGraph))
                guard let triplemtime = try store.effectiveVersion(matching: quad) else { continue }
                mtime = max(mtime, triplemtime)
            }
            return mtime
        }
    }
    
    
    
    
    func evaluateUnion(_ patterns: [Algebra], activeGraph: Term) throws -> AnyIterator<TermResult> {
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

    func evaluateJoin(lhs lhsAlgebra: Algebra, rhs rhsAlgebra: Algebra, left: Bool, activeGraph: Term) throws -> AnyIterator<TermResult> {
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
            let joinVariables = intersection
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

    func evaluateLeftJoin(lhs: Algebra, rhs: Algebra, expression expr: Expression, activeGraph: Term) throws -> AnyIterator<TermResult> {
        let i = try evaluateJoin(lhs: lhs, rhs: rhs, left: true, activeGraph: activeGraph)
        return AnyIterator {
            repeat {
                guard let result = i.next() else { return nil }
                do {
                    let term = try self.ee.evaluate(expression: expr, result: result)
                    if case .some(true) = try? term.ebv() {
                        return result
                    }
                } catch let err {
                    if self.verbose {
                        print(err)
                    }
                }
            } while true
        }
    }

    func evaluateCount<S: Sequence>(results: S, expression keyExpr: Expression, distinct: Bool) -> Term? where S.Iterator.Element == TermResult {
        if distinct {
            let terms = results.map { try? self.ee.evaluate(expression: keyExpr, result: $0) }.compactMap { $0 }
            let unique = Set(terms)
            return Term(integer: unique.count)
        } else {
            var count = 0
            for result in results {
                do {
                    let _ = try self.ee.evaluate(expression: keyExpr, result: result)
                    count += 1
                } catch let err {
                    if self.verbose {
                        print(err)
                    }
                }
            }
            return Term(integer: count)
        }
    }

    func evaluateCountAll<S: Sequence>(results: S) -> Term? where S.Iterator.Element == TermResult {
        var count = 0
        for _ in results {
            count += 1
        }
        return Term(integer: count)
    }

    func evaluateAvg<S: Sequence>(results: S, expression keyExpr: Expression, distinct: Bool) -> Term? where S.Iterator.Element == TermResult {
        var doubleSum: Double = 0.0
        let integer = TermType.datatype("http://www.w3.org/2001/XMLSchema#integer")
        var resultingType: TermType? = integer
        var count = 0

        var terms = results.map { try? self.ee.evaluate(expression: keyExpr, result: $0) }.compactMap { $0 }
        if distinct {
            terms = Array(Set(terms))
        }

        for term in terms {
            if term.isNumeric {
                count += 1
                resultingType = resultingType?.resultType(for: "+", withOperandType: term.type)
                doubleSum += term.numericValue
            }
        }

        doubleSum /= Double(count)
        resultingType = resultingType?.resultType(for: "/", withOperandType: integer)
        if let type = resultingType {
            if let n = Term(numeric: doubleSum, type: type) {
                return n
            } else {
                // cannot create a numeric term with this combination of value and type
            }
        } else {
            warn("*** Cannot determine resulting numeric datatype for AVG operation")
        }
        return nil
    }

    func evaluateSum<S: Sequence>(results: S, expression keyExpr: Expression, distinct: Bool) -> Term? where S.Iterator.Element == TermResult {
        var runningSum = NumericValue.integer(0)
        if distinct {
            let terms = results.map { try? self.ee.evaluate(expression: keyExpr, result: $0) }.compactMap { $0 }.sorted()
            let unique = Set(terms)
            if unique.count == 0 {
                return nil
            }
            for term in unique {
                if let numeric = term.numeric {
                    runningSum = runningSum + numeric
                }
            }
            return runningSum.term
        } else {
            var count = 0
            for result in results {
                if let term = try? self.ee.evaluate(expression: keyExpr, result: result) {
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
    }

    func evaluateGroupConcat<S: Sequence>(results: S, expression keyExpr: Expression, separator: String, distinct: Bool) -> Term? where S.Iterator.Element == TermResult {
        var terms = results.map { try? self.ee.evaluate(expression: keyExpr, result: $0) }.compactMap { $0 }
        if distinct {
            terms = Array(Set(terms))
        }

        if terms.count == 0 {
            return nil
        }

        let values = terms.map { $0.value }
        let type = terms.first!.type
        let c = values.joined(separator: separator)
        return Term(value: c, type: type)
    }

    func evaluateSinglePipelinedAggregation(algebra child: Algebra, groups: [Expression], aggregation agg: Aggregation, variable name: String, activeGraph: Term) throws -> AnyIterator<TermResult> {
        let i = try self.evaluate(algebra: child, activeGraph: activeGraph)
        var numericGroups = [String:NumericValue]()
        var termGroups = [String:Term]()
        var groupCount = [String:Int]()
        var groupBindings = [String:[String:Term]]()
        for result in i {
            let group = groups.map { (expr) -> Term? in return try? self.ee.evaluate(expression: expr, result: result) }
            let groupKey = "\(group)"
            if let value = termGroups[groupKey] {
                switch agg {
                case .min(let keyExpr):
                    if let term = try? self.ee.evaluate(expression: keyExpr, result: result) {
                        termGroups[groupKey] = min(value, term)
                    }
                case .max(let keyExpr):
                    if let term = try? self.ee.evaluate(expression: keyExpr, result: result) {
                        termGroups[groupKey] = max(value, term)
                    }
                case .sample(_):
                    break
                case .groupConcat(let keyExpr, let sep, false):
                    guard case .datatype(_) = value.type else { fatalError("Unexpected term in generating GROUP_CONCAT value") }
                    let string = value.value
                    if let term = try? self.ee.evaluate(expression: keyExpr, result: result) {
                        let updated = string + sep + term.value
                        termGroups[groupKey] = Term(value: updated, type: value.type)
                    }
                default:
                    fatalError("unexpected pipelined evaluation for \(agg)")
                }
            } else if let value = numericGroups[groupKey] {
                switch agg {
                case .countAll:
                    numericGroups[groupKey] = value + .integer(1)
                case .avg(let keyExpr, false):
                    if let term = try? self.ee.evaluate(expression: keyExpr, result: result), let c = groupCount[groupKey] {
                        if let n = term.numeric {
                            numericGroups[groupKey] = value + n
                            groupCount[groupKey] = c + 1
                        }
                    }
                case .count(let keyExpr, false):
                    if let _ = try? self.ee.evaluate(expression: keyExpr, result: result) {
                        numericGroups[groupKey] = value + .integer(1)
                    }
                case .sum(let keyExpr, false):
                    if let term = try? self.ee.evaluate(expression: keyExpr, result: result) {
                        if let n = term.numeric {
                            numericGroups[groupKey] = value + n
                        }
                    }
                default:
                    fatalError("unexpected pipelined evaluation for \(agg)")
                }
            } else {
                switch agg {
                case .countAll:
                    numericGroups[groupKey] = .integer(1)
                case .avg(let keyExpr, false):
                    if let term = try? self.ee.evaluate(expression: keyExpr, result: result) {
                        if term.isNumeric {
                            numericGroups[groupKey] = term.numeric
                            groupCount[groupKey] = 1
                        }
                    }
                case .count(let keyExpr, false):
                    if let _ = try? self.ee.evaluate(expression: keyExpr, result: result) {
                        numericGroups[groupKey] = .integer(1)
                    }
                case .sum(let keyExpr, false):
                    if let term = try? self.ee.evaluate(expression: keyExpr, result: result) {
                        if term.isNumeric {
                            numericGroups[groupKey] = term.numeric
                        }
                    }
                case .min(let keyExpr):
                    if let term = try? self.ee.evaluate(expression: keyExpr, result: result) {
                        termGroups[groupKey] = term
                    }
                case .max(let keyExpr):
                    if let term = try? self.ee.evaluate(expression: keyExpr, result: result) {
                        termGroups[groupKey] = term
                    }
                case .sample(let keyExpr):
                    if let term = try? self.ee.evaluate(expression: keyExpr, result: result) {
                        termGroups[groupKey] = term
                    }
                case .groupConcat(let keyExpr, _, false):
                    if let term = try? self.ee.evaluate(expression: keyExpr, result: result) {
                        switch term.type {
                        case .datatype(_):
                            termGroups[groupKey] = term
                        default:
                            termGroups[groupKey] = Term(value: term.value, type: .datatype("http://www.w3.org/2001/XMLSchema#string"))
                        }
                    }
                default:
                    fatalError("unexpected pipelined evaluation for \(agg)")
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
        
        if numericGroups.count == 0 && termGroups.count == 0 {
            // special case where there are no groups (no input rows led to no groups being created);
            // in this case, counts should return a single result with { $name=0 }
            let result = TermResult(bindings: [name: Term(integer: 0)])
            return AnyIterator([result].makeIterator())
        }
        
        var a = numericGroups.makeIterator()
        let numericIterator : AnyIterator<TermResult> = AnyIterator {
            guard let pair = a.next() else { return nil }
            let (groupKey, v) = pair
            var value = v
            if case .avg(_) = agg {
                guard let count = groupCount[groupKey] else { fatalError("Failed to find expected group data during aggregation") }
                value = v / NumericValue.double(mantissa: Double(count), exponent: 0)
            }

            guard var bindings = groupBindings[groupKey] else { fatalError("Unexpected missing aggregation group template") }
            bindings[name] = value.term
            return TermResult(bindings: bindings)
        }
        var b = termGroups.makeIterator()
        let termIterator : AnyIterator<TermResult> = AnyIterator {
            guard let pair = b.next() else { return nil }
            let (groupKey, term) = pair
            guard var bindings = groupBindings[groupKey] else { fatalError("Unexpected missing aggregation group template") }
            bindings[name] = term
            return TermResult(bindings: bindings)
        }
        
        return AnyIterator {
            if let r = numericIterator.next() {
                return r
            } else {
                return termIterator.next()
            }
        }
    }

    func evaluateWindow(algebra child: Algebra, groups: [Expression], functions: [(WindowFunction, [Algebra.SortComparator], String)], activeGraph: Term) throws -> AnyIterator<TermResult> {
        let i = try self.evaluate(algebra: child, activeGraph: activeGraph)
        var groupBuckets = [String:[TermResult]]()
        for result in i {
            let group = groups.map { (expr) -> Term? in return try? self.ee.evaluate(expression: expr, result: result) }
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
            } else {
                groupBuckets[groupKey]?.append(result)
            }
        }

        var groups = Array(groupBuckets.values)
        for (f, comparators, name) in functions {
            let results = groups.map { (results) -> [TermResult] in
                var newResults = [TermResult]()
                
                if case .rowNumber = f {
                    for (n, result) in _sortResults(results, comparators: comparators).enumerated() {
                        var r = result
                        try? r.extend(variable: name, value: Term(integer: n))
                        newResults.append(r)
                    }
                } else if case .rank = f {
                    let sorted = _sortResults(results, comparators: comparators)
                    if sorted.count > 0 {
                        var last = sorted.first!
                        var n = 0
                        
                        try? last.extend(variable: name, value: Term(integer: n))
                        newResults.append(last)
                        
                        for result in sorted.dropFirst() {
                            var r = result
                            if !_resultsEqual(r, last, comparators: comparators) {
                                n += 1
                            }
                            try? r.extend(variable: name, value: Term(integer: n))
                            newResults.append(r)
                        }
                    }
                }
                
                return newResults
            }
            groups = results
        }

        let results = groups.flatMap { $0 }
        return AnyIterator(results.makeIterator())
    }

    private func alp(term: Term, path: PropertyPath, graph: Node) throws -> AnyIterator<Term> {
        var v = Set<Term>()
        try alp(term: term, path: path, seen: &v, graph: graph)
        return AnyIterator(v.makeIterator())
    }

    private func alp(term: Term, path: PropertyPath, seen: inout Set<Term>, graph: Node) throws {
        guard !seen.contains(term) else { return }
        seen.insert(term)
        let pvar = freshVariable()
        for result in try evaluatePath(subject: .bound(term), object: pvar, graph: graph, path: path) {
            if let n = result[pvar] {
                try alp(term: n, path: path, seen: &seen, graph: graph)
            }
        }
    }

    func evaluatePath(subject: Node, object: Node, graph: Node, path: PropertyPath) throws -> AnyIterator<TermResult> {
        switch path {
        case .link(let predicate):
            let quad = QuadPattern(subject: subject, predicate: .bound(predicate), object: object, graph: graph)
            return try store.results(matching: quad)
        case .inv(let ipath):
            return try evaluatePath(subject: object, object: subject, graph: graph, path: ipath)
        case .nps(let iris):
            return try evaluateNPS(subject: subject, object: object, graph: graph, not: iris)
        case let .alt(lhs, rhs):
            let i = try evaluatePath(subject: subject, object: object, graph: graph, path: lhs)
            let j = try evaluatePath(subject: subject, object: object, graph: graph, path: rhs)
            var iters = [i, j]
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

        case let .seq(lhs, rhs):
            let jvar = freshVariable()
            guard case .variable(let jvarname, _) = jvar else { fatalError() }
            let lhsIter = try evaluatePath(subject: subject, object: jvar, graph: graph, path: lhs)
            let rhsIter = try evaluatePath(subject: jvar, object: object, graph: graph, path: rhs)
            let i = pipelinedHashJoin(joinVariables: [jvarname], lhs: lhsIter, rhs: rhsIter)
                .map { $0.removing(variables: Set([jvarname])) }
            return AnyIterator(i.makeIterator())
        case .plus(let pp):
            switch (subject, object) {
            case (.bound(_), .variable(let oname, binding: _)):
                let pvar = freshVariable()
                var v = Set<Term>()
                for result in try evaluatePath(subject: subject, object: pvar, graph: graph, path: pp) {
                    if let n = result[pvar] {
                        try alp(term: n, path: path, seen: &v, graph: graph)
                    }
                }
                
                var i = v.makeIterator()
                return AnyIterator {
                    guard let t = i.next() else { return nil }
                    let r = TermResult(bindings: [oname: t])
                    return r
                }
            case (.variable(_), .bound(_)):
                let ipath: PropertyPath = .plus(.inv(pp))
                return try evaluatePath(subject: object, object: subject, graph: graph, path: ipath)
            case (.bound(_), .bound(let oterm)):
                let pvar = freshVariable()
                var v = Set<Term>()
                for result in try evaluatePath(subject: subject, object: pvar, graph: graph, path: pp) {
                    if let n = result[pvar] {
                        try alp(term: n, path: path, seen: &v, graph: graph)
                    }
                }
                
                var results = [TermResult]()
                if v.contains(oterm) {
                    results.append(TermResult(bindings: [:]))
                }
                return AnyIterator(results.makeIterator())
            case (.variable(let sname, binding: _), .variable(_)):
                var results = [TermResult]()
                for t in store.graphNodeTerms() {
                    let i = try evaluatePath(subject: .bound(t), object: object, graph: graph, path: pp)
                    let j = i.map {
                        $0.extended(variable: sname, value: t) ?? $0
                    }
                    results.append(contentsOf: j)
                }
                return AnyIterator(results.makeIterator())
            }
        case .star(let pp):
            switch (subject, object) {
            case (.bound(let t), .variable(let oname, binding: _)):
                let i = try alp(term: t, path: pp, graph: graph)
                return AnyIterator {
                    guard let o = i.next() else { return nil }
                    let r = TermResult(bindings: [oname: o])
                    return r
                }
            case (.variable(_), .bound(_)):
                let ipath: PropertyPath = .star(.inv(pp))
                return try evaluatePath(subject: object, object: subject, graph: graph, path: ipath)
            case (.bound(let t), .bound(let oterm)):
                var v = Set<Term>()
                try alp(term: t, path: path, seen: &v, graph: graph)

                var results = [TermResult]()
                if v.contains(oterm) {
                    results.append(TermResult(bindings: [:]))
                }
                return AnyIterator(results.makeIterator())
            case let (.variable(sname, binding: _), .variable(_)):
                var results = [TermResult]()
                for t in store.graphNodeTerms() {
                    let i = try evaluatePath(subject: .bound(t), object: object, graph: graph, path: path)
                    let j = i.map {
                        $0.extended(variable: sname, value: t) ?? $0
                    }
                    results.append(contentsOf: j)
                }
                return AnyIterator(results.makeIterator())
            }
        case .zeroOrOne(let pp):
            switch (subject, object) {
            case (.bound(_), .variable(let oname, binding: _)):
                // eval(Path(X:term, ZeroOrOnePath(P), Y:var)) = { (Y, yn) | yn = X or {(Y, yn)} in eval(Path(X,P,Y)) }
                var results = [TermResult]()
                for t in store.graphNodeTerms() {
                    results.append(TermResult(bindings: [oname: t]))
                }
                let i = try evaluatePath(subject: subject, object: object, graph: graph, path: pp)
                results.append(contentsOf: i)
                return AnyIterator(results.makeIterator())
            case (.variable(let sname, binding: _), .bound(_)):
                // eval(Path(X:var, ZeroOrOnePath(P), Y:term)) = { (X, xn) | xn = Y or {(X, xn)} in eval(Path(X,P,Y)) }
                var results = [TermResult]()
                for t in store.graphNodeTerms() {
                    results.append(TermResult(bindings: [sname: t]))
                }
                let i = try evaluatePath(subject: subject, object: object, graph: graph, path: pp)
                results.append(contentsOf: i)
                return AnyIterator(results.makeIterator())
            case (.bound(let s), .bound(let o)) where s == o:
                let results = [TermResult(bindings: [:])]
                return AnyIterator(results.makeIterator())
            case (.bound(_), .bound(_)):
                // eval(Path(X:term, ZeroOrOnePath(P), Y:term)) =
                //     { {} } if X = Y or eval(Path(X,P,Y)) is not empty
                //     { } othewise
                var results = [TermResult]()
                let i = try evaluatePath(subject: subject, object: object, graph: graph, path: pp)
                if let _ = i.next() {
                    results.append(TermResult(bindings: [:]))
                }
                return AnyIterator(results.makeIterator())
            case (.variable(let sname, binding: _), .variable(let oname, binding: _)):
                // eval(Path(X:var, ZeroOrOnePath(P), Y:var)) = { (X, xn) (Y, yn) | either (yn in nodes(G) and xn = yn) or {(X,xn), (Y,yn)} in eval(Path(X,P,Y)) }
                var results = [TermResult]()
                for t in store.graphNodeTerms() {
                    results.append(TermResult(bindings: [sname: t, oname: t]))
                }
                let i = try evaluatePath(subject: subject, object: object, graph: graph, path: pp)
                results.append(contentsOf: i)
                return AnyIterator(results.makeIterator())
            }
        }
    }

    func evaluateNPS(subject: Node, object: Node, graph: Node, not iris: [Term]) throws -> AnyIterator<TermResult> {
        let predicate = self.freshVariable()
        let quad = QuadPattern(subject: subject, predicate: predicate, object: object, graph: graph)
        let i = try store.results(matching: quad)
        // OPTIMIZE: this can be made more efficient by adding an NPS function to the store,
        //           and allowing it to do the filtering based on a IDResult objects before
        //           materializing the terms
        let set = Set(iris)
        var keys = Set<String>()
        for node in [subject, object] {
            if case .variable(let name, true) = node {
                keys.insert(name)
            }
        }
        return AnyIterator {
            repeat {
                guard let r = i.next() else { return nil }
                guard let p = r[predicate] else { continue }
                guard !set.contains(p) else { continue }
                return r.projected(variables: keys)
            } while true
        }
    }

    func evaluateAggregation(algebra child: Algebra, groups: [Expression], aggregations aggs: [(Aggregation, String)], activeGraph: Term) throws -> AnyIterator<TermResult> {
        let i = try self.evaluate(algebra: child, activeGraph: activeGraph)
        var groupBuckets = [String:[TermResult]]()
        var groupBindings = [String:[String:Term]]()
        for result in i {
            let group = groups.map { (expr) -> Term? in return try? self.ee.evaluate(expression: expr, result: result) }
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
                case .count(let keyExpr, let distinct):
                    if let n = self.evaluateCount(results: results, expression: keyExpr, distinct: distinct) {
                        bindings[name] = n
                    }
                case .sum(let keyExpr, let distinct):
                    if let n = self.evaluateSum(results: results, expression: keyExpr, distinct: distinct) {
                        bindings[name] = n
                    }
                case .avg(let keyExpr, let distinct):
                    if let n = self.evaluateAvg(results: results, expression: keyExpr, distinct: distinct) {
                        bindings[name] = n
                    }
                case .min(let keyExpr):
                    let terms = results.map { try? self.ee.evaluate(expression: keyExpr, result: $0) }.compactMap { $0 }
                    if terms.count > 0 {
                        let n = terms.reduce(terms.first!) { min($0, $1) }
                        bindings[name] = n
                    }
                case .max(let keyExpr):
                    let terms = results.map { try? self.ee.evaluate(expression: keyExpr, result: $0) }.compactMap { $0 }
                    if terms.count > 0 {
                        let n = terms.reduce(terms.first!) { max($0, $1) }
                        bindings[name] = n
                    }
                case .sample(let keyExpr):
                    let terms = results.map { try? self.ee.evaluate(expression: keyExpr, result: $0) }.compactMap { $0 }
                    if let n = terms.first {
                        bindings[name] = n
                    }
                case .groupConcat(let keyExpr, let sep, let distinct):
                    if let n = self.evaluateGroupConcat(results: results, expression: keyExpr, separator: sep, distinct: distinct) {
                        bindings[name] = n
                    }
                }
            }
            return TermResult(bindings: bindings)
        }
    }

    private func _resultsEqual(_ a : TermResult, _ b : TermResult, comparators: [Algebra.SortComparator]) -> Bool {
        for (ascending, expr) in comparators {
            guard var lhs = try? self.ee.evaluate(expression: expr, result: a) else { return true }
            guard var rhs = try? self.ee.evaluate(expression: expr, result: b) else { return false }
            if !ascending {
                (lhs, rhs) = (rhs, lhs)
            }
            if lhs < rhs {
                return false
            } else if lhs > rhs {
                return false
            }
        }
        return true
    }
    
    private func _sortResults(_ results: [TermResult], comparators: [Algebra.SortComparator]) -> [TermResult] {
        let s = results.sorted { (a, b) -> Bool in
            for (ascending, expr) in comparators {
                guard var lhs = try? self.ee.evaluate(expression: expr, result: a) else { return true }
                guard var rhs = try? self.ee.evaluate(expression: expr, result: b) else { return false }
                if !ascending {
                    (lhs, rhs) = (rhs, lhs)
                }
                if lhs < rhs {
                    return true
                } else if lhs > rhs {
                    return false
                }
            }
            return false
        }
        return s
    }
}

public func pipelinedHashJoin<R: ResultProtocol>(joinVariables: Set<String>, lhs: AnyIterator<R>, rhs: AnyIterator<R>, left: Bool = false) -> AnyIterator<R> {
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
                let r = buffer.remove(at: 0)
                return r
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

public func nestedLoopJoin<R: ResultProtocol>(_ results: [[R]], left: Bool = false, cb callback: (R) -> ()) {
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
                        callback(j)
                    } else {
                        joinedResults.append(j)
                    }
                }
            }
            if left && !joined {
                if finalPass {
                    callback(lresult)
                } else {
                    joinedResults.append(lresult)
                }
            }
        }
        patternResults.append(joinedResults)
    }
}
