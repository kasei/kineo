//
//  Plan.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 9/22/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation

public typealias IDType = UInt64
public typealias IDListResult = [IDType]
public typealias Variable = String
public typealias IRI = String

public typealias TermResultComparator = (TermResult, TermResult) -> Bool
public typealias IDListResultComparator = (IDListResult, IDListResult) -> Bool

public indirect enum TermGroupPlan {
    case group(ResultPlan, [Variable])
}

public enum IDNode {
    case bound(IDType)
    case variable(Int)
}

public indirect enum IDExpression {
    case node(IDNode)
    case sameterm(IDExpression, IDExpression)
    case and(IDExpression, IDExpression)
    case or(IDExpression, IDExpression)
    case isiri(IDExpression)
    case isblank(IDExpression)
    case isliteral(IDExpression)
    case isnumeric(IDExpression)
    case bound(IDExpression)
}

public indirect enum IDListPlan {
    case quad(IDNode, IDNode, IDNode, IDNode)
//    case nestedLoopJoin(IDListPlan, IDListPlan)
    case hashJoin(IDListPlan, IDListPlan)
//    case ebvFilter(IDListPlan, IDExpression)
//    case merge(IDListPlan, IDListPlan, IDListResultComparator)
//    case union(IDListPlan, IDListPlan)
//    case extend(IDListPlan, IDExpression, Int)
//    case hashDistinct(IDListPlan)
//    case unique(IDListPlan)
//    case slice(IDListPlan, Int, Int)
//    case project(IDListPlan, Set<Int>)
//    case orderBy(IDListPlan, [(IDListResultComparator, Bool)])
//    case table([IDListResult])
//    case graphNodes(IDType, Int)
    case graphNames(Int)
//    case aggregate(TermGroupPlan, [(Aggregation, Int)])
//    case window(TermGroupPlan, [(WindowFunction, Int, [(IDExpression, Bool)])])
}

public indirect enum ResultPlan {
    case idListPlan(IDListPlan, [Variable])
//    case quad(QuadPattern)
//    case nestedLoopJoin(ResultPlan, ResultPlan)
    case hashJoin(ResultPlan, ResultPlan)
//    case ebvFilter(ResultPlan, Expression)
//    case merge(ResultPlan, ResultPlan, TermResultComparator)
//    case union(ResultPlan, ResultPlan)
//    case extend(ResultPlan, Expression, Variable)
//    case hashDistinct(ResultPlan)
//    case unique(ResultPlan)
//    case slice(ResultPlan, Int, Int)
//    case project(ResultPlan, Set<String>)
//    case orderBy(ResultPlan, [(TermResultComparator, Bool)])
//    case service(IRI, String)
//    case table([TermResult])
//    case graphNodes(Node, Variable)
//    case graphNames(Variable)
//    case aggregate(TermGroupPlan, [(Aggregation, Variable)])
//    case window(TermGroupPlan, [(WindowFunction, Variable, [(Expression, Bool)])])
}

public class ResultPlanEvaluator {
    var store: QuadStore
    var ide: IDPlanEvaluator
    public init(store: QuadStore) {
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
            fatalError("Cannot evaluate ResultPlan \(plan)")
        }
    }
}

public class IDPlanEvaluator {
    var store: QuadStore
    public init(store: QuadStore) {
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
            fatalError("Unimplemented: \(plan)")
        }
    }
}

public class QuadStorePlanner {
    var store: QuadStore
    var defaultGraph: Term
    var variables: [String]
    var variableNumbers: [String:Int]

    public init(store: QuadStore, defaultGraph: Term) {
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
                    guard let id = store.id.id(for: t) else { fatalError("Failed to retrieve ID for RDF Term during query planning") }
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
                    guard let id = store.id.id(for: t) else { fatalError("Failed to retrieve ID for RDF Term during query planning") }
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
            fatalError("Cannot plan \(algebra)")
        }
    }
}
