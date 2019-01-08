# Kineo

## A persistent RDF quadstore and SPARQL engine

### Install dependencies

Install [serd](http://drobilla.net/software/serd):

* MacOS: `brew install serd`
* Linux: `apt-get install libserd-dev`

### Build

```
% swift build -c release
```

### Load data

Create a database file (`geo.db`) and load one or more N-Triples files:

```
% ./.build/release/kineo-cli geo.db load dbpedia-geo.nt
```

Each file will be loaded into its own graph. By default, the first graph created
during data loading will be used as the default graph when querying the database.

Alternatively, data can be loaded into a specific named graph (similarly, a
custom graph name can be used for the query default graph):

```
% ./.build/release/kineo-cli geo.db load -g http://example.org/dbpedia dbpedia-geo.nt
```

### Query

Querying of the data can be done using SPARQL:

```
% cat geo.rq
PREFIX geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
SELECT  ?s
WHERE {
	?s geo:lat ?lat ;
	   geo:long ?long ;
	FILTER(?long < -117.0)
	FILTER(?lat >= 31.0)
	FILTER(?lat <= 33.0)
}
ORDER BY ?s

% ./.build/release/kineo-cli geo.db query geo.rq
Using default graph <file:///Users/greg/kineo/geo.nt>
1	Result["s": <http://dbpedia.org/resource/Bonita,_California>]
2	Result["s": <http://dbpedia.org/resource/Fairbanks_Ranch,_California>]
3	Result["s": <http://dbpedia.org/resource/Imperial_Beach,_California>]
4	Result["s": <http://dbpedia.org/resource/La_Mesa,_California>]
5	Result["s": <http://dbpedia.org/resource/La_Presa,_California>]
6	Result["s": <http://dbpedia.org/resource/Lemon_Grove,_California>]
7	Result["s": <http://dbpedia.org/resource/National_City,_California>]
8	Result["s": <http://dbpedia.org/resource/Poway,_California>]
9	Result["s": <http://dbpedia.org/resource/Solana_Beach,_California>]
10	Result["s": <http://dbpedia.org/resource/Tijuana>]
11	Result["s": <http://dbpedia.org/resource/University_of_California,_San_Diego>]
```

### SPARQL Endpoint

Finally, using the companion [kineo-endpoint](https://github.com/kasei/kineo-endpoint) package,
a SPARQL endpoint can be run allowing SPARQL Protocol clients to access the data:

```
% kineo-endpoint -f geo.db &
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
