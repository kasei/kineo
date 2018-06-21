//
//  QueryRewriting.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 6/21/18.
//

import Foundation
import SPARQLSyntax

public struct SPARQLQueryRewriter {
    public init () {
    }
    
    public func simplify(query: Query) throws -> Query {
        return try Query(
            form: query.form,
            algebra: simplify(algebra: query.algebra),
            dataset: query.dataset,
            base: query.base
        )
    }
    
    public func simplify(algebra: Algebra) throws -> Algebra {
        var a = algebra
        a = try a.rewrite(pushdownProjection)
        return a
    }
}

private func pushdownProjection(_ algebra: Algebra) throws -> RewriteStatus<Algebra> {
    switch algebra {
    case let .project(.project(child, inner), outer):
        return .rewriteChildren(.project(child, inner.intersection(outer)))
    case let .project(.order(child, cmps), vars):
        return .rewriteChildren(.order(.project(child, vars), cmps))
    case .project(.table(_), _):
        print("TODO: coalesce projection with .table(_)")
        // make the header Nodes in the .table non-binding, and ensure that .table evaluation respects the nodes' binding flags
        break
    case let .project(.triple(t), vars):
        let unbind = Algebra.triple(t).inscope.symmetricDifference(vars)
        var triple = t
        for v in unbind {
            triple = triple.bind(v, to: .variable(v, binding: false))
        }
        return .rewrite(.triple(triple))
    case let .project(.quad(q), vars):
        let unbind = Algebra.quad(q).inscope.symmetricDifference(vars)
        var quad = q
        for v in unbind {
            quad = quad.bind(v, to: .variable(v, binding: false))
        }
        return .rewrite(.quad(quad))
    case .project(.bgp(_), _):
        print("TODO: coalesce projection with .bgp(_) to eliminate binding of non-join variables, and leave a wrapping projection for everything else")
        break
    case let .project(.innerJoin(lhs, rhs), vars):
        let intersection = lhs.inscope.intersection(rhs.inscope)
        let needed = vars.union(intersection)
        let l : Algebra = .project(lhs, needed)
        let r : Algebra = .project(rhs, needed)
        let rewritten : Algebra = .innerJoin(l, r)
        if rewritten.inscope == vars {
            return .rewriteChildren(rewritten)
        } else {
            return .rewriteChildren(.project(rewritten, vars))
        }
    case .project(.leftOuterJoin(_, _, _), _):
        break // TODO
    case .project(.filter(_, _), _):
        break // TODO
    case let .project(.union(lhs, rhs), vars):
        return .rewriteChildren(
            .union(
                .project(lhs, vars),
                .project(rhs, vars)
            )
        )
    case let .project(.extend(child, expr, name), vars):
        if vars.contains(name) {
            let needed = vars.union(expr.variables)
            return .rewriteChildren(.project(.extend(.project(child, needed), expr, name), vars))
        } else {
            // projection immediately makes the newly bound variable go away, so drop it
            return .rewriteChildren(.project(child, vars))
        }
    case let .project(.distinct(child), vars):
        return .rewriteChildren(.distinct(.project(child, vars)))
    case let .project(.slice(child, offset, limit), vars):
        return .rewriteChildren(.slice(.project(child, vars), offset, limit))
    case let .project(.path(s, pp, o), vars):
        var path = Algebra.path(s, pp, o)
        let unbind = path.inscope.symmetricDifference(vars)
        for v in unbind {
            path = try path.bind(v, to: .variable(v, binding: false))
        }
        return .rewrite(path)
    default:
        break
    }
    return .rewriteChildren(algebra)
}


/**
 
    case unionIdentity
    case joinIdentity
    case table([Node], [[Term?]])
    case quad(QuadPattern)
    case triple(TriplePattern)
    case bgp([TriplePattern])
    case innerJoin(Algebra, Algebra)
    case leftOuterJoin(Algebra, Algebra, Expression)
    case filter(Algebra, Expression)
    case union(Algebra, Algebra)
    case namedGraph(Algebra, Node)
    case extend(Algebra, Expression, String)
    case minus(Algebra, Algebra)
    case project(Algebra, Set<String>)
    case distinct(Algebra)
    case service(URL, Algebra, Bool)
    case slice(Algebra, Int?, Int?)
    case order(Algebra, [SortComparator])
    case path(Node, PropertyPath, Node)
    case aggregate(Algebra, [Expression], Set<AggregationMapping>)
    case window(Algebra, [Expression], [WindowFunctionMapping])
    case subquery(Query)

 **/
