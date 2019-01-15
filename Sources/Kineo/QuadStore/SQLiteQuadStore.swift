//
//  SQLiteQuadStore.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 1/11/19.
//

import Foundation
import SQLite
import struct SPARQLSyntax.Namespace
import struct SPARQLSyntax.Term
import struct SPARQLSyntax.Quad
import struct SPARQLSyntax.QuadPattern
import enum SPARQLSyntax.TermDataType
import enum SPARQLSyntax.Node

// swiftlint:disable:next type_body_length
open class SQLiteQuadStore: Sequence, MutableQuadStoreProtocol {
    typealias TermID = Int64
    let schemaVersion : Int64 = 1
    let sysTable = SQLite.Table("kineo_sys")
    let versionColumn = Expression<Int64>("dataset_version")
    let schemaVersionColumn = Expression<Int64>("schema_version")

    let quadsTable = SQLite.Table("quads")
    let subjColumn = Expression<Int64>("subject")
    let predColumn = Expression<Int64>("predicate")
    let objColumn = Expression<Int64>("object")
    let graphColumn = Expression<Int64>("graph")

    let termsTable = SQLite.Table("terms")
    let idColumn = Expression<Int64>("id")
    let termValueColumn = Expression<String>("value")
    let termTypeColumn = Expression<Int64>("type")
    let termDatatypeColumn = Expression<Int64?>("datatype")
    let termLangColumn = Expression<String?>("language")

    public enum SQLiteQuadStoreError: Error {
        case idAssignmentError
    }
    
    internal enum TermType: Int64 {
        case blank = 1
        case iri = 2
        case literal = 3
    }
    
    public var count: Int {
        let count = try? db.scalar(quadsTable.count)
        return count ?? 0
    }
    
    var db: Connection
    var t2icache: LRUCache<Term, TermID>
    var i2tcache: LRUCache<TermID, Term>

    public init(filename: String, initialize: Bool = false) throws {
        db = try Connection(filename)
        i2tcache = LRUCache(capacity: 1024)
        t2icache = LRUCache(capacity: 1024)
        if initialize {
            try initializeTables()
        }
    }
    
    internal func initializeTables() throws {
        try db.run(sysTable.create { t in     // CREATE TABLE "kineo_sys" (
            t.column(idColumn, primaryKey: .autoincrement) //     "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            t.column(schemaVersionColumn) //     "schema_version" INTEGER NOT NULL,
            t.column(versionColumn) //     "dataset_version" INTEGER NOT NULL,
            // )
        })
        
        try db.run(quadsTable.create { t in     // CREATE TABLE "quads" (
            t.column(subjColumn) //     "subject" INTEGER NOT NULL,
            t.column(predColumn) //     "predicate" INTEGER NOT NULL,
            t.column(objColumn) //     "object" INTEGER NOT NULL,
            t.column(graphColumn) //     "graph" INTEGER NOT NULL,
            t.unique([subjColumn, predColumn, objColumn, graphColumn]) // UNIQUE("subject", "predicate", "object", "graph")
            // )
        })
        try db.run(quadsTable.createIndex(graphColumn))
        try db.run(quadsTable.createIndex(predColumn, objColumn, graphColumn, subjColumn))

        try db.run(termsTable.create { t in     // CREATE TABLE "terms" (
            t.column(idColumn, primaryKey: .autoincrement) //     "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            t.column(termTypeColumn) //     "type" INTEGER NOT NULL,
            t.column(termValueColumn) //     "value" TEXT NOT NULL,
            t.column(termDatatypeColumn, references: termsTable, idColumn) //     "datatype" INTEGER NULL REFERENCES terms(id),
            t.column(termLangColumn) //     "language" TEXT NULL,
            t.unique([termValueColumn, termTypeColumn, termDatatypeColumn, termLangColumn]) // UNIQUE("type", "value", "datatype", "language")
            // )
        })
        try db.run(termsTable.createIndex(termTypeColumn))
        try db.run(termsTable.createIndex(termValueColumn))
        try db.run(termsTable.createIndex(termLangColumn))
        
        let iris = [
            Namespace.rdf.type,
            Namespace.rdf.langString,
            Namespace.rdf.List,
            Namespace.rdf.Resource,
            Namespace.rdf.first,
            Namespace.rdf.rest,
            Namespace.rdf.nil,
            Namespace.xsd.string,
            Namespace.xsd.integer,
            Namespace.xsd.decimal,
            Namespace.xsd.double,
            Namespace.xsd.float
        ]

        try db.transaction {
            try db.run(sysTable.insert(or: .replace,
                                       idColumn <- 0,
                                       schemaVersionColumn <- schemaVersion,
                                       versionColumn <- 0
            ))
            
            for iri in iris {
                try db.run(termsTable.insert(
                    termTypeColumn <- TermType.iri.rawValue,
                    termValueColumn <- iri
                ))
            }
        }
    }
    
