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

//let store = try SQLiteQuadStore(filename: "/tmp/qs.sqlite3")
let store = try SQLiteQuadStore(filename: "/tmp/foaf.sqlite3")
let defaultGraph = store.graphs().next() ?? Term(iri: "tag:kasei.us,2018:default-graph")

//let sparql = "SELECT DISTINCT ?type ?p WHERE { ?s a ?type ; ?p ?o . ?q <q> 3 } ORDER BY ?type LIMIT 10"
//let sparql = """
//    PREFIX geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
//    SELECT DISTINCT * WHERE {
//        ?s geo:lat ?lat ;
//            geo:long ?long
//        FILTER NOT EXISTS { ?s <p> <q> }
//    }
//    OFFSET 1
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
let sparql = """
    PREFIX foaf: <http://xmlns.com/foaf/0.1/>
    SELECT DISTINCT * WHERE {
        ?s a foaf:Person ; foaf:name ?name .
    }
    """
guard var p = SPARQLParser(data: sparql.data(using: .utf8)!) else { fatalError("Failed to construct SPARQL parser") }
let q = try p.parseQuery()

let dataset = store.dataset(withDefault: defaultGraph)

let planner = QueryPlanner(store: store, dataset: dataset)
let plan = try planner.plan(query: q, activeGraph: dataset.defaultGraphs.first!)
print(plan.serialize())

for (i, r) in try plan.evaluate().enumerated() {
    print("\(i) >>> \(r)")
}
