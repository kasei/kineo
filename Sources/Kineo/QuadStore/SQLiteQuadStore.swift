//
//  SQLiteQuadStore.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 1/11/19.
//

import Foundation
import SPARQLSyntax
import SQLite

public struct SQLitePlan: NullaryQueryPlan {
    var query: SQLite.Table
    var projected: [String: SQLite.Expression<Int64>]
    var store: SQLiteQuadStore
    public var selfDescription: String { return "SQLite Plan { \(query.expression.template) : \(query.expression.bindings) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        let store = self.store
        guard let dbh = try? store.db.prepare(query) else {
            return AnyIterator { return nil }
        }
        let projected = self.projected
        let results = dbh.lazy.compactMap { (row) -> TermResult? in
            do {
                let d = try projected.map({ (name, id) throws -> (String, Term) in
                    guard let t = store.term(for: row[id]) else {
                        throw SQLiteQuadStore.SQLiteQuadStoreError.idAccessError
                    }
                    return (name, t)
                })
                let r = TermResult(bindings: Dictionary(uniqueKeysWithValues: d))
                return r
            } catch {
                return nil
            }
        }
        return AnyIterator(results.makeIterator())
    }
}

public struct SQLitePreparedPlan: NullaryQueryPlan {
    var dbh: SQLite.Statement
    var projected: [String: String]
    var store: SQLiteQuadStore
    public var selfDescription: String { return "SQLite Prepared Plan { \(dbh) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        let projected = self.projected
        let map = Dictionary(uniqueKeysWithValues: dbh.columnNames.enumerated().map { ($1, $0) })
        let store = self.store
        let results = dbh.lazy.compactMap { (row) -> TermResult? in
            do {
                let d = try projected.map({ (name, colName) throws -> (String, Term) in
                    guard let i = map[colName], let id : Int64 = row[i] as? Int64, let t = store.term(for: id) else {
                        throw SQLiteQuadStore.SQLiteQuadStoreError.idAccessError
                    }
                    return (name, t)
                })
                let r = TermResult(bindings: Dictionary(uniqueKeysWithValues: d))
                return r
            } catch {
                return nil
            }
        }
        return AnyIterator(results.makeIterator())
    }
}

public struct SQLiteSingleIntegerAggregationPlan<D: Value>: NullaryQueryPlan {
    var query: SQLite.Table
    var aggregateColumn: SQLite.Expression<D>
    var aggregateName: String
    var projected: [String: SQLite.Expression<Int64>]
    var store: SQLiteQuadStore
    public var selfDescription: String { return "SQLite Aggregation Plan { \(aggregateColumn) AS \(aggregateName) : \(query.expression.template) : \(query.expression.bindings) }" }
    public func evaluate() throws -> AnyIterator<TermResult> {
        let store = self.store
        guard let dbh = try? store.db.prepare(query) else {
            return AnyIterator { return nil }
        }
        let projected = self.projected
        let aggregateColumn = self.aggregateColumn
        let aggregateName = self.aggregateName
        let results = dbh.lazy.compactMap { (row : Row) -> TermResult? in
            do {
                let aggValue: D? = try row.get(aggregateColumn)
                var d = try projected.map({ (name, id) throws -> (String, Term) in
                    guard let t = store.term(for: row[id]) else {
                        throw SQLiteQuadStore.SQLiteQuadStoreError.idAccessError
                    }
                    return (name, t)
                })
                if let value = aggValue as? Int {
                    d.append((aggregateName, Term(integer: value)))
                }
                let r = TermResult(bindings: Dictionary(uniqueKeysWithValues: d))
                return r
            } catch {
                return nil
            }
        }
        return AnyIterator(results.makeIterator())
    }
}


// swiftlint:disable:next type_body_length
open class SQLiteQuadStore: Sequence, MutableQuadStoreProtocol {
    typealias TermID = Int64
    let schemaVersion : Int64 = 1
    let sysTable = SQLite.Table("kineo_sys")
    let versionColumn = SQLite.Expression<Int64>("dataset_version")
    let schemaVersionColumn = SQLite.Expression<Int64>("schema_version")

