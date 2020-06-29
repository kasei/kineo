//
//  IDQueryPlan.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 6/6/20.
//

import Foundation
import SPARQLSyntax

public struct IDQuadPlan: NullaryIDQueryPlan {
    var pattern: IDQuad
    var store: LazyMaterializingQuadStore
    var repeatedVariables: [String : Set<Int>]
    public var selfDescription: String { return "IDQuad(\(pattern))" }
    
    public init(pattern: IDQuad, repeatedVariables: [String : Set<Int>], store: LazyMaterializingQuadStore) {
        self.pattern = pattern
        self.store = store
        self.repeatedVariables = repeatedVariables
    }
    
    func idResults(matching pattern: IDQuad) throws -> AnyIterator<SPARQLResultSolution<IDType>> {
        let dupCheck = { (qids: [UInt64]) -> Bool in
            for (_, positions) in self.repeatedVariables {
                let values = positions.map { qids[$0] }.sorted()
                if let f = values.first, let l = values.last {
                    if f != l {
                        return false
                    }
                }
            }
            return true
        }

        var bindings : [String: Int] = [:]
        for (i, node) in pattern.enumerated() {
            if case IDNode.variable(let name, binding: _) = node {
                bindings[name] = i
            }
        }
        // TODO: get quads matching the *ID* pattern, not a term pattern
        let idpattern = pattern.map { (node) -> UInt64 in
            switch node {
            case .variable:
                return 0
            case .bound(let tid):
                return tid
            }
        }
        var quads = try store.quadIds(matchingIDs: idpattern)
        if !repeatedVariables.isEmpty {
            quads = AnyIterator(quads.filter(dupCheck).makeIterator())
        }
        
        let results = quads.lazy.map { (q) -> SPARQLResultSolution<UInt64> in
            var b = [String: UInt64]()
            for (name, pos) in bindings {
                b[name] = q[pos]
            }
            return SPARQLResultSolution(bindings: b)
        }
        return AnyIterator(results.makeIterator())
    }

    public func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        return try self.idResults(matching: self.pattern)
    }
    
    public var isJoinIdentity: Bool { return false }
    public var isUnionIdentity: Bool { return false }
}

public struct IDIndexBindQuadPlan: UnaryIDQueryPlan { // for each LHS result, replace variables in the RHS and probe the quadstore for matching results
    public var child: IDQueryPlan
    public var pattern: IDQuad
    var bindings: [String: WritableKeyPath<IDQuad, IDNode>]
    var store: LazyMaterializingQuadStore
    var repeatedVariables: [String : Set<Int>]
    public var selfDescription: String { return "IDIndexBindQuadPlan(\(pattern))" }
    
    public init(child: IDQueryPlan, pattern: IDQuad, bindings: [String: WritableKeyPath<IDQuad, IDNode>], repeatedVariables: [String : Set<Int>], store: LazyMaterializingQuadStore) {
        self.child = child
        self.pattern = pattern
        self.bindings = bindings
        self.store = store
        self.repeatedVariables = repeatedVariables
    }
    
    func idResults(matching pattern: IDQuad) throws -> AnyIterator<SPARQLResultSolution<IDType>> {
        let dupCheck = { (qids: [UInt64]) -> Bool in
            for (_, positions) in self.repeatedVariables {
                let values = positions.map { qids[$0] }.sorted()
                if let f = values.first, let l = values.last {
                    if f != l {
                        return false
                    }
                }
            }
            return true
        }

        var bindings : [String: Int] = [:]
        for (i, node) in pattern.enumerated() {
            if case IDNode.variable(let name, binding: _) = node {
                bindings[name] = i
            }
        }
        // TODO: get quads matching the *ID* pattern, not a term pattern
        let idpattern = pattern.map { (node) -> UInt64 in
            switch node {
            case .variable:
                return 0
            case .bound(let tid):
                return tid
            }
        }
        var quads = try store.quadIds(matchingIDs: idpattern)
        if !repeatedVariables.isEmpty {
            quads = AnyIterator(quads.filter(dupCheck).makeIterator())
        }
        
        let results = quads.lazy.map { (q) -> SPARQLResultSolution<UInt64> in
            var b = [String: UInt64]()
            for (name, pos) in bindings {
                b[name] = q[pos]
            }
            return SPARQLResultSolution(bindings: b)
        }
        return AnyIterator(results.makeIterator())
    }

