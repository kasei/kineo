//
//  QueryPlan.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 1/15/19.
//

import Foundation
import SPARQLSyntax

enum QueryPlanError : Error {
    case invalidChild
    case invalidExpression
    case unimplemented
    case nonConstantExpression
}

public protocol PlanSerializable {
    func serialize(depth: Int) -> String
}

public protocol QueryPlan: PlanSerializable {
    var selfDescription: String { get }
    var children : [QueryPlan] { get }
    var properties: [PlanSerializable] { get }
    func evaluate() throws -> AnyIterator<TermResult>
}

public protocol UnaryQueryPlan: QueryPlan {
    var child: QueryPlan { get }
}

public extension UnaryQueryPlan {
    var children : [QueryPlan] { return [child] }
}

public protocol BinaryQueryPlan: QueryPlan {
    var lhs: QueryPlan { get }
    var rhs: QueryPlan { get }
}

public extension BinaryQueryPlan {
    var children : [QueryPlan] { return [lhs, rhs] }
}

public protocol NullaryQueryPlan: QueryPlan {}

public extension NullaryQueryPlan {
    var children : [QueryPlan] { return [] }
}

public extension QueryPlan {
    var arity: Int { return children.count }
    var selfDescription: String {
        return "\(self)"
    }
    
    var properties: [PlanSerializable] { return [] }
    func serialize(depth: Int=0) -> String {
        let indent = String(repeating: " ", count: (depth*2))
        let name = self.selfDescription
        var d = "\(indent)\(name)\n"
        for c in self.properties {
            d += c.serialize(depth: depth+1)
        }
        for c in self.children {
            d += c.serialize(depth: depth+1)
        }
        // TODO: include non-queryplan children (e.g. TablePlan rows)
        return d
    }
}

public struct TablePlan: NullaryQueryPlan {
    var columns: [Node]
    var rows: [[Term?]]
    public var selfDescription: String { return "Table { \(columns) }" }
    public static var joinIdentity = TablePlan(columns: [], rows: [[]])
    public static var unionIdentity = TablePlan(columns: [], rows: [])
    public func evaluate() throws -> AnyIterator<TermResult> {
        var results = [TermResult]()
        for row in rows {
            var bindings = [String:Term]()
            for (node, term) in zip(columns, row) {
                guard case .variable(let name, _) = node else {
                    Logger.shared.error("Unexpected variable generated during table evaluation")
                    throw QueryError.evaluationError("Unexpected variable generated during table evaluation")
                }
                if let term = term {
                    bindings[name] = term
                }
            }
            let result = TermResult(bindings: bindings)
            results.append(result)
        }
        return AnyIterator(results.makeIterator())
    }
}

public struct QuadPlan: NullaryQueryPlan {
    var quad: QuadPattern
    var store: QuadStoreProtocol
    public var selfDescription: String { return "Quad(\(quad))" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        return try store.results(matching: quad)
    }
}

public struct NestedLoopJoinPlan: BinaryQueryPlan {
    public var lhs: QueryPlan
    public var rhs: QueryPlan
    public var selfDescription: String { return "Nested Loop Join" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        let l = try Array(lhs.evaluate())
        let r = try rhs.evaluate()
        var results = [TermResult]()
        for rresult in r {
            for lresult in l {
                if let j = lresult.join(rresult) {
                    results.append(j)
                }
            }
        }
        return AnyIterator(results.makeIterator())
    }
}

public struct HashJoinPlan: BinaryQueryPlan {
    public var lhs: QueryPlan
    public var rhs: QueryPlan
    var joinVariables: Set<String>
    public var selfDescription: String { return "Hash Join { \(joinVariables) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        let joinVariables = self.joinVariables
        let l = try lhs.evaluate()
        let r = try rhs.evaluate()
        var table = [TermResult:[TermResult]]()
        var unboundTable = [TermResult]()
        //    warn(">>> filling hash table")
        var count = 0
        for result in r {
            count += 1
            let key = result.projected(variables: joinVariables)
            if key.keys.count != joinVariables.count {
                unboundTable.append(result)
            } else {
                table[key, default: []].append(result)
            }
        }
        //    warn(">>> done (\(count) results in \(Array(table.keys).count) buckets)")
        
        var buffer = [TermResult]()
        return AnyIterator {
            repeat {
                if buffer.count > 0 {
                    let r = buffer.remove(at: 0)
                    return r
                }
                guard let result = l.next() else { return nil }
                let key = result.projected(variables: joinVariables)
                var buckets = [TermResult]()
                if key.keys.count != joinVariables.count {
                    for bucket in table.keys {
                        if let _ = bucket.join(result) {
                            buckets.append(bucket)
                        }
                    }
                } else {
                    buckets.append(key)
                }
                for bucket in buckets {
                    if let results = table[bucket] {
                        for lhs in results {
                            if let j = lhs.join(result) {
                                buffer.append(j)
                            }
                        }
                    }
                }
                for lhs in unboundTable {
                    if let j = lhs.join(result) {
                        buffer.append(j)
                    }
                }
            } while true
        }
    }
}

public struct UnionPlan: BinaryQueryPlan {
    public var lhs: QueryPlan
    public var rhs: QueryPlan
    public var selfDescription: String { return "Union" }
    public init(lhs: QueryPlan, rhs: QueryPlan) {
        self.lhs = lhs
        self.rhs = rhs
    }
    public func evaluate() throws -> AnyIterator<TermResult> {
        let l = try lhs.evaluate()
        let r = try rhs.evaluate()
        var lok = true
        let i = AnyIterator { () -> TermResult? in
            if lok, let ll = l.next() {
                return ll
            } else {
                lok = false
                return r.next()
            }
            // TODO: this simplified version should work but breaks due to a bug in the SQLite bindings that make repeated calls to next() after end-of-iterator throw an error
//            return l.next() ?? r.next()
        }
        return i
    }
}

public struct FilterPlan: UnaryQueryPlan {
    public var child: QueryPlan
    var expression: Expression
    var evaluator: ExpressionEvaluator
    public var selfDescription: String { return "Filter \(expression)" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        let i = try child.evaluate()
        let expression = self.expression
        let evaluator = self.evaluator
        let s = i.lazy.filter { (r) -> Bool in
//            evaluator.nextResult()
            do {
                let term = try evaluator.evaluate(expression: expression, result: r)
                let e = try term.ebv()
                return e
            } catch {
                return false
            }
        }
        return AnyIterator(s.makeIterator())
    }
}

public struct DiffPlan: BinaryQueryPlan {
    public var lhs: QueryPlan
    public var rhs: QueryPlan
    var expression: Expression
    var evaluator: ExpressionEvaluator
    public var selfDescription: String { return "Diff \(expression)" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        let i = try lhs.evaluate()
        let r = try Array(rhs.evaluate())
        let evaluator = self.evaluator
        let expression = self.expression
        return AnyIterator {
            repeat {
                guard let result = i.next() else { return nil }
                var ok = true
                for candidate in r {
                    if let j = result.join(candidate) {
                        evaluator.nextResult()
                        if let term = try? evaluator.evaluate(expression: expression, result: j) {
                            if case .some(true) = try? term.ebv() {
                                ok = false
                                break
                            }
                        }
                    }
                }
                
                if ok {
                    return result
                }
            } while true
        }
    }
}

public struct ExtendPlan: UnaryQueryPlan {
    public var child: QueryPlan
    var expression: Expression
    var variable: String
    var evaluator: ExpressionEvaluator
    public var selfDescription: String { return "Extend ?\(variable) ← \(expression)" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        let i = try child.evaluate()
        let expression = self.expression
        let evaluator = self.evaluator
        let variable = self.variable
        let s = i.lazy.map { (r) -> TermResult in
//            evaluator.nextResult()
            do {
                let term = try evaluator.evaluate(expression: expression, result: r)
                return r.extended(variable: variable, value: term) ?? r
            } catch {
                return r
            }
        }
        return AnyIterator(s.makeIterator())
    }
}

