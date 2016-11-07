import XCTest
import Foundation
import Kineo

class SPARQLParserTest: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testParser() {
        guard var p = SPARQLParser(string: "PREFIX ex: <http://example.org/> SELECT * WHERE {\n_:s ex:value ?o . FILTER(?o != 7.0)\n}\n") else { XCTFail(); return }
        do {
            let a = try p.parse()
            guard case .filter(let pattern, .ne(.node(.variable("o", binding: true)), .node(.bound(Term(value: "7.0", type: .datatype("http://www.w3.org/2001/XMLSchema#decimal")))))) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            guard case .triple(_) = pattern else {
                XCTFail("Unexpected algebra: \(pattern.serialize())")
                return
            }
            
            XCTAssert(true)
        } catch let e {
            XCTFail("\(e)")
        }
    }
    
    func testLexer() {
        guard let data = "[ [] { - @en-US 'foo' \"bar\" PREFIX ex: <http://example.org/> SELECT * WHERE {\n_:s ex:value ?o . FILTER(?o != 7.0)\n}\n".data(using: .utf8) else { XCTFail(); return }
//        guard let data = "[ [] { - @en-US".data(using: .utf8) else { XCTFail(); return }
        let stream = InputStream(data: data)
        stream.open()
        var lexer = SPARQLLexer(source: stream)
        XCTAssertEqual(lexer.next()!, .lbracket, "expected token")
        XCTAssertEqual(lexer.next()!, .anon, "expected token")
        XCTAssertEqual(lexer.next()!, .lbrace, "expected token")
        XCTAssertEqual(lexer.next()!, .minus, "expected token")
        XCTAssertEqual(lexer.next()!, .lang("en-us"), "expected token")
        XCTAssertEqual(lexer.next()!, .string1s("foo"), "expected token")
        XCTAssertEqual(lexer.next()!, .string1d("bar"), "expected token")

        XCTAssertEqual(lexer.next()!, .keyword("PREFIX"), "expected token")
        XCTAssertEqual(lexer.next()!, .prefixname("ex", ""), "expected token")
        XCTAssertEqual(lexer.next()!, .iri("http://example.org/"), "expected token")
        
        XCTAssertEqual(lexer.next()!, .keyword("SELECT"), "expected token")
        XCTAssertEqual(lexer.next()!, .star, "expected token")
        XCTAssertEqual(lexer.next()!, .keyword("WHERE"), "expected token")
        XCTAssertEqual(lexer.next()!, .lbrace, "expected token")
        XCTAssertEqual(lexer.next()!, .bnode("s"), "expected token")
        XCTAssertEqual(lexer.next()!, .prefixname("ex", "value"), "expected token")
        XCTAssertEqual(lexer.next()!, ._var("o"), "expected token")
        XCTAssertEqual(lexer.next()!, .dot, "expected token")
        XCTAssertEqual(lexer.next()!, .keyword("FILTER"), "expected token")
        XCTAssertEqual(lexer.next()!, .lparen, "expected token")
        XCTAssertEqual(lexer.next()!, ._var("o"), "expected token")
        XCTAssertEqual(lexer.next()!, .notequals, "expected token")
        XCTAssertEqual(lexer.next()!, .decimal("7.0"), "expected token")
        XCTAssertEqual(lexer.next()!, .rparen, "expected token")
        XCTAssertEqual(lexer.next()!, .rbrace, "expected token")
        XCTAssertNil(lexer.next())
    }
    
    func testLexerSingleQuotedStrings() {
        guard let data = "'foo' 'foo\\nbar' '\\u706B' '\\U0000661F' '''baz''' '''' ''' ''''''''".data(using: .utf8) else { XCTFail(); return }
        let stream = InputStream(data: data)
        stream.open()
        var lexer = SPARQLLexer(source: stream)
        
        XCTAssertEqual(lexer.next()!, .string1s("foo"), "expected token")
        XCTAssertEqual(lexer.next()!, .string1s("foo\nbar"), "expected token")
        XCTAssertEqual(lexer.next()!, .string1s("火"), "expected token")
        XCTAssertEqual(lexer.next()!, .string1s("星"), "expected token")
        XCTAssertEqual(lexer.next()!, .string3s("baz"), "expected token")
        XCTAssertEqual(lexer.next()!, .string3s("' "), "expected token")
        XCTAssertEqual(lexer.next()!, .string3s("''"), "expected token")
    }
    
    func testLexerDoubleQuotedStrings() {
        guard let data = "\"foo\" \"foo\\nbar\" \"\\u706B\" \"\\U0000661F\" \"\"\"baz\"\"\" \"\"\"\" \"\"\" \"\"\"\"\"\"\"\"".data(using: .utf8) else { XCTFail(); return }
        let stream = InputStream(data: data)
        stream.open()
        var lexer = SPARQLLexer(source: stream)
        
        XCTAssertEqual(lexer.next()!, .string1d("foo"), "expected token")
        XCTAssertEqual(lexer.next()!, .string1d("foo\nbar"), "expected token")
        XCTAssertEqual(lexer.next()!, .string1d("火"), "expected token")
        XCTAssertEqual(lexer.next()!, .string1d("星"), "expected token")
        XCTAssertEqual(lexer.next()!, .string3d("baz"), "expected token")
        XCTAssertEqual(lexer.next()!, .string3d("\" "), "expected token")
        XCTAssertEqual(lexer.next()!, .string3d("\"\""), "expected token")
    }
    
    func testProjectExpression() {
        guard var p = SPARQLParser(string: "SELECT (?x+1 AS ?y) ?x WHERE {\n_:s <p> ?x .\n}\n") else { XCTFail(); return }
        do {
            let a = try p.parse()
            guard case .project(let algebra, let variables) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            XCTAssertEqual(variables, ["y", "x"])
            guard case .extend(_, _, "y") = algebra else { XCTFail(); return }
            
            XCTAssert(true)
        } catch let e {
            XCTFail("\(e)")
        }
    }
    
    func testSubSelect() {
        guard var p = SPARQLParser(string: "SELECT ?x WHERE {\n{ SELECT ?x ?y { ?x ?y ?z } }}\n") else { XCTFail(); return }
        do {
            let a = try p.parse()
            guard case .project(let algebra, let variables) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            XCTAssertEqual(variables, ["x"])
            guard case .project(_, let subvariables) = algebra else {
                XCTFail("Unexpected algebra: \(algebra.serialize())");
                return
            }
            
            XCTAssertEqual(subvariables, ["x", "y"])
            XCTAssert(true)
        } catch let e {
            XCTFail("\(e)")
        }
    }

    func testBuiltinFunctionCallExpression() {
        guard var p = SPARQLParser(string: "SELECT * WHERE {\n_:s <p> ?x . FILTER ISNUMERIC(?x)\n}\n") else { XCTFail(); return }
        do {
            let a = try p.parse()
            guard case .filter(_, let expr) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            let expected : Expression = .call("ISNUMERIC", [.node(.variable("x", binding: true))])
            XCTAssertEqual(expr, expected)
        } catch let e {
            XCTFail("\(e)")
        }
    }
    
    func testFunctionCallExpression() {
        guard var p = SPARQLParser(string: "PREFIX ex: <http://example.org/> SELECT * WHERE {\n_:s <p> ?x . FILTER ex:function(?x)\n}\n") else { XCTFail(); return }
        do {
            let a = try p.parse()
            guard case .filter(_, let expr) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            let expected : Expression = .call("http://example.org/function", [.node(.variable("x", binding: true))])
            XCTAssertEqual(expr, expected)
        } catch let e {
            XCTFail("\(e)")
        }
    }
    
    func testAggregation1() {
        guard var p = SPARQLParser(string: "SELECT ?x (SUM(?y) AS ?z) WHERE {\n?x <p> ?y\n}\nGROUP BY ?x") else { XCTFail(); return }
        do {
            let a = try p.parse()
            guard case .project(let extend, let projection) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            guard case .extend(let agg, .node(.variable(".agg-1", _)), "z") = extend else {
                XCTFail("Unexpected algebra: \(extend.serialize())")
                return
            }
            
            guard case .aggregate(_, let groups, let aggs) = agg else {
                XCTFail("Unexpected algebra: \(agg.serialize())")
                return
            }
            
            XCTAssertEqual(aggs.count, 1)
            XCTAssertEqual(projection, ["x", "z"])
            guard case (.sum(_), ".agg-1") = aggs[0] else {
                XCTFail("Unexpected aggregation: \(aggs[0])")
                return
            }
            let expected : [Expression] = [.node(.variable("x", binding: true))]
            XCTAssertEqual(groups, expected)
        } catch let e {
            XCTFail("\(e)")
        }
    }
    
    func testAggregation2() {
        guard var p = SPARQLParser(string: "SELECT ?x (SUM(?y) AS ?sum) (AVG(?y) AS ?avg) WHERE {\n?x <p> ?y\n}\nGROUP BY ?x") else { XCTFail(); return }
        do {
            let a = try p.parse()
            guard case .project(let extend1, let projection) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            guard case .extend(let extend2, .node(.variable(".agg-2", _)), "avg") = extend1 else {
                XCTFail("Unexpected algebra: \(extend1.serialize())")
                return
            }
            
            guard case .extend(let agg, .node(.variable(".agg-1", _)), "sum") = extend2 else {
                XCTFail("Unexpected algebra: \(extend2.serialize())")
                return
            }
            
            guard case .aggregate(_, let groups, let aggs) = agg else {
                XCTFail("Unexpected algebra: \(agg.serialize())")
                return
            }
            
            XCTAssertEqual(aggs.count, 2)
            XCTAssertEqual(projection, ["x", "sum", "avg"])
            guard case (.sum(_), ".agg-1") = aggs[0] else {
                XCTFail("Unexpected aggregation: \(aggs[0])")
                return
            }
            guard case (.avg(_), ".agg-2") = aggs[1] else {
                XCTFail("Unexpected aggregation: \(aggs[1])")
                return
            }
            let expected : [Expression] = [.node(.variable("x", binding: true))]
            XCTAssertEqual(groups, expected)
        } catch let e {
            XCTFail("\(e)")
        }
    }
    
    func testAggregationGroupBy() {
        guard var p = SPARQLParser(string: "SELECT ?x WHERE {\n_:s <p> ?x\n}\nGROUP BY ?x") else { XCTFail(); return }
        do {
            let a = try p.parse()
            guard case .project(.aggregate(_, let groups, let aggs), let projection) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            XCTAssertEqual(aggs.count, 0)
            XCTAssertEqual(projection, ["x"])
            let expected : [Expression] = [.node(.variable("x", binding: true))]
            XCTAssertEqual(groups, expected)
        } catch let e {
            XCTFail("\(e)")
        }
    }
    
    func testAggregationHaving() {
        guard var p = SPARQLParser(string: "SELECT ?x WHERE {\n_:s <p> ?x\n}\nGROUP BY ?x HAVING (?x > 2)") else { XCTFail(); return }
        do {
            let a = try p.parse()
            guard case .project(.filter(.aggregate(_, let groups, let aggs), .gt(.node(.variable("x", binding: true)), .node(.bound(Term(value: "2", type: .datatype("http://www.w3.org/2001/XMLSchema#integer")))))), let projection) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            XCTAssertEqual(aggs.count, 0)
            XCTAssertEqual(projection, ["x"])
            let expected : [Expression] = [.node(.variable("x", binding: true))]
            XCTAssertEqual(groups, expected)
        } catch let e {
            XCTFail("\(e)")
        }
    }
    
    func testInlineData1() {
        guard var p = SPARQLParser(string: "SELECT ?x WHERE {\nVALUES ?x {7 2 3}\n}\n") else { XCTFail(); return }
        do {
            let a = try p.parse()
            guard case .project(let table, _) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            guard case .table(let nodes, let seq) = table else {
                XCTFail("Unexpected algebra: \(table.serialize())")
                return
            }
            
            let expectedInScope : [Node] = [.variable("x", binding: true)]
            XCTAssertEqual(nodes, expectedInScope)
            
            let terms = Array(seq)
            XCTAssertEqual(terms.count, 3)
            let term = terms[0]
            let expectedTerm = TermResult(bindings: ["x": Term(integer: 7)])
            XCTAssertEqual(term, expectedTerm)
        } catch let e {
            XCTFail("\(e)")
        }
    }

    func testInlineData2() {
        guard var p = SPARQLParser(string: "SELECT * WHERE {\n\n}\nVALUES (?x ?y) { (UNDEF 7) (2 UNDEF) }\n") else { XCTFail(); return }
        do {
            let a = try p.parse()
            guard case .innerJoin(.joinIdentity, let table) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            guard case .table(let nodes, let seq) = table else {
                XCTFail("Unexpected algebra: \(table.serialize())")
                return
            }
            
            let expectedInScope : [Node] = [.variable("x", binding: true), .variable("y", binding: true)]
            XCTAssertEqual(nodes, expectedInScope)
            
            let terms = Array(seq)
            XCTAssertEqual(terms.count, 2)
            let term = terms[0]
            let expectedTerm = TermResult(bindings: ["y": Term(integer: 7)])
            XCTAssertEqual(term, expectedTerm)
        } catch let e {
            XCTFail("\(e)")
        }
    }

    func testFilterNotIn() {
        guard var p = SPARQLParser(string: "SELECT * WHERE {\n?x ?y ?z . FILTER(?z NOT IN (1,2,3))\n}\n") else { XCTFail(); return }
        do {
            let a = try p.parse()
            guard case .filter(_, let expr) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            guard case .not(.valuein(_, _)) = expr else {
                XCTFail("Unexpected expression: \(expr.description)")
                return
            }
            
            XCTAssertEqual(expr.description, "?z NOT IN (1,2,3)")
        } catch let e {
            XCTFail("\(e)")
        }
    }
    
    func testList() {
        guard var p = SPARQLParser(string: "SELECT * WHERE { ( () ) }") else { XCTFail(); return }
        do {
            let a = try p.parse()
            guard case .bgp(let triples) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            XCTAssertEqual(triples.count, 2)
        } catch let e {
            XCTFail("\(e)")
        }
    }
    
    func testConstruct() {
        guard var p = SPARQLParser(string: "CONSTRUCT { ?s <p1> <o> . ?s <p2> ?o } WHERE {?s ?p ?o}") else { XCTFail(); return }
        do {
            let a = try p.parse()
            guard case .construct(.triple(_), let ctriples) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            XCTAssertEqual(ctriples.count, 2)
        } catch let e {
            XCTFail("\(e)")
        }
    }
    
    func testDescribe() {
        guard var p = SPARQLParser(string: "DESCRIBE <u>") else { XCTFail(); return }
        do {
            let a = try p.parse()
            guard case .describe(.joinIdentity, let nodes) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            XCTAssertEqual(nodes.count, 1)
        } catch let e {
            XCTFail("\(e)")
        }
    }
    
    func testNumericLiteral() {
        guard var p = SPARQLParser(string: "SELECT * WHERE { <a><b>-1 }") else { XCTFail(); return }
        do {
            let a = try p.parse()
            guard case .triple(_) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            XCTAssert(true)
        } catch let e {
            XCTFail("\(e)")
        }
    }
    
    func testBind() {
        guard var p = SPARQLParser(string: "PREFIX : <http://www.example.org> SELECT * WHERE { :s :p ?o . BIND((1+?o) AS ?o1) :s :q ?o1 }") else { XCTFail(); return }
        do {
            let a = try p.parse()
            guard case .innerJoin(.extend(_, _, _), _) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            XCTAssert(true)
        } catch let e {
            XCTFail("\(e)")
        }
    }
    
    func testConstructCollection1() {
        guard var p = SPARQLParser(string: "PREFIX : <http://www.example.org> CONSTRUCT { ?s :p (1 2) } WHERE { ?s ?p ?o }") else { XCTFail(); return }
        do {
            let a = try p.parse()
            guard case .construct(.triple(_), let template) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            XCTAssertEqual(template.count, 5)
        } catch let e {
            XCTFail("\(e)")
        }
    }
    
    func testConstructCollection2() {
        guard var p = SPARQLParser(string: "PREFIX : <http://www.example.org> CONSTRUCT { (1 2) :p ?o } WHERE { ?s ?p ?o }") else { XCTFail(); return }
        do {
            let a = try p.parse()
            guard case .construct(.triple(_), let template) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            XCTAssertEqual(template.count, 5)
        } catch let e {
            XCTFail("\(e)")
        }
    }
    
    func testConstructBlank() {
        guard var p = SPARQLParser(string: "PREFIX : <http://www.example.org> CONSTRUCT { [ :p ?o ] } WHERE { ?s ?p ?o }") else { XCTFail(); return }
        do {
            let a = try p.parse()
            guard case .construct(.triple(_), let template) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            XCTAssertEqual(template.count, 1)
        } catch let e {
            XCTFail("\(e)")
        }
    }
    
    func testI18N() {
        guard var p = SPARQLParser(string: "PREFIX foaf: <http://xmlns.com/foaf/0.1/> PREFIX 食: <http://www.w3.org/2001/sw/DataAccess/tests/data/i18n/kanji.ttl#> SELECT ?name ?food WHERE { [ foaf:name ?name ; 食:食べる ?food ] . }") else { XCTFail(); return }
        do {
            let a = try p.parse()
            print("\(a.serialize())")
            guard case .project(.innerJoin(.triple(let ta), .triple(let tb)), let variables) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            XCTAssertEqual(ta.subject, tb.subject)
            XCTAssertEqual(ta.predicate, .bound(Term(value: "http://xmlns.com/foaf/0.1/name", type: .iri)))
            XCTAssertEqual(ta.object, .variable("name", binding: true))
            
            XCTAssertEqual(tb.predicate, .bound(Term(value: "http://www.w3.org/2001/sw/DataAccess/tests/data/i18n/kanji.ttl#食べる", type: .iri)))
            XCTAssertEqual(tb.object, .variable("food", binding: true))
            
            XCTAssertEqual(variables, ["name", "food"])
        } catch let e {
            XCTFail("\(e)")
        }
    }
    
    func testIRIResolution() {
        guard var p = SPARQLParser(string: "BASE <http://example.org/foo/> SELECT * WHERE { ?s <p> <../bar> }") else { XCTFail(); return }
        do {
            let a = try p.parse()
            print("\(a.serialize())")
            guard case .triple(let triple) = a else {
                XCTFail("Unexpected algebra: \(a.serialize())")
                return
            }
            
            XCTAssertEqual(triple.subject, .variable("s", binding: true))
            XCTAssertEqual(triple.predicate, .bound(Term(value: "http://example.org/foo/p", type: .iri)))
            XCTAssertEqual(triple.object, .bound(Term(value: "http://example.org/bar", type: .iri)))
        } catch let e {
            XCTFail("\(e)")
        }
    }
}
