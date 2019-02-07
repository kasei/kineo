//
//  main.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 6/24/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import Kineo
import SPARQLSyntax

Logger.shared.level = .silent


private func numericDatasetQuads(min_value: Int, max_value: Int, graph: Term) -> [Quad] {
    var quads = [Quad]()
    let s1 = Term(iri: "http://example.org/s1")
    let s2 = Term(iri: "http://example.org/s2")
    let p = Term(iri: "http://example.org/ns/p")
    
    let third = Double(max_value)/3.0
    for n in min_value..<max_value {
        let i = Term(integer: n)
        let f = Term(float: Double(n)-third)
        quads.append(Quad(subject: s1, predicate: p, object: i, graph: graph))
        quads.append(Quad(subject: s2, predicate: p, object: f, graph: graph))
    }
    return quads
}


//let store = try SQLiteQuadStore(filename: "/tmp/paths.sqlite3")
let store = try SQLiteQuadStore(filename: "/tmp/qs.sqlite3")
//let store = try SQLiteQuadStore(filename: "/tmp/foaf.sqlite3")
//let store = try SQLiteQuadStore(version: 0)
let defaultGraph = store.graphs().next() ?? Term(iri: "tag:kasei.us,2018:default-graph")


//let quads = numericDatasetQuads(min_value: 0, max_value: 10_000, graph: defaultGraph)
//try store.load(version: 1, quads: quads)


//let sparql = "SELECT DISTINCT ?type ?p WHERE { ?s a ?type ; ?p ?o . ?q <q> 3 } ORDER BY ?type LIMIT 10"
//let sparql = """
//    PREFIX geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
//    SELECT DISTINCT * WHERE {
//        ?s geo:lat ?lat ;
//            geo:long ?long
//        FILTER(?long < - 116.0)
//        FILTER(?long > - 121.0)
//        FILTER(?lat >= 30.0)
//        FILTER(?lat <= 34.0)
//        # FILTER NOT EXISTS { ?s <p> <q> }
//    }
//    # OFFSET 1
//    LIMIT 10
//    """
//let sparql = """
//    PREFIX foaf: <http://xmlns.com/foaf/0.1/>
//    SELECT DISTINCT * WHERE {
//        ?s a ?class ;
//            foaf:name ?name .
//        FILTER (EXISTS { ?s foaf:knows ?knows })
//    }
//    """
//let sparql = """
//    PREFIX foaf: <http://xmlns.com/foaf/0.1/>
//    SELECT DISTINCT ?s ?p WHERE {
//        ?s ?p ?o
//    }
//    ORDER BY ?s
//    """
//let sparql = """
//    PREFIX foaf: <http://xmlns.com/foaf/0.1/>
//    SELECT DISTINCT ?s ?p WHERE {
//        ?s a ?type ; ?p ?o
//    }
//    ORDER BY ?s
//    """
//let sparql = """
//    PREFIX foaf: <http://xmlns.com/foaf/0.1/>
//    SELECT (COUNT(*) AS ?c) ?p WHERE {
//        ?s ?p ?o
//    }
//    GROUP BY ?p
//    """
//let sparql = """
//    PREFIX : <http://example.org/>
//    PREFIX foaf: <http://xmlns.com/foaf/0.1/>
//    PREFIX visit: <http://purl.org/net/vocab/2004/07/visit#>
//    SELECT DISTINCT * WHERE {
//        # <http://kasei.us/about/#greg> ?p ?o
//        <http://kasei.us/about/#greg> !(foaf:account|visit:usstate|visit:country|visit:caregion) ?o
//        # :a :knows+ ?o
//        # :a :knows+ :e
//    }
//    # ORDER BY ?s ?o
//"""
//let sparql = """
//PREFIX : <http://example.org/>
//SELECT ?a ?o WHERE {
//    # :a :knows* ?o
//    ?a :knows* ?o
//    # :a :knows+ :e
//}
//ORDER BY ?a ?o
//"""
//let sparql = """
//PREFIX foaf: <http://xmlns.com/foaf/0.1/>
//SELECT ?p (COUNT(*) AS ?count) (GROUP_CONCAT(DISTINCT ?o) AS ?g) WHERE {
//    ?s ?p ?o
//}
//GROUP BY ?p (ISIRI(?p) AS ?iri)
//ORDER BY ?count
//"""
//let sparql = """
//PREFIX foaf: <http://xmlns.com/foaf/0.1/>
//SELECT (SUM(?v) AS ?avg) WHERE {
//    VALUES ?v { 1 1 2 }
//}
//"""
//let sparql = """
//PREFIX foaf: <http://xmlns.com/foaf/0.1/>
//SELECT * WHERE {
//    ?s ?p ?o
//}
//"""
let sparql = """
    PREFIX geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
    SELECT ?lat ?s WHERE {
        ?s geo:lat ?lat ;
            geo:long ?long
    }
    ORDER BY ?lat
    LIMIT 10
    """
guard var p = SPARQLParser(data: sparql.data(using: .utf8)!) else { fatalError("Failed to construct SPARQL parser") }
let q = try p.parseQuery()

let startTime = getCurrentTime()
print("SPARQL:")
print(sparql)
let dataset = store.dataset(withDefault: defaultGraph)
if true {
    print("Query:")
    print(q)
    let e = QueryPlanEvaluator(store: store, dataset: dataset)
    e.planner.allowStoreOptimizedPlans = false
    let r = try e.evaluate(query: q)
    switch r {
    case let .bindings(vars, seq):
        for (i, r) in seq.enumerated() {
            let terms = vars.map({ r[$0]?.description ?? "" })
            print("[\(i+1)] \(terms.joined(separator: "\t"))")
        }
    default:
        fatalError("unimplemented") // TODO: implement
    }
} else {
    let e = SimpleQueryEvaluator(store: store, dataset: dataset)
    let r = try e.evaluate(query: q)
    switch r {
    case let .bindings(vars, seq):
        for (i, r) in seq.enumerated() {
            let terms = vars.map({ r[$0]?.description ?? "" })
            print("[\(i+1)] \(terms.joined(separator: "\t"))")
        }
    default:
        fatalError("unimplemented") // TODO: implement
    }
}
print("done")

let endTime = getCurrentTime()
let elapsed = Double(endTime - startTime)
warn("elapsed time: \(elapsed)s)")
