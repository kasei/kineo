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
        return try algebra
            .rewrite(mergeFilters)
            .rewrite(simplifyExpressions)
            .rewrite(foldConstantExpressions)
            .rewrite(foldConstantAlgebras)
            .rewrite(propertyPathExpansion)
            .rewrite(pushdownProjection)
            .rewrite(pushdownSlice)
            .rewrite(pushdownFilter)
    }
}

private func pushdownProjection(_ algebra: Algebra) throws -> RewriteStatus<Algebra> {
    switch algebra {
    case let .project(.project(child, inner), outer):
        return .rewriteChildren(.project(child, inner.intersection(outer)))
    case let .project(.order(child, cmps), vars):
        return .rewriteChildren(.order(.project(child, vars), cmps))
    case let .project(.table(columns, rows), vars):
        // make the header Nodes in the .table non-binding, and ensure that .table evaluation respects the nodes' binding flags
        var tableVariables = [String]()
        for c in columns {
            guard case .variable(let v, true) = c else {
                // table is structurally invalid, bail out of rewriting
                return .keep
            }
            tableVariables.append(v)
        }
        let preserveVariablesSet = Set(tableVariables).intersection(vars)
        var rewrittenRows = [[Term?]]()
        for row in rows {
            var rewrittenRow = [Term?]()
            for (name, term) in zip(tableVariables, row) {
                if preserveVariablesSet.contains(name) {
                    rewrittenRow.append(term)
                }
            }
            rewrittenRows.append(rewrittenRow)
        }
        let preserveColumns = columns.filter { (node) -> Bool in
            if case .variable(let v, _) = node, preserveVariablesSet.contains(v) {
                return true
            } else {
                return false
            }
        }
        return .rewrite(.table(preserveColumns, rewrittenRows))
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
            return .rewriteChildren(.project(.extend(.project(child, needed.subtracting([name])), expr, name), vars))
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

private func pushdownSlice(_ algebra: Algebra) throws -> RewriteStatus<Algebra> {
    switch algebra {
    case let .slice(_, _, .some(limit)) where limit == 0:
        return .rewrite(.unionIdentity) // LIMIT 0 -> no results
    case let .slice(.joinIdentity, .some(offset), _) where offset > 0:
        return .rewrite(.unionIdentity) // OFFSET >0 over a single row -> no results
    case let .slice(.table(columns, rows), .some(offset), .some(limit)):
        let rewrittenRows = rows.dropFirst(offset).prefix(limit)
        return .rewrite(.table(columns, Array(rewrittenRows)))
    case let .slice(.table(columns, rows), nil, .some(limit)):
        let rewrittenRows = rows.prefix(limit)
        return .rewrite(.table(columns, Array(rewrittenRows)))
    case let .slice(.table(columns, rows), .some(offset), nil):
        let rewrittenRows = rows.dropFirst(offset)
        return .rewrite(.table(columns, Array(rewrittenRows)))
    case let .slice(.leftOuterJoin(lhs, rhs, expr), nil, .some(limit)), let .slice(.leftOuterJoin(lhs, rhs, expr), 0, .some(limit)):
        // slicing an OPTIONAL with a limit but no offset can safely limit the lhs
        return .rewriteChildren(.slice(.leftOuterJoin(.slice(lhs, 0, limit), rhs, expr), 0, limit))
    case let .slice(.union(lhs, rhs), nil, .some(limit)), let .slice(.union(lhs, rhs), 0, .some(limit)):
        // slicing a UNION with a limit but no offset can safely limit both sides
        return .rewriteChildren(.slice(.union(.slice(lhs, 0, limit), .slice(rhs, 0, limit)), 0, limit))
    case let .slice(.extend(child, expr, name), offset, limit):
        return .rewriteChildren(.extend(.slice(child, offset, limit), expr, name))
    default:
        break
    }
    return .rewriteChildren(algebra)
}

private func mergeFilters(_ algebra: Algebra) throws -> RewriteStatus<Algebra> {
    switch algebra {
    case let .filter(.filter(child, inner), outer):
        return .rewriteChildren(.filter(child, .and(inner, outer)))
    default:
        break
    }
    return .rewriteChildren(algebra)
}

private func pushdownFilter(_ algebra: Algebra) throws -> RewriteStatus<Algebra> {
    guard case let .filter(child, expr) = algebra else {
        return .rewriteChildren(algebra)
    }
    
    let vars = expr.variables
    
    switch child {
    case .table(_):
        print("TODO: rewrite .table(_) with filtering applied")
        break
    case let .innerJoin(lhs, rhs):
        let lok = vars.isSubset(of: lhs.inscope)
        let rok = vars.isSubset(of: rhs.inscope)
        if lok && rok {
            return .rewriteChildren(.innerJoin(.filter(lhs, expr), .filter(rhs, expr)))
        } else if lok {
            return .rewriteChildren(.innerJoin(.filter(lhs, expr), rhs))
        } else if rok {
            return .rewriteChildren(.innerJoin(lhs, .filter(rhs, expr)))
        }
    case let .union(lhs, rhs):
        return .rewriteChildren(.union(.filter(lhs, expr), .filter(rhs, expr)))
    case let .minus(lhs, rhs):
        return .rewriteChildren(.minus(.filter(lhs, expr), rhs))
    case let .distinct(lhs):
        return .rewriteChildren(.distinct(.filter(lhs, expr)))
    case let .order(lhs, cmps):
        return .rewriteChildren(.order(.filter(lhs, expr), cmps))
    default:
        break
    }
    return .rewriteChildren(algebra)
}

private func propertyPathExpansion(_ algebra: Algebra) throws -> RewriteStatus<Algebra> {
    guard case let .path(s, pp, o) = algebra else {
        return .rewriteChildren(algebra)
    }
    
    switch pp {
    case let .link(p):
        return .rewrite(.triple(TriplePattern(subject: s, predicate: .bound(p), object: o)))
    case let .inv(ppi):
        return .rewrite(.path(o, ppi, s))
    case let .alt(lhs, rhs):
        return .rewrite(.union(.path(s, lhs, o), .path(s, rhs, o)))
    default:
        return .keep
    }
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

private func foldConstantAlgebras(_ algebra: Algebra) throws -> RewriteStatus<Algebra> {
    switch algebra {
    case .innerJoin(.unionIdentity, _), .innerJoin(_, .unionIdentity):
        return .rewriteChildren(.unionIdentity)
    case .innerJoin(.joinIdentity, let child), .innerJoin(let child, .joinIdentity):
        return .rewriteChildren(child)
    case .union(.unionIdentity, let child), .union(let child, .unionIdentity):
        return .rewriteChildren(child)
    default:
        break
    }
    return .rewriteChildren(algebra)
}

private func foldConstantExpressions(_ algebra: Algebra) throws -> RewriteStatus<Algebra> {
    switch algebra {
    case .filter(_, .node(.bound(Term.falseValue))):
        return .rewrite(.unionIdentity)
    case .filter(let child, .node(.bound(Term.trueValue))):
        return .rewrite(child)
    case .table(_, []):
        return .rewrite(.unionIdentity)
    default:
        break
    }
    return .rewriteChildren(algebra)
}

private func simplifyExpressions(_ algebra: Algebra) throws -> RewriteStatus<Algebra> {
    switch algebra {
    case let .extend(child, expr, name):
        let e = try expr.rewrite(simplifyExpression)
        return .rewriteChildren(.extend(child, e, name))
    case let .filter(child, expr):
        let e = try expr.rewrite(simplifyExpression)
        return .rewriteChildren(.filter(child, e))
    case let .leftOuterJoin(lhs, rhs, expr):
        let e = try expr.rewrite(simplifyExpression)
        return .rewriteChildren(.leftOuterJoin(lhs, rhs, e))
    default:
        break
    }
    return .rewriteChildren(algebra)
}


private func simplifyExpression(_ expr: Expression) throws -> RewriteStatus<Expression> {
    guard expr.isConstant else {
        return .rewriteChildren(expr)
    }

    let ee = ExpressionEvaluator()
    do {
        let term = try ee.evaluate(expression: expr, result: TermResult(bindings: [:]))
        return .rewrite(.node(.bound(term)))
    } catch {
        return .rewriteChildren(expr)
    }
}
