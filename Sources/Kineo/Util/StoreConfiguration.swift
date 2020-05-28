//
//  StoreConfiguration.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 10/9/18.
//

import Foundation
import SPARQLSyntax
import DiomedeQuadStore

public enum StoreConfigurationError: Error {
    case initializationError
    case unsupportedConfiguration(String)
}

public struct QuadStoreConfiguration {
    public enum StoreType {
        case memoryDatabase
        case diomedeDatabase(String)
        case sqliteFileDatabase(String)
        case sqliteMemoryDatabase
    }
    
    public enum StoreInitialization {
        case none
        case loadFiles(default: [String], named: [Term: String])
    }
    
    public var type: StoreType
    public var initialize: StoreInitialization
    public var languageAware: Bool
    public var acceptLanguages: [(String, Double)]
    
    public init(type: StoreType, initialize: StoreInitialization, languageAware: Bool) {
        self.type = type
        self.initialize = initialize
        self.languageAware = languageAware
        self.acceptLanguages = [("*", 1.0)]
    }
    
    public init(arguments args: inout [String]) throws {
        self.init(type: .sqliteMemoryDatabase, initialize: .none, languageAware: false)
        self.acceptLanguages = [("*", 1.0)]
        
        var defaultGraphs = [String]()
        var namedGraphs = [(Term, String)]()
        
        let index = args.index(after: args.startIndex)
        LOOP: while true {
            if args.count <= 1 {
                break
            }
            let arg = args.remove(at: index)
            switch arg {
            case "-m", "--memory":
                break
            case "-l", "--language":
                languageAware = true
                var langs = Locale.preferredLanguages.map { (l) -> String in
                    if l.contains("-") {
                        // Locale always produces country-specific subtags,
                        // but the DWIM expectation is probably to use just
                        // the language code
                        return String(l.prefix { $0 != "-" })
                    } else {
                        return l
                    }
                }
                langs.append("*")
                
                let q = (1...langs.count).reversed()
                    .map { Double($0)/Double(langs.count) }
                    .map { (v: Double) -> Double in Double(Int(v*100.0))/100.0 }
                acceptLanguages = Array(zip(langs, q))
            case "-D":
                let path = args.remove(at: index)
                let url = URL(fileURLWithPath: path)
                let m = FileManager.default
                let d = url.appendingPathComponent("default")
                let n = url.appendingPathComponent("named")
                if m.fileExists(atPath: d.path) {
                    for file in try m.contentsOfDirectory(at: d, includingPropertiesForKeys: []) {
                        defaultGraphs.append(file.path)
                    }
                }
                if m.fileExists(atPath: n.path) {
                    for file in try m.contentsOfDirectory(at: n, includingPropertiesForKeys: []) {
                        namedGraphs.append((Term(iri: file.absoluteString), file.path))
                    }
                }
            case "-d":
                defaultGraphs.append(args.remove(at: index))
            case _ where arg.hasPrefix("--language="):
                languageAware = true
                let langs = String(arg.dropFirst(11)).split(separator: ",").map { String($0) }
                let q = (1...langs.count).reversed()
                    .map { Double($0)/Double(langs.count) }
                    .map { (v: Double) -> Double in Double(Int(v*100.0))/100.0 }
                acceptLanguages = Array(zip(langs, q))
            case _ where arg.hasPrefix("--default-graph="):
                defaultGraphs.append(String(arg.dropFirst(16)))
            case "-g":
                let name = args.remove(at: index)
                let file = args.remove(at: index)
                namedGraphs.append((Term(iri: name), file))
            case "-n":
                let file = args.remove(at: index)
                namedGraphs.append((Term(iri: file), file))
            case _ where arg.hasPrefix("--named-graph="):
                let file = String(arg.dropFirst(14))
                namedGraphs.append((Term(iri: file), file))
            case "-q":
                type = .diomedeDatabase(args.remove(at: index))
            case "-s":
                type = .sqliteFileDatabase(args.remove(at: index))
            case _ where arg.hasPrefix("--store="):
                let filename = String(arg.dropFirst(7))
                type = .sqliteFileDatabase(filename)
            default:
                args.insert(arg, at: index)
                break LOOP
            }
        }
        
        if !defaultGraphs.isEmpty || !namedGraphs.isEmpty {
            let named = Dictionary(uniqueKeysWithValues: namedGraphs)
            initialize = .loadFiles(default: defaultGraphs, named: named)
        }
    }
    
