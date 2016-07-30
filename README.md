# Kineo

## A persistent RDF quadstore

### Build

```
% swift build -c release
```

### Load data

Create a database file (`geo.db`) and load one or more N-Triples files:

```
% ./.build/release/kineo-cli geo.db load dbpedia-geo.nt
```

Each file will be loaded into its own graph. When querying the database, the
first graph created during data loading will be used as the default graph.

### Query

A simple line-based query format (equivalent to a subset of SPARQL) allows querying the data.

Triple patterns can be joined and results filtered:

```
% cat geo.q
triple ?s <http://www.w3.org/2003/01/geo/wgs84_pos#lat> ?lat
triple ?s <http://www.w3.org/2003/01/geo/wgs84_pos#long> ?long
join
filter > ?lat 31
filter < ?lat 33
filter < ?long -117

% ./.build/release/kineo-cli geo.db query geo.q
Using default graph <file:///Users/greg/kineo/geo.nt>
1	Result["lat": 32.65842e0, "s": <http://dbpedia.org/resource/Bonita,_California>, "long": -117.035336e0]
2	Result["lat": 32.97e0, "s": <http://dbpedia.org/resource/Poway,_California>, "long": -117.03861111111111e0]
3	Result["lat": 32.99583333333333e0, "s": <http://dbpedia.org/resource/Fairbanks_Ranch,_California>, "long": -117.18305555555555e0]
4	Result["lat": 32.57833333333333e0, "s": <http://dbpedia.org/resource/Imperial_Beach,_California>, "long": -117.11722222222222e0]
5	Result["lat": 32.771388888888886e0, "s": <http://dbpedia.org/resource/La_Mesa,_California>, "long": -117.02277777777778e0]
6	Result["lat": 32.71194444444444e0, "s": <http://dbpedia.org/resource/La_Presa,_California>, "long": -117.0038888888889e0]
7	Result["lat": 32.733333333333334e0, "s": <http://dbpedia.org/resource/Lemon_Grove,_California>, "long": -117.03361111111111e0]
8	Result["lat": 32.670833333333334e0, "s": <http://dbpedia.org/resource/National_City,_California>, "long": -117.09277777777778e0]
9	Result["lat": 32.99527777777778e0, "s": <http://dbpedia.org/resource/Solana_Beach,_California>, "long": -117.26027777777777e0]
10	Result["lat": 32.525e0, "s": <http://dbpedia.org/resource/Tijuana>, "long": -117.03333333333333e0]
11	Result["lat": 32.881e0, "s": <http://dbpedia.org/resource/University_of_California,_San_Diego>, "long": -117.238e0]
```

Results can be aggregated:

```
% echo 'avg lat avg_of_lats' >> geo.q
% ./.build/release/kineo-cli geo.db query geo.q
Using default graph <file:///Users/greg/kineo/geo.nt>
1	Result["avg_of_lats": "32.7719422222222"^^<http://www.w3.org/2001/XMLSchema#double>]
```

