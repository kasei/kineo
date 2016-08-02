# Expression Syntax

* `EXPR1 EXPR2 ||` - Short-circuiting logical-or
* `EXPR1 EXPR2 &&` - Short-circuiting logical-and
* `EXPR1 EXPR2 =` - Value-based equality test
* `EXPR1 EXPR2 !=` - Value-based not-equality test
* `EXPR1 LOWER-EXPR UPPER-EXPR between` - Numeric between (equivalent to `EXPR1 >= LOWER-EXPR && EXPR1 <= UPPER-EXPR`)
* `EXPR1 EXPR2 <` - Less-than
* `EXPR1 EXPR2 >` - Greater-than
* `EXPR1 EXPR2 <=` - Less-than or equal-to
* `EXPR1 EXPR2 >=` - Greater-than or equal-to
* `EXPR1 EXPR2 +` - Numeric addition
* `EXPR1 EXPR2 -` - Numeric subtraction
* `EXPR1 EXPR2 *` - Numeric multiplication
* `EXPR1 EXPR2 /` - Numeric division
* `EXPR not` - Logical-not
* `EXPR isiri` - IRI test
* `EXPR isliteral` - Literal test
* `EXPR isblank` - Blank test
* `EXPR isnumeric` - Numeric literal test
* `EXPR lang` - The language tag of a literal as a string
* `EXPR datatype` - Datatype of a literal as an IRI
* `EXPR int` - Numeric integer cast
* `EXPR float` - Numeric float cast
* `EXPR double` - Numeric double case
