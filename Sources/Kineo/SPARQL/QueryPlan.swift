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
}

public protocol QueryPlan {
    var selfDescription: String { get }
    var children : [QueryPlan] { get }
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
        let r = try lhs.evaluate()
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
        let r = try lhs.evaluate()
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
            evaluator.nextResult()
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
            evaluator.nextResult()
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

protocol PathPlan {}
extension PathPlan {
    func alp(term: Term, path: QueryPlan, seen: inout Set<Term>, graph: Term, pathVariable pvar: Node) throws {
        guard !seen.contains(term) else { return }
        seen.insert(term)
        for result in try path.evaluate() {
            if let n = result[pvar] {
                try alp(term: n, path: path, seen: &seen, graph: graph, pathVariable: pvar)
            }
        }
    }
}

public struct NPSPathPlan: NullaryQueryPlan, PathPlan {
    var iris: [Term]
    var subject: Node
    var predicate: Node
    var object: Node
    var graph: Term
    var store: QuadStoreProtocol
    public var selfDescription: String { return "NPS Path { \(subject) \(iris) \(object) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        let predicate = self.predicate
        let quad = QuadPattern(subject: subject, predicate: predicate, object: object, graph: .bound(graph))
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
}

public struct FullyBoundPlusPathPlan: UnaryQueryPlan, PathPlan {
    public var child: QueryPlan
    var subject: Node
    var object: Node
    var graph: Term
    public var selfDescription: String { return "Plus Path { \(subject) + \(object) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        fatalError("unimplemented") // TODO: implement
    }
}

public struct PartiallyBoundPlusPathPlan: UnaryQueryPlan, PathPlan {
    public var child: QueryPlan
    var subject: Node
    var object: Node
    var graph: Term
    var objectVariable: String
    public var selfDescription: String { return "Plus Path { \(subject) + \(object) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        fatalError("unimplemented") // TODO: implement
    }
}

public struct UnboundPlusPathPlan: UnaryQueryPlan, PathPlan {
    public var child: QueryPlan
    var subject: Node
    var object: Node
    var graph: Term
    var subjectVariable: String
    var objectVariable: String
    public var selfDescription: String { return "Plus Path { \(subject) + \(object) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        fatalError("unimplemented") // TODO: implement
    }
}

public struct FullyBoundStarPathPlan: UnaryQueryPlan, PathPlan {
    public var child: QueryPlan
    var subject: Node
    var object: Node
    var graph: Term
    public var selfDescription: String { return "Star Path { \(subject) * \(object) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        fatalError("unimplemented") // TODO: implement
    }
}

public struct PartiallyBoundStarPathPlan: UnaryQueryPlan, PathPlan {
    public var child: QueryPlan
    var subject: Node
    var object: Node
    var graph: Term
    var objectVariable: String
    public var selfDescription: String { return "Star Path { \(subject) * \(object) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        fatalError("unimplemented") // TODO: implement
    }
}

public struct UnboundStarPathPlan: UnaryQueryPlan, PathPlan {
    public var child: QueryPlan
    var subject: Node
    var object: Node
    var graph: Term
    var subjectVariable: String
    var objectVariable: String
    public var selfDescription: String { return "Star Path { \(subject) * \(object) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        fatalError("unimplemented") // TODO: implement
    }
}

public struct FullyBoundZeroOrOnePathPlan: UnaryQueryPlan, PathPlan {
    public var child: QueryPlan
    var subject: Node
    var object: Node
    var graph: Term
    public var selfDescription: String { return "ZeroOrOne Path { \(subject) ? \(object) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        fatalError("unimplemented") // TODO: implement
    }
}

public struct PartiallyBoundZeroOrOnePathPlan: UnaryQueryPlan, PathPlan {
    public var child: QueryPlan
    var subject: Node
    var object: Node
    var graph: Term
    var objectVariable: String
    public var selfDescription: String { return "ZeroOrOne Path { \(subject) ? \(object) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        fatalError("unimplemented") // TODO: implement
    }
}

public struct UnboundZeroOrOnePathPlan: UnaryQueryPlan, PathPlan {
    public var child: QueryPlan
    var subject: Node
    var object: Node
    var graph: Term
    var subjectVariable: String
    var objectVariable: String
    public var selfDescription: String { return "ZeroOrOne Path { \(subject) ? \(object) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        fatalError("unimplemented") // TODO: implement
    }
}

public struct AggregationPlan: UnaryQueryPlan {
    public var child: QueryPlan
    var groups: [Expression]
    var aggregates: Set<Algebra.AggregationMapping>
    public var selfDescription: String { return "Aggregate \(aggregates) over groups \(groups)" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        fatalError("unimplemented") // TODO: implement
    }
}

public struct WindowPlan: UnaryQueryPlan {
    public var child: QueryPlan
    var groups: [Expression]
    var functions: Set<Algebra.WindowFunctionMapping>
    public var selfDescription: String { return "Window \(functions) over groups \(groups)" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        fatalError("unimplemented") // TODO: implement
    }
}

public struct HeapSortLimitPlan: UnaryQueryPlan {
    public var child: QueryPlan
    var comparators: [Algebra.SortComparator]
    var limit: Int
    public var selfDescription: String { return "Heap Sort with Limit \(limit) { \(comparators) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        fatalError("unimplemented") // TODO: implement
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
