//
//  Plan.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 9/22/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import SPARQLSyntax

public typealias IDType = UInt64
public typealias IDListResult = [IDType]

public typealias TermResultComparator = (TermResult, TermResult) -> Bool
public typealias IDListResultComparator = (IDListResult, IDListResult) -> Bool

public indirect enum TermGroupPlan {
    case group(ResultPlan, [String])
}

public enum IDNode {
    case bound(IDType)
    case variable(Int)
}

public indirect enum IDListPlan {
    case quad(IDNode, IDNode, IDNode, IDNode)
    case hashJoin(IDListPlan, IDListPlan)
    case graphNames(Int)
}

public indirect enum ResultPlan {
    public typealias SortComparator = (Bool, Expression)
    case idListPlan(IDListPlan, [String])
    case nestedLoopJoin(ResultPlan, ResultPlan)
    case merge(ResultPlan, ResultPlan, TermResultComparator)
    case table([TermResult])
    case hashJoin(ResultPlan, ResultPlan)
    case leftOuterJoin(ResultPlan, ResultPlan, Expression)
    case filter(ResultPlan, Expression)
    case union(ResultPlan, ResultPlan)
    case namedGraph(ResultPlan, String)
    case extend(ResultPlan, Expression, String)
    case exists(ResultPlan, ResultPlan, String)
    case minus(ResultPlan, ResultPlan)
    case project(ResultPlan, Set<String>)
    case unique(ResultPlan)
    case hashDistinct(ResultPlan)
    case service(URL, String, Bool)
    case heapsort(ResultPlan, [SortComparator], Int)
    case slice(ResultPlan, Int, Int)
    case limit(ResultPlan, Int)
    case offset(ResultPlan, Int)
    case order(ResultPlan, [SortComparator])
    case path(Node, PropertyPath, Node)
    case aggregate(ResultPlan, [Expression], [(Aggregation, String)])
    case window(ResultPlan, [Expression], [(WindowFunction, [SortComparator], String)])
}

extension IDListPlan {
    public func serialize(depth: Int=0) -> String {
        let indent = String(repeating: " ", count: (depth*2))
        var s = ""
        switch self {
        case .quad(let subj, let p, let o, let g):
            s += "\(indent)Quad(\(subj), \(p), \(o), \(g)\n"
        case .hashJoin(let lhs, let rhs):
            s += "\(indent)Hash Join:\n"
            s += lhs.serialize(depth: depth+1)
            s += rhs.serialize(depth: depth+1)
        case .graphNames(let v):
            s += "\(indent)$\(v) <- Graph Names\n"
        }
        return s
    }
}

extension ResultPlan {
    public func serialize(depth: Int=0) -> String {
        let indent = String(repeating: " ", count: (depth*2))
        var s = ""
        switch self {
        case .idListPlan(let p, let vars):
            s += "\(indent)ID Plan (variables: \(vars)):\n"
            s += p.serialize(depth: depth+1)
        case .hashJoin(let lhs, let rhs):
            s += "\(indent)Hash Join:\n"
            s += lhs.serialize(depth: depth+1)
            s += rhs.serialize(depth: depth+1)
        default:
            break
        }
        return s
    }
}

public class ResultPlanEvaluator {
    var store: MediatedPageQuadStore
    var ide: IDPlanEvaluator
    public init(store: MediatedPageQuadStore) {
        self.ide = IDPlanEvaluator(store: store)
        self.store = store
    }

    public func evaluate(_ plan: ResultPlan) throws -> AnyIterator<TermResult> {
        switch plan {
        case .idListPlan(let idplan, let variables):
            let i = try ide.evaluate(idplan, width: variables.count)
            let idmap = store.id
            return AnyIterator {
                guard let list = i.next() else { return nil }
                var b = [String:Term]()
                for (i, v) in variables.enumerated() {
                    let id = list[i]
                    if let term = idmap.term(for: id) {
                        b[v] = term
                    }
                }
                return TermResult(bindings: b)
            }
        default:
            throw QueryPlanError.unexpectedError("Cannot evaluate ResultPlan \(plan)")
        }
    }
}