    public func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        let i = try self.child.evaluate()
        var buffer = [SPARQLResultSolution<UInt64>]()
        return AnyIterator {
            repeat {
                if !buffer.isEmpty {
                    return buffer.removeFirst()
                }
                guard let lhs = i.next() else { return nil }
                var pattern = self.pattern
                for (name, path) in self.bindings {
                    if let tid = lhs[name] {
                        pattern[keyPath: path] = .bound(tid)
                    }
                }
                guard let j = try? self.idResults(matching: pattern) else { continue }
                for rhs in j {
                    if let j = lhs.join(rhs) {
                        buffer.append(j)
                    }
                }
            } while true
        }
    }
    
    public var isJoinIdentity: Bool { return false }
    public var isUnionIdentity: Bool { return false }
}

public struct IDOrderedQuadPlan: NullaryIDQueryPlan {
    var quad: QuadPattern
    var order: [Quad.Position]
    var store: LazyMaterializingQuadStore
    public var selfDescription: String {
        let orderNames : [String] = order.map {
            switch $0 {
            case .subject:
                return "s"
            case .predicate:
                return "p"
            case .object:
                return "o"
            case .graph:
                return "g"
            }
        }
        let ordering = orderNames.joined(separator: "")
        return "OrderedIDQuad(\(quad)) [using index \(ordering)]"
    }
    public func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        return try store.idresults(matching: quad, orderedBy: order)
    }
    public var isJoinIdentity: Bool { return false }
    public var isUnionIdentity: Bool { return false }
}

public struct IDNestedLoopJoinPlan: BinaryIDQueryPlan {
    public var lhs: IDQueryPlan
    public var rhs: IDQueryPlan
    public var children : [IDQueryPlan] { return [lhs, rhs] }
    public var isJoinIdentity: Bool { return false }
    public var isUnionIdentity: Bool { return false }
    public var selfDescription: String { return "ID Nested Loop Join" }
    public func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        let l = try Array(lhs.evaluate())
        let r = try rhs.evaluate()
        var results = [SPARQLResultSolution<UInt64>]()
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

public struct IDNestedLoopLeftJoinPlan: BinaryIDQueryPlan {
    public var lhs: IDQueryPlan
    public var rhs: IDQueryPlan
    public var children : [IDQueryPlan] { return [lhs, rhs] }
    public var isJoinIdentity: Bool { return false }
    public var isUnionIdentity: Bool { return false }
    public var selfDescription: String { return "ID Nested Loop Left Join" }
    public func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        let r = try Array(rhs.evaluate())
        let l = try rhs.evaluate()
        var results = [SPARQLResultSolution<UInt64>]()
        for lresult in l {
            var seen = false
            for rresult in r {
                if let j = lresult.join(rresult) {
                    seen = true
                    results.append(j)
                }
            }
            if !seen {
                results.append(lresult)
            }
        }
        return AnyIterator(results.makeIterator())
    }
}

public struct IDHashJoinPlan: BinaryIDQueryPlan {
    public var lhs: IDQueryPlan
    public var rhs: IDQueryPlan
    var joinVariables: Set<String>
    public var selfDescription: String { return "ID Hash-Join { \(joinVariables) }" }
    public func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        let joinVariables = self.joinVariables
        let l = try lhs.evaluate()
        let r = try rhs.evaluate()
        return hashJoin(l, r, joinVariables: joinVariables)
    }
}

public struct IDMergeJoinPlan: BinaryIDQueryPlan {
    public var lhs: IDQueryPlan
    public var rhs: IDQueryPlan
    public var variables: [String]
    public var selfDescription: String { return "ID Merge-Join { \(variables) }" }
    public func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        let l = try lhs.evaluate()
        let r = try rhs.evaluate()
        return mergeJoin(l, r, variables: self.variables)
    }
}

public struct IDHashLeftJoinPlan: BinaryIDQueryPlan {
    public var lhs: IDQueryPlan
    public var rhs: IDQueryPlan
    var joinVariables: Set<String>
    public var selfDescription: String { return "ID Hash Left-Join { \(joinVariables) }" }
    public func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        let joinVariables = self.joinVariables
        let l = try lhs.evaluate()
        let r = try rhs.evaluate()
        return hashJoin(l, r, joinVariables: joinVariables, type: .outer)
    }
}

