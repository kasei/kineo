# Query Syntax

Queries are expressed in a line-based stack format. Each query operator pops
zero or more sub-queries form an implicit stack, and pushes a new sub-query
onto the stack. The top of the stack after processing the query string is used
as the query for evaluation.

## Query Operators

* `project VAR1 VAR2 ...` - Project to the listed variable names (`project s p`)
* `union` - Union the two patterns on the top of the stack
* `join` - Join the two patterns on the top of the stack
* `leftjoin` - Join the two patterns on the top of the stack
* `quad SUBJECT PREDICATE OBJECT GRAPH` - Quad pattern (nodes expressed as either `?variables` or terms in N-Triples format)
* `triple SUBJECT PREDICATE OBJECT` - Triple pattern (the active graph during evaluation is used to treat this as a quad pattern)
* `avg KEY RESULT GROUPVAR1 GROUPVAR2 ...` - Aggregate the pattern on the top of the stack, grouping by the group variables, binding the *average* of the `?KEY` variable to `?RESULT`
* `sum KEY RESULT GROUPVAR1 GROUPVAR2 ...` - Aggregate the pattern on the top of the stack, grouping by the group variables, binding the *sum* of the `?KEY` variable to `?RESULT`
* `agg AGG1 RESULT1 EXPR1 , AGG2 RESULT2 EXPR2 ; GROUPEXPR1 , GROUPEXPR2 , ...` - Aggregate the pattern on the top of the stack, grouping by the group expressions
* `count KEY RESULT GROUPVAR1 GROUPVAR2 ...` - Aggregate the pattern on the top of the stack, grouping by the group variables, binding the *count* of bound values of `?KEY` to `?RESULT`
* `countall RESULT GROUPVAR1 GROUPVAR2 ...` - Aggregate the pattern on the top of the stack, grouping by the group variables, binding the *count* of results to `?RESULT`
* `limit COUNT` - Limit the result count to `COUNT`
* `graph ?VAR` - Evaluate the pattern on the top of the stack with each named graph in the store as the active graph (and bound to `?VAR`)
* `graph <IRI>` - Change the active graph to `IRI`
* `extend RESULT EXPR` - Evaluate results for the pattern on the top of the stack, evaluating `EXPR` for each row, and binding the result to `?RESULT`
* `filter EXPR` - Evaluate results for the pattern on the top of the stack, evaluating `EXPR` for each row, and returning the result iff a true value is produced
* `sort EXPR1 , EXPR2 , ...` - Sort the results for the pattern on the top of the stack by `?VAR`


## Examples

Average of latitutes for points near Southern California:

```
triple ?s <http://www.w3.org/2003/01/geo/wgs84_pos#lat> ?lat
triple ?s <http://www.w3.org/2003/01/geo/wgs84_pos#long> ?long
join
filter ?long -117 < ?lat 31 33 between &&
filter ?long -117 < ?long -120 >
avg lat avg_of_lats
```