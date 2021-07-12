# Kineo

## A persistent RDF quadstore and SPARQL engine

### Build

`swift build -c release`

### Swift Package Manager

You can use the [Swift Package Manager](https://swift.org/package-manager/) to add Kineo to a Swift project by adding it as a dependency in `Package.swift`:

```swift
.package(name: "Kineo", url: "https://github.com/kasei/kineo.git", .upToNextMinor(from: "0.0.91")),
```

### Load data

Create a database file (`geo.db`) and load one or more N-Triples or Turtle files:

```
% ./.build/release/kineo -q geo.db -d examples/geo-data/geo.ttl load
```

Specifying `-d FILENAME` will load data from `FILENAME` into the default graph.
Alternatively, data can be loaded into a specific named graph (similarly, a
custom graph name can be used for the query default graph):

```
% ./.build/release/kineo -q geo.db -g http://example.org/dbpedia examples/geo-data/geo.ttl load
```

### Query

Querying of the data can be done using SPARQL:

```
% cat examples/geo-data/geo.rq
PREFIX geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
SELECT  ?s
WHERE {
	?s geo:lat ?lat ;
	   geo:long ?long ;
	FILTER(?long < -120)
	FILTER(?lat >= 34.0)
	FILTER(?lat <= 35.0)
}
ORDER BY ?s

% ./.build/release/kineo -q geo.db query examples/geo-data/geo.rq
Using default graph <file://examples/geo-data/geo.ttl>
1	Result[s: <http://dbpedia.org/resource/Buellton,_California>]
2	Result[s: <http://dbpedia.org/resource/Lompoc,_California>]
3	Result[s: <http://dbpedia.org/resource/Los_Alamos,_California>]
4	Result[s: <http://dbpedia.org/resource/Mission_Hills,_California>]
5	Result[s: <http://dbpedia.org/resource/Orcutt,_California>]
6	Result[s: <http://dbpedia.org/resource/Santa_Barbara_County,_California>]
7	Result[s: <http://dbpedia.org/resource/Santa_Maria,_California>]
8	Result[s: <http://dbpedia.org/resource/Santa_Ynez,_California>]
9	Result[s: <http://dbpedia.org/resource/Solvang,_California>]
10	Result[s: <http://dbpedia.org/resource/Vandenberg_Air_Force_Base>]
```

### Kineo API

The Kineo API can be used to create an in-memory or persistent quadstore,
load RDF data into it, and evaluate SPARQL queries over the data:

```swift
import Foundation
import SPARQLSyntax
import Kineo

let graph = Term(iri: "http://example.org/default-graph")
let store = MemoryQuadStore()

let url = URL(string: "http://kasei.us/about/foaf.ttl")!
try store.load(url: url, defaultGraph: graph)

let sparql = "PREFIX foaf: <http://xmlns.com/foaf/0.1/> SELECT * WHERE { ?person a foaf:Person ; foaf:name ?name }"
let q = try SPARQLParser.parse(query: sparql)
let results = try store.query(q, defaultGraph: graph)
for (i, result) in results.bindings.enumerated() {
    print("\(i+1)\t\(result)")
}
```

There is also an API that exposes the RDF data in terms of graph vertices and edge traversals:

```swift
import Foundation
import SPARQLSyntax
import Kineo

let graph = Term(iri: "http://example.org/default-graph")
let store = MemoryQuadStore()

let url = URL(string: "http://kasei.us/about/foaf.ttl")!
try store.load(url: url, defaultGraph: graph)

let graphView = store.graph(graph)
let greg = graphView.vertex(Term(iri: "http://kasei.us/about/#greg"))

let knows = Term(iri: "http://xmlns.com/foaf/0.1/knows")
let name = Term(iri: "http://xmlns.com/foaf/0.1/name")
for v in try greg.outgoing(knows) {
    let names = try v.outgoing(name)
    if let nameVertex = names.first {
        let name = nameVertex.term
        print("Greg know \(name)")
    }
}
```

### SPARQL Endpoint

Finally, using the companion [kineo-endpoint](https://github.com/kasei/kineo-endpoint) package,
a SPARQL endpoint can be run allowing SPARQL Protocol clients to access the data:

```
% kineo-endpoint -q geo.db &
% curl -H "Accept: application/sparql-results+json" -H "Content-Type: application/sparql-query" --data 'PREFIX geo: <http://www.w3.org/2003/01/geo/wgs84_pos#> SELECT ?s ?lat ?long WHERE { ?s geo:lat ?lat ; geo:long ?long } LIMIT 3' 'http://localhost:8080/sparql'
{
  "head": {
    "vars": [ "s", "lat", "long" ]
  },
  "results": {
    "bindings": [
      {
        "s": { "type": "uri", "value": "http://dbpedia.org/resource/'s-Gravendeel" },
        "lat": { "type": "literal", "value": "5.17833333333333E1", "datatype": "http://www.w3.org/2001/XMLSchema#float" },
        "long": { "type": "literal", "value": "4.61666666666667E0", "datatype": "http://www.w3.org/2001/XMLSchema#float" }
      },
      {
        "s": { "type": "uri", "value": "http://dbpedia.org/resource/'s-Hertogenbosch" },
        "lat": { "type": "literal", "value": "5.17833333333333E1", "datatype": "http://www.w3.org/2001/XMLSchema#float" },
        "s": { "type": "uri", "value": "http://dbpedia.org/resource/Groesbeek" },
        "long": { "type": "literal", "value": "5.93333333333333E0", "datatype": "http://www.w3.org/2001/XMLSchema#float" }
      },
      {
        "s": { "type": "uri", "value": "http://dbpedia.org/resource/'s-Hertogenbosch" },
        "lat": { "type": "literal", "value": "5.1729918E1", "datatype": "http://www.w3.org/2001/XMLSchema#float" },
        "long": { "type": "literal", "value": "5.306938E0", "datatype": "http://www.w3.org/2001/XMLSchema#float" }
      }
    ]
  }
}
```