public struct IDHashAntiJoinPlan: BinaryIDQueryPlan {
    public var lhs: IDQueryPlan
    public var rhs: IDQueryPlan
    var joinVariables: Set<String>
    public var selfDescription: String { return "ID Hash Anti-Join { \(joinVariables) }" }
    public func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        let joinVariables = self.joinVariables
        let l = try lhs.evaluate()
        let r = try rhs.evaluate()
        return hashJoin(l, r, joinVariables: joinVariables, type: .anti)
    }
}

public struct IDDiffPlan: BinaryIDQueryPlan {
    public var lhs: IDQueryPlan
    public var rhs: IDQueryPlan
    public var selfDescription: String { return "ID Diff" }
    public func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        let i = try lhs.evaluate()
        let r = try Array(rhs.evaluate())
        return AnyIterator {
            repeat {
                guard let result = i.next() else { return nil }
                var ok = true
                for candidate in r {
                    if let _ = result.join(candidate) {
                        ok = false
                    }
                }
                
                if ok {
                    return result
                }
            } while true
        }
    }
}


public struct IDUnionPlan: BinaryIDQueryPlan {
    public var lhs: IDQueryPlan
    public var rhs: IDQueryPlan
    public var selfDescription: String { return "ID Union" }
    public init(lhs: IDQueryPlan, rhs: IDQueryPlan) {
        self.lhs = lhs
        self.rhs = rhs
    }
    public func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        let l = try lhs.evaluate()
        let r = try rhs.evaluate()
        var lok = true
        let i = AnyIterator { () -> SPARQLResultSolution<UInt64>? in
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

public struct IDMinusPlan: BinaryIDQueryPlan {
    public var lhs: IDQueryPlan
    public var rhs: IDQueryPlan
    public var selfDescription: String { return "ID Minus" }
    public func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        let l = try lhs.evaluate()
        let r = try Array(rhs.evaluate())
        return AnyIterator {
            while true {
                var candidateOK = true
                guard let candidate = l.next() else { return nil }
                let candidateKeys = Set(candidate.keys)
                for result in r {
                    let domainIntersection = candidateKeys.intersection(result.keys)
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

public struct IDProjectPlan: UnaryIDQueryPlan {
    public var child: IDQueryPlan
    var variables: Set<String>
    public init(child: IDQueryPlan, variables: Set<String>) {
        self.child = child
        self.variables = variables
    }
    public var selfDescription: String { return "ID Project { \(variables.sorted().joined(separator: ", ")) }" }
    public func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        let vars = self.variables
        let s = try child.evaluate().lazy.map { $0.projected(variables: vars) }
        return AnyIterator(s.makeIterator())
    }
}

public struct IDLimitPlan: UnaryIDQueryPlan {
    public var child: IDQueryPlan
    var limit: Int
    public var selfDescription: String { return "ID Limit { \(limit) }" }
    public func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        let s = try child.evaluate().prefix(limit)
        return AnyIterator(s.makeIterator())
    }
}

public struct IDOffsetPlan: UnaryIDQueryPlan {
    public var child: IDQueryPlan
    var offset: Int
    public var selfDescription: String { return "ID Offset { \(offset) }" }
    public func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        let s = try child.evaluate().lazy.dropFirst(offset)
        return AnyIterator(s.makeIterator())
    }
}

public struct IDReducedPlan: UnaryIDQueryPlan {
    public var child: IDQueryPlan
    public var selfDescription: String { return "ID Distinct" }
    public func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        var last: SPARQLResultSolution<UInt64>? = nil
        let s = try child.evaluate().lazy.compactMap { (r) -> SPARQLResultSolution<UInt64>? in
            if let l = last, l == r {
                return nil
            }
            last = r
            return r
        }
        return AnyIterator(s.makeIterator())
    }
}

public struct IDSortPlan: UnaryIDQueryPlan {
    fileprivate struct SortElem {
        var result: SPARQLResultSolution<UInt64>
        var sortIDs: [UInt64]
    }
    
    public var child: IDQueryPlan
    var orderVariables: [String]
    public var selfDescription: String { return "ID Sort { \(orderVariables) }" }
    public func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        let results = try Array(child.evaluate())
        let elements = results.map { (r) -> SortElem in
            let ids = orderVariables.map { (name) in
                return r[name] ?? 0
            }
            return SortElem(result: r, sortIDs: ids)
        }
        
        let sorted = elements.sorted { (a, b) -> Bool in
            let pairs = zip(a.sortIDs, b.sortIDs)
            for (_, pair) in zip(orderVariables, pairs) {
                let lhs = pair.0
                let rhs = pair.1
                
                guard lhs != 0 else { return true }
                guard rhs != 0 else { return false }
                
                if lhs == rhs {
                    continue
                }
                let sorted = lhs < rhs
                return sorted
            }
            return false
        }
        
        return AnyIterator(sorted.map { $0.result }.makeIterator())
    }
}

public struct IDUniquePlan: UnaryIDQueryPlan {
    public var child: IDQueryPlan
    public var selfDescription: String { return "ID Unique" }
    public func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        let results = try child.evaluate()
        var last : SPARQLResultSolution<UInt64>? = nil
        return AnyIterator {
            repeat {
                guard let r = results.next() else { return nil }
                if let l = last {
                    if l == r {
                        continue
                    } else {
                        last = r
                        return r
                    }
                } else {
                    last = r
                    return r
                }
            } while true
        }
    }
}


