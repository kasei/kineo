# Kineo

## A persistent RDF quadstore and SPARQL engine

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

A simple line-based query format (equivalent to a subset of SPARQL) allows querying the data.

Triple patterns can be joined and results filtered (with expressions encoded in postfix notation):

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

% ./.build/release/kineo-cli geo.db sparql geo.rq
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