public class IDPlanEvaluator {
    var store: MediatedPageQuadStore
    public init(store: MediatedPageQuadStore) {
        self.store = store
    }

    public func evaluate(_ plan: IDListPlan, width: Int) throws -> AnyIterator<IDListResult> {
        switch plan {
        case .graphNames(let pos):
            let ids = store.graphIDs()
            let results = ids.map { (id) -> IDListResult in
                var r: [IDType] = Array(repeating: 0, count: width)
                r[pos] = id
                return r
            }
            return AnyIterator(results.makeIterator())
        case .quad(let s, let p, let o, let g):
            var ids = [IDType]()
            var pos = [Int:Int]()
            for (j, n) in [s, p, o, g].enumerated() {
                switch n {
                case .bound(let i):
                    ids.append(i)
                case .variable(let i):
                    ids.append(0)
                    pos[i] = j
                }
            }
            let idquads = try store.idquads(matching: ids)
            return AnyIterator {
                guard let idq = idquads.next() else { return nil }
                var r: [IDType] = Array(repeating: 0, count: width)
                for (i, id) in idq.enumerated() {
                    if let j = pos[i] {
                        r[j] = id
                    }
                }
                return r
            }
        default:
            throw QueryPlanError.unimplemented("\(plan)")
        }
    }
}

public class PageQuadStorePlanner {
    var store: MediatedPageQuadStore
    var defaultGraph: Term
    var variables: [String]
    var variableNumbers: [String:Int]

    public init(store: MediatedPageQuadStore, defaultGraph: Term) {
        self.store = store
        self.defaultGraph = defaultGraph
        variables = []
        variableNumbers = [:]
    }

    public func plan(_ query: Query) throws -> ResultPlan {
        let algebra = query.algebra
        let plan = try self.plan(algebra)
        return plan
    }
    
    public func plan(_ algebra: Algebra) throws -> ResultPlan {
        return try plan(algebra, activeGraph: defaultGraph)
    }

    private func variableNumber(_ name: String) -> Int {
        if let n = variableNumbers[name] {
            return n
        } else {
            let n = variables.count
            variables.append(name)
            variableNumbers[name] = n
            return n
        }
    }

    private func plan(_ algebra: Algebra, activeGraph: Term) throws -> ResultPlan {
        switch algebra {
        case .triple(let t):
            var idnodes = [IDNode]()
            let nodes = [t.subject, t.predicate, t.object, .bound(activeGraph)]
            for n in nodes {
                switch n {
                case .bound(let t):
                    guard let id = store.id.id(for: t) else {
                        throw QueryPlanError.unexpectedError("Failed to retrieve ID for RDF Term during query planning")
                    }
                    idnodes.append(.bound(id))
                case .variable(let name, binding: _):
                    idnodes.append(.variable(self.variableNumber(name)))
                }
            }
            let idplan: IDListPlan = .quad(idnodes[0], idnodes[1], idnodes[2], idnodes[3])
            return .idListPlan(idplan, self.variables)
        case .quad(let q):
            var idnodes = [IDNode]()
            let nodes = [q.subject, q.predicate, q.object, q.graph]
            for n in nodes {
                switch n {
                case .bound(let t):
                    guard let id = store.id.id(for: t) else {
                        throw QueryPlanError.unexpectedError("Failed to retrieve ID for RDF Term during query planning")
                    }
                    idnodes.append(.bound(id))
                case .variable(let name, binding: _):
                    idnodes.append(.variable(self.variableNumber(name)))
                }
            }
            let idplan: IDListPlan = .quad(idnodes[0], idnodes[1], idnodes[2], idnodes[3])
            return .idListPlan(idplan, self.variables)
        case .innerJoin(let lhs, let rhs):
            let l = try plan(lhs, activeGraph: activeGraph)
            let r = try plan(rhs, activeGraph: activeGraph)
            switch (l, r) {
            case (.idListPlan(let li, let lv), .idListPlan(let ri, let rv)) where lv == rv:
                return .idListPlan(.hashJoin(li, ri), self.variables)
            default:
                return .hashJoin(l, r)
            }
        default:
            throw QueryPlanError.unexpectedError("Cannot plan algebra:\n\(algebra.serialize())")
        }
    }
}
