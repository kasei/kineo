//
//  TriplePatternFragmentQuadStore.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 6/6/18.
//

import Foundation
import SPARQLSyntax
import URITemplate
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum TPFError : Error {
    case blankNodeUse(String)
    case dataError(String)
    case requestError(String)
    case hypermediaControlError(String)
}
// swiftlint:disable:next type_body_length
open class TriplePatternFragmentQuadStore: Sequence, QuadStoreProtocol {
    
    let emptyPattern = QuadPattern(
        subject: .variable("s", binding: true),
        predicate: .variable("p", binding: true),
        object: .variable("o", binding: true),
        graph: .variable("g", binding: true)
    )
    
    var template: URITemplate
    public var defaultGraph: Term
    var subjectVariable: String
    var predicateVariable: String
    var objectVariable: String
    var nextPattern: QuadPattern
    
    public init?(urlTemplate: String, defaultGraph: Term = Term(iri: "http://example.org/graph")) {
        do {
            let (t, s, p, o) = try TriplePatternFragmentQuadStore.loadHypermediaControls(urlTemplate: urlTemplate)
            self.template = t
            self.subjectVariable = s
            self.predicateVariable = p
            self.objectVariable = o
            self.defaultGraph = defaultGraph
            self.nextPattern = QuadPattern(
                subject: .variable("s", binding: true),
                predicate: .bound(Term(iri: "http://www.w3.org/ns/hydra/core#next")),
                object: .variable("o", binding: true),
                graph: .bound(defaultGraph)
            )
        } catch {
            return nil
        }
    }
    
    public var count: Int {
        do {
            let q = try quads(matching: emptyPattern)
            return Array(q).count
        } catch {
            return 0
        }
    }
    
    func url(for: QuadPattern) -> URL? {
        return URL(string: template.template)
    }
    
    public var graphsCount: Int { return 1 }

    public func graphs() -> AnyIterator<Term> {
        return AnyIterator([defaultGraph].makeIterator())
    }
    
    public func graphTerms(in graph: Term) -> AnyIterator<Term> {
        // NOTE: this is a very expensive operation for TPF
        var terms = Set<Term>()
        for q in self {
            terms.insert(q.subject)
            terms.insert(q.object)
        }
        return AnyIterator(terms.makeIterator())
    }
    
    public func makeIterator() -> AnyIterator<Quad> {
        let qp = emptyPattern
        do {
            return try quads(matching: qp)
        } catch {
            return AnyIterator([].makeIterator())
        }
    }
    
    public func results(matching pattern: QuadPattern) throws -> AnyIterator<SPARQLResultSolution<Term>> {
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
        let bindings = matching.lazy.map { (quad) -> SPARQLResultSolution<Term> in
            var dict = [String:Term]()
            for (name, path) in map {
                dict[name] = quad[keyPath: path]
            }
            return SPARQLResultSolution<Term>(bindings: dict)
        }
        return AnyIterator(bindings.makeIterator())
    }
    
    public func quads(matching pattern: QuadPattern) throws -> AnyIterator<Quad> {
        var url: URL
        do {
            url = try tpfURL(for: pattern)
        } catch TPFError.blankNodeUse {
            return AnyIterator([].makeIterator())
        }
        
        let client = Client()
        var seenURLs = Set<URL>()
        var buffer = [Quad]()
        let graph = defaultGraph
        let nextPattern = self.nextPattern
        return AnyIterator { () -> Quad? in
            while true {
                if buffer.count > 0 {
                    return buffer.remove(at: 0)
                }
                
                if seenURLs.contains(url) {
                    return nil
                } else {
                    seenURLs.insert(url)
                }
                do {
                    let store = try client.store(from: url, defaultGraph: graph)
                    let i = try store.quads(matching: pattern)
                    buffer.append(contentsOf: i)
                    
                    let nexts = try Array(store.quads(matching: nextPattern))
                    if let nextQuad = nexts.first {
                        if let u = URL(string: nextQuad.object.value) {
                            url = u
                        }
                    }
                } catch {
                    return nil
                }
            }
        }
    }
    
    public func countQuads(matching pattern: QuadPattern) throws -> Int {
        var count = 0
        for _ in try quads(matching: pattern) {
            count += 1
        }
        return count
    }

    public func effectiveVersion(matching pattern: QuadPattern) throws -> Version? {
        return nil
    }
    
    func tpfURL(for pattern: QuadPattern) throws -> URL {
        var fill = [String:Any]()
        
        if case .bound(let t) = pattern.subject {
            fill[subjectVariable] = try t.tpfString()
        }
        if case .bound(let t) = pattern.predicate {
            fill[predicateVariable] = try t.tpfString()
        }
        if case .bound(let t) = pattern.object {
            fill[objectVariable] = try t.tpfString()
        }
        
        let expanded = template.expand(fill)
        guard let url = URL(string: expanded) else {
            throw TPFError.requestError("Failed to create a URL from expanded URI Template: '\(expanded)'")
        }
        return url
    }
    
    private static func loadHypermediaControls(urlTemplate: String) throws -> (URITemplate, String, String, String) {
        let t = URITemplate(template: urlTemplate)
        let expanded = t.expand([:])
        guard let url = URL(string: expanded) else {
            throw TPFError.requestError("Failed to create a URL from expanded URI Template: '\(expanded)'")
        }
//        print("Extracting hypermedia controls from \(url) ...")
        
        let client = Client()
        let graph = Term(iri: "http://example.org/graph")
        let store = try client.store(from: url, defaultGraph: graph)
        let sparql = """
            PREFIX rdf:   <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
            PREFIX hydra: <http://www.w3.org/ns/hydra/core#>
            SELECT * WHERE {
            ?dataset
                hydra:search [
                    hydra:template ?template ;
                    hydra:mapping  [ hydra:variable ?s ; hydra:property rdf:subject ],
                                   [ hydra:variable ?p ; hydra:property rdf:predicate ],
                                   [ hydra:variable ?o ; hydra:property rdf:object ]
                ].
            }
        """
        guard var parser = SPARQLParser(string: sparql) else {
            throw QueryError.evaluationError("Failed to construct SPARQL parser")
        }
        let query = try parser.parseQuery()
        let dataset = store.dataset(withDefault: graph)
        let e = SimpleQueryEvaluator(store: store, dataset: dataset, verbose: false)
        let results = try e.evaluate(query: query)
        guard case let .bindings(_, rows) = results, let row = rows.first else {
            throw TPFError.hypermediaControlError("Failed to extract hypermedia controls from endpoint")
        }
        
//        print("Found \(rows.count) datasets described in the TPF entrypoint")
        guard let tterm = row["template"], let sterm = row["s"], let pterm = row["p"], let oterm = row["o"] else {
            throw TPFError.hypermediaControlError("Failed to extract hypermedia controls from endpoint")
        }
        
        let template = URITemplate(template: tterm.value)
        let s = sterm.value
        let p = pterm.value
        let o = oterm.value
        
//        print("Got template: \(template)")
//        print("-> with rdf:subject variable: \(s)")
//        print("-> with rdf:predicate variable: \(p)")
//        print("-> with rdf:object variable: \(o)")

        return (template, s, p, o)
    }
}

extension TriplePatternFragmentQuadStore: CustomStringConvertible {
    public var description: String {
        var s = "TriplePatternFragmentQuadStore {\n"
        for q in self {
            s += "    \(q)\n"
        }
        s += "}\n"
        return s
    }
}

struct Client {
    var timeout: Double
    
    public init(timeout: Double = 5.0) {
        self.timeout = timeout
    }

    func store(from u: URL, defaultGraph: Term) throws -> MemoryQuadStore {
        let q = try quads(from: u, defaultGraph: defaultGraph)
        let s = MemoryQuadStore(version: 0)
        try s.load(version: 0, quads: q)
        return s
    }