    public func withStore<R>(_ handler: (QuadStoreProtocol) throws -> R) throws -> R {
        switch type {
        case .diomedeDatabase(let filename):
            let fileManager = FileManager.default
            let initialize = !fileManager.fileExists(atPath: filename)
            guard let store = DiomedeQuadStore(path: filename, create: initialize) else {
                throw StoreConfigurationError.initializationError
            }
            if languageAware {
                throw StoreConfigurationError.unsupportedConfiguration("DiomedeQuadStore does not support language-aware queries")
            } else {
                return try handler(store)
            }
        case .sqliteFileDatabase(let filename):
            let fileManager = FileManager.default
            let initialize = !fileManager.fileExists(atPath: filename)
            let store = try SQLiteQuadStore(filename: filename, initialize: initialize)
            if languageAware {
                let lstore = SQLiteLanguageQuadStore(quadstore: store, acceptLanguages: acceptLanguages)
                return try handler(lstore)
            } else {
                return try handler(store)
            }
        case .sqliteMemoryDatabase:
            let store = try SQLiteQuadStore()
            if languageAware {
                let acceptLanguages = [("*", 1.0)] // can be changed later
                let lstore = SQLiteLanguageQuadStore(quadstore: store, acceptLanguages: acceptLanguages)
                return try handler(lstore)
            } else {
                return try handler(store)
            }
        case .memoryDatabase:
            let store = MemoryQuadStore()
            if languageAware {
                let acceptLanguages = [("*", 1.0)] // can be changed later
                let lstore = LanguageMemoryQuadStore(quadstore: store, acceptLanguages: acceptLanguages)
                return try handler(lstore)
            } else {
                return try handler(store)
            }
        }
    }
    
    public func store() throws -> QuadStoreProtocol {
        var store: QuadStoreProtocol!
        try withStore { (s) in
            store = s
        }
        return store
    }
    
       public func anystore() throws -> AnyQuadStore {
           return try _anystore(mutable: false) as! AnyQuadStore
       }
    
       public func anymutablestore() throws -> AnyMutableQuadStore {
           return try _anystore(mutable: true) as! AnyMutableQuadStore
       }
    
    public func _anystore(mutable: Bool) throws -> Any {
        switch type {
        case .sqliteFileDatabase(let filename):
            let fileManager = FileManager.default
            let initialize = !fileManager.fileExists(atPath: filename)
            let store = try SQLiteQuadStore(filename: filename, initialize: initialize)
            if languageAware {
                let lstore = SQLiteLanguageQuadStore(quadstore: store, acceptLanguages: acceptLanguages)
                return mutable ? AnyMutableQuadStore(lstore) : AnyQuadStore(lstore)
            } else {
                return mutable ? AnyMutableQuadStore(store) : AnyQuadStore(store)
            }
        case .sqliteMemoryDatabase:
            let store = try SQLiteQuadStore()
            if languageAware {
                let acceptLanguages = [("*", 1.0)] // can be changed later
                let lstore = SQLiteLanguageQuadStore(quadstore: store, acceptLanguages: acceptLanguages)
                return mutable ? AnyMutableQuadStore(lstore) : AnyQuadStore(lstore)
            } else {
                return mutable ? AnyMutableQuadStore(store) : AnyQuadStore(store)
            }
        case .memoryDatabase:
            let store = MemoryQuadStore()
            if languageAware {
                let acceptLanguages = [("*", 1.0)] // can be changed later
                let lstore = LanguageMemoryQuadStore(quadstore: store, acceptLanguages: acceptLanguages)
                return mutable ? AnyMutableQuadStore(lstore) : AnyQuadStore(lstore)
            } else {
                return mutable ? AnyMutableQuadStore(store) : AnyQuadStore(store)
            }
        }
    }
}

public struct AnyQuadStore: QuadStoreProtocol {
    typealias A = Any
    
    private let _count: () -> Int
    private let _graphs: () -> AnyIterator<Term>
    private let _graphTerms: (Term) -> AnyIterator<Term>
    private let _makeIterator: () -> AnyIterator<Quad>
    private let _results: (QuadPattern) throws -> AnyIterator<TermResult>
    private let _quads: (QuadPattern) throws -> AnyIterator<Quad>
    private let _effectiveVersion: (QuadPattern) throws -> Version?
    private let _graphDescriptions: () -> [Term:GraphDescription]
    private let _features: () -> [QuadStoreFeature]
    private let _plan: (Algebra, Term, Dataset) throws -> QueryPlan?
    