/******************************************************************************************/

public enum IDNode: Hashable {
    case bound(UInt64)
    case variable(String, binding: Bool)
    public var isVariable: Bool {
        switch self {
        case .variable:
            return true
        default:
            return false
        }
    }
}

extension IDNode: CustomStringConvertible {
    public var description: String {
        switch self {
        case .variable(let name, binding: true):
            return "?\(name)"
        case .variable(let name, binding: false):
            return "_:\(name)"
        case .bound(let tid):
            return "#\(tid)"
        }
    }
}
extension SPARQLResultSolution where T == UInt64 {
    subscript(_ key: IDNode) -> UInt64? {
        switch key {
        case .bound(let v):
            return v
        case .variable(let name, _):
            return self.bindings[name]
        }
    }
}

public struct IDQuad: Hashable, Equatable, CustomStringConvertible, Sequence {
    public var subject: IDNode
    public var predicate: IDNode
    public var object: IDNode
    public var graph: IDNode

    public init(ids: [UInt64]) {
        let convert: (String, UInt64) -> IDNode = { (name, v) in
            if v == 0 {
                return .variable(name, binding: true)
            } else {
                return .bound(v)
            }
            
        }
        self.subject = convert("s", ids[0])
        self.predicate = convert("p", ids[1])
        self.object = convert("o", ids[2])
        self.graph = convert("g", ids[3])
    }
    
    public init(subject: IDNode, predicate: IDNode, object: IDNode, graph: IDNode) {
        self.subject = subject
        self.predicate = predicate
        self.object = object
        self.graph = graph
    }
    public var description: String {
        return "\(subject) \(predicate) \(object) \(graph)."
    }
    
    public func makeIterator() -> AnyIterator<IDNode> {
        return AnyIterator([subject, predicate, object, graph].makeIterator())
    }
    
    public var ids: [UInt64] {
        return self.map { (node) -> UInt64 in
            switch node {
            case .bound(let tid):
                return tid
            case .variable:
                return 0
            }
        }
    }
}

public protocol IDPathPlan: IDPlanSerializable {
    var selfDescription: String { get }
    var children : [IDPathPlan] { get }
    func evaluate(from: IDNode, to: IDNode, in: UInt64) throws -> AnyIterator<SPARQLResultSolution<UInt64>>
}

public struct IDPathQueryPlan: NullaryIDQueryPlan {
    var subject: IDNode
    var path: IDPathPlan
    var object: IDNode
    var graph: UInt64
    public var selfDescription: String { return "ID Path { \(subject) ---> \(object) in graph \(graph) }" }
    public var properties: [IDPlanSerializable] { return [path] }
    public var isJoinIdentity: Bool { return false }
    public var isUnionIdentity: Bool { return false }

    public func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        return try path.evaluate(from: subject, to: object, in: graph)
    }
}

public extension IDPathPlan {
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
    
