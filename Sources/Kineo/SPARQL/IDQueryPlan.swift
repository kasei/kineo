//
//  IDQueryPlan.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 6/6/20.
//

import Foundation
import SPARQLSyntax

public struct IDQuadPlan: NullaryIDQueryPlan {
    var quad: QuadPattern
    var store: LazyMaterializingQuadStore
    public var selfDescription: String { return "IDQuad(\(quad))" }
    public func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>> {
        return try store.idresults(matching: quad)
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
    public var selfDescription: String { return "ID Project { \(variables) }" }
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