    init<Q: QuadStoreProtocol>(_ value: Q) {
        self._count = { value.count }
        self._graphs = value.graphs
        self._graphTerms = value.graphTerms
        self._makeIterator = value.makeIterator
        self._results = value.results
        self._quads = value.quads
        self._effectiveVersion = value.effectiveVersion
        self._graphDescriptions = { value.graphDescriptions }
        self._features = { value.features }
        if let pqs = value as? PlanningQuadStore {
            self._plan = pqs.plan
        } else {
            self._plan = { (_, _, _) -> QueryPlan? in return nil }
        }
    }
    
    public var count : Int { return _count() }
    
    public func graphs() -> AnyIterator<Term> {
        return _graphs()
    }
    
    public func graphTerms(in graph: Term) -> AnyIterator<Term> {
        return _graphTerms(graph)
    }
    
    public func makeIterator() -> AnyIterator<Quad> {
        return _makeIterator()
    }
    
    public func results(matching pattern: QuadPattern) throws -> AnyIterator<TermResult> {
        return try _results(pattern)
    }
    
    public func quads(matching pattern: QuadPattern) throws -> AnyIterator<Quad> {
        return try _quads(pattern)
    }
    
    public func effectiveVersion(matching pattern: QuadPattern) throws -> Version? {
        return try _effectiveVersion(pattern)
    }
    
    public func plan(algebra: Algebra, activeGraph: Term, dataset: Dataset) throws -> QueryPlan? {
        return try _plan(algebra, activeGraph, dataset)
    }
}

public struct AnyMutableQuadStore: MutableQuadStoreProtocol, PlanningQuadStore {
    public let _store: Any
    private let _count: () -> Int
    private let _graphs: () -> AnyIterator<Term>
    private let _graphTerms: (Term) -> AnyIterator<Term>
    private let _makeIterator: () -> AnyIterator<Quad>
    private let _results: (QuadPattern) throws -> AnyIterator<TermResult>
    private let _quads: (QuadPattern) throws -> AnyIterator<Quad>
    private let _effectiveVersion: (QuadPattern) throws -> Version?
    private let _graphDescriptions: () -> [Term:GraphDescription]
    private let _features: () -> [QuadStoreFeature]
    private let _load: (Version, AnySequence<Quad>) throws -> ()
    private let _plan: (Algebra, Term, Dataset) throws -> QueryPlan?

    init<Q: MutableQuadStoreProtocol>(_ value: Q) {
        self._store = value
        self._count = { value.count }
        self._graphs = value.graphs
        self._graphTerms = value.graphTerms
        self._makeIterator = value.makeIterator
        self._results = value.results
        self._quads = value.quads
        self._effectiveVersion = value.effectiveVersion
        self._graphDescriptions = { value.graphDescriptions }
        self._features = { value.features }
        self._load = { try value.load(version: $0, quads: $1) }
        if let pqs = value as? PlanningQuadStore {
            self._plan = pqs.plan
        } else {
            self._plan = { (_, _, _) -> QueryPlan? in return nil }
        }
    }
    
    public var count : Int { return _count() }
    
    public func graphs() -> AnyIterator<Term> {
        return _graphs()
    }
    
    public func graphTerms(in graph: Term) -> AnyIterator<Term> {
        return _graphTerms(graph)
    }
    
    public func makeIterator() -> AnyIterator<Quad> {
        return _makeIterator()
    }
    
    public func results(matching pattern: QuadPattern) throws -> AnyIterator<TermResult> {
        return try _results(pattern)
    }
    
    public func quads(matching pattern: QuadPattern) throws -> AnyIterator<Quad> {
        return try _quads(pattern)
    }
    
    public func effectiveVersion(matching pattern: QuadPattern) throws -> Version? {
        return try _effectiveVersion(pattern)
    }
    
    public func load<S>(version: Version, quads: S) throws where S : Sequence, S.Element == Quad {
        return try _load(version, AnySequence(quads))
    }

    public func plan(algebra: Algebra, activeGraph: Term, dataset: Dataset) throws -> QueryPlan? {
        return try _plan(algebra, activeGraph, dataset)
    }
}