    internal func alp(term: UInt64, path: IDPathPlan, graph: UInt64) throws -> AnyIterator<UInt64> {
        var v = Set<UInt64>()
        try alp(term: term, path: path, seen: &v, graph: graph)
        return AnyIterator(v.makeIterator())
    }
    
    internal func alp(term: UInt64, path: IDPathPlan, seen: inout Set<UInt64>, graph: UInt64) throws {
        guard !seen.contains(term) else { return }
        seen.insert(term)
        let node : IDNode = .variable(".pp", binding: true)
        for r in try path.evaluate(from: .bound(term), to: node, in: graph) {
            if let term = r[node] {
                try alp(term: term, path: path, seen: &seen, graph: graph)
            }
        }
    }
}


public struct IDNPSPathPlan: IDPathPlan {
    public var iris: [UInt64]
    var store: LazyMaterializingQuadStore
    public var children: [IDPathPlan] { return [] }
    public var selfDescription: String { return "ID NPS { \(iris) }" }
    public func evaluate(from subject: IDNode, to object: IDNode, in graph: UInt64) throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        switch (subject, object) {
        case let (.bound(_), .variable(oname, binding: bind)):
            let objects = try evaluate(from: subject, in: graph)
            if bind {
                let i = objects.lazy.map {
                    return SPARQLResultSolution<UInt64>(bindings: [oname: $0])
                }
                return AnyIterator(i.makeIterator())
            } else {
                let i = objects.lazy.map { (_) -> SPARQLResultSolution<UInt64> in
                    return SPARQLResultSolution<UInt64>(bindings: [:])
                }
                return AnyIterator(i.makeIterator())
            }
        case (.bound(_), .bound(let o)):
            let objects = try evaluate(from: subject, in: graph)
            let i = objects.lazy.compactMap { (term) -> SPARQLResultSolution<UInt64>? in
                guard term == o else { return nil }
                return SPARQLResultSolution<UInt64>(bindings: [:])
            }
            return AnyIterator(i.makeIterator())
        case (.variable(let s, _), .bound(_)):
            let p : IDNode = .variable(".p", binding: true)
            let qp = IDQuad(subject: subject, predicate: p, object: object, graph: .bound(graph))
            let i = try store.quadIds(matchingIDs: qp.ids).makeIterator()
            let set = Set(iris)
            return AnyIterator {
                repeat {
                    guard let q = i.next() else { return nil }
                    let subject = q[0]
                    let predicate = q[1]
                    if !set.contains(predicate) { continue }
                    return SPARQLResultSolution(bindings: [s: subject])
                } while true
            }
        case let (.variable(s, _), .variable(o, _)):
            let p : IDNode = .variable(".p", binding: true)
            let qp = IDQuad(subject: subject, predicate: p, object: object, graph: .bound(graph))
            let i = try store.quadIds(matchingIDs: qp.ids).makeIterator()
            let set = Set(iris)
            return AnyIterator {
                repeat {
                    guard let q = i.next() else { return nil }
                    let subject = q[0]
                    let predicate = q[1]
                    let object = q[2]
                    guard !set.contains(predicate) else { continue }
                    return SPARQLResultSolution(bindings: [s: subject, o: object])
                } while true
            }
        }
    }
    
    public func evaluate(from subject: IDNode, in graph: UInt64) throws -> AnyIterator<UInt64> {
        let object = IDNode.variable(".npso", binding: true)
        let predicate = IDNode.variable(".npsp", binding: true)
        let quad = IDQuad(subject: subject, predicate: predicate, object: object, graph: .bound(graph))
        let i = try store.quadIds(matchingIDs: quad.ids).makeIterator()
        // OPTIMIZE: this can be made more efficient by adding an NPS function to the store,
        //           and allowing it to do the filtering based on a SPARQLResultSolution<UInt64> objects before
        //           materializing the terms
        let set = Set(iris)
        return AnyIterator {
            repeat {
                guard let q = i.next() else { return nil }
                let predicate = q[1]
                let object = q[2]
                guard !set.contains(predicate) else { continue }
                return object
            } while true
        }
    }
}