    public init(version: Version? = nil) throws {
        db = try Connection()
        i2tcache = LRUCache(capacity: 1024)
        t2icache = LRUCache(capacity: 1024)
        try initializeTables()
        if let v = version {
            try db.run(sysTable.update(versionColumn <- Int64(v)))
        }
    }
    
    public func graphs() -> AnyIterator<Term> {
        let query = quadsTable.select(distinct: graphColumn)
        do {
            let dbh = try db.prepare(query)
            let graphs = dbh.compactMap { (row) -> Term? in
                return term(for: row[graphColumn])
            }
            return AnyIterator(graphs.makeIterator())
        } catch {
            return AnyIterator { return nil }
        }
    }
    
    public func graphTerms(in graph: Term) -> AnyIterator<Term> {
        guard let gid = id(for: graph) else {
            return AnyIterator { return nil }
        }
        let subjects = quadsTable.select(distinct: subjColumn).filter(graphColumn == gid)
        let objects = quadsTable.select(distinct: objColumn).filter(graphColumn == gid)
        do {
            var ids = Set<Int64>()
            for row in try db.prepare(subjects) {
                ids.insert(row[subjColumn])
            }
            for row in try db.prepare(objects) {
                ids.insert(row[objColumn])
            }
            let terms = ids.compactMap { (id) -> Term? in
                return term(for: id)
            }
            return AnyIterator(terms.makeIterator())
        } catch {
            return AnyIterator { return nil }
        }
    }
    
    internal func assignID(for term: Term) throws -> TermID {
        if let i = id(for: term) {
//            print("term already has ID: \(i) <-> \(term)")
            return i
        }
        
//        print("assigning ID for \(term)")
        let insert: Insert
        switch term.type {
        case .iri:
            insert = termsTable.insert(termTypeColumn <- TermType.iri.rawValue, termValueColumn <- term.value)
        case .blank:
            insert = termsTable.insert(termTypeColumn <- TermType.blank.rawValue, termValueColumn <- term.value)
        case .language(let lang):
            insert = termsTable.insert(
                termTypeColumn <- TermType.literal.rawValue,
                termValueColumn <- term.value,
                termDatatypeColumn <- id(for: Term(iri: Namespace.rdf.langString)),
                termLangColumn <- lang)
        case .datatype(let dt):
            insert = try termsTable.insert(
                termTypeColumn <- TermType.literal.rawValue,
                termValueColumn <- term.value,
                termDatatypeColumn <- assignID(for: Term(iri: dt.value)))
        }
//        print("INSERT: \(insert)")
        try db.run(insert)
        guard let i = id(for: term) else {
            throw SQLiteQuadStoreError.idAssignmentError
        }
        return i
    }
    
    internal func id(for term: Term) -> TermID? {
        if let i = t2icache[term] {
            return i
        }
        
        var query = termsTable.select(idColumn).filter(termValueColumn == term.value)
        switch term.type {
        case .blank:
            query = query.filter(termTypeColumn == TermType.blank.rawValue)
        case .iri:
            query = query.filter(termTypeColumn == TermType.iri.rawValue)
        case .language(let lang):
            query = query.filter(termTypeColumn == TermType.literal.rawValue).filter(termLangColumn == lang)
        case .datatype(let dt):
            guard let dtid = id(for: Term(iri: dt.value)) else {
                return nil
            }
            query = query.filter(termTypeColumn == TermType.literal.rawValue).filter(termDatatypeColumn == dtid)
        }
        
        do {
            guard let row = try db.pluck(query) else {
//                print("============")
//                print("Failed to find row for term: \(term)")
//                print("\(query)")
//                print("------------")
                return nil
            }
            let i = row[idColumn]
            t2icache[term] = i
            return i
        } catch {}
        return nil
    }
    
    internal func term(for id: TermID) -> Term? {
        if let t = i2tcache[id] {
            return t
        }
        
        let query = termsTable.select(termsTable[*]).filter(idColumn == id)
        do {
            guard let row = try db.pluck(query) else {
                return nil
            }
            guard let type = TermType(rawValue: row[termTypeColumn]) else {
                return nil
            }
            
            let value = row[termValueColumn]
            switch type {
            case .iri:
                let t = Term(iri: value)
                i2tcache[id] = t
                return t
            case .blank:
                let t = Term(value: value, type: .blank)
                i2tcache[id] = t
                return t
            case .literal:
                guard let datatypeID = row[termDatatypeColumn] else {
                    return nil
                }
                guard let dtTerm = term(for: datatypeID) else {
                    return nil
                }
                let dt = dtTerm.value
                if dt == Namespace.rdf.langString {
                    guard let lang = row[termLangColumn] else {
                        return nil
                    }
                    let t = Term(value: value, type: .language(lang))
                    i2tcache[id] = t
                    return t
                } else {
                    let t = Term(value: value, type: .datatype(TermDataType(stringLiteral: dt)))
                    i2tcache[id] = t
                    return t
                }
            }
        } catch {}
        return nil
    }
    