    let quadsTable = SQLite.Table("quads")
    let subjColumn = SQLite.Expression<Int64>("subject")
    let predColumn = SQLite.Expression<Int64>("predicate")
    let objColumn = SQLite.Expression<Int64>("object")
    let graphColumn = SQLite.Expression<Int64>("graph")

    let termsTable = SQLite.Table("terms")
    let idColumn = SQLite.Expression<Int64>("id")
    let termValueColumn = SQLite.Expression<String>("value")
    let termTypeColumn = SQLite.Expression<Int64>("type")
    let termDatatypeColumn = SQLite.Expression<Int64?>("datatype")
    let termLangColumn = SQLite.Expression<String?>("language")

    public enum SQLiteQuadStoreError: Error {
        case idAssignmentError
        case idAccessError
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
//        db.trace {
//            print($0)
//        }
        i2tcache = LRUCache(capacity: 1024)
        t2icache = LRUCache(capacity: 1024)
        if initialize {
            try initializeTables()
        }
    }
    
    public init(version: Version? = nil) throws {
        db = try Connection()
//        db.trace {
//            print($0)
//        }
        i2tcache = LRUCache(capacity: 1024)
        t2icache = LRUCache(capacity: 1024)
        try initializeTables()
        if let v = version {
            try db.run(sysTable.update(versionColumn <- Int64(v)))
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
        try db.run(quadsTable.createIndex(graphColumn, predColumn, objColumn, subjColumn))

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
                    let t = Term(canonicalValue: value, type: .language(lang))
                    i2tcache[id] = t
                    return t
                } else {
                    let t = Term(canonicalValue: value, type: .datatype(TermDataType(stringLiteral: dt)))
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
        var mapping = [String: [SQLite.Expression<Int64>]]()
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

extension SQLiteQuadStore: PlanningQuadStore {
    public func plan(algebra: Algebra, activeGraph: Term, dataset: Dataset) throws -> QueryPlan? {
        switch algebra {
        case let .project(a, vars):
            if let qp = try plan(algebra: a, activeGraph: activeGraph, dataset: dataset) {
                if let q = qp as? SQLitePlan {
                    let query = q.query
                    let projected = q.projected
                    let d = query.select(distinct: vars.compactMap { projected[$0] })
                    let p = projected.filter { vars.contains($0.key) }
                    return SQLitePlan(query: d, projected: p, store: self)
                }
            }
            return nil
        case .distinct(let a):
            if let qp = try plan(algebra: a, activeGraph: activeGraph, dataset: dataset) {
                if let q = qp as? SQLitePlan {
                    let query = q.query
                    let projected = q.projected
                    let d = query.select(distinct: Array(projected.values))
                    return SQLitePlan(query: d, projected: projected, store: self)
                }
            }
            return nil
        case .quad(let qp):
            let (q, projected, _) = try query(quad: qp, alias: "t")
            return SQLitePlan(query: q, projected: projected, store: self)
        case .triple(let t):
            return try plan(bgp: [t], activeGraph: activeGraph)
        case .bgp(let triples):
            return try plan(bgp: triples, activeGraph: activeGraph)
        case let .aggregate(a, groups, aggs) where aggs.count == 1:
            guard groups.allSatisfy({ if case .node(.variable(_)) = $0 { return true } else { return false } }) else {
                return nil
            }
            let agg = aggs.first!
            // this is a single aggregation, grouped by only simple variables
            let groupVars = groups.compactMap { (e) -> String? in
                if case .node(.variable(let name, _)) = e {
                    return name
                }
                return nil
            }
            if case .countAll = agg.aggregation {
                if let qp = try plan(algebra: a, activeGraph: activeGraph, dataset: dataset) {
                    if let q = qp as? SQLitePlan {
                        let query = q.query
                        let projected = q.projected.filter { groupVars.contains($0.key) }
                        var d = query
                        if !projected.isEmpty {
                            d = d.group(Array(projected.values))
                        }
                        let aggCol = SQLite.Expression<Int>(literal: "COUNT(*)")
                        d = d.select(Array(projected.values) + [aggCol])
                        return SQLiteSingleIntegerAggregationPlan(
                            query: d,
                            aggregateColumn: aggCol,
                            aggregateName: agg.variableName,
                            projected: projected,
                            store: self
                        )
                    }
                }
            }
        case let .path(.bound(sTerm), .plus(.link(p)), .variable(oname, binding: true)):
            let path : PropertyPath = .plus(.link(p))
            guard let sid = id(for: sTerm), let gid = id(for: activeGraph) else {
                return nil
            }
            let pathTable = "pp"
            let (ppsql, ppbindings) = try pathQuery(path, in: gid, tableName: pathTable)
            let sql = "WITH RECURSIVE \(pathTable)(subject, object, graph) AS (\(ppsql)) SELECT DISTINCT subject, object, graph FROM \(pathTable) WHERE subject = ? AND graph = ?"
            let bindings = ppbindings + [sid, gid]
            let dbh = try db.prepare(sql, bindings)
            return SQLitePreparedPlan(dbh: dbh, projected: [oname: "object"], store: self)
        case let .path(.bound(sTerm), .star(.link(p)), .variable(oname, binding: true)):
            let path : PropertyPath = .star(.link(p))
            guard let sid = id(for: sTerm), let gid = id(for: activeGraph) else {
                return nil
            }
            let pathTable = "pp"
            let (ppsql, ppbindings) = try pathQuery(path, in: gid, tableName: pathTable)
            let sql = "WITH RECURSIVE \(pathTable)(subject, object, graph) AS (\(ppsql)) SELECT DISTINCT subject, object, graph FROM \(pathTable) WHERE subject = ? AND graph = ? UNION ALL VALUES(?, ?, ?)"
            let bindings = ppbindings + [sid, gid, sid, sid, gid]
            let dbh = try db.prepare(sql, bindings)
            return SQLitePreparedPlan(dbh: dbh, projected: [oname: "object"], store: self)
        case let .path(.variable(sname, binding: true), .star(.link(p)), .variable(oname, binding: true)):
            let path : PropertyPath = .star(.link(p))
            guard let gid = id(for: activeGraph) else {
                return nil
            }
            let pathTable = "pp"
            let (ppsql, ppbindings) = try pathQuery(path, in: gid, tableName: pathTable)
            let sql = "WITH RECURSIVE \(pathTable)(subject, object, graph) AS (\(ppsql)) SELECT DISTINCT subject, object, graph FROM \(pathTable) UNION SELECT DISTINCT subject, subject, graph FROM quads WHERE graph = ? UNION SELECT DISTINCT object, object, graph FROM quads WHERE graph = ?"
            let bindings = ppbindings + [gid, gid]
            let dbh = try db.prepare(sql, bindings)
            return SQLitePreparedPlan(dbh: dbh, projected: [sname: "subject", oname: "object"], store: self)
        default:
            return nil
        }
        return nil
    }
    
    private func pathQuery(_ path: PropertyPath, in gid: TermID, tableName: String) throws -> (String, [Binding?]) {
        var q: SQLite.Table
        switch path {
        case .link(let p):
            guard let pid = id(for: p) else {
                throw SQLiteQuadStoreError.idAccessError
            }
            let columns : [Expressible] = [subjColumn, objColumn, graphColumn]
            q = quadsTable.select(columns).filter(predColumn == pid).filter(graphColumn == gid)
            let e = q.expression
            return (e.template, e.bindings)
        case .plus(let pp), .star(let pp):
            let (ppsql, bindings) = try pathQuery(pp, in: gid, tableName: tableName)
            let sql = """
            \(ppsql) UNION SELECT k.subject, q.object, q.graph FROM (\(ppsql)) q JOIN \(tableName) k WHERE k.object = q.subject AND q.graph = k.graph
            """
            return (sql, bindings + bindings)
        default:
            fatalError()
        }
        /**
        WITH RECURSIVE
         knowsPlus(subject, object, graph) AS (
            SELECT subject, object, graph
                FROM quads
                WHERE predicate = 14
            UNION ALL
            SELECT q.subject, k.object, k.graph
                FROM quads q JOIN knowsPlus k
                WHERE q.object = k.subject AND q.graph = k.graph
         )
         SELECT DISTINCT * FROM knowsPlus WHERE subject = 13;
         **/
    }
    
    private func plan(bgp: [TriplePattern], activeGraph: Term) throws -> QueryPlan? {
//        let seq = sequence(first: 0) { $0 + 1 }
        if bgp.isEmpty {
            return TablePlan.joinIdentity
        } else if bgp.count == 1 {
            let tp = bgp.first!
            let qp = QuadPattern(triplePattern: tp, graph: .bound(activeGraph))
            let (q, projected, _) = try query(quad: qp, alias: "t")
            return SQLitePlan(query: q, projected: projected, store: self)
        } else {
            let tp = bgp.first!
            let qp = QuadPattern(triplePattern: tp, graph: .bound(activeGraph)).bindingAllVariables
            var (bgpQuery, projected, mapping) = try query(quad: qp, alias: "t")
            for (i, tp) in bgp.dropFirst().enumerated() {
                let qp = QuadPattern(triplePattern: tp, graph: .bound(activeGraph)).bindingAllVariables
                let (q, p, m) = try query(quad: qp, alias: "t\(i)")
                let joinVars = Set(m.keys).intersection(mapping.keys)
                var joinExpression = SQLite.Expression<Bool>(value: true)
                for v in joinVars {
                    if let ll = m[v], let lhs = ll.first, let rr = mapping[v], let rhs = rr.first {
//                        print("Add join condition on \(v) between \(lhs) and \(rhs)")
                        joinExpression = joinExpression && (lhs == rhs)
                    }
                }
                for (name, cols) in m {
                    mapping[name, default: []].append(contentsOf: cols)
                }
                
                projected.merge(p) { $1 }
                bgpQuery = bgpQuery.join(q, on: joinExpression)
            }
            
            let inscope = Algebra.bgp(bgp).inscope
            let bound = Set(projected.keys)
            if inscope != bound {
                // we need to remove the variables that were bound only for the purpose of joining the quad patterns
                for remove in bound.filter({ !inscope.contains($0) }) {
//                    print("removing projection for ?\(remove)")
                    projected.removeValue(forKey: remove)
                }
            }

            bgpQuery = bgpQuery.select(Array(projected.values))
            return SQLitePlan(query: bgpQuery, projected: projected, store: self)
        }
    }
    
    func query(quad qp: QuadPattern, alias: String) throws -> (SQLite.Table, [String: SQLite.Expression<Int64>], [String: [SQLite.Expression<Int64>]]) {
        let nodes = [qp.subject, qp.predicate, qp.object, qp.graph]
        var projected = [String: SQLite.Expression<Int64>]()
        var mapping = [String: [SQLite.Expression<Int64>]]()
        let tt = quadsTable.alias(alias)
        if case .variable(let name, true) = nodes[0] { projected[name] = tt[subjColumn]; mapping[name, default: []].append(tt[subjColumn]) }
        if case .variable(let name, true) = nodes[1] { projected[name] = tt[predColumn]; mapping[name, default: []].append(tt[predColumn]) }
        if case .variable(let name, true) = nodes[2] { projected[name] = tt[objColumn]; mapping[name, default: []].append(tt[objColumn]) }
        if case .variable(let name, true) = nodes[3] { projected[name] = tt[graphColumn]; mapping[name, default: []].append(tt[graphColumn]) }
        var q = projected.isEmpty ? tt : tt.select(Array(projected.values))
        
        for columns in mapping.values.filter({ $0.count > 1 }) {
            if let first = columns.first {
                q = columns.dropFirst().reduce(q, { (q, col) -> SQLite.Table in
                    q.filter(first == col)
                })
            }
        }
        
        if case .bound(let t) = nodes[0] {
            guard let sid = id(for: t) else { throw SQLiteQuadStoreError.idAccessError }
            q = q.filter(tt[subjColumn] == sid)
        }
        if case .bound(let t) = nodes[1] {
            guard let pid = id(for: t) else { throw SQLiteQuadStoreError.idAccessError }
            q = q.filter(tt[predColumn] == pid)
        }
        if case .bound(let t) = nodes[2] {
            guard let oid = id(for: t) else { throw SQLiteQuadStoreError.idAccessError }
            q = q.filter(tt[objColumn] == oid)
        }
        if case .bound(let t) = nodes[3] {
            guard let gid = id(for: t) else { throw SQLiteQuadStoreError.idAccessError }
            q = q.filter(tt[graphColumn] == gid)
        }
        return (q, projected, mapping)
    }
}