public struct IDLinkPathPlan : IDPathPlan {
    public var predicate: UInt64
    var store: LazyMaterializingQuadStore
    public var children: [IDPathPlan] { return [] }
    public var selfDescription: String { return "Link { \(predicate) }" }
    public func evaluate(from subject: IDNode, to object: IDNode, in graph: UInt64) throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
//        print("eval(linkPath[\(subject) \(predicate) \(object) \(graph)])")
        let qp = IDQuad(subject: subject, predicate: .bound(predicate), object: object, graph: .bound(graph))
        let plan = IDQuadPlan(pattern: qp, repeatedVariables: [:], store: store)
        return try plan.evaluate()
    }
    
    public func evaluate(from subject: IDNode, in graph: UInt64) throws -> AnyIterator<UInt64> {
        let object = IDNode.variable(".lpo", binding: true)
        let qp = IDQuad(
            subject: subject,
            predicate: .bound(predicate),
            object: object,
            graph: .bound(graph)
        )
//        print("eval(linkPath[from: \(qp)])")

        let plan = IDQuadPlan(pattern: qp, repeatedVariables: [:], store: store)
        let i = try plan.evaluate().lazy.compactMap {
            return $0[object]
        }
        return AnyIterator(i.makeIterator())
    }
}

public struct IDUnionPathPlan: IDPathPlan {
    public var lhs: IDPathPlan
    public var rhs: IDPathPlan
    public var children: [IDPathPlan] { return [lhs, rhs] }
    public var selfDescription: String { return "Alt" }
    public func evaluate(from subject: IDNode, to object: IDNode, in graph: UInt64) throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        let l = try lhs.evaluate(from: subject, to: object, in: graph)
        let r = try rhs.evaluate(from: subject, to: object, in: graph)
        return AnyIterator(ConcatenatingIterator(l, r))
    }
}

public struct IDSequencePathPlan: IDPathPlan {
    public var lhs: IDPathPlan
    public var joinNode: IDNode
    public var rhs: IDPathPlan
    public var children: [IDPathPlan] { return [lhs, rhs] }
    public var selfDescription: String { return "Seq { \(joinNode) }" }
    
    public func evaluate(from subject: IDNode, to object: IDNode, in graph: UInt64) throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
//        print("eval(sequencePath[\(subject) --> \(object)])")
        guard case .variable(_, _) = joinNode else {
            print("*** invalid child in query plan evaluation")
            throw QueryPlanError.invalidChild
        }
        let l = try lhs.evaluate(from: subject, to: joinNode, in: graph)
        var results = [SPARQLResultSolution<UInt64>]()
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

public struct IDInversePathPlan: IDPathPlan {
    public var child: IDPathPlan
    public var children: [IDPathPlan] { return [child] }
    public var selfDescription: String { return "Inv" }
    public func evaluate(from subject: IDNode, to object: IDNode, in graph: UInt64) throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        return try child.evaluate(from: object, to: subject, in: graph)
    }
}

public struct IDPlusPathPlan : IDPathPlan {
    public var child: IDPathPlan
    var store: LazyMaterializingQuadStore
    public var children: [IDPathPlan] { return [child] }
    public var selfDescription: String { return "Plus" }
    public func evaluate(from subject: IDNode, to object: IDNode, in graph: UInt64) throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        switch subject {
        case .bound:
            var v = Set<UInt64>()
            let frontierNode : IDNode = .variable(".pp-plus", binding: true)
            for r in try child.evaluate(from: subject, to: frontierNode, in: graph) {
                if let n = r[frontierNode] {
//                    print("First step of + resulted in term: \(n)")
                    try alp(term: n, path: child, seen: &v, graph: graph)
                }
            }
//            print("ALP resulted in: \(v)")
            
            let i = v.lazy.map { (term) -> SPARQLResultSolution<UInt64> in
                if case .variable(let name, true) = object {
                    return SPARQLResultSolution<UInt64>(bindings: [name: term])
                } else {
                    return SPARQLResultSolution<UInt64>(bindings: [:])
                }
            }
            
            return AnyIterator(i.makeIterator())
        case .variable(let s, binding: _):
            switch object {
            case .variable:
                var iterators = [AnyIterator<SPARQLResultSolution<UInt64>>]()
                for gn in store.graphTermIDs(in: graph) {
                    let results = try evaluate(from: .bound(gn), to: object, in: graph).lazy.compactMap { (r) -> SPARQLResultSolution<UInt64>? in
                        r.extended(variable: s, value: gn)
                    }
                    iterators.append(AnyIterator(results.makeIterator()))
                }
                return AnyIterator { () -> SPARQLResultSolution<UInt64>? in
                    repeat {
                        guard let i = iterators.first else { return nil }
                        if let r = i.next() {
                            return r
                        } else {
                            iterators.removeFirst(1)
                        }
                    } while true
                }
            case .bound:
                // ?subject path+ <bound>
                let ipath = IDPlusPathPlan(child: IDInversePathPlan(child: child), store: store)
                return try ipath.evaluate(from: object, to: subject, in: graph)
            }
        }
    }
}

