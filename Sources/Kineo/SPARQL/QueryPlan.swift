//
//  QueryPlan.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 1/15/19.
//

import Foundation
import SPARQLSyntax

public class QueryPlanEvaluationMetrics {
    var indent: Int
    var counter: Int
    var stack: [CFAbsoluteTime]
    var times: [Token: Double]
    var plans: [Token: (Int, _QueryPlan)]
    var verbose: Bool
    public typealias Token = Int
    static let silentToken: Token = -1
    
    public init(verbose: Bool = false) {
        self.counter = 1
        self.stack = []
        self.indent = 0
        self.times = [:]
        self.plans = [:]
        self.verbose = verbose
    }
    
    public func getOperatorToken() -> Token {
        let token = self.counter
        self.counter += 1
        return token
    }
    
    private func getCurrentTime() -> CFAbsoluteTime {
        return CFAbsoluteTimeGetCurrent()
    }

    public func startPlanning() {
        self.stack.append(getCurrentTime())
        self.indent += 1
    }

    public func endPlanning() {
        let end = getCurrentTime()
        let start = stack.popLast()!
        let elapsed = end - start
        
        self.times[0, default: 0] += elapsed
        self.indent -= 1
    }

    public func startEvaluation(_ token: Token, _ plan: _QueryPlan) {
        self.plans[token] = (indent, plan)
        self.resumeEvaluation(token: token)
    }

    public func resumeEvaluation(token: Token) {
        guard let _ = self.plans[token] else {
            fatalError("No plan set during evaluation for evaluation token \(token)")
        }
        self.stack.append(getCurrentTime())
//        let prefix = String(repeating: "  ", count: self.indent)
//        print("\(prefix)\(plan.selfDescription)")
        self.indent += 1
    }

    public func endEvaluation(_ token: Token) {
//        let plan = self.plans[token]!
        let end = getCurrentTime()
        let start = stack.popLast()!
        let elapsed = end - start

//        let name = plan.selfDescription
//        let prefix = String(repeating: "  ", count: self.indent)
//        print("\(prefix)<--- [\(elapsed)s] end \(name)")

        self.times[token, default: 0] += elapsed
        self.indent -= 1
    }
    
    deinit {
        if verbose {
            print("Query operator times:")
            let printByTime = false
            if printByTime {
                let sortedPairs = self.times.sorted { (a, b) -> Bool in
                    a.value < b.value
                }
                for (token, time) in sortedPairs {
                    if token == 0 {
                        print(String(format: "%.7f\tplanning", time))
                    } else if let (_, plan) = self.plans[token] {
                        let prefix = String(repeating: "  ", count: 0)
                        print(String(format: "%.7f\t\(prefix)\(plan.selfDescription)", time))
                    }
                }
            } else {
                let planningTime = self.times[0]!
                print(String(format: "%.7f\tplanning", planningTime))
                for token in self.plans.keys.sorted() {
                    let time = self.times[token]!
                    let (indent, plan) = self.plans[token]!
                    let prefix = String(repeating: "  ", count: indent)
                    print(String(format: "%.7f\t\(prefix)\(plan.selfDescription)", time))
                }
            }
        }
    }
}

enum QueryPlanError : Error {
    case invalidChild
    case invalidExpression
    case unimplemented(String)
    case nonConstantExpression
    case unexpectedError(String)
}

public protocol PlanSerializable {
    func serialize(depth: Int) -> String
}

public protocol IDPlanSerializable {
    func serialize(depth: Int) -> String
}

public protocol _QueryPlan: PlanSerializable {
    var selfDescription: String { get }
    var properties: [PlanSerializable] { get }
    var isJoinIdentity: Bool { get }
    var isUnionIdentity: Bool { get }
    var metricsToken: QueryPlanEvaluationMetrics.Token { get }
}

public extension _QueryPlan {
    var selfDescription: String {
        return "\(self)"
    }
    var properties: [PlanSerializable] { return [] }
}


// Materialized Query Plans

public protocol QueryPlan: _QueryPlan {
    var children : [QueryPlan] { get }
    func evaluate(_ metrics: QueryPlanEvaluationMetrics) throws -> AnyIterator<SPARQLResultSolution<Term>>
}

public protocol NullaryQueryPlan: QueryPlan {}
public extension NullaryQueryPlan {
    var children : [QueryPlan] { return [] }
}

public protocol UnaryQueryPlan: QueryPlan {
    var child: QueryPlan { get }
}
public extension UnaryQueryPlan {
    var children : [QueryPlan] { return [child] }
    var isJoinIdentity: Bool { return false }
    var isUnionIdentity: Bool { return false }
}

public protocol BinaryQueryPlan: QueryPlan {
    var lhs: QueryPlan { get }
    var rhs: QueryPlan { get }
}
public extension BinaryQueryPlan {
    var children : [QueryPlan] { return [lhs, rhs] }
    var isJoinIdentity: Bool { return false }
    var isUnionIdentity: Bool { return false }
}

    
public extension QueryPlan {
    var arity: Int { return children.count }
}
public protocol QueryPlanSerialization: QueryPlan {
    func serialize(depth: Int) -> String
}
public extension QueryPlanSerialization {
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

// Non-materialized (ID) Query Plans

public protocol IDQueryPlan: _QueryPlan {
    var children : [IDQueryPlan] { get }
    var variables: Set<String> { get }
    var orderVars: [String] { get }
    func evaluate(_ metrics: QueryPlanEvaluationMetrics) throws -> AnyIterator<SPARQLResultSolution<UInt64>>
}

public protocol NullaryIDQueryPlan: IDQueryPlan {}
public extension NullaryIDQueryPlan {
    var children : [IDQueryPlan] { return [] }
}

public protocol UnaryIDQueryPlan: IDQueryPlan {
    var child: IDQueryPlan { get }
}
public extension UnaryIDQueryPlan {
    var children : [IDQueryPlan] { return [child] }
    var isJoinIdentity: Bool { return false }
    var isUnionIdentity: Bool { return false }
}

public protocol BinaryIDQueryPlan: IDQueryPlan {
    var lhs: IDQueryPlan { get }
    var rhs: IDQueryPlan { get }
}
public extension BinaryIDQueryPlan {
    var children : [IDQueryPlan] { return [lhs, rhs] }
    var isJoinIdentity: Bool { return false }
    var isUnionIdentity: Bool { return false }
}

public extension IDQueryPlan {
    var arity: Int { return children.count }
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

