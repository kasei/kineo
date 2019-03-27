//
//  StoreConfiguration.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 10/9/18.
//

import Foundation
import SPARQLSyntax

public enum StoreConfigurationError: Error {
    case unsupportedConfiguration(String)
}

public struct QuadStoreConfiguration {
    public enum StoreType {
        case memoryDatabase
        case filePageDatabase(String)
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
            case "-f":
                type = .filePageDatabase(args.remove(at: index))
            case _ where arg.hasPrefix("--file="):
                let filename = String(arg.dropFirst(7))
                type = .filePageDatabase(filename)
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

    public func withStore(_ handler: (QuadStoreProtocol) throws -> ()) throws {
        switch type {
        case .sqliteFileDatabase(let filename):
            let fileManager = FileManager.default
            let initialize = !fileManager.fileExists(atPath: filename)
            let store = try SQLiteQuadStore(filename: filename, initialize: initialize)
            if languageAware {
                let lstore = SQLiteLanguageQuadStore(quadstore: store, acceptLanguages: acceptLanguages)
                try handler(lstore)
            } else {
                try handler(store)
            }
        case .sqliteMemoryDatabase:
            let store = try SQLiteQuadStore()
            if languageAware {
                let acceptLanguages = [("*", 1.0)] // can be changed later
                let lstore = SQLiteLanguageQuadStore(quadstore: store, acceptLanguages: acceptLanguages)
                try handler(lstore)
            } else {
                try handler(store)
            }
        case .memoryDatabase:
            let store = MemoryQuadStore()
            if languageAware {
                let acceptLanguages = [("*", 1.0)] // can be changed later
                let lstore = LanguageMemoryQuadStore(quadstore: store, acceptLanguages: acceptLanguages)
                try handler(lstore)
            } else {
                try handler(store)
            }
        case .filePageDatabase(let filename):
            let pageSize = 8192 // TODO: read from the database file
            guard let database = FilePageDatabase(filename, size: pageSize) else {
                warn("Failed to open database file '\(filename)'")
                exit(1)
            }
            if languageAware {
                let acceptLanguages = [("*", 1.0)] // can be changed later
                let store = try LanguagePageQuadStore(database: database, acceptLanguages: acceptLanguages)
                try handler(store)
            } else {
                let store = try PageQuadStore(database: database)
                try handler(store)
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
}

