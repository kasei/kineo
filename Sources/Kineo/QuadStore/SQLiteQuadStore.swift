//
//  SQLiteQuadStore.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 1/11/19.
//

import Foundation
import SPARQLSyntax
import SQLite

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
        do {
            let count = try db.scalar(quadsTable.count)
            print("SQLiteQuadStore count: \(count)")
            return count
        } catch let error {
            print("*** SQLiteQuadStore.count error: \(error)")
            return 0
        }
    }
    
    var cachedGraphDescriptions: [Term:GraphDescription]?
    var db: Connection
    var t2icache: LRUCache<Term, TermID>
    var i2tcache: LRUCache<TermID, Term>
    var next: (iri: Int64, blank: Int64, datatype: Int64, language: Int64)

    public init(filename: String, initialize: Bool = false) throws {
        db = try Connection(filename)
//        db.trace {
//            print("[TRACE] \($0)")
//        }
        i2tcache = LRUCache(capacity: 1024)
        t2icache = LRUCache(capacity: 1024)
        cachedGraphDescriptions = nil
        if initialize {
            next = (iri: 0, blank: 0, datatype: 0, language: 0)
            try initializeTables()
        } else {
            next = try SQLiteQuadStore.loadMaxIDs(from: db)
        }
    }
    
    public init(version: Version? = nil) throws {
        db = try Connection()
//        db.trace {
//            print("[TRACE] \($0)")
//        }
        next = (iri: 0, blank: 0, datatype: 0, language: 0)
        i2tcache = LRUCache(capacity: 1024)
        t2icache = LRUCache(capacity: 1024)
        cachedGraphDescriptions = nil
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
        
        try db.run(quadsTable.create { t in         // CREATE TABLE "quads" (
            t.column(idColumn, primaryKey: true)    //     "id" INTEGER PRIMARY KEY NOT NULL
            t.column(subjColumn)                    //     "subject" INTEGER NOT NULL,
            t.column(predColumn)                    //     "predicate" INTEGER NOT NULL,
            t.column(objColumn)                     //     "object" INTEGER NOT NULL,
            t.column(graphColumn)                   //     "graph" INTEGER NOT NULL,
            t.unique([
                subjColumn,
                predColumn,
                objColumn,
                graphColumn]
            )                                       // UNIQUE("subject", "predicate", "object", "graph")
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
                let _ = try getOrSetID(for: Term(iri: iri))
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
    
//    internal func assignID(for term: Term) throws -> TermID {
//        if let i = id(for: term) {
////            print("term already has ID: \(i) <-> \(term)")
//            return i
//        }
//
////        print("assigning ID for \(term)")
//        let insert: Insert
//        switch term.type {
//        case .iri:
//            insert = termsTable.insert(termTypeColumn <- TermType.iri.rawValue, termValueColumn <- term.value)
//        case .blank:
//            insert = termsTable.insert(termTypeColumn <- TermType.blank.rawValue, termValueColumn <- term.value)
//        case .language(let lang):
//            insert = termsTable.insert(
//                termTypeColumn <- TermType.literal.rawValue,
//                termValueColumn <- term.value,
//                termDatatypeColumn <- id(for: Term(iri: Namespace.rdf.langString)),
//                termLangColumn <- lang)
//        case .datatype(let dt):
//            insert = try termsTable.insert(
//                termTypeColumn <- TermType.literal.rawValue,
//                termValueColumn <- term.value,
//                termDatatypeColumn <- assignID(for: Term(iri: dt.value)))
//        }
////        print("INSERT: \(insert)")
//        try db.run(insert)
//        guard let i = id(for: term) else {
//            throw SQLiteQuadStoreError.idAssignmentError
//        }
//        return i
//    }
    
//    internal func id(for term: Term) -> TermID? {
//        if let i = t2icache[term] {
//            return i
//        }
//
//        var query = termsTable.select(idColumn).filter(termValueColumn == term.value)
//        switch term.type {
//        case .blank:
//            query = query.filter(termTypeColumn == TermType.blank.rawValue)
//        case .iri:
//            query = query.filter(termTypeColumn == TermType.iri.rawValue)
//        case .language(let lang):
//            query = query.filter(termTypeColumn == TermType.literal.rawValue).filter(termLangColumn == lang)
//        case .datatype(let dt):
//            guard let dtid = id(for: Term(iri: dt.value)) else {
//                return nil
//            }
//            query = query.filter(termTypeColumn == TermType.literal.rawValue).filter(termDatatypeColumn == dtid)
//        }
//
//        do {
//            guard let row = try db.pluck(query) else {
////                print("============")
////                print("Failed to find row for term: \(term)")
////                print("\(query)")
////                print("------------")
//                return nil
//            }
//            let i = row[idColumn]
//            t2icache[term] = i
//            return i
//        } catch {}
//        return nil
//    }

    internal func term(from row: Row, typeColumn: SQLite.Expression<Int64>, valueColumn: SQLite.Expression<String>, languageColumn: SQLite.Expression<String?>, datatypeColumn: SQLite.Expression<Int64?>) -> Term? {
        guard let type = TermType(rawValue: row[typeColumn]) else {
            return nil
        }
        
        let value = row[valueColumn]
        switch type {
        case .iri:
            let t = Term(iri: value)
            return t
        case .blank:
            let t = Term(value: value, type: .blank)
            return t
        case .literal:
            guard let datatypeID = row[datatypeColumn] else {
                return nil
            }
            guard let dtTerm = term(for: datatypeID) else {
                return nil
            }
            let dt = dtTerm.value
            if dt == Namespace.rdf.langString {
                guard let lang = row[languageColumn] else {
                    return nil
                }
                let t = Term(canonicalValue: value, type: .language(lang))
                return t
            } else {
                let t = Term(canonicalValue: value, type: .datatype(TermDataType(stringLiteral: dt)))
                return t
            }
        }
    }
    
//    internal func term(for id: TermID) -> Term? {
//        if let t = i2tcache[id] {
//            return t
//        }
//
//        let query = termsTable.select(termsTable[*]).filter(idColumn == id)
//        do {
//            guard let row = try db.pluck(query) else {
//                return nil
//            }
//            guard let t = term(from: row, typeColumn: termTypeColumn, valueColumn: termValueColumn, languageColumn: termLangColumn, datatypeColumn: termDatatypeColumn) else {
//                return nil
//            }
//            i2tcache[id] = t
//            return t
//        } catch {}
//        return nil
//    }
    
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
    
    func quadsQuery(matching pattern: QuadPattern) -> SQLite.Table? {
        var query = quadsTable.select(quadsTable[*])
        
        let quadPatternKeyPaths : [KeyPath<QuadPattern, Node>] = [\.subject, \.predicate, \.object, \.graph]
        let quadColumns = [subjColumn, predColumn, objColumn, graphColumn]
        for (qpkp, col) in zip(quadPatternKeyPaths, quadColumns) {
            switch pattern[keyPath: qpkp] {
            case .bound(let t):
                guard let id = id(for: t) else {
                    return nil
                }
                query = query.filter(col == id)
            default:
                break
            }
        }
        return query
    }
    
    public func quads(matching pattern: QuadPattern) throws -> AnyIterator<Quad> {
        guard let query = quadsQuery(matching: pattern) else {
            return AnyIterator { return  nil }
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
    
    public func countQuads(matching pattern: QuadPattern) throws -> Int {
        guard let query = quadsQuery(matching: pattern) else {
            throw QueryError.evaluationError("Failed to get count of matching quads from endpoint")
        }
        guard let dbh = try? db.prepare(query) else {
            throw QueryError.evaluationError("Failed to get count of matching quads from endpoint")
        }
        var count = 0
        for _ in dbh.lazy {
            count += 1
        }
        return count
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
                let sid = try getOrSetID(for: q.subject)
                let pid = try getOrSetID(for: q.predicate)
                let oid = try getOrSetID(for: q.object)
                let gid = try getOrSetID(for: q.graph)
                try db.run(quadsTable.insert(or: .ignore, subjColumn <- sid, predColumn <- pid, objColumn <- oid, graphColumn <- gid))
            }
            try db.run(sysTable.update(versionColumn <- Int64(version)))
        }
    }

    public func graphDescription(_ graph: Term, limit topK: Int) throws -> GraphDescription {
        guard let gid = id(for: graph) else {
            return GraphDescription(triplesCount: 0, isComplete: true, predicates: [], histograms: [])
        }

        let countDbh = try db.prepare("SELECT COUNT(*) FROM quads WHERE graph = ?", [gid])
        let rows = countDbh.compactMap { $0[0] as? Int64 }
        let count = Int(rows.first ?? 0)

        let sql = "SELECT COUNT(*) AS c, \(termValueColumn.template) AS p FROM quads JOIN terms ON (predicate = terms.id) WHERE quads.graph = ? GROUP BY \(predColumn.template) ORDER BY COUNT(*) DESC"
        do {
            let dbh = try db.prepare(sql, [gid])
            let map = Dictionary(uniqueKeysWithValues: dbh.columnNames.enumerated().map { ($1, $0) })
            let p = map["p"]!
            let c = map["c"]!
            let preds = dbh.lazy.compactMap { (row) -> (key: Term, value: Int)? in
                guard let pb = row[p], let pred = pb as? String, let cb = row[c], let count = cb as? Int64 else { return nil }
                return (key: Term(iri: pred), value: Int(count))
            }
            let topPreds = preds.prefix(topK)
            let predsSet = Set(topPreds.map { $0.key })
            let predBuckets = topPreds.map {
                GraphDescription.Histogram.Bucket(term: $0.key, count: $0.value)
            }
            
            let predHistogram = GraphDescription.Histogram(
                isComplete: false,
                position: .predicate,
                buckets: predBuckets
            )
            
            return GraphDescription(
                triplesCount: count,
                isComplete: false,
                predicates: predsSet,
                histograms: [predHistogram]
            )
        } catch {
            throw error
        }
    }

    public var graphDescriptions: [Term:GraphDescription] {
        if let d = cachedGraphDescriptions {
            return d
        } else {
            var descriptions = [Term:GraphDescription]()
            for g in graphs() {
                do {
                    descriptions[g] = try graphDescription(g, limit: Int.max)
                } catch {
                    print("*** \(error)")
                }
            }
            cachedGraphDescriptions = descriptions
            return descriptions
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
                    return SQLitePlan(query: d, distinct: true, projected: p, store: self)
                }
            }
            return nil
        case .distinct(let a):
            if let qp = try plan(algebra: a, activeGraph: activeGraph, dataset: dataset) {
                if let q = qp as? SQLitePlan {
                    let query = q.query
                    let projected = q.projected
                    let d = query.select(distinct: Array(projected.values))
                    return SQLitePlan(query: d, distinct: true, projected: projected, store: self)
                }
            }
            return nil
        case .quad(let qp):
            let (q, projected, _) = try query(quad: qp, alias: "t")
            return SQLitePlan(query: q, distinct: false, projected: projected, store: self)
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
            throw QueryPlanError.unexpectedError("pathQuery other than link, plus, or star")
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
        if bgp.isEmpty {
            return TablePlan.joinIdentity
        } else if bgp.count == 1 {
            let tp = bgp.first!
            let qp = QuadPattern(triplePattern: tp, graph: .bound(activeGraph))
            let (q, projected, _) = try query(quad: qp, alias: "t")
            return SQLitePlan(query: q, distinct: false, projected: projected, store: self)
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
                // remove the variables that were bound only for the purpose of joining the quad patterns
                for remove in bound.filter({ !inscope.contains($0) }) {
//                    print("removing projection for ?\(remove)")
                    projected.removeValue(forKey: remove)
                }
            }

            bgpQuery = bgpQuery.select(Array(projected.values))
            return SQLitePlan(query: bgpQuery, distinct: false, projected: projected, store: self)
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

open class SQLiteLanguageQuadStore: Sequence, LanguageAwareQuadStore, MutableQuadStoreProtocol {
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
    
    public var acceptLanguages: [(String, Double)]
    var quadstore: SQLiteQuadStore
    public var siteLanguageQuality: [String: Double]
    
    public init(quadstore: SQLiteQuadStore, acceptLanguages: [(String, Double)]) {
        print("SQLiteLanguageQuadStore.init called with acceptable languages: \(acceptLanguages)")
        self.acceptLanguages = acceptLanguages
        self.quadstore = quadstore
        self.siteLanguageQuality = [:]
        quadstore.db.createFunction("__acceptableObject", deterministic: true) { args in
            guard let s = args[0] as? Int64, let p = args[1] as? Int64, let g = args[2] as? Int64 else { return 0 }
            print("__acceptableObject(\(s), \(p), _, \(g))")
            return 1
        }
    }
    
    public func quads(matching pattern: QuadPattern) throws -> AnyIterator<Quad> {
        switch pattern.object {
        case .bound(_):
            // if the quad pattern's object is bound, we don't need to
            // perform filtering for language conneg
            return try quadstore.quads(matching: pattern)
        default:
            // TODO: optimize this to push language restrictions into the SQL query
            let i = try quadstore.quads(matching: pattern)
            var cachedAcceptance = [[Term]: Set<String>]()
            return AnyIterator {
                repeat {
                    guard let quad = i.next() else { return nil }
                    let object = quad.object
                    if self.acceptLanguages.isEmpty {
                        // special case: if there is no preference (e.g. no Accept-Language header is present),
                        // then all quads are kept in the model
                        return quad
                    } else if case .language(_) = object.type {
                        let cacheKey : [Term] = [quad.subject, quad.predicate, quad.graph]
                        if self.accept(quad: quad, languages: self.acceptLanguages, cacheKey: cacheKey, cachedAcceptance: &cachedAcceptance) {
                            return quad
                        }
                    } else {
                        return quad
                    }
                } while true
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
                guard let quads = try? quadstore.quads(matching: pattern) else { return false }
                let langs = quads.compactMap { (quad) -> String? in
                    if case .language(let lang) = quad.object.type {
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

extension SQLiteLanguageQuadStore: PlanningQuadStore {
    public func plan(algebra: Algebra, activeGraph: Term, dataset: Dataset) throws -> QueryPlan? {
        return nil
    }
}

extension SQLiteQuadStore: PackedIdentityMap {
    public typealias Item = Term
    public typealias Result = Int64
    
    static func loadMaxIDs(from db: Connection) throws -> (Int64, Int64, Int64, Int64) {
        let mask        = UInt64(0x00ffffffffffffff)
        let blankID = SQLiteQuadStore.TermType.blank.rawValue
        let iriID = SQLiteQuadStore.TermType.iri.rawValue
        let literalID = SQLiteQuadStore.TermType.literal.rawValue

        let blankMax = (try db.scalar("SELECT MAX(id) FROM terms WHERE type = ?", blankID) as? Int64 ?? 0)
        let iriMax = (try db.scalar("SELECT MAX(id) FROM terms WHERE type = ?", iriID) as? Int64 ?? 0)
        let languageMax = (try db.scalar("SELECT MAX(id) FROM terms WHERE type = ? AND language IS NOT NULL", literalID) as? Int64 ?? 0)
        let datatypeMax = (try db.scalar("SELECT MAX(id) FROM terms WHERE type = ? AND language IS NULL", literalID) as? Int64 ?? 0)
        
        let b = Int64(bitPattern: UInt64(bitPattern: blankMax) & mask)
        let i = Int64(bitPattern: UInt64(bitPattern: iriMax) & mask)
        let l = Int64(bitPattern: UInt64(bitPattern: languageMax) & mask)
        let d = Int64(bitPattern: UInt64(bitPattern: datatypeMax) & mask)
        
        //        print("# Max term IDs: \(blankMax) \(iriMax) \(languageMax) \(datatypeMax)")
        return (iri: i+1, blank: b+1, datatype: d+1, langauge: l+1)
    }
    
    public func term(for id: Result) -> Term? {
        if let term = self.i2tcache[id] {
            return term
        } else if let term = self.unpack(id: id) {
            return term
        }
        let query = termsTable.select(termsTable[*]).filter(idColumn == id)
        do {
            guard let row = try db.pluck(query) else {
                return nil
            }
            guard let t = term(from: row, typeColumn: termTypeColumn, valueColumn: termValueColumn, languageColumn: termLangColumn, datatypeColumn: termDatatypeColumn) else {
                return nil
            }
            i2tcache[id] = t
            return t
        } catch {}
        return nil
    }
    
    public func id(for term: Item) -> Result? {
        if let id = self.t2icache[term] {
            return id
        } else if let id = self.pack(value: term) {
            return id
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
    
    public func getOrSetID(for term: Item) throws -> Int64 {
        let packedId = self.pack(value: term)
        // if there is an ID, but it's packed,
        // we need to ensure that it's in the terms table
        // so that it can be used in joins with the quads table
        if let id = id(for: term), packedId == nil {
            return id
        }
        
        var i : Int64
        if let v = packedId {
            i = v
        } else {
            var v: Int64
            var type: UInt64 = 0
            switch term.type {
            case .blank:
                type = PackedTermType.blank.typedEmptyValue
                v = next.blank
                next.blank += 1
            case .iri:
                type = PackedTermType.iri.typedEmptyValue
                v = next.iri
                next.iri += 1
            case .language(_):
                type = PackedTermType.language.typedEmptyValue
                v = next.language
                next.language += 1
            case .datatype(_):
                type = PackedTermType.datatype.typedEmptyValue
                v = next.datatype
                next.datatype += 1
            }
            guard v < Int64(0x00ffffffffffffff) else { throw DatabaseError.DataError("Term ID overflows the 56 bits available") }
            i = Int64(bitPattern: type + UInt64(bitPattern: v))
        }
        
        i2tcache[i] = term
        t2icache[term] = i
        
        let insert: Insert
        switch term.type {
        case .iri:
            insert = termsTable.insert(or: .ignore,
                                       idColumn <- i,
                                       termTypeColumn <- TermType.iri.rawValue,
                                       termValueColumn <- term.value)
        case .blank:
            insert = termsTable.insert(or: .ignore,
                                       idColumn <- i,
                                       termTypeColumn <- TermType.blank.rawValue,
                                       termValueColumn <- term.value)
        case .language(let lang):
            let id = try getOrSetID(for: Term(iri: Namespace.rdf.langString))
            insert = termsTable.insert(or: .ignore,
                                       idColumn <- i,
                                       termTypeColumn <- TermType.literal.rawValue,
                                       termValueColumn <- term.value,
                                       termDatatypeColumn <- id,
                                       termLangColumn <- lang)
        case .datatype(let dt):
            let id = try getOrSetID(for: Term(iri: dt.value))
            insert = termsTable.insert(or: .ignore,
                                       idColumn <- i,
                                       termTypeColumn <- TermType.literal.rawValue,
                                       termValueColumn <- term.value,
                                       termDatatypeColumn <- id)
        }
        //        print("INSERT: \(insert)")
        try db.run(insert)
        return i
    }
    
    
    /**
     
     Term ID type byte:
     
     01    0x01    0000 0001    Blank
     02    0x02    0000 0010    IRI
     03    0x03    0000 0011        common IRIs
     16    0x10    0001 0000    Language
     17    0x11    0001 0001    Datatype
     18    0x12    0001 0010        inlined xsd:string
     19    0x13    0001 0011        xsd:boolean
     20    0x14    0001 0100        xsd:date
     21    0x15    0001 0101        xsd:dateTime
     22    0x16    0001 0110        xsd:string
     24    0x18    0001 1000        xsd:integer
     25    0x19    0001 1001        xsd:int
     26    0x1A    0001 1010        xsd:decimal
     
     Prefixes:
     
     0000 0001  blank
     0000 001   iri
     0001       literal
     0001 010       date (with optional time)
     0001 1         numeric
     
     **/
    
    internal static func isIRI(id: Result) -> Bool {
        guard let type = PackedTermType(from: UInt64(bitPattern: id)) else { return false }
        return type == .iri
    }
    
    internal static func isBlank(id: Result) -> Bool {
        guard let type = PackedTermType(from: UInt64(bitPattern: id)) else { return false }
        return type == .blank
    }
    
    internal static func isLanguageLiteral(id: Result) -> Bool {
        guard let type = PackedTermType(from: UInt64(bitPattern: id)) else { return false }
        return type == .language
    }
    
    internal static func isDatatypeLiteral(id: Result) -> Bool {
        guard let type = PackedTermType(from: UInt64(bitPattern: id)) else { return false }
        return type == .datatype
    }
    
    func unpack(id: Result) -> Item? {
        let byte = id >> 56
        let value = id & 0x00ffffffffffffff
        guard let type = PackedTermType(rawValue: UInt8(byte)) else { return nil }
        switch type {
        case .commonIRI:
            return unpack(iri: value)
        case .boolean:
            return unpack(boolean: value)
        case .date:
            return unpack(date: value)
        case .dateTime:
            return unpack(dateTime: value)
        case .inlinedString:
            return unpack(string: value)
        case .integer:
            return unpack(integer: value)
        case .int:
            return unpack(int: value)
        case .decimal:
            return unpack(decimal: value)
        default:
            return nil
        }
    }
    
    func pack(value: Item) -> Result? {
        switch (value.type, value.value) {
        case (.iri, let v):
            return pack(iri: v)
        case (.datatype(.boolean), "true"), (.datatype(.boolean), "1"):
            return pack(boolean: true)
        case (.datatype(.boolean), "false"), (.datatype(.boolean), "0"):
            return pack(boolean: false)
        case (.datatype(.dateTime), _):
            return pack(dateTime: value)
        case (.datatype(.date), let v):
            return pack(date: v)
        case (.datatype(.string), let v):
            return pack(string: v)
        case (.datatype(.integer), let v):
            return pack(integer: v)
        case (.datatype("http://www.w3.org/2001/XMLSchema#int"), let v):
            return pack(int: v)
        case (.datatype(.decimal), let v):
            return pack(decimal: v)
        default:
            return nil
        }
    }
    
    private func pack(string: String) -> Result? {
        guard string.utf8.count <= 7 else { return nil }
        var id: UInt64 = PackedTermType.inlinedString.typedEmptyValue
        for (i, u) in string.utf8.enumerated() {
            let shift = UInt64(8 * (6 - i))
            let b: UInt64 = UInt64(u) << shift
            id += b
        }
//        print("packed ID for string \(string) => \(id)")
        return Int64(bitPattern: id)
    }
    
    private func unpack(string: Result) -> Item? {
        let value = UInt64(bitPattern: string)
        var buffer = value.bigEndian
        var string: String? = nil
        withUnsafePointer(to: &buffer) { (p) in
            var chars = [CChar]()
            p.withMemoryRebound(to: CChar.self, capacity: 8) { (charsptr) in
                for i in 1...7 {
                    chars.append(charsptr[i])
                }
            }
            chars.append(0)
            chars.withUnsafeBufferPointer { (q) in
                if let p = q.baseAddress {
                    string = String(utf8String: p)
                }
            }
        }
        
        if let string = string {
//            print("unpacked string for ID \(value) => \(string)")
            return Term(value: string, type: .datatype(.string))
        }
        return nil
    }
    
    private func unpack(boolean packedBooleanValue: Result) -> Item? {
        let value = (packedBooleanValue > 0) ? "true" : "false"
        return Term(value: value, type: .datatype(.boolean))
    }
    
    private func unpack(integer value: Result) -> Item? {
        return Term(value: "\(value)", type: .datatype(.integer))
    }
    
    private func unpack(int value: Result) -> Item? {
        return Term(value: "\(value)", type: .datatype("http://www.w3.org/2001/XMLSchema#int"))
    }
    
    private func unpack(decimal d: Result) -> Item? {
        let decimal = UInt64(bitPattern: d)
        let scale = Int((decimal & 0x00ff000000000000) >> 48)
        let value = decimal & 0x00007fffffffffff
        let highByte = (decimal & 0x0000ff0000000000) >> 40
        let highBit = highByte & UInt64(0x80)
        guard scale >= 0 else { return nil }
        var combined = "\(value)"
        var string = ""
        while combined.count <= scale {
            // pad with leading zeros so that there is at least one digit to the left of the decimal point
            combined = "0\(combined)"
        }
        let breakpoint = combined.count - scale
        for (i, c) in combined.enumerated() {
            if i == breakpoint {
                if i == 0 {
                    string += "0."
                } else {
                    string += "."
                }
            }
            string += String(c)
        }
        if highBit > 0 {
            string = "-\(string)"
        }
        return Term(value: string, type: .datatype(.decimal))
    }
    
    private func unpack(date: Result) -> Item? {
        let value   = UInt64(bitPattern: date)
        let day     = value & 0x000000000000001f
        let months  = (value & 0x00000000001fffe0) >> 5
        let month   = months % 12
        let year    = months / 12
        let date    = String(format: "%04d-%02d-%02d", year, month, day)
        return Term(value: date, type: .datatype(.date))
    }
    
    private func unpack(dateTime: Result) -> Item? {
        let value   = UInt64(bitPattern: dateTime)
        // ZZZZ ZZZY YYYY YYYY YYYY MMMM DDDD Dhhh hhmm mmmm ssss ssss ssss ssss
        let tzSign  = (value & 0x0080000000000000) >> 55
        let tz      = (value & 0x007e000000000000) >> 49
        let year    = (value & 0x0001fff000000000) >> 36
        let month   = (value & 0x0000000f00000000) >> 32
        let day     = (value & 0x00000000f8000000) >> 27
        let hours   = (value & 0x0000000007c00000) >> 22
        let minutes = (value & 0x00000000003f0000) >> 16
        let msecs   = (value & 0x000000000000ffff)
        let seconds = Double(msecs) / 1_000.0
        var dateTime = String(format: "%04d-%02d-%02dT%02d:%02d:%02g", year, month, day, hours, minutes, seconds)
        if tz == 0 {
            dateTime = "\(dateTime)Z"
        } else {
            let offset  = tz * 15
            var hours   = Int(offset) / 60
            let minutes = Int(offset) % 60
            if tzSign == 1 {
                hours   *= -1
            }
            dateTime = dateTime + String(format: "%+03d:%02d", hours, minutes)
        }
        return Term(value: dateTime, type: .datatype(.dateTime))
    }
    
    private func pack(decimal stringValue: String) -> Result? {
        var c = stringValue.components(separatedBy: ".")
        guard c.count == 2 else { return nil }
        let integralValue = c[0]
        var sign : UInt64 = 0
        if integralValue.hasPrefix("-") {
            sign = UInt64(0x80) << 40
            c[0] = String(integralValue[integralValue.index(integralValue.startIndex, offsetBy: 1)...])
        }
        let combined = c.joined(separator: "")
        guard let value = UInt64(combined) else { return nil }
        let scale = UInt8(c[1].count)
        guard value <= 0x00007fffffffffff else { return nil }
        let id = PackedTermType.decimal.typedEmptyValue + (UInt64(scale) << 48) + (sign | value)
        return Int64(bitPattern: id)
    }
    
    private func pack(boolean booleanValue: Bool) -> Result? {
        let i : UInt64 = booleanValue ? 1 : 0
        let value: UInt64 = PackedTermType.boolean.typedEmptyValue
        return Int64(bitPattern: value + i)
    }
    
    private func pack(integer stringValue: String) -> Result? {
        guard let i = UInt64(stringValue) else { return nil }
        guard i < 0x00ffffffffffffff else { return nil }
        let value: UInt64 = PackedTermType.integer.typedEmptyValue
        return Int64(bitPattern: value + i)
    }
    
    private func pack(int stringValue: String) -> Result? {
        guard let i = UInt64(stringValue) else { return nil }
        guard i <= 2147483647 else { return nil }
        let value: UInt64 = PackedTermType.int.typedEmptyValue
        return Int64(bitPattern: value + i)
    }
    
    private func pack(date stringValue: String) -> Result? {
        let values = stringValue.components(separatedBy: "-").map { Int($0) }
        guard values.count == 3 else { return nil }
        if let y = values[0], let m = values[1], let d = values[2] {
            guard y <= 5000 else { return nil }
            let months  = 12 * y + m
            var value   = PackedTermType.date.typedEmptyValue
            value       += UInt64(months << 5)
            value       += UInt64(d)
            return Int64(bitPattern: value)
        } else {
            return nil
        }
    }
    
    private func pack(dateTime term: Term) -> Result? {
        // ZZZZ ZZZY YYYY YYYY YYYY MMMM DDDD Dhhh hhmm mmmm ssss ssss ssss ssss
        guard let date = term.dateValue else {
            return nil
        }
        guard let tz = term.timeZone else {
            return nil
        }
        let calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents(in: utc, from: date)
        
        guard let _year = components.year,
            let _month = components.month,
            let _day = components.day,
            let _hours = components.hour,
            let _minutes = components.minute,
            let _seconds = components.second else { return nil }
        let year : UInt64 = UInt64(_year)
        let month : UInt64 = UInt64(_month)
        let day : UInt64 = UInt64(_day)
        let hours : UInt64 = UInt64(_hours)
        let minutes : UInt64 = UInt64(_minutes)
        let seconds : UInt64 = UInt64(_seconds)
        let msecs : UInt64   = seconds * 1_000
        let offsetSeconds = tz.secondsFromGMT()
        let tzSign : UInt64 = (offsetSeconds < 0) ? 1 : 0
        let offsetMinutes : UInt64 = UInt64(abs(offsetSeconds) / 60)
        let offset : UInt64  = offsetMinutes / 15
        
        // guard against overflow values
        guard offset >= 0 && offset < 0x7f else { return nil }
        guard year >= 0 && year < 0x1fff else { return nil }
        guard month >= 0 && month < 0xf else { return nil }
        guard day >= 0 && day < 0x1f else { return nil }
        guard hours >= 0 && hours < 0x1f else { return nil }
        guard minutes >= 0 && minutes < 0x3f else { return nil }
        guard seconds >= 0 && seconds < 0xffff else { return nil }
        
        var value   = PackedTermType.dateTime.typedEmptyValue
        value       |= (tzSign << 55)
        value       |= (offset << 49)
        value       |= (year << 36)
        value       |= (month << 32)
        value       |= (day << 27)
        value       |= (hours << 22)
        value       |= (minutes << 16)
        value       |= (msecs)
        
        return Int64(bitPattern: value)
    }
    
    private func unpack(iri value: Result) -> Item? {
        switch value {
        case 1:
            return Term(value: Namespace.rdf.type, type: .iri)
        case 2:
            return Term(value: Namespace.rdf.List, type: .iri)
        case 3:
            return Term(value: Namespace.rdf.Resource, type: .iri)
        case 4:
            return Term(value: Namespace.rdf.first, type: .iri)
        case 5:
            return Term(value: Namespace.rdf.rest, type: .iri)
        case 6:
            return Term(value: "http://www.w3.org/2000/01/rdf-schema#comment", type: .iri)
        case 7:
            return Term(value: "http://www.w3.org/2000/01/rdf-schema#label", type: .iri)
        case 8:
            return Term(value: "http://www.w3.org/2000/01/rdf-schema#seeAlso", type: .iri)
        case 9:
            return Term(value: "http://www.w3.org/2000/01/rdf-schema#isDefinedBy", type: .iri)
        case 256..<512:
            return Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#_\(value-256)", type: .iri)
        default:
            return nil
        }
    }
    
    private func pack(iri: String) -> Result? {
        let mask    = PackedTermType.commonIRI.typedEmptyValue
        switch iri {
        case Namespace.rdf.type:
            return Int64(bitPattern: mask + 1)
        case Namespace.rdf.List:
            return Int64(bitPattern: mask + 2)
        case Namespace.rdf.Resource:
            return Int64(bitPattern: mask + 3)
        case Namespace.rdf.first:
            return Int64(bitPattern: mask + 4)
        case Namespace.rdf.rest:
            return Int64(bitPattern: mask + 5)
        case "http://www.w3.org/2000/01/rdf-schema#comment":
            return Int64(bitPattern: mask + 6)
        case "http://www.w3.org/2000/01/rdf-schema#label":
            return Int64(bitPattern: mask + 7)
        case "http://www.w3.org/2000/01/rdf-schema#seeAlso":
            return Int64(bitPattern: mask + 8)
        case "http://www.w3.org/2000/01/rdf-schema#isDefinedBy":
            return Int64(bitPattern: mask + 9)
        case _ where iri.hasPrefix("http://www.w3.org/1999/02/22-rdf-syntax-ns#_"):
            let c = iri.components(separatedBy: "_")
            guard c.count == 2 else { return nil }
            guard let value = UInt64(c[1]) else { return nil }
            if value >= 0 && value < 256 {
                return Int64(bitPattern: mask + 0x100 + value)
            }
        default:
            break
        }
        return nil
    }

}

public struct SQLitePlan: NullaryQueryPlan {
    private typealias ColumnMapping = [String:(SQLite.Expression<Int64>, SQLite.Expression<String>, SQLite.Expression<String?>, SQLite.Expression<Int64?>)]
    var query: SQLite.Table
    var distinct: Bool
    var projected: [String: SQLite.Expression<Int64>]
    var store: SQLiteQuadStore
    public var selfDescription: String { return "SQLite Plan { \(query.expression.template) : \(query.expression.bindings) }" }
    
    private func wrapQuery() -> (SQLite.Table, ColumnMapping) {
        // add joins to the terms table for all projected variables, executing everything in a single query
        
        var columnMapping = ColumnMapping()
        var q = query
        if !projected.isEmpty {
            var columns = [Expressible]()
            for (id, expr) in projected {
                let tt = store.termsTable.alias("term_\(id)")
                let tid = store.idColumn
                q = q.join(tt, on: tt[tid] == expr)
                let termCols = (tt[store.termTypeColumn], tt[store.termValueColumn], tt[store.termLangColumn], tt[store.termDatatypeColumn])
                columns.append(termCols.0)
                columns.append(termCols.1)
                columns.append(termCols.2)
                columns.append(termCols.3)
                columnMapping[id] = termCols
            }
            if distinct {
                q = q.select(distinct: columns)
            } else {
                q = q.select(columns)
            }
        }
        return (q, columnMapping)
    }
    
    public func evaluate() throws -> AnyIterator<TermResult> {
        let store = self.store
        
        if true {
            let (q, columnMapping) = wrapQuery()
            guard let dbh = try? store.db.prepare(q) else {
                return AnyIterator { return nil }
            }
            let results = dbh.lazy.compactMap { (row) -> TermResult? in
                do {
                    let d = try columnMapping.map { (pair) throws -> (String, Term) in
                        let name = pair.key
                        let cols = pair.value
                        guard let t = store.term(from: row, typeColumn: cols.0, valueColumn: cols.1, languageColumn: cols.2, datatypeColumn: cols.3) else {
                            throw SQLiteQuadStore.SQLiteQuadStoreError.idAccessError
                        }
                        return (name, t)
                    }
                    let r = TermResult(bindings: Dictionary(uniqueKeysWithValues: d))
                    return r
                } catch {
                    return nil
                }
            }
            return AnyIterator(results.makeIterator())
        } else {
            // execute the query, and then pull term values from the terms table as separate queries
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