    func quads(from u: URL, defaultGraph: Term) throws -> [Quad] {
        let triples = try rdf(from: u)
        let q = triples.map { (t) in Quad(triple: t, graph: defaultGraph) }
        return q
    }
    
    func rdf(from u: URL) throws -> [Triple] {
        var args : (Data?, URLResponse?, Error?) = (nil, nil, nil)
        let semaphore = DispatchSemaphore(value: 0)
        let session = URLSession.shared
        var urlRequest = URLRequest(url: u)
        urlRequest.addValue("text/turtle, text/n-triples, application/rdf+xml;q=0.8, */*;q=0.1", forHTTPHeaderField: "Accept")
        
//        print("(getting RDF from \(u))")
        let task = session.dataTask(with: urlRequest) {
            args = ($0, $1, $2)
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: DispatchTime.now() + timeout)
        
        if let error = args.2 {
            throw TPFError.requestError("URL request failed: \(error)")
        }
        
        guard let data = args.0 else {
            throw TPFError.requestError("URL request did not return data")
        }
        
        guard let resp = args.1 else {
            throw TPFError.requestError("URL request did not return a response object")
        }

        var syntax = RDFParserCombined.RDFSyntax.turtle
        if let resp = resp as? HTTPURLResponse {
            if let type = resp.allHeaderFields["Content-Type"] as? String {
                syntax = RDFParserCombined.guessSyntax(mediaType: type)
            }
        }
        
        var triples = [Triple]()
        let parser = RDFParserCombined()
        guard let s = String(data: data, encoding: .utf8) else {
            throw TPFError.dataError("Could not decode HTTP response as utf8")
        }
        try parser.parse(string: s, syntax: syntax) { (s,p,o) in
            let t = Triple(subject: s, predicate: p, object: o)
            triples.append(t)
        }
        return triples
    }
}

extension Term {
    func tpfString() throws -> String {
        switch self.type {
        case .iri:
            return self.value
        case .datatype(.string):
            return "\"\(value)\""
        case .datatype(let dt):
            return "\"\(value)\"^^<\(dt)>"
        case .language(let lang):
            return "\"\(value)\"@\(lang)"
        case .blank:
            throw TPFError.blankNodeUse(value)
        }
    }
}

public extension TriplePatternFragmentQuadStore {
    private func extend<C : Collection>(result: SPARQLResultSolution<Term>, with patterns: C) throws -> AnyIterator<SPARQLResultSolution<Term>> where C.Element == TriplePattern {
        if let tp = patterns.first {
            let qp = QuadPattern(triplePattern: tp, graph: .bound(defaultGraph)).expand(result.bindings)
            let r = try results(matching: qp)

            let bindings = r.lazy.compactMap { (r) -> SPARQLResultSolution<Term>? in
                return r.join(result)
            }
            
            let rest = patterns.dropFirst()
            if rest.count == 0 {
                return AnyIterator(bindings.makeIterator())
            } else {
                var buffer = [SPARQLResultSolution<Term>]()
                var source = bindings.makeIterator()
                return AnyIterator { () -> SPARQLResultSolution<Term>? in
                    while true {
                        if buffer.count > 0 {
                            return buffer.remove(at: 0)
                        }
                        
                        guard let b = source.next() else {
                            return nil
                        }
                        
                        if let i = try? self.extend(result: b, with: rest) {
                            buffer.append(contentsOf: i)
                        } else {
                            return nil
                        }
                    }
                }
            }
        } else {
            return AnyIterator([result].makeIterator())
        }
    }
    
    func evaluate(bgp: [TriplePattern], activeGraph: Term) throws -> AnyIterator<SPARQLResultSolution<Term>> {
        // TODO: re-order triple patterns based on selectivity (obtained from metadata on first page of each fragment)
        guard activeGraph == defaultGraph else {
            return AnyIterator([].makeIterator())
        }
        
        return try extend(result: SPARQLResultSolution<Term>(bindings: [:]), with: bgp)
    }
}
