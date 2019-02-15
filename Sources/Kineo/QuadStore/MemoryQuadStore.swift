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
    public enum MemoryQuadStoreError: Error {
        case existingMapping(UInt64, Term)
    }
    
    typealias TermID = UInt64
    typealias MemoryQuad = (subject: TermID, predicate: TermID, object: TermID, graph: TermID)
    public var count: Int
    var idquads: [MemoryQuad]
    var i2t: [TermID: Term]
    var t2i: [Term: TermID]
    var version: Version?
    var next: TermID
    var graphIDs: Set<TermID>
    
    public init<S: Sequence, T: Sequence>(version: Version? = nil, dictionary: S, quads: T) throws where S.Element == (UInt64, Term), T.Element == (UInt64, UInt64, UInt64, UInt64) {
        self.i2t = [:]
        self.t2i = [:]
        self.count = 0
        self.idquads = []
        self.graphIDs = []
        self.version = version
        self.next = 1
        try? load(version: self.version ?? 0, dictionary: dictionary, quads: quads)
    }
    
    public func load<S: Sequence, T: Sequence>(version: Version, dictionary: S, quads: T) throws where S.Element == (UInt64, Term), T.Element == (UInt64, UInt64, UInt64, UInt64) {
//        print("optimized MemoryQuadStore.load(version:dictionary:quads:) called")
        for (id, term) in dictionary {
            guard i2t[id] == nil, t2i[term] == nil else {
                throw MemoryQuadStoreError.existingMapping(id, term)
            }
            i2t[id] = term
            t2i[term] = id
        }
        self.version = version
        self.idquads.append(contentsOf: quads.map { (subject: $0.0, predicate: $0.1, object: $0.2, graph: $0.3) })
        self.count = self.idquads.count
        self.graphIDs = Set(self.idquads.map { $0.graph })
        let m = self.i2t.keys.max() ?? 0
        self.next = m + 1
    }
    
    public init(version: Version? = nil) {
        self.next = 1
        self.count = 0
        self.idquads = []
        self.i2t = [:]
        self.t2i = [:]
        self.graphIDs = []
        self.version = version
    }
    
    public func graphs() -> AnyIterator<Term> {
        let graphs = graphIDs.map { i2t[$0]! }
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
        let graphs = Set(idq.map { $0.graph })
        self.count += idq.count
        for g in graphs {
            self.graphIDs.insert(g)
        }
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

open class LanguageMemoryQuadStore: Sequence, LanguageAwareQuadStore, MutableQuadStoreProtocol {
    public var count: Int {
        let qp = QuadPattern(
            subject: Node(variable: "s"),
            predicate: Node(variable: "p"),
            object: Node(variable: "o"),
            graph: Node(variable: "g")
        )
        guard let quads = try? self.quads(matching: qp) else { return 0 }
        var count = 0
        for _ in quads {
            count += 1
        }
        return count
    }
    
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
    
    public init(quadstore: MemoryQuadStore, acceptLanguages: [(String, Double)]) {
        self.acceptLanguages = acceptLanguages
        self.quadstore = quadstore
        self.siteLanguageQuality = [:]
    }
    
    internal func idquads(matching pattern: QuadPattern) throws -> AnyIterator<MemoryQuadStore.MemoryQuad> {
        switch pattern.object {
        case .bound(_):
            // if the quad pattern's object is bound, we don't need to
            // perform filtering for language conneg
            return try quadstore.idquads(matching: pattern)
        default:
            let i = try quadstore.idquads(matching: pattern)
            var cachedAcceptance = [[MemoryQuadStore.TermID]: Set<String>]()
            return AnyIterator {
                repeat {
                    guard let idquad = i.next() else { return nil }
                    let quad = self.quadstore.quad(from: idquad)
                    let object = quad.object
                    if self.acceptLanguages.isEmpty {
                        // special case: if there is no preference (e.g. no Accept-Language header is present),
                        // then all quads are kept in the model
                        return idquad
                    } else if case .language(_) = object.type {
                        let cacheKey : [MemoryQuadStore.TermID] = [idquad.subject, idquad.predicate, 0, idquad.graph]
                        if self.accept(quad: quad, languages: self.acceptLanguages, cacheKey: cacheKey, cachedAcceptance: &cachedAcceptance) {
                            return idquad
                        }
                    } else {
                        return idquad
                    }
                } while true
            }
        }
    }
    
    internal func qValue(_ language: String, qualityValues: [(String, Double)]) -> Double {
        for (lang, value) in qualityValues {
            if language.hasPrefix(lang) || lang == "*" {
                return value
            }
        }
        return 0.0
    }
    
    func siteQuality(for language: String) -> Double {
        // Site-defined quality for specific languages.
        return siteLanguageQuality[language] ?? 1.0
    }
    
    private func accept<K: Hashable>(quad: Quad, languages: [(String, Double)], cacheKey: K, cachedAcceptance: inout [K: Set<String>]) -> Bool {
        let object = quad.object
        switch object.type {
        case .language(let l):
            if let acceptable = cachedAcceptance[cacheKey] {
                return acceptable.contains(l)
            } else {
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
                
                guard maxvalue > 0.0 else { return false }
                let acceptable = Set(pairs.filter { $0.1 == maxvalue }.map { $0.0 })
                
                // NOTE: in cases where multiple languages are equally preferable, we tie-break using lexicographic ordering based on language code
                guard let bestAcceptable = acceptable.sorted().first else { return false }
                cachedAcceptance[cacheKey] = Set([bestAcceptable])

                return l == bestAcceptable
            }
        default:
            return true
        }
    }

    public func load<S>(version: Version, quads: S) throws where S : Sequence, S.Element == Quad {
        return try quadstore.load(version: version, quads: quads)
    }
}
