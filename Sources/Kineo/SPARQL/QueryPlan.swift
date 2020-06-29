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
    func evaluate() throws -> AnyIterator<SPARQLResultSolution<Term>>
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
    func evaluate() throws -> AnyIterator<SPARQLResultSolution<UInt64>>
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