public struct NextRowPlan: UnaryQueryPlan {
    public var child: QueryPlan
    var evaluator: ExpressionEvaluator
    public var selfDescription: String { return "Next Row" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        let i = try child.evaluate()
        let evaluator = self.evaluator
        let s = i.lazy.map { (r) -> TermResult in
            evaluator.nextResult()
            return r
        }
        return AnyIterator(s.makeIterator())
    }
}

public struct MinusPlan: BinaryQueryPlan {
    public var lhs: QueryPlan
    public var rhs: QueryPlan
    public var selfDescription: String { return "Minus" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        let l = try lhs.evaluate()
        let r = try Array(rhs.evaluate())
        return AnyIterator {
            while true {
                var candidateOK = true
                guard let candidate = l.next() else { return nil }
                for result in r {
                    let domainIntersection = Set(candidate.keys).intersection(result.keys)
                    let disjoint = (domainIntersection.count == 0)
                    let compatible = !(candidate.join(result) == nil)
                    if !(disjoint || !compatible) {
                        candidateOK = false
                        break
                    }
                }
                if candidateOK {
                    return candidate
                }
            }
        }
    }
}

public struct ProjectPlan: UnaryQueryPlan {
    public var child: QueryPlan
    var variables: Set<String>
    public init(child: QueryPlan, variables: Set<String>) {
        self.child = child
        self.variables = variables
    }
    public var selfDescription: String { return "Project { \(variables) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        let vars = self.variables
        let s = try child.evaluate().lazy.map { $0.projected(variables: vars) }
        return AnyIterator(s.makeIterator())
    }
}

public struct LimitPlan: UnaryQueryPlan {
    public var child: QueryPlan
    var limit: Int
    public var selfDescription: String { return "Limit { \(limit) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        let s = try child.evaluate().prefix(limit)
        return AnyIterator(s.makeIterator())
    }
}

public struct OffsetPlan: UnaryQueryPlan {
    public var child: QueryPlan
    var offset: Int
    public var selfDescription: String { return "Offset { \(offset) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        let s = try child.evaluate().lazy.dropFirst(offset)
        return AnyIterator(s.makeIterator())
    }
}

public struct DistinctPlan: UnaryQueryPlan {
    public var child: QueryPlan
    public var selfDescription: String { return "Distinct" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        var seen = Set<TermResult>()
        let s = try child.evaluate().lazy.filter { (r) -> Bool in
            if seen.contains(r) {
                return false
            } else {
                seen.insert(r)
                return true
            }
        }
        return AnyIterator(s.makeIterator())
    }
}

public struct ServicePlan: NullaryQueryPlan {
    var endpoint: URL
    var query: String
    var silent: Bool
    public var selfDescription: String { return "Service \(silent ? "Silent " : "")<\(endpoint)>: \(query)" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        let client = SPARQLClient(endpoint: endpoint, silent: silent)
        do {
            let r = try client.execute(query)
            switch r {
            case let .bindings(_, seq):
                return AnyIterator(seq.makeIterator())
            default:
                throw QueryError.evaluationError("SERVICE request did not return bindings")
            }
        } catch let e {
            throw QueryError.evaluationError("SERVICE error: \(e)")
        }
    }
}

public struct OrderPlan: UnaryQueryPlan {
    fileprivate struct SortElem {
        var result: TermResult
        var terms: [Term?]
    }
    
    public var child: QueryPlan
    var comparators: [Algebra.SortComparator]
    var evaluator: ExpressionEvaluator
    public var selfDescription: String { return "Order { \(comparators) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        let evaluator = self.evaluator
        let results = try Array(child.evaluate())
        let elements = results.map { (r) -> SortElem in
            let terms = comparators.map { (cmp) in
                try? evaluator.evaluate(expression: cmp.expression, result: r)
            }
            return SortElem(result: r, terms: terms)
        }
        
        let sorted = elements.sorted { (a, b) -> Bool in
            let pairs = zip(a.terms, b.terms)
            for (cmp, pair) in zip(comparators, pairs) {
                guard let lhs = pair.0 else { return true }
                guard let rhs = pair.1 else { return false }
                if lhs == rhs {
                    continue
                }
                var sorted = lhs < rhs
                if !cmp.ascending {
                    sorted = !sorted
                }
                return sorted
            }
            return false
        }
        
        return AnyIterator(sorted.map { $0.result }.makeIterator())
    }
}

private extension Array {
    init<I: IteratorProtocol>(consuming i: inout I, limit: Int? = nil) where I.Element == Element {
        if limit == .some(0) {
            self = []
            return
        }
        var buffer = [I.Element]()
        while let item = i.next() {
            buffer.append(item)
            if let l = limit, buffer.count >= l {
                break
            }
        }
        self = buffer
    }
}
public struct WindowPlan: UnaryQueryPlan {
    // NOTE: WindowPlan assumes the child plan is sorted in the expected order of the window application's partitioning and sort comparators
    public var child: QueryPlan
    var function: Algebra.WindowFunctionMapping
    var evaluator: ExpressionEvaluator
    public var selfDescription: String {
        return "Window \(function.description))"
    }
    
    private func partition<I: IteratorProtocol>(_ results: I, by partition: [Expression]) -> AnyIterator<AnyIterator<TermResult>> where I.Element == TermResult {
        let ee = evaluator
        let seq = AnySequence { return results }
        let withGroups = seq.lazy.map { (r) -> (TermResult, [Term?]) in
            let group = partition.map { try? ee.evaluate(expression: $0, result: r) }
            return (r, group)
        }
        var buffer = [TermResult]()
        var currentGroup = [Term?]()
        var i = withGroups.makeIterator()
        let grouped = AnyIterator { () -> AnyIterator<TermResult>? in
            while true {
                guard let pair = i.next() else {
                    if buffer.isEmpty {
                        return nil
                    } else {
                        let b = buffer
                        buffer = []
                        return AnyIterator(b.makeIterator())
                    }
                }
                let r = pair.0
                let g = pair.1
                if g != currentGroup {
                    currentGroup = g
                    if !buffer.isEmpty {
                        let b = buffer
                        buffer = [r]
                        return AnyIterator(b.makeIterator())
                    }
                }
                buffer.append(r)
            }
        }
        
        return grouped
    }
    
