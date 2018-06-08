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

guard CommandLine.arguments.dropFirst().count >= 1 else {
    fatalError("No template URL given.")
}

guard let template = CommandLine.arguments.dropFirst().first else {
    fatalError("No template URL given.")
}

Logger.shared.level = .silent

let defaultGraph = Term(iri: "http://example.org/graph")
guard let store = TriplePatternFragmentQuadStore(urlTemplate: template, defaultGraph: defaultGraph) else {
    fatalError("Failed to construct TPF QuadStore")
}

//let qp = QuadPattern(
//    subject: .variable("s", binding: true),
////    predicate: .bound(Term(iri: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type")),
//    predicate: .bound(Term(iri: "http://purl.org/dc/terms/title")),
//    //    predicate: .bound(Term(iri: "http://xmlns.com/foaf/0.1/name")),
//    //    predicate: .variable("p", binding: true),
//    object: .variable("o", binding: true),
//    graph: .bound(defaultGraph)
//)
//
//
//print("Getting triples matching: \(qp)")
//let quads = try store.quads(matching: qp)
//for (i, q) in quads.enumerated() {
//    let t = q.triple
//    print("\(i) >>> \(t)")
//}



let type = TriplePattern(
    subject: .variable("s", binding: true),
    predicate: .bound(Term(iri: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type")),
    object: .bound(Term(iri: "http://dbpedia.org/ontology/Document"))
)
let title = TriplePattern(
    subject: .variable("s", binding: true),
    predicate: .bound(Term(iri: "http://purl.org/dc/terms/title")),
    object: .variable("title", binding: true)
)

let bgp = [type, title]
print("Getting results matching: \(bgp)")
let results = try store.evaluate(bgp: bgp, activeGraph: defaultGraph)
for (i, r) in results.enumerated() {
    print("\(i) >>> \(r)")
}