    public func makeIterator() -> AnyIterator<Quad> {
        let query = quadsTable.select(quadsTable[*])
        guard let dbh = try? db.prepare(query) else {
            return AnyIterator { return nil }
        }
        let quads = dbh.compactMap { (row) -> Quad? in
            guard let s = term(for: row[subjColumn]) else { return nil }
            guard let p = term(for: row[predColumn]) else { return nil }
            guard let o = term(for: row[objColumn]) else { return nil }
            guard let g = term(for: row[graphColumn]) else { return nil }
            return Quad(subject: s, predicate: p, object: o, graph: g)
        }
        return AnyIterator(quads.makeIterator())
    }
    
    public func results(matching pattern: QuadPattern) throws -> AnyIterator<TermResult> {
        var query = quadsTable.select(quadsTable[*])
        
        let quadPatternKeyPaths : [KeyPath<QuadPattern, Node>] = [\.subject, \.predicate, \.object, \.graph]
        let quadColumns = [subjColumn, predColumn, objColumn, graphColumn]
        var mapping = [String: [Expression<Int64>]]()
        for (qpkp, col) in zip(quadPatternKeyPaths, quadColumns) {
            switch pattern[keyPath: qpkp] {
            case .bound(let t):
                guard let id = id(for: t) else {
                    return AnyIterator { return nil }
                }
                query = query.filter(col == id)
            case let .variable(name, binding: true):
                mapping[name, default: []].append(col)
            default:
                break
            }
        }
        
        guard let dbh = try? db.prepare(query) else {
            return AnyIterator { return nil }
        }
        let results = dbh.lazy.compactMap { (row) -> TermResult? in
            var bindings = [String: Term]()
            for (name, cols) in mapping {
                if cols.count == 1 {
                    let col = cols.first!
                    let id = row[col]
                    guard let t = self.term(for: id) else { return nil }
                    bindings[name] = t
                } else {
                    let ids = cols.map { row[$0] }
                    let terms = ids.compactMap { self.term(for: $0) }
                    guard terms.count == cols.count else { return nil }
                    if let t = terms.first {
                        guard terms.allSatisfy({ t == $0 }) else {
                            return nil
                        }
                        bindings[name] = t
                    } else {
                        continue
                    }
                }
            }
            return TermResult(bindings: bindings)
        }
        return AnyIterator(results.makeIterator())
    }
    
    public func quads(matching pattern: QuadPattern) throws -> AnyIterator<Quad> {
        var query = quadsTable.select(quadsTable[*])
        
        let quadPatternKeyPaths : [KeyPath<QuadPattern, Node>] = [\.subject, \.predicate, \.object, \.graph]
        let quadColumns = [subjColumn, predColumn, objColumn, graphColumn]
        for (qpkp, col) in zip(quadPatternKeyPaths, quadColumns) {
            switch pattern[keyPath: qpkp] {
            case .bound(let t):
                guard let id = id(for: t) else {
                    return AnyIterator { return nil }
                }
                query = query.filter(col == id)
            default:
                break
            }
        }
        
        guard let dbh = try? db.prepare(query) else {
            return AnyIterator { return nil }
        }
        let quads = dbh.lazy.compactMap { (row) -> Quad? in
            guard let s = self.term(for: row[self.subjColumn]) else { return nil }
            guard let p = self.term(for: row[self.predColumn]) else { return nil }
            guard let o = self.term(for: row[self.objColumn]) else { return nil }
            guard let g = self.term(for: row[self.graphColumn]) else { return nil }
            return Quad(subject: s, predicate: p, object: o, graph: g)
        }
        return AnyIterator(quads.makeIterator())
    }
    
    public func effectiveVersion(matching pattern: QuadPattern) throws -> Version? {
        let query = sysTable.select(versionColumn)
        guard let row = try db.pluck(query) else { return nil }
        let v = row[versionColumn]
        return Version(v)
    }
    
    public func load<S: Sequence>(version: Version, quads: S) throws where S.Iterator.Element == Quad {
        try db.transaction {
            for q in quads {
                let sid = try assignID(for: q.subject)
                let pid = try assignID(for: q.predicate)
                let oid = try assignID(for: q.object)
                let gid = try assignID(for: q.graph)
                try db.run(quadsTable.insert(or: .ignore, subjColumn <- sid, predColumn <- pid, objColumn <- oid, graphColumn <- gid))
            }
            try db.run(sysTable.update(versionColumn <- Int64(version)))
        }
    }
}

extension SQLiteQuadStore: CustomStringConvertible {
    public var description: String {
        let s = "SQLiteQuadStore { \(db) }\n"
        return s
    }
}