    private func resultsAreEqual(_ a : TermResult, _ b : TermResult, usingComparators comparators: [Algebra.SortComparator]) -> Bool {
        if comparators.isEmpty {
            return a == b
        }
        for cmp in comparators {
            guard var lhs = try? evaluator.evaluate(expression: cmp.expression, result: a) else { return true }
            guard var rhs = try? evaluator.evaluate(expression: cmp.expression, result: b) else { return false }
            if !cmp.ascending {
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
    
    public func evaluate() throws -> AnyIterator<TermResult> {
        let app = function.windowApplication
        let group = app.partition
        let results = try child.evaluate()
        let partitionGroups = partition(results, by: group)
        let v = function.variableName
        
        switch app.windowFunction {
        case .rank:
            // RANK ignores any specified window frame
            let order = app.comparators
            let groups = AnySequence(partitionGroups).lazy.map { (g) -> [TermResult] in
                var rank = 0
                var last: TermResult? = nil
                let groupResults = g.map { (r) -> TermResult in
                    if let last = last {
                        if !self.resultsAreEqual(last, r, usingComparators: order) {
                            rank += 1
                        }
                    } else {
                        rank += 1
                    }
                    last = r
                    let rr = r.extended(variable: v, value: Term(integer: rank)) ?? r
                    return rr
                }
                return groupResults
            }
            let groupsResults = groups.lazy.flatMap { $0 }
            return AnyIterator(groupsResults.makeIterator())
        case .rowNumber:
            // ROW_NUMBER ignores any specified window frame
            let groups = AnySequence(partitionGroups).lazy.map { (g) -> [TermResult] in
                let groupResults = g.lazy.enumerated().map { (i, r) -> TermResult in
                    let rr = r.extended(variable: v, value: Term(integer: i+1)) ?? r
                    return rr
                }
                return groupResults
            }
            let groupsResults = groups.flatMap { $0 }
            return AnyIterator(groupsResults.makeIterator())
        case .aggregation(let agg):
            let frame = app.frame
            let impl = windowAggregation(agg)
            let seq = AnySequence(partitionGroups)
            let groups = try seq.lazy.map { (g) -> [TermResult] in
                let groupResults = try impl.evaluate(
                    g,
                    frame: frame,
                    variableName: v,
                    evaluator: evaluator
                )
                return Array(groupResults)
            }
            let groupsResults = groups.flatMap { $0 }
            return AnyIterator(groupsResults.makeIterator())
        }
        
        /**
         
         For each group:
            * Buffer each TermResult in the group
            * create a sequence that will emit a Sequence<TermResult> with the window value
            * zip the group buffer and the window sequence, produing a joined result sequence
         Return the concatenation of each group's zipped result sequence
         
         **/
    }
    
    struct SlidingWindowImplementation {
        var add: (TermResult) -> ()
        var remove: (TermResult) -> ()
        var value: () -> Term?

        func evaluate<I: IteratorProtocol>(_ group: I, frame: WindowFrame, variableName: String, evaluator: ExpressionEvaluator) throws -> AnyIterator<TermResult> where I.Element == TermResult {
            // This is broken down into several different methods that each implement
            // a different frame bound type (e.g. anything to current row, anything
            // from current row, unbounded/preceding(n) to preceding(m), etc.)
            // It's likely that these could be combined into fewer distinct methods
            // and be implemented more efficiently in the future.
            
            switch (frame.from, frame.to) {
            case (_, .current):
                return try evaluateToCurrent(group, frame: frame, variableName: variableName, evaluator: evaluator)
            case (.current, _):
                return try evaluateFromCurrent(group, frame: frame, variableName: variableName, evaluator: evaluator)
            case (.unbound, .unbound):
                return try evaluateComplete(group, frame: frame, variableName: variableName, evaluator: evaluator)
            case (.unbound, .preceding(let tpe)), (.preceding(_), .preceding(let tpe)):
                return try evaluateToPreceding(group, frame: frame, variableName: variableName, evaluator: evaluator, bound: tpe)
            case (.following(let ffe), .unbound), (.following(let ffe), .following(_)):
                return try evaluateFromFollowing(group, frame: frame, variableName: variableName, evaluator: evaluator, bound: ffe)
            case (.unbound, .following(let tfe)), (.preceding(_), .following(let tfe)):
                return try evaluateToFollowing(group, frame: frame, variableName: variableName, evaluator: evaluator, bound: tfe)
            case (.preceding(let fpe), .unbound):
                return try evaluateFromPrecedingToUnbounded(group, frame: frame, variableName: variableName, evaluator: evaluator, bound: fpe)
            case (_, .preceding(_)), (.following(_), _):
                throw QueryPlanError.invalidExpression
            }
        }
        
        func evaluateComplete<I: IteratorProtocol>(_ group: I, frame: WindowFrame, variableName: String, evaluator: ExpressionEvaluator) throws -> AnyIterator<TermResult> where I.Element == TermResult {
            var group = group
            var buffer = Array(consuming: &group)
            buffer.forEach { self.add($0) }
            let value = self.value()
            
            let i = AnyIterator { () -> TermResult? in
                guard !buffer.isEmpty else { return nil }
                let r = buffer.removeFirst()
                var result = r
                if let v = value {
                    result = result.extended(variable: variableName, value: v) ?? result
                }
                return result
            }
            return i
        }
        
        func evaluateFromFollowing<I: IteratorProtocol>(_ group: I, frame: WindowFrame, variableName: String, evaluator: ExpressionEvaluator, bound toPrecedingExpression: Expression) throws -> AnyIterator<TermResult> where I.Element == TermResult {
            let fflt = try evaluator.evaluate(expression: toPrecedingExpression, result: TermResult(bindings: [:]))
            guard let ffln = fflt.numeric else {
                throw QueryPlanError.nonConstantExpression
            }
            let fromFollowingLimit = Int(ffln.value)
            
            var toFollowingLimit: Int? = nil
            switch frame.to {
            case .following(let expr):
                let t = try evaluator.evaluate(expression: expr, result: TermResult(bindings: [:]))
                guard let n = t.numeric else {
                    throw QueryPlanError.nonConstantExpression
                }
                toFollowingLimit = Int(n.value)
            default:
                break
            }
            
            var group = group
            if let toFollowingLimit = toFollowingLimit {
                // BETWEEN $fromFollowingLimit AND $toFollowingLimit
                let buffer = Array(consuming: &group)
                buffer.prefix(1+toFollowingLimit).forEach { self.add($0) }
                
                var windowEndIndex = buffer.index(buffer.startIndex, offsetBy: toFollowingLimit)
                var window = Array(buffer.prefix(upTo: buffer.index(after: windowEndIndex)))

                for _ in 0..<fromFollowingLimit {
                    guard !window.isEmpty else { break }
                    let rr = window.removeFirst()
                    self.remove(rr)
                }

                let seq = buffer.map { (r) ->TermResult in
                    var result = r
                    if let v = self.value() {
                        result = result.extended(variable: variableName, value: v) ?? result
                    }
                    
                    if !window.isEmpty {
                        let rr = window.removeFirst()
                        self.remove(rr)
                        
                        if windowEndIndex != buffer.endIndex {
                            windowEndIndex = buffer.index(after: windowEndIndex)
                            if windowEndIndex != buffer.endIndex {
                                let r = buffer[windowEndIndex]
                                window.append(r)
                                self.add(r)
                            }
                        }
                    }
                    
                    return result
                }
                return AnyIterator(seq.makeIterator())
            } else {
                // BETWEEN $fromFollowingLimit AND UNBOUNDED
                let buffer = Array(consuming: &group)
                buffer.forEach { self.add($0) }
                
                var window = buffer
                for _ in 0..<fromFollowingLimit {
                    guard !window.isEmpty else { break }
                    let rr = window.removeFirst()
                    self.remove(rr)
                }
                
                let seq = buffer.map { (r) ->TermResult in
                    var result = r
                    if let v = self.value() {
                        result = result.extended(variable: variableName, value: v) ?? result
                    }
                    
                    if !window.isEmpty {
                        self.remove(window.removeFirst())
                    }
                    
                    return result
                }
                return AnyIterator(seq.makeIterator())
            }
        }
        
        func evaluateToPreceding<I: IteratorProtocol>(_ group: I, frame: WindowFrame, variableName: String, evaluator: ExpressionEvaluator, bound toPrecedingExpression: Expression) throws -> AnyIterator<TermResult> where I.Element == TermResult {
            let tplt = try evaluator.evaluate(expression: toPrecedingExpression, result: TermResult(bindings: [:]))
            guard let tpln = tplt.numeric else {
                throw QueryPlanError.nonConstantExpression
            }
            let toPrecedingLimit = Int(tpln.value)
            
            var fromPrecedingLimit: Int? = nil
            switch frame.from {
            case .preceding(let expr):
                let t = try evaluator.evaluate(expression: expr, result: TermResult(bindings: [:]))
                guard let n = t.numeric else {
                    throw QueryPlanError.nonConstantExpression
                }
                fromPrecedingLimit = Int(n.value)
            default:
                break
            }
            
            var group = group
            var buffer = [TermResult]()
            var window = [TermResult]()
            var count = 0
            let i = AnyIterator { () -> TermResult? in
                guard let r = group.next() else { return nil }
                buffer.append(r)
                
                if let fromPrecedingLimit = fromPrecedingLimit {
                    // BETWEEN $fromPrecedingLimit AND $toPrecedingLimit
                    if count > fromPrecedingLimit {
                        let r = window.removeFirst()
                        self.remove(r)
                    }
                } else {
                    // BETWEEN UNBOUNDED AND $toPrecedingLimit
                }
                if buffer.count > toPrecedingLimit {
                    let r = buffer.removeFirst()
                    self.add(r)
                    window.append(r)
                }
                
                var result = r
                if let v = self.value() {
                    result = result.extended(variable: variableName, value: v) ?? result
                }
                count += 1
                return result
            }
            return i
        }
        
        func evaluateFromPrecedingToUnbounded<I: IteratorProtocol>(_ group: I, frame: WindowFrame, variableName: String, evaluator: ExpressionEvaluator, bound fromPrecedingExpression: Expression) throws -> AnyIterator<TermResult> where I.Element == TermResult {
            let fplt = try evaluator.evaluate(expression: fromPrecedingExpression, result: TermResult(bindings: [:]))
            guard let fpln = fplt.numeric else {
                throw QueryPlanError.nonConstantExpression
            }
            let fromPrecedingLimit = Int(fpln.value)
            
            var group = group
            var buffer = Array(consuming: &group)
            var window = buffer
            buffer.forEach { self.add($0) }

            var count = 0
            let i = AnyIterator { () -> TermResult? in
                guard !buffer.isEmpty else { return nil }
                let r = buffer.removeFirst()
                if count > fromPrecedingLimit {
                    let rr = window.removeFirst()
                    self.remove(rr)
                }
                var result = r
                if let v = self.value() {
                    result = result.extended(variable: variableName, value: v) ?? result
                }
                
                count += 1
                return result
            }
            return i
        }
        
        func evaluateToFollowing<I: IteratorProtocol>(_ group: I, frame: WindowFrame, variableName: String, evaluator: ExpressionEvaluator, bound toPrecedingExpression: Expression) throws -> AnyIterator<TermResult> where I.Element == TermResult {
            let tflt = try evaluator.evaluate(expression: toPrecedingExpression, result: TermResult(bindings: [:]))
            guard let tfln = tflt.numeric else {
                throw QueryPlanError.nonConstantExpression
            }
            let toFollowingLimit = Int(tfln.value)
            
            var fromPrecedingLimit: Int? = nil
            switch frame.from {
            case .preceding(let expr):
                let t = try evaluator.evaluate(expression: expr, result: TermResult(bindings: [:]))
                guard let n = t.numeric else {
                    throw QueryPlanError.nonConstantExpression
                }
                fromPrecedingLimit = Int(n.value)
            default:
                break
            }
            
            var group = group
            var buffer = Array(consuming: &group, limit: 1+toFollowingLimit)
            var window = buffer.prefix(1+toFollowingLimit)
            buffer.forEach { self.add($0) }
            var count = 0
            let i = AnyIterator { () -> TermResult? in
                guard !buffer.isEmpty else { return nil }
                let r = buffer.removeFirst()
                if let fromPrecedingLimit = fromPrecedingLimit {
                    // BETWEEN $fromPrecedingLimit AND $toFollowingLimit FOLLOWING
                    if count > fromPrecedingLimit {
                        let rr = window.removeFirst()
                        self.remove(rr)
                    }
                } else {
                    // BETWEEN UNBOUNDED AND $toFollowingLimit FOLLOWING
                }
                var result = r
                if let v = self.value() {
                    result = result.extended(variable: variableName, value: v) ?? result
                }
                
                if let rr = group.next() {
                    window.append(rr)
                    buffer.append(rr)
                    self.add(rr)
                }
                
                count += 1
                return result
            }
            return i
        }
        
        func evaluateToCurrent<I: IteratorProtocol>(_ group: I, frame: WindowFrame, variableName: String, evaluator: ExpressionEvaluator) throws -> AnyIterator<TermResult> where I.Element == TermResult {
            var precedingLimit: Int? = nil
            switch frame.from {
            case .preceding(let expr):
                let t = try evaluator.evaluate(expression: expr, result: TermResult(bindings: [:]))
                guard let n = t.numeric else {
                    throw QueryPlanError.nonConstantExpression
                }
                precedingLimit = Int(n.value)
            default:
                break
            }
            
            var group = group
            if case .unbound = frame.from {
                let i = AnyIterator { () -> TermResult? in
                    guard let r = group.next() else { return nil }
                    self.add(r)
                    var result = r
                    if let v = self.value() {
                        result = result.extended(variable: variableName, value: v) ?? result
                    }
                    return result
                }
                return i
            } else if case .current = frame.from {
                let i = AnyIterator { () -> TermResult? in
                    guard let r = group.next() else { return nil }
                    self.add(r)
                    var result = r
                    if let v = self.value() {
                        result = result.extended(variable: variableName, value: v) ?? result
                    }
                    self.remove(r)
                    return result
                }
                return i
            } else {
                var buffer = [TermResult]()
                let i = AnyIterator { () -> TermResult? in
                    guard let r = group.next() else { return nil }
                    if let l = precedingLimit, !buffer.isEmpty, buffer.count > l {
                        let r = buffer.first!
                        self.remove(r)
                        buffer.removeFirst()
                    }
                    buffer.append(r)
                    self.add(r)
                    var result = r
                    if let v = self.value() {
                        result = result.extended(variable: variableName, value: v) ?? result
                    }
                    return result
                }
                return i
            }
        }
        
        func evaluateFromCurrent<I: IteratorProtocol>(_ group: I, frame: WindowFrame, variableName: String, evaluator: ExpressionEvaluator) throws -> AnyIterator<TermResult> where I.Element == TermResult {
            var followingLimit: Int? = nil
            switch frame.to {
            case .following(let expr):
                let t = try evaluator.evaluate(expression: expr, result: TermResult(bindings: [:]))
                guard let n = t.numeric else {
                    throw QueryPlanError.nonConstantExpression
                }
                followingLimit = Int(n.value)
            default:
                break
            }
            
            var group = group
            if case .unbound = frame.to {
                var buffer = Array(consuming: &group)
                buffer.forEach { self.add($0) }
                
                let i = AnyIterator { () -> TermResult? in
                    guard !buffer.isEmpty else { return nil }
                    let r = buffer.removeFirst()
                    var result = r
                    if let v = self.value() {
                        result = result.extended(variable: variableName, value: v) ?? result
                    }
                    self.remove(r)
                    return result
                }
                return i
            } else if case .current = frame.to {
                let i = AnyIterator { () -> TermResult? in
                    guard let r = group.next() else { return nil }
                    self.add(r)
                    var result = r
                    if let v = self.value() {
                        result = result.extended(variable: variableName, value: v) ?? result
                    }
                    self.remove(r)
                    return result
                }
                return i
            } else {
                var buffer : [TermResult]
                if let limit = followingLimit {
                    buffer = Array(consuming: &group, limit: limit+1)
                } else {
                    buffer = Array(consuming: &group)
                }
                buffer.forEach { self.add($0) }

                let i = AnyIterator { () -> TermResult? in
                    guard !buffer.isEmpty else { return nil }
                    let r = buffer.removeFirst()
                    var result = r
                    if let v = self.value() {
                        result = result.extended(variable: variableName, value: v) ?? result
                    }
                    self.remove(r)
                    if let r = group.next() {
                        buffer.append(r)
                        self.add(r)
                    }
                    return result
                }
                return i
            }
        }
    }
    
    private func windowAggregation(_ agg: Aggregation) -> SlidingWindowImplementation {
        let ee = evaluator
        switch agg {
        case .countAll:
            var value = 0
            return SlidingWindowImplementation(
                add: { (_) in value += 1 },
                remove: { (_) in value -= 1 },
                value: { return Term(integer: value) }
            )
        case let .count(expr, _):
            var value = 0
            return SlidingWindowImplementation(
                add: { (r) in
                    if let _ = try? ee.evaluate(expression: expr, result: r) {
                        value += 1
                    }
                },
                remove: { (r) in
                    if let _ = try? ee.evaluate(expression: expr, result: r) {
                        value -= 1
                    }
                },
                value: { return Term(integer: value) }
            )
        case let .sum(expr, _):
            var intCount = 0
            var fltCount = 0
            var decCount = 0
            var dblCount = 0
            var int = NumericValue.integer(0)
            var flt = NumericValue.float(mantissa: 0, exponent: 0)
            var dec = NumericValue.decimal(Decimal(integerLiteral: 0))
            var dbl = NumericValue.double(mantissa: 0, exponent: 0)
            return SlidingWindowImplementation(
                add: { (r) in
                    if let t = try? ee.evaluate(expression: expr, result: r), let n = t.numeric {
                        switch n {
                        case .integer(_):
                            intCount += 1
                            int += n
                        case .float(_):
                            fltCount += 1
                            flt += n
                        case .decimal(_):
                            decCount += 1
                            dec += n
                        case .double(_):
                            dblCount += 1
                            dbl += n
                        }
                    }
                },
                remove: { (r) in
                    if let t = try? ee.evaluate(expression: expr, result: r), let n = t.numeric {
                        switch n {
                        case .integer(_):
                            intCount -= 1
                            int -= n
                        case .float(_):
                            fltCount -= 1
                            flt -= n
                        case .decimal(_):
                            decCount -= 1
                            dec -= n
                        case .double(_):
                            dblCount -= 1
                            dbl -= n
                        }
                    }
                },
                value: {
                    var value = NumericValue.integer(0)
                    if intCount > 0 { value += int }
                    if fltCount > 0 { value += flt }
                    if decCount > 0 { value += dec }
                    if dblCount > 0 { value += dbl }
                    return value.term
                }
            )
        case let .avg(expr, _):
            var intCount = 0
            var fltCount = 0
            var decCount = 0
            var dblCount = 0
            var int = NumericValue.integer(0)
            var flt = NumericValue.float(mantissa: 0, exponent: 0)
            var dec = NumericValue.decimal(Decimal(integerLiteral: 0))
            var dbl = NumericValue.double(mantissa: 0, exponent: 0)
            return SlidingWindowImplementation(
                add: { (r) in
                    if let t = try? ee.evaluate(expression: expr, result: r), let n = t.numeric {
                        switch n {
                        case .integer(_):
                            intCount += 1
                            int += n
                        case .float(_):
                            fltCount += 1
                            flt += n
                        case .decimal(_):
                            decCount += 1
                            dec += n
                        case .double(_):
                            dblCount += 1
                            dbl += n
                        }
                    }
                },
                remove: { (r) in
                    if let t = try? ee.evaluate(expression: expr, result: r), let n = t.numeric {
                        switch n {
                        case .integer(_):
                            intCount -= 1
                            int -= n
                        case .float(_):
                            fltCount -= 1
                            flt -= n
                        case .decimal(_):
                            decCount -= 1
                            dec -= n
                        case .double(_):
                            dblCount -= 1
                            dbl -= n
                        }
                    }
                },
                value: {
                    var value = NumericValue.integer(0)
                    if intCount > 0 { value += int }
                    if fltCount > 0 { value += flt }
                    if decCount > 0 { value += dec }
                    if dblCount > 0 { value += dbl }
                    let count = NumericValue.integer(intCount + fltCount + decCount + dblCount)
                    return (value / count).term
                }
            )
        case .min(let expr):
            var values = [Term]()
            return SlidingWindowImplementation(
                add: { (r) in
                    if let t = try? ee.evaluate(expression: expr, result: r) {
                        values.append(t)
                    }
                },
                remove: { (r) in
                    if let t = try? ee.evaluate(expression: expr, result: r) {
                        if let i = values.firstIndex(of: t) {
                            precondition(i == 0)
                            values.remove(at: i)
                        }
                    }
                },
                value: { return values.min() }
            )
        case .max(let expr):
            var values = [Term]()
            return SlidingWindowImplementation(
                add: { (r) in
                    if let t = try? ee.evaluate(expression: expr, result: r) {
                        values.append(t)
                    }
                },
                remove: { (r) in
                    if let t = try? ee.evaluate(expression: expr, result: r) {
                        if let i = values.firstIndex(of: t) {
                            precondition(i == 0)
                            values.remove(at: i)
                        }
                    }
                },
                value: { return values.max() }
            )
        case .sample(let expr):
            var value : Term? = nil
            return SlidingWindowImplementation(
                add: { (r) in
                    if let t = try? ee.evaluate(expression: expr, result: r) {
                        value = t
                    }
                },
                remove: { (_) in return },
                value: { return value }
            )
        case let .groupConcat(expr, sep, _):
            var values = [Term?]()
            return SlidingWindowImplementation(
                add: { (r) in
                    let t = try? ee.evaluate(expression: expr, result: r)
                    values.append(t)
                },
                remove: { (_) in
                    values.remove(at: 0)
                },
                value: {
                    let strings = values.compactMap { $0?.value }
                    let j = strings.joined(separator: sep)
                    return Term(string: j)
                    
                }
            )
        }
        
        
    }
    
}

public struct HeapSortLimitPlan: UnaryQueryPlan {
    public var child: QueryPlan
    var comparators: [Algebra.SortComparator]
    var limit: Int
    var evaluator: ExpressionEvaluator
    public var selfDescription: String { return "Heap Sort with Limit \(limit) { \(comparators) }" }

    fileprivate struct SortElem {
        var result: TermResult
        var terms: [Term?]
    }

    private var sortFunction: (SortElem, SortElem) -> Bool {
        let cmps = self.comparators
        return { (a, b) -> Bool in
            let pairs = zip(a.terms, b.terms)
            for (cmp, pair) in zip(cmps, pairs) {
                guard let lhs = pair.0 else { return true }
                guard let rhs = pair.1 else { return false }
                if lhs == rhs {
                    continue
                }
                var sorted = lhs > rhs
                if !cmp.ascending {
                    sorted = !sorted
                }
                return sorted
            }
            return false
        }
    }
    
    public func evaluate() throws -> AnyIterator<TermResult> {
        let i = try child.evaluate()
        var heap = Heap(sort: sortFunction)
        for r in i {
            let terms = comparators.map { (cmp) in
                try? evaluator.evaluate(expression: cmp.expression, result: r)
            }
            let elem = SortElem(result: r, terms: terms)
            heap.insert(elem)
            if heap.count > limit {
                heap.remove()
            }
        }
        
        let rows = heap.sort().map { $0.result }.prefix(limit)
        return AnyIterator(rows.makeIterator())
    }
}

public struct ExistsPlan: UnaryQueryPlan {
    public var child: QueryPlan
    var pattern: QueryPlan
    var variable: String
    var patternAlgebra: Algebra
    public var selfDescription: String {
        let s = SPARQLSerializer(prettyPrint: true)
        do {
            let q = try Query(form: .select(.star), algebra: patternAlgebra)
            let tokens = try q.sparqlTokens()
            let query = s.serialize(tokens)
            return "Exists ?\(variable) ← { \(query.filter { $0 != "\n" }) }"
        } catch {
            return "*** Failed to serialize EXISTS algebra into SPARQL string ***"
        }
    }
    public func evaluate() throws -> AnyIterator<TermResult> {
        let i = try child.evaluate()
        let pattern = self.pattern
        let variable = self.variable
        let s = i.lazy.compactMap { (r) -> TermResult? in
            let columns = r.keys.map { Node.variable($0, binding: true) }
            let row = r.keys.map { r[$0] }
            let table = TablePlan(columns: columns, rows: [row])
            let plan = NestedLoopJoinPlan(lhs: table, rhs: pattern)
            guard let existsIter = try? plan.evaluate() else {
                return nil
            }
            if let _ = existsIter.next() {
                return r.extended(variable: variable, value: Term.trueValue)
            } else {
                return r.extended(variable: variable, value: Term.falseValue)
            }
        }
        return AnyIterator(s.makeIterator())
    }
}

/********************************************************************************************************/
// -
/********************************************************************************************************/

public protocol PathPlan: PlanSerializable {
    var selfDescription: String { get }
    var children : [PathPlan] { get }
    func evaluate(from: Node, to: Node, in: Term) throws -> AnyIterator<TermResult>
}

public struct PathQueryPlan: NullaryQueryPlan {
    var subject: Node
    var path: PathPlan
    var object: Node
    var graph: Term
    public var selfDescription: String { return "Path { \(subject) ---> \(object) in graph \(graph) }" }
    public var properties: [PlanSerializable] { return [path] }
    public func evaluate() throws -> AnyIterator<TermResult> {
        return try path.evaluate(from: subject, to: object, in: graph)
    }
}


public extension PathPlan {
    var arity: Int { return children.count }
    var selfDescription: String {
        return "\(self)"
    }
    
    func serialize(depth: Int=0) -> String {
        let indent = String(repeating: " ", count: (depth*2))
        let name = self.selfDescription
        var d = "\(indent)\(name)\n"
        for c in self.children {
            d += c.serialize(depth: depth+1)
        }
        // TODO: include non-queryplan children (e.g. TablePlan rows)
        return d
    }
    
    internal func alp(term: Term, path: PathPlan, graph: Term) throws -> AnyIterator<Term> {
        var v = Set<Term>()
        try alp(term: term, path: path, seen: &v, graph: graph)
        return AnyIterator(v.makeIterator())
    }
    
    internal func alp(term: Term, path: PathPlan, seen: inout Set<Term>, graph: Term) throws {
        guard !seen.contains(term) else { return }
        seen.insert(term)
        let node : Node = .variable(".pp", binding: true)
        for r in try path.evaluate(from: .bound(term), to: node, in: graph) {
            if let term = r[node] {
                try alp(term: term, path: path, seen: &seen, graph: graph)
            }
        }
    }
}


public struct NPSPathPlan: PathPlan {
    public var iris: [Term]
    var store: QuadStoreProtocol
    public var children: [PathPlan] { return [] }
    public var selfDescription: String { return "NPS { \(iris) }" }
    public func evaluate(from subject: Node, to object: Node, in graph: Term) throws -> AnyIterator<TermResult> {
        switch (subject, object) {
        case let (.bound(_), .variable(oname, binding: bind)):
            let objects = try evaluate(from: subject, in: graph)
            if bind {
                let i = objects.lazy.map {
                    return TermResult(bindings: [oname: $0])
                }
                return AnyIterator(i.makeIterator())
            } else {
                let i = objects.lazy.map { (_) -> TermResult in
                    return TermResult(bindings: [:])
                }
                return AnyIterator(i.makeIterator())
            }
        case (.bound(_), .bound(let o)):
            let objects = try evaluate(from: subject, in: graph)
            let i = objects.lazy.compactMap { (term) -> TermResult? in
                guard term == o else { return nil }
                return TermResult(bindings: [:])
            }
            return AnyIterator(i.makeIterator())
        case (.variable(let s, _), .bound(_)):
            let p : Node = .variable(".p", binding: true)
            let qp = QuadPattern(subject: subject, predicate: p, object: object, graph: .bound(graph))
            let i = try store.quads(matching: qp)
            let set = Set(iris)
            return AnyIterator {
                repeat {
                    guard let q = i.next() else { return nil }
                    let p = q.predicate
                    guard !set.contains(p) else { continue }
                    return TermResult(bindings: [s: q.subject])
                } while true
            }
        case let (.variable(s, _), .variable(o, _)):
            let p : Node = .variable(".p", binding: true)
            let qp = QuadPattern(subject: subject, predicate: p, object: object, graph: .bound(graph))
            let i = try store.quads(matching: qp)
            let set = Set(iris)
            return AnyIterator {
                repeat {
                    guard let q = i.next() else { return nil }
                    let p = q.predicate
                    guard !set.contains(p) else { continue }
                    return TermResult(bindings: [s: q.subject, o: q.object])
                } while true
            }
        }
    }
    
    public func evaluate(from subject: Node, in graph: Term) throws -> AnyIterator<Term> {
        let object = Node.variable(".npso", binding: true)
        let predicate = Node.variable(".npsp", binding: true)
        let quad = QuadPattern(subject: subject, predicate: predicate, object: object, graph: .bound(graph))
        let i = try store.quads(matching: quad)
        // OPTIMIZE: this can be made more efficient by adding an NPS function to the store,
        //           and allowing it to do the filtering based on a IDResult objects before
        //           materializing the terms
        let set = Set(iris)
        return AnyIterator {
            repeat {
                guard let q = i.next() else { return nil }
                let p = q.predicate
                guard !set.contains(p) else { continue }
                return q.object
            } while true
        }
    }
}

public struct LinkPathPlan : PathPlan {
    public var predicate: Term
    var store: QuadStoreProtocol
    public var children: [PathPlan] { return [] }
    public var selfDescription: String { return "Link { \(predicate) }" }
    public func evaluate(from subject: Node, to object: Node, in graph: Term) throws -> AnyIterator<TermResult> {
//        print("eval(linkPath[\(subject) \(predicate) \(object) \(graph)])")
        let qp = QuadPattern(subject: subject, predicate: .bound(predicate), object: object, graph: .bound(graph))
        let r = try store.results(matching: qp)
        return r
    }
    
    public func evaluate(from subject: Node, in graph: Term) throws -> AnyIterator<Term> {
        let object = Node.variable(".lpo", binding: true)
        let qp = QuadPattern(
            subject: subject,
            predicate: .bound(predicate),
            object: object,
            graph: .bound(graph)
        )
//        print("eval(linkPath[from: \(qp)])")
        let plan = QuadPlan(quad: qp, store: store)
        let i = try plan.evaluate().lazy.compactMap {
            return $0[object]
        }
        return AnyIterator(i.makeIterator())
    }
}

public struct UnionPathPlan: PathPlan {
    public var lhs: PathPlan
    public var rhs: PathPlan
    public var children: [PathPlan] { return [lhs, rhs] }
    public var selfDescription: String { return "Alt" }
    public func evaluate(from subject: Node, to object: Node, in graph: Term) throws -> AnyIterator<TermResult> {
        let l = try lhs.evaluate(from: subject, to: object, in: graph)
        let r = try rhs.evaluate(from: subject, to: object, in: graph)
        return AnyIterator(ConcatenatingIterator(l, r))
    }
}

public struct SequencePathPlan: PathPlan {
    public var lhs: PathPlan
    public var joinNode: Node
    public var rhs: PathPlan
    public var children: [PathPlan] { return [lhs, rhs] }
    public var selfDescription: String { return "Seq { \(joinNode) }" }
    
    public func evaluate(from subject: Node, to object: Node, in graph: Term) throws -> AnyIterator<TermResult> {
//        print("eval(sequencePath[\(subject) --> \(object)])")
        guard case .variable(_, _) = joinNode else {
            print("*** invalid child in query plan evaluation")
            throw QueryPlanError.invalidChild
        }
        let l = try lhs.evaluate(from: subject, to: joinNode, in: graph)
        var results = [TermResult]()
        for lr in l {
            if let j = lr[joinNode] {
                let r = try rhs.evaluate(from: .bound(j), to: object, in: graph)
                for rr in r {
                    var result = rr
                    if case .variable(let name, true) = subject, let term = lr[subject] {
                        result = result.extended(variable: name, value: term) ?? result
                    }
                    results.append(result)
                }
            }
        }
        return AnyIterator(results.makeIterator())
    }
}

public struct InversePathPlan: PathPlan {
    public var child: PathPlan
    public var children: [PathPlan] { return [child] }
    public var selfDescription: String { return "Inv" }
    public func evaluate(from subject: Node, to object: Node, in graph: Term) throws -> AnyIterator<TermResult> {
        return try child.evaluate(from: object, to: subject, in: graph)
    }
}

public struct PlusPathPlan : PathPlan {
    public var child: PathPlan
    var store: QuadStoreProtocol
    public var children: [PathPlan] { return [child] }
    public var selfDescription: String { return "Plus" }
    public func evaluate(from subject: Node, to object: Node, in graph: Term) throws -> AnyIterator<TermResult> {
        switch subject {
        case .bound(_):
            var v = Set<Term>()
            let frontierNode : Node = .variable(".pp-plus", binding: true)
            for r in try child.evaluate(from: subject, to: frontierNode, in: graph) {
                if let n = r[frontierNode] {
//                    print("First step of + resulted in term: \(n)")
                    try alp(term: n, path: child, seen: &v, graph: graph)
                }
            }
//            print("ALP resulted in: \(v)")
            
            let i = v.lazy.map { (term) -> TermResult in
                if case .variable(let name, true) = object {
                    return TermResult(bindings: [name: term])
                } else {
                    return TermResult(bindings: [:])
                }
            }
            
            return AnyIterator(i.makeIterator())
        default:
            fatalError()
        }
    }
}

public struct StarPathPlan : PathPlan {
    public var child: PathPlan
    var store: QuadStoreProtocol
    public var children: [PathPlan] { return [child] }
    public var selfDescription: String { return "Plus" }
    public func evaluate(from subject: Node, to object: Node, in graph: Term) throws -> AnyIterator<TermResult> {
        switch subject {
        case .bound(let term):
            var v = Set<Term>()
            try alp(term: term, path: child, seen: &v, graph: graph)
//            print("ALP resulted in: \(v)")
            
            switch object {
            case let .variable(name, binding: true):
                let i = v.lazy.map { TermResult(bindings: [name: $0]) }
                return AnyIterator(i.makeIterator())
            case .variable(_, binding: false):
                let i = v.lazy.map { (_) in TermResult(bindings: [:]) }.prefix(1)
                return AnyIterator(i.makeIterator())
            case .bound(let o):
                let i = v.lazy.compactMap { (term) -> TermResult? in
                    guard term == o else { return nil }
                    return TermResult(bindings: [:])
                }
                return AnyIterator(i.prefix(1).makeIterator())
            }
        case .variable(let s, binding: _):
            switch object {
            case .variable(_):
                var iterators = [AnyIterator<TermResult>]()
                for gn in store.graphTerms(in: graph) {
                    let results = try evaluate(from: .bound(gn), to: object, in: graph).lazy.compactMap { (r) -> TermResult? in
                        r.extended(variable: s, value: gn)
                    }
                    iterators.append(AnyIterator(results.makeIterator()))
                }
                return AnyIterator { () -> TermResult? in
                    repeat {
                        guard let i = iterators.first else { return nil }
                        if let r = i.next() {
                            return r
                        } else {
                            iterators.removeFirst(1)
                        }
                    } while true
                }
            case .bound(_):
                fatalError("unimplemented: ?var :starpath* <bound>") // TODO: implement
            }
        }
    }
}
public struct ZeroOrOnePathPlan : PathPlan {
    public var child: PathPlan
    var store: QuadStoreProtocol
    public var children: [PathPlan] { return [child] }
    public var selfDescription: String { return "ZeroOrOne" }
    public func evaluate(from subject: Node, to object: Node, in graph: Term) throws -> AnyIterator<TermResult> {
        let i = try child.evaluate(from: subject, to: object, in: graph)
        switch (subject, object) {
        case (.variable(let s, _), .variable(_)):
            let gn = store.graphTerms(in: graph)
            let results = try gn.lazy.map { (term) -> AnyIterator<TermResult> in
                let i = try child.evaluate(from: .bound(term), to: object, in: graph)
                let j = i.lazy.map { (r) -> TermResult in
                    r.extended(variable: s, value: term) ?? r
                }
                return AnyIterator(j.makeIterator())
            }
            return AnyIterator(results.joined().makeIterator())
        case (.bound(_), .bound(_)):
            if subject == object {
                let r = [TermResult(bindings: [:])]
                return AnyIterator(r.makeIterator())
            } else {
                return i
            }
        case let (.bound(term), .variable(name, _)), let (.variable(name, _), .bound(term)):
            let r = [TermResult(bindings: [name: term])]
            var seen = Set<Term>()
            let j = i.lazy.compactMap { (r) -> TermResult? in
                guard let t = r[name] else { return nil }
                guard t != term else { return nil }
                guard !seen.contains(t) else { return nil }
                seen.insert(t)
                return r
            }
            return AnyIterator(ConcatenatingIterator(r.makeIterator(), j.makeIterator()))
        }
    }
}

/********************************************************************************************************/

protocol Aggregate {
    func handle(_ row: TermResult)
    func result() -> Term?
}

public struct AggregationPlan: UnaryQueryPlan {
    private class CountAllAggregate: Aggregate {
        var count: Int
        init() {
            self.count = 0
        }
        func handle(_ row: TermResult) {
            count += 1
        }
        func result() -> Term? {
            return Term(integer: count)
        }
    }
    
    private class MinimumAggregate: Aggregate {
        var value: Term?
        var expression: Expression
        var ee: ExpressionEvaluator
        init(expression: Expression, evaluator: ExpressionEvaluator) {
            self.expression = expression
            self.value = nil
            self.ee = evaluator
        }
        func handle(_ row: TermResult) {
            let term = try? ee.evaluate(expression: expression, result: row)
            if let t = value {
                if let term = term, term < t {
                    value = term
                }
            } else {
                value = term
            }
        }
        func result() -> Term? {
            return value
        }
    }
    
    private class MaximumAggregate: Aggregate {
        var value: Term?
        var expression: Expression
        var ee: ExpressionEvaluator
        init(expression: Expression, evaluator: ExpressionEvaluator) {
            self.expression = expression
            self.value = nil
            self.ee = evaluator
        }
        func handle(_ row: TermResult) {
            let term = try? ee.evaluate(expression: expression, result: row)
            if let t = value {
                if let term = term, term > t {
                    value = term
                }
            } else {
                value = term
            }
        }
        func result() -> Term? {
            return value
        }
    }
    
    private class AverageAggregate: Aggregate {
        var error: Bool
        var value: NumericValue
        var count: Int
        var expression: Expression
        var ee: ExpressionEvaluator
        init(expression: Expression, evaluator: ExpressionEvaluator) {
            self.error = false
            self.expression = expression
            self.value = .integer(0)
            self.count = 0
            self.ee = evaluator
        }
        func handle(_ row: TermResult) {
            if let term = try? ee.evaluate(expression: expression, result: row) {
                if let n = term.numeric {
                    value = value + n
                    count += 1
                } else {
                    error = true
                }
            }
        }
        func result() -> Term? {
            guard !error else { return nil }
            let avg = value / .integer(count)
            return avg.term
        }
    }
    
    private class AverageDistinctAggregate: Aggregate {
        var error: Bool
        var values: Set<NumericValue>
        var expression: Expression
        var ee: ExpressionEvaluator
        init(expression: Expression, evaluator: ExpressionEvaluator) {
            self.error = false
            self.expression = expression
            self.values = Set()
            self.ee = evaluator
        }
        func handle(_ row: TermResult) {
            if let term = try? ee.evaluate(expression: expression, result: row) {
                if let n = term.numeric {
                    values.insert(n)
                } else {
                    error = true
                }
            }
        }
        func result() -> Term? {
            guard !error else { return nil }
            let value = values.reduce(NumericValue.integer(0)) { $0 + $1 }
            let avg = value / .integer(values.count)
            return avg.term
        }
    }
    
    private class SumAggregate: Aggregate {
        var error: Bool
        var value: NumericValue
        var expression: Expression
        var ee: ExpressionEvaluator
        init(expression: Expression, evaluator: ExpressionEvaluator) {
            self.error = false
            self.expression = expression
            self.value = .integer(0)
            self.ee = evaluator
        }
        func handle(_ row: TermResult) {
            if let term = try? ee.evaluate(expression: expression, result: row) {
                if let n = term.numeric {
                    value = value + n
                } else {
                    error = true
                }
            }
        }
        func result() -> Term? {
            guard !error else { return nil }
            return value.term
        }
    }
    
    private class SumDistinctAggregate: Aggregate {
        var error: Bool
        var values: Set<NumericValue>
        var expression: Expression
        var ee: ExpressionEvaluator
        init(expression: Expression, evaluator: ExpressionEvaluator) {
            self.error = false
            self.expression = expression
            self.values = Set()
            self.ee = evaluator
        }
        func handle(_ row: TermResult) {
            if let term = try? ee.evaluate(expression: expression, result: row) {
                if let n = term.numeric {
                    values.insert(n)
                } else {
                    error = true
                }
            }
        }
        func result() -> Term? {
            guard !error else { return nil }
            let value = values.reduce(NumericValue.integer(0)) { $0 + $1 }
            return value.term
        }
    }
    
    private class CountAggregate: Aggregate {
        var count: Int
        var expression: Expression
        var ee: ExpressionEvaluator
        init(expression: Expression, evaluator: ExpressionEvaluator) {
            self.expression = expression
            self.count = 0
            self.ee = evaluator
        }
        func handle(_ row: TermResult) {
            if let _ = try? ee.evaluate(expression: expression, result: row) {
                count += 1
            }
        }
        func result() -> Term? {
            return Term(integer: count)
        }
    }
    
    private class CountDistinctAggregate: Aggregate {
        var values: Set<Term>
        var expression: Expression
        var ee: ExpressionEvaluator
        init(expression: Expression, evaluator: ExpressionEvaluator) {
            self.expression = expression
            self.values = Set()
            self.ee = evaluator
        }
        func handle(_ row: TermResult) {
            if let term = try? ee.evaluate(expression: expression, result: row) {
                values.insert(term)
            }
        }
        func result() -> Term? {
            print("COUNT DISTINCT has these values: \(values)")
            return Term(integer: values.count)
        }
    }
    
    private class SampleAggregate: Aggregate {
        var value: Term?
        var expression: Expression
        var ee: ExpressionEvaluator
        init(expression: Expression, evaluator: ExpressionEvaluator) {
            self.expression = expression
            self.value = nil
            self.ee = evaluator
        }
        func handle(_ row: TermResult) {
            if let term = try? ee.evaluate(expression: expression, result: row) {
                value = term
            }
        }
        func result() -> Term? {
            return value
        }
    }

    private class GroupConcatDistinctAggregate: Aggregate {
        var values: Set<Term>
        var separator: String
        var expression: Expression
        var ee: ExpressionEvaluator
        init(expression: Expression, separator: String, evaluator: ExpressionEvaluator) {
            self.expression = expression
            self.separator = separator
            self.values = Set()
            self.ee = evaluator
        }
        func handle(_ row: TermResult) {
            if let term = try? ee.evaluate(expression: expression, result: row) {
                values.insert(term)
            }
        }
        func result() -> Term? {
            let s = values.sorted().map { $0.value }.joined(separator: separator)
            return Term(string: s)
        }
    }

    private class GroupConcatAggregate: Aggregate {
        var value: String
        var separator: String
        var expression: Expression
        var ee: ExpressionEvaluator
        init(expression: Expression, separator: String, evaluator: ExpressionEvaluator) {
            self.expression = expression
            self.separator = separator
            self.value = ""
            self.ee = evaluator
        }
        func handle(_ row: TermResult) {
            if let term = try? ee.evaluate(expression: expression, result: row) {
                if !value.isEmpty {
                    value += separator
                }
                value += term.value
            }
        }
        func result() -> Term? {
            return Term(string: value)
        }
    }

    public var child: QueryPlan
    var groups: [Expression]
    var aggregates: [String: () -> (Aggregate)]
    var ee: ExpressionEvaluator
    public init(child: QueryPlan, groups: [Expression], aggregates: Set<Algebra.AggregationMapping>) {
        self.child = child
        self.groups = groups
        self.aggregates = [:]
        let ee = ExpressionEvaluator(base: nil)
        self.ee = ee

        for a in aggregates {
            switch a.aggregation {
            case .countAll:
                self.aggregates[a.variableName] = { return CountAllAggregate() }
            case let .count(e, true):
                self.aggregates[a.variableName] = { return CountDistinctAggregate(expression: e, evaluator: ee) }
            case let .count(e, false):
                self.aggregates[a.variableName] = { return CountAggregate(expression: e, evaluator: ee) }
            case .min(let e):
                self.aggregates[a.variableName] = { return MinimumAggregate(expression: e, evaluator: ee) }
            case .max(let e):
                self.aggregates[a.variableName] = { return MaximumAggregate(expression: e, evaluator: ee) }
            case .sample(let e):
                self.aggregates[a.variableName] = { return SampleAggregate(expression: e, evaluator: ee) }
            case let .groupConcat(e, sep, true):
                self.aggregates[a.variableName] = { return GroupConcatDistinctAggregate(expression: e, separator: sep, evaluator: ee) }
            case let .groupConcat(e, sep, false):
                self.aggregates[a.variableName] = { return GroupConcatAggregate(expression: e, separator: sep, evaluator: ee) }
            case let .avg(e, false):
                self.aggregates[a.variableName] = { return AverageAggregate(expression: e, evaluator: ee) }
            case let .avg(e, true):
                self.aggregates[a.variableName] = { return AverageDistinctAggregate(expression: e, evaluator: ee) }
            case let .sum(e, true):
                self.aggregates[a.variableName] = { return SumDistinctAggregate(expression: e, evaluator: ee) }
            case let .sum(e, false):
                self.aggregates[a.variableName] = { return SumAggregate(expression: e, evaluator: ee) }
            }
        }
    }
    
    public var selfDescription: String { return "Aggregate \(aggregates) over groups \(groups)" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        var aggData = [[Term?]:[String:Aggregate]]()
        for r in try child.evaluate() {
            let group = groups.map { try? ee.evaluate(expression: $0, result: r) }
            if let _ = aggData[group] {
            } else {
                // instantiate all aggregates for this group
                aggData[group] = Dictionary(uniqueKeysWithValues: aggregates.map { ($0.key, $0.value()) })
            }
            
            aggData[group]!.forEach { (_, agg) in
                agg.handle(r)
            }
        }
        
        guard aggData.count > 0 else {
            let d = aggregates.compactMap { (name, a) -> (String, Term)? in
                let agg = a()
                guard let term = agg.result() else { return nil }
                return (name, term)
            }
            let r = TermResult(bindings: Dictionary(uniqueKeysWithValues: d))
            return AnyIterator([r].makeIterator())
        }
        
        let rows = aggData.map { (group, aggs) -> TermResult in
            var groupTerms = [String:Term]()
            for (e, t) in zip(groups, group) {
                if case .node(.variable(let name, _)) = e {
                    if let term = t {
                        groupTerms[name] = term
                    }
                }
            }
            let d = Dictionary(uniqueKeysWithValues: aggs.compactMap { (a) -> (String, Term)? in
                guard let term = a.value.result() else {
                    return nil
                }
                return (a.key, term)
            })
            let result = groupTerms.merging(d) { (l, r) in l }
            return TermResult(bindings: result)
        }
        return AnyIterator(rows.makeIterator())
    }
}
