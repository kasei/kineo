//
//  Query.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 7/8/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation

public indirect enum Expression {
    case term(Term)
    case variable(String)
    case add(Expression, Expression)
    case sub(Expression, Expression)
    case div(Expression, Expression)
    case mul(Expression, Expression)
    case not(Expression)
    case eq(Expression, Expression)
    case ne(Expression, Expression)
    case lt(Expression, Expression)
    case le(Expression, Expression)
    case gt(Expression, Expression)
    case ge(Expression, Expression)
    case call(String, [Expression])
    case isiri(Expression)
    case isblank(Expression)
    case isliteral(Expression)
    case isnumeric(Expression)
    case lang(Expression)
    case datatype(Expression)
    case langmatches(Expression, String)
    case bound(Expression)
    // TODO: add other expression functions
}

public indirect enum Algebra {
    case identity
    case quad(QuadPattern)
    case triple(TriplePattern)
    case bgp([TriplePattern])
    case innerJoin([Algebra])
    case leftOuterJoin(Algebra, Algebra, Expression)
    case filter(Algebra, Expression)
    case union(Algebra, Algebra)
    case namedGraph(Algebra, Node)
    case extend(Algebra, Expression, String)
    case minus(Algebra, Algebra)
    case project([String])
    case distinct(Algebra)
    case slice(Algebra, offset: Int?, limit: Int?)
    // TODO: add property paths
    // TODO: add aggregation
    
    public var inscope : Set<String> {
        var variables = Set<String>()
        switch self {
        case .identity: return Set()
        case .innerJoin(let children):
            if children.count == 0 {
                return Set()
            }
            var vars = children.map { $0.inscope }
            while vars.count > 1 {
                let l = vars.popLast()!
                let r = vars.popLast()!
                vars.append(l.union(r))
            }
            return vars.popLast()!
        case .triple(let t):
            for node in [t.subject, t.predicate, t.object] {
                if case .variable(let name) = node {
                    variables.insert(name)
                }
            }
            return variables
        case .quad(let q):
            for node in [q.subject, q.predicate, q.object, q.graph] {
                if case .variable(let name) = node {
                    variables.insert(name)
                }
            }
            return variables
        default: fatalError()
        }
    }
}

public class QueryParser<T : LineReadable> {
    let reader : T
    var stack : [Algebra]
    public init(reader : T) {
        self.reader = reader
        self.stack = []
    }
    
    func parse(line : String) -> Algebra? {
        var parts = line.components(separatedBy: " ")
        let rest = parts.suffix(from: 1).joined(separator: " ")
        guard parts.count > 0 else { return nil }
        let op = parts[0]
        if op == "join" {
            guard let count = Int(rest) else { return nil }
            var children = [Algebra]()
            for _ in 0..<count {
                guard let child = stack.popLast() else { return nil }
                children.insert(child, at: 0)
            }
            return .innerJoin(children)
        } else if op == "quad" {
            let parser = NTriplesPatternParser(reader: "")
            guard let pattern = parser.parsePattern(line: rest) else { return nil }
            return .quad(pattern)
        }
        warn("Cannot parse query line: \(line)")
        return nil
    }
    
    public func parse() -> Algebra? {
        let lines = self.reader.lines()
        for line in lines {
            guard let algebra = self.parse(line: line) else { return nil }
            stack.append(algebra)
        }
        return stack.popLast()
    }
}

public class SimpleQueryEvaluator {
    var store : QuadStore
    var activeGraph : Term
    public init(store : QuadStore, activeGraph : Term) {
        self.store = store
        self.activeGraph = activeGraph
    }
    
    func evaluateJoin(_ patterns : [Algebra]) throws -> AnyIterator<Result> {
        if patterns.count == 2 {
            var seen = [Set<String>]()
            for pattern in patterns {
                seen.append(pattern.inscope)
            }
            
            while seen.count > 1 {
                let first   = seen.popLast()!
                let next    = seen.popLast()!
                let inter   = first.intersection(next)
                seen.append(inter)
            }
            
            let intersection = seen.popLast()!
            if intersection.count > 0 {
                //                    warn("# using hash join on: \(intersection)")
                let joinVariables = Array(intersection)
                let lhs = Array(try self.evaluate(algebra: patterns[0]))
                let rhs = Array(try self.evaluate(algebra: patterns[1]))
                var results = [Result]()
                hashJoin(joinVariables: joinVariables, lhs: lhs, rhs: rhs) { (result) in
                    results.append(result)
                }
                return AnyIterator(results.makeIterator())
            }
        }
        
        //            warn("# resorting to nested loop join")
        if patterns.count > 0 {
            var patternResults = [[Result]]()
            for pattern in patterns {
                let results     = try self.evaluate(algebra: pattern)
                patternResults.append(Array(results))
            }
            
            var results = [Result]()
            nestedLoopJoin(patternResults) { (result) in
                results.append(result)
            }
            return AnyIterator(results.makeIterator())
        }
        
        return AnyIterator { return nil }
    }
    
    public func evaluate(algebra : Algebra) throws -> AnyIterator<Result> {
        switch algebra {
        case .triple(let t):
            let quad = QuadPattern(subject: t.subject, predicate: t.predicate, object: t.object, graph: .bound(activeGraph))
            return try store.results(matching: quad)
        case .quad(let quad):
            return try store.results(matching: quad)
        case .innerJoin(let patterns):
            return try self.evaluateJoin(patterns)
        default:
            fatalError("Unimplemented: \(algebra)")
        }
    }
}

public func hashJoin(joinVariables : [String], lhs : [Result], rhs : [Result], cb : @noescape (Result) -> ()) {
    var table = [Int:[Result]]()
    for result in lhs {
        let hashes = joinVariables.map { result[$0]?.hashValue ?? 0 }
        let hash = hashes.reduce(0, combine: { $0 ^ $1 })
        if let results = table[hash] {
            table[hash] = results + [result]
        } else {
            table[hash] = [result]
        }
    }
    
    for result in rhs {
        let hashes = joinVariables.map { result[$0]?.hashValue ?? 0 }
        let hash = hashes.reduce(0, combine: { $0 ^ $1 })
        if let results = table[hash] {
            for lhs in results {
                if let j = lhs.join(result) {
                    cb(j)
                }
            }
        }
    }
}


public func nestedLoopJoin(_ results : [[Result]], cb : @noescape (Result) -> ()) {
    var patternResults = results
    while patternResults.count > 1 {
        let rhs = patternResults.popLast()!
        let lhs = patternResults.popLast()!
        let finalPass = patternResults.count == 0
        var joined = [Result]()
        for lresult in lhs {
            for rresult in rhs {
                if let j = lresult.join(rresult) {
                    if finalPass {
                        cb(j)
                    } else {
                        joined.append(j)
                    }
                }
            }
        }
        patternResults.append(joined)
    }
}

