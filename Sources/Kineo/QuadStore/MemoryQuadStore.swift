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
    
    public init(version: Version? = nil) {
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
    
    public func graphTerms(in graph: Term) -> AnyIterator<Term> {
        let qp = QuadPattern(subject: .variable("s", binding: true), predicate: .variable("p", binding: false), object: .variable("o", binding: true), graph: .bound(graph))
        do {
            let matching = try idquads(matching: qp)
            let nodes = Set(matching.map { [$0.subject, $0.object] }.flatMap { $0 }.map { i2t[$0]! })
            return AnyIterator(nodes.makeIterator())
        } catch {
            return AnyIterator([].makeIterator())
        }
    }
    
    internal func quad(from idquad: MemoryQuad) -> Quad {
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
    
    internal func idquads(matching pattern: QuadPattern) throws -> AnyIterator<MemoryQuad> {
        var s : TermID = 0
        var p : TermID = 0
        var o : TermID = 0
        var g : TermID = 0
        var variablePositions = [String:[Int]]()
        for (i, node) in pattern.enumerated() {
            if case .variable(let name, _) = node {
                variablePositions[name, default: []] += [i]
            }
        }
        let repeats = variablePositions.filter { (_, pos) in pos.count > 1 }

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

            for (_, pos) in repeats {
                let terms = pos.map { (i) -> TermID in
                    switch i {
                    case 0:
                        return idquad.0
                    case 1:
                        return idquad.1
                    case 2:
                        return idquad.2
                    case 3:
                        return idquad.3
                    default:
                        fatalError()
                    }
                }
                if Set(terms).count != 1 {
                    return false
                }
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

    internal func id(for term: Term) -> TermID {
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
    
    internal func idquad(from quad: Quad) -> MemoryQuad {
        let ids = quad.map { id(for: $0) }
        return MemoryQuad(ids[0], ids[1], ids[2], ids[3])
    }
    
    internal func term(for id: IDType) -> Term? {
        let t = i2t[id]
        return t
    }
    public func load<S: Sequence>(version: Version, quads: S) throws where S.Iterator.Element == Quad {
        self.version = version
        let idq = quads.map { idquad(from: $0) }
        self.count += idq.count
        self.idquads.append(contentsOf: idq)
    }
}

extension MemoryQuadStore: CustomStringConvertible {
    public var description: String {
        var s = "MemoryQuadStore {\n"
        for q in self {
            s += "    \(q)\n"
        }
        s += "}\n"
        return s
    }
}

open class LanguageMemoryQuadStore: Sequence, LanguageAwareQuadStore {
    public var count: Int { return quadstore.count }
    public func graphs() -> AnyIterator<Term> {
        return quadstore.graphs()
    }
    
    public func graphTerms(in graph: Term) -> AnyIterator<Term> {
        return quadstore.graphTerms(in: graph)
    }
    
    public func makeIterator() -> AnyIterator<Quad> {
        return quadstore.makeIterator()
    }

    public func effectiveVersion(matching pattern: QuadPattern) throws -> Version? {
        return try quadstore.effectiveVersion(matching: pattern)
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

    public func quads(matching pattern: QuadPattern) throws -> AnyIterator<Quad> {
        let matching = try idquads(matching: pattern).map{ quadstore.quad(from: $0) }
        return AnyIterator(matching.makeIterator())
    }

    public var acceptLanguages: [(String, Double)]
    var quadstore: MemoryQuadStore
    public var siteLanguageQuality: [String: Double]
    
    public init(quadstore: MemoryQuadStore, acceptLanguages: [(String, Double)]) throws {
        self.acceptLanguages = acceptLanguages
        self.quadstore = quadstore
        self.siteLanguageQuality = [:]
    }
    
    internal func idquads(matching pattern: QuadPattern) throws -> AnyIterator<MemoryQuadStore.MemoryQuad> {
        let i = try quadstore.idquads(matching: pattern)
        return AnyIterator {
            repeat {
                guard let idquad = i.next() else { return nil }
                let oid = idquad.object
                let languageQuad = PersistentTermIdentityMap.isLanguageLiteral(id: oid)
                if languageQuad {
                    return idquad
                } else {
                    let quad = self.quadstore.quad(from: idquad)
                    if self.accept(quad: quad, languages: self.acceptLanguages) {
                        return idquad
                    }
                }
            } while true
        }
    }
    
    internal func qValue(_ language: String, qualityValues: [(String, Double)]) -> Double {
        for (lang, value) in qualityValues {
            if language.hasPrefix(lang) {
                return value
            }
        }
        return 0.0
    }
    
    func siteQuality(for language: String) -> Double {
        // Site-defined quality for specific languages.
        return siteLanguageQuality[language] ?? 1.0
    }
    
    private func accept(quad: Quad, languages: [(String, Double)]) -> Bool {
        let object = quad.object
        switch object.type {
        case .language(let l):
            let pattern = QuadPattern(subject: .bound(quad.subject), predicate: .bound(quad.predicate), object: .variable(".o", binding: true), graph: .bound(quad.graph))
            guard let quads = try? quadstore.idquads(matching: pattern) else { return false }
            let langs = quads.compactMap { (idquad) -> String? in
                guard let object = quadstore.term(for: idquad.object) else { return nil }
                if case .language(let lang) = object.type {
                    return lang
                }
                return nil
            }
            let pairs = langs.map { (lang) -> (String, Double) in
                let value = self.qValue(lang, qualityValues: languages) * siteQuality(for: lang)
                return (lang, value)
            }
            
            guard var (_, maxvalue) = pairs.first else { return true }
            for (_, value) in pairs {
                if value > maxvalue {
                    maxvalue = value
                }
            }
            
            let acceptable = Set(pairs.filter { $0.1 == maxvalue }.map { $0.0 })
            return acceptable.contains(l)
        default:
            return true
        }
    }
    
}
