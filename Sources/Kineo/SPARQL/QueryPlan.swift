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
    case unimplemented
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
        let i = try store.results(matching: quad)
        let a = Array(i)
        return AnyIterator(a.makeIterator())
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
    public func evaluate() throws -> AnyIterator<TermResult> {
        let l = try lhs.evaluate()
        let r = try rhs.evaluate()
        let i = AnyIterator {
            return l.next() ?? r.next()
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

public struct AggregationPlan: UnaryQueryPlan {
    public var child: QueryPlan
    var groups: [Expression]
    var aggregates: Set<Algebra.AggregationMapping>
    public var selfDescription: String { return "Aggregate \(aggregates) over groups \(groups)" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        print("unimplemented")
        throw QueryPlanError.unimplemented // TODO: implement
    }
}

public struct WindowPlan: UnaryQueryPlan {
    public var child: QueryPlan
    var groups: [Expression]
    var functions: Set<Algebra.WindowFunctionMapping>
    public var selfDescription: String { return "Window \(functions) over groups \(groups)" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        print("unimplemented")
        throw QueryPlanError.unimplemented // TODO: implement
    }
}

public struct HeapSortLimitPlan: UnaryQueryPlan {
    public var child: QueryPlan
    var comparators: [Algebra.SortComparator]
    var limit: Int
    public var selfDescription: String { return "Heap Sort with Limit \(limit) { \(comparators) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        print("unimplemented")
        throw QueryPlanError.unimplemented // TODO: implement
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

public protocol PathPlan: QueryPlan {
    var selfDescription: String { get }
    var children : [QueryPlan] { get }
    func evaluate(from: Node, in: Term) throws -> AnyIterator<Term>
    var subject: Node { get }
    var object: Node { get }
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
        for n in try path.evaluate(from: .bound(term), in: graph) {
            try alp(term: n, path: path, seen: &seen, graph: graph)
        }
    }
}


public struct NPSPathPlan: NullaryQueryPlan, PathPlan {
    public var subject: Node
    public var iris: [Term]
    public var object: Node
    public var graph: Term
    var store: QuadStoreProtocol
    public var selfDescription: String { return "NPS Path { { \(subject) --\(iris)--> \(object) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        switch (subject, object) {
        case (.bound(_), .variable(let oname, binding: true)):
            let objects = try evaluate(from: subject, in: graph)
            let i = objects.lazy.map {
                return TermResult(bindings: [oname: $0])
            }
            return AnyIterator(i.makeIterator())
        default:
            fatalError()
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

public struct LinkPathPlan : NullaryQueryPlan, PathPlan {
    public var subject: Node
    public var predicate: Term
    public var object: Node
    public var graph: Term
    var store: QuadStoreProtocol
    public var selfDescription: String { return "Link Path { \(subject) --\(predicate)--> \(object) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
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
    public var subject: Node
    public var lhs: PathPlan
    public var rhs: PathPlan
    public var object: Node
    public var children: [QueryPlan] { return [lhs, rhs] }
    public var selfDescription: String { return "Union { \(subject) --> \(object) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
//        print("eval(unionPath[\(subject) --> \(object)])")
        let qp = UnionPlan(lhs: lhs, rhs: rhs)
        return try qp.evaluate()
    }
    
    public func evaluate(from subject: Node, in graph: Term) throws -> AnyIterator<Term> {
//        print("eval(unionPath[from: \(subject) --> \(self.object)])")
        let li = try lhs.evaluate(from: subject, in: graph)
        let ri = try rhs.evaluate(from: subject, in: graph)
        return AnyIterator {
            return li.next() ?? ri.next()
        }
    }
}

public struct SequencePathPlan: PathPlan {
    public var subject: Node
    public var lhs: PathPlan
    public var joinNode: Node
    public var rhs: PathPlan
    public var object: Node
    public var children: [QueryPlan] { return [lhs, rhs] }
    public var selfDescription: String { return "Sequence { \(subject) --> \(object) }" }
    
    public func evaluate() throws -> AnyIterator<TermResult> {
//        print("eval(sequencePath[\(subject) --> \(object)])")
        guard case .variable(let joinVariable, _) = lhs.object else {
            throw QueryPlanError.invalidChild
        }
        let qp = HashJoinPlan(lhs: lhs, rhs: rhs, joinVariables: [joinVariable])
        return try qp.evaluate()
    }
    
    public func evaluate(from subject: Node, in graph: Term) throws -> AnyIterator<Term> {
//        print("eval(sequencePath[from: \(subject) --> \(self.object)])")
        let lhs = self.lhs
        let rhs = self.rhs
        return AnyIterator { () -> Term? in
            do {
                for lo in try lhs.evaluate(from: subject, in: graph) {
                    for ro in try rhs.evaluate(from: .bound(lo), in: graph) {
                        return ro
                    }
                }
            } catch { print("*** caught error during SequencePathPlan evaluation") }
            return nil
        }
    }
}

public struct PlusPathPlan : PathPlan {
    public var subject: Node
    public var child: PathPlan
    public var object: Node
    public var graph: Term
    var store: QuadStoreProtocol
    var frontierNode: Node
    public var children: [QueryPlan] { return [child] }
    public var selfDescription: String { return "Plus { \(subject) --> \(object) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
//        print("eval(plusPath[\(subject) --> \(object) \(graph)])")
        let objects = try evaluate(from: subject, in: graph)
        switch object {
        case .variable(let name, true):
            let i = objects.lazy.map { TermResult(bindings: [name: $0]) }
            return AnyIterator(i.makeIterator())
        default:
            fatalError()
        }
    }
    
    public func evaluate(from subject: Node, in graph: Term) throws -> AnyIterator<Term> {
//        print("eval(plusPath[from: \(subject) --> \(self.object)])")
        switch subject {
        case .bound(_):
            var v = Set<Term>()
            for r in try child.evaluate() {
                guard let n = r[frontierNode] else {
                    fatalError()
                }
                print("First step of + resulted in term: \(n)")
                try alp(term: n, path: child, seen: &v, graph: graph)
            }
            print("ALP resulted in: \(v)")

            return AnyIterator(v.makeIterator())
//        case (.variable(_), .bound(_)):
//            fatalError()
////            let ipath: PropertyPath = .plus(.inv(pp))
////            return try evaluatePath(subject: object, object: subject, graph: graph, path: ipath)
//        case (.bound(_), .bound(let oterm)):
//            var v = Set<Term>()
//            for result in try child.evaluate() {
//                if let n = result[innerObject] {
//                    try alp(term: n, path: child, seen: &v, graph: graph, objectVariable: innerObject)
//                }
//            }
//
//            var results = [TermResult]()
//            if v.contains(oterm) {
//                results.append(TermResult(bindings: [:]))
//            }
//            return AnyIterator(results.makeIterator())
//        case (.variable(let sname, binding: _), .variable(_)):
//            var results = [TermResult]()
//            for t in store.graphTerms(in: graph) {
//                let pp = PlusPathPlan(
//                    child: child,
//                    subject: .bound(t),
//                    innerSubject: innerSubject,
//                    innerObject: innerObject,
//                    object: object,
//                    graph: graph,
//                    store: store
//                )
//                let i = try pp.evaluate()
//                let j = i.map {
//                    $0.extended(variable: sname, value: t) ?? $0
//                }
//                results.append(contentsOf: j)
//            }
//            return AnyIterator(results.makeIterator())
        default:
            fatalError()
        }
    }
}


