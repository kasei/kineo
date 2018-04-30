//
//  MemoryQuadStore.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 4/27/18.
//

import Foundation
import SPARQLSyntax

// swiftlint:disable:next type_body_length
open class MemoryQuadStore: Sequence, MutableQuadStoreProtocol {
    typealias TermID = UInt64
    typealias MemoryQuad = (subject: TermID, predicate: TermID, object: TermID, graph: TermID)
    public var count: Int
    var idquads: [MemoryQuad]
    var i2t: [TermID: Term]
    var t2i: [Term: TermID]
    var version: Version?
    var next: TermID
    
    init(version: Version? = nil) {
        self.next = 1
        self.count = 0
        self.idquads = []
        self.i2t = [:]
        self.t2i = [:]
        self.version = version
    }
    
    public func graphs() -> AnyIterator<Term> {
        let graphs = Set(idquads.map { $0.graph }.map { i2t[$0]! })
        return AnyIterator(graphs.makeIterator())
    }
    
    public func graphNodeTerms() -> AnyIterator<Term> {
        let nodes = Set(idquads.map { [$0.subject, $0.object] }.flatMap { $0 }.map { i2t[$0]! })
        return AnyIterator(nodes.makeIterator())
    }
    
    private func quad(from idquad: MemoryQuad) -> Quad {
        let s = i2t[idquad.subject]!
        let p = i2t[idquad.predicate]!
        let o = i2t[idquad.object]!
        let g = i2t[idquad.graph]!
        let q = Quad(subject: s, predicate: p, object: o, graph: g)
        return q
    }
    
    public func makeIterator() -> AnyIterator<Quad> {
        let quads = idquads.map { (idquad) -> Quad in
            return quad(from: idquad)
        }
        return AnyIterator(quads.makeIterator())
    }
    
    public func results(matching pattern: QuadPattern) throws -> AnyIterator<TermResult> {
        var map = [String: KeyPath<Quad, Term>]()
        for (node, path) in zip(pattern, QuadPattern.groundKeyPaths) {
            switch node {
            case let .variable(name, binding: true):
                map[name] = path
            default:
                break
            }
        }
        let matching = try quads(matching: pattern)
        let bindings = matching.map { (quad) -> TermResult in
            var dict = [String:Term]()
            for (name, path) in map {
                dict[name] = quad[keyPath: path]
            }
            return TermResult(bindings: dict)
        }
        return AnyIterator(bindings.makeIterator())
    }
    
    private func idquads(matching pattern: QuadPattern) throws -> AnyIterator<MemoryQuad> {
        var s : TermID = 0
        var p : TermID = 0
        var o : TermID = 0
        var g : TermID = 0
        if case .bound(let t) = pattern.subject {
            if let i = t2i[t] {
                s = i
            } else {
                return AnyIterator { return nil }
            }
        }
        if case .bound(let t) = pattern.predicate {
            if let i = t2i[t] {
                p = i
            } else {
                return AnyIterator { return nil }
            }
        }
        if case .bound(let t) = pattern.object {
            if let i = t2i[t] {
                o = i
            } else {
                return AnyIterator { return nil }
            }
        }
        if case .bound(let t) = pattern.graph {
            if let i = t2i[t] {
                g = i
            } else {
                return AnyIterator { return nil }
            }
        }
        
        let matching = idquads.filter { (idquad) -> Bool in
            if s > 0 && idquad.subject != s {
                return false
            }
            if p > 0 && idquad.predicate != p {
                return false
            }
            if o > 0 && idquad.object != o {
                return false
            }
            if g > 0 && idquad.graph != g {
                return false
            }

            return true
        }
        return AnyIterator(matching.makeIterator())
    }
    
    public func quads(matching pattern: QuadPattern) throws -> AnyIterator<Quad> {
        let matching = try idquads(matching: pattern).map{ quad(from: $0) }
        return AnyIterator(matching.makeIterator())
    }
    
    public func effectiveVersion(matching pattern: QuadPattern) throws -> Version? {
        return version
    }

    private func id(for term: Term) -> TermID {
        if let i = t2i[term] {
            return i
        } else {
            let i = self.next
            self.next += 1
            t2i[term] = i
            i2t[i] = term
            return i
        }
    }
    
    private func idquad(from quad: Quad) -> MemoryQuad {
        let ids = quad.map { id(for: $0) }
        return MemoryQuad(ids[0], ids[1], ids[2], ids[3])
    }
    
    public func load<S: Sequence>(quads: S) throws where S.Iterator.Element == Quad {
        self.idquads.append(contentsOf: quads.map { idquad(from: $0) })
    }
}