public struct IDStarPathPlan : IDPathPlan {
    public var child: IDPathPlan
    var store: LazyMaterializingQuadStore
    public var children: [IDPathPlan] { return [child] }
    public var selfDescription: String { return "Plus" }
    public func evaluate(from subject: IDNode, to object: IDNode, in graph: UInt64) throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        switch subject {
        case .bound(let term):
            var v = Set<UInt64>()
            try alp(term: term, path: child, seen: &v, graph: graph)
//            print("ALP resulted in: \(v)")
            
            switch object {
            case let .variable(name, binding: true):
                let i = v.lazy.map { SPARQLResultSolution<UInt64>(bindings: [name: $0]) }
                return AnyIterator(i.makeIterator())
            case .variable(_, binding: false):
                let i = v.lazy.map { (_) in SPARQLResultSolution<UInt64>(bindings: [:]) }.prefix(1)
                return AnyIterator(i.makeIterator())
            case .bound(let o):
                let i = v.lazy.compactMap { (term) -> SPARQLResultSolution<UInt64>? in
                    guard term == o else { return nil }
                    return SPARQLResultSolution<UInt64>(bindings: [:])
                }
                return AnyIterator(i.prefix(1).makeIterator())
            }
        case .variable(let s, binding: _):
            switch object {
            case .variable:
                var iterators = [AnyIterator<SPARQLResultSolution<UInt64>>]()
                for gn in store.graphTermIDs(in: graph) {
                    let results = try evaluate(from: .bound(gn), to: object, in: graph).lazy.compactMap { (r) -> SPARQLResultSolution<UInt64>? in
                        r.extended(variable: s, value: gn)
                    }
                    iterators.append(AnyIterator(results.makeIterator()))
                }
                return AnyIterator { () -> SPARQLResultSolution<UInt64>? in
                    repeat {
                        guard let i = iterators.first else { return nil }
                        if let r = i.next() {
                            return r
                        } else {
                            iterators.removeFirst(1)
                        }
                    } while true
                }
            case .bound:
                let ipath = IDStarPathPlan(child: IDInversePathPlan(child: child), store: store)
                return try ipath.evaluate(from: object, to: subject, in: graph)
            }
        }
    }
}
public struct IDZeroOrOnePathPlan : IDPathPlan {
    public var child: IDPathPlan
    var store: LazyMaterializingQuadStore
    public var children: [IDPathPlan] { return [child] }
    public var selfDescription: String { return "ZeroOrOne" }
    public func evaluate(from subject: IDNode, to object: IDNode, in graph: UInt64) throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        let i = try child.evaluate(from: subject, to: object, in: graph)
        switch (subject, object) {
        case (.variable(let s, _), .variable):
            let gn = store.graphTermIDs(in: graph)
            let results = try gn.lazy.map { (term) -> AnyIterator<SPARQLResultSolution<UInt64>> in
                let i = try child.evaluate(from: .bound(term), to: object, in: graph)
                let j = i.lazy.map { (r) -> SPARQLResultSolution<UInt64> in
                    r.extended(variable: s, value: term) ?? r
                }
                return AnyIterator(j.makeIterator())
            }
            return AnyIterator(results.joined().makeIterator())
        case (.bound, .bound):
            if subject == object {
                let r = [SPARQLResultSolution<UInt64>(bindings: [:])]
                return AnyIterator(r.makeIterator())
            } else {
                return i
            }
        case let (.bound(term), .variable(name, _)), let (.variable(name, _), .bound(term)):
            let r = [SPARQLResultSolution<UInt64>(bindings: [name: term])]
            var seen = Set<UInt64>()
            let j = i.lazy.compactMap { (r) -> SPARQLResultSolution<UInt64>? in
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

