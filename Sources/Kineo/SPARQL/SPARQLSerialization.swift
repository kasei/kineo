//
//  SPARQLSerialization.swift
//  kineo-test
//
//  Created by Gregory Todd Williams on 4/12/18.
//  Copyright © 2018 Gregory Todd Williams. All rights reserved.
//

import Foundation
import SPARQLParser

public struct SPARQLSerializer {
    public init() {}
    
    public func serialize(_ algebra: Algebra) -> String {
        return self.serialize(algebra.sparqlQueryTokens())
    }
    
    public func serialize<S: Sequence>(_ tokens: S) -> String where S.Iterator.Element == SPARQLToken {
        var s = ""
        self.serialize(tokens, to: &s)
        return s
    }
    
    public func serialize<S: Sequence, Target: TextOutputStream>(_ tokens: S, to output: inout Target) where S.Iterator.Element == SPARQLToken {
        for (i, token) in tokens.enumerated() {
            if i > 0 {
                print(" ", terminator: "", to: &output)
            }
            print("\(token.sparql)", terminator: "", to: &output)
        }
    }
    
    private struct ParseState {
        // swiftlint:disable:next nesting
        struct NestingCallback {
            let level: [Int]
        }
        
        var indentLevel: Int   = 0
        var inSemicolon: Bool  = false
        var openParens: Int    = 0
//        {
//            didSet { checkCallbacks() }
//        }
        var openBraces: Int    = 0
//        {
//            didSet { checkCallbacks() }
//        }
        var openBrackets: Int  = 0
//        {
//            didSet { checkCallbacks() }
//        }
        var callbackStack: [NestingCallback] = []
//        mutating func checkCallbacks() {
//            let currentLevel = [openBraces, openBrackets, openParens]
//            //        println("current level: \(currentLevel)")
//            if let top = callbackStack.last {
//                //            println("-----> callback set for level: \(top.level)")
//                if top.level == currentLevel {
//                    //                println("*** MATCHED")
//                    top.code(self)
//                    callbackStack.removeLast()
//                }
//            }
//        }
        
        mutating func checkBookmark() -> Bool {
            let currentLevel = [openBraces, openBrackets, openParens]
            if let top = callbackStack.last {
                if top.level == currentLevel {
                    callbackStack.removeLast()
                    return true
                }
            }
            return false
        }
        
        mutating func registerForClose() {
            let currentLevel = [openBraces, openBrackets, openParens]
            let cb = NestingCallback(level: currentLevel)
            callbackStack.append(cb)
        }
    }
    
    struct SerializerState {
        var spaceSeparator = " "
        var indent = "\t"
    }
    
    enum SerializerOutput {
        case newline(Int)
        case spaceSeparator
        case tokenString(String)
        
        var description: String {
            switch self {
            case .newline(_):
                return "␤"
            case .spaceSeparator:
                return "␠"
            case .tokenString(let s):
                return "\"\(s)\""
            }
        }
    }
    
    public func serializePretty<S: Sequence>(_ tokenSequence: S) -> String where S.Iterator.Element == SPARQLToken {
        var s = ""
        self.serializePretty(tokenSequence, to: &s)
        return s
    }
    
    // swiftlint:disable:next cyclomatic_complexity
    public func serializePretty<S: Sequence, Target: TextOutputStream>(_ tokenSequence: S, to output: inout Target) where S.Iterator.Element == SPARQLToken {
        var tokens = Array(tokenSequence)
        tokens.append(.ws)
        var pretty = ""
        var outputArray: [(SPARQLToken, SerializerOutput)] = []
        var pstate = ParseState()
        //        var sstate_stack = [SerializerState()]
        for i in 0..<(tokens.count-1) {
            let t = tokens[i]
            let u = tokens[i+1]
            //        println("handling token: \(t.sparqlStringWithDefinedPrefixes([:]))")
            
            if case .rbrace = t {
                pstate.openBraces -= 1
                pstate.indentLevel -= 1
                pstate.inSemicolon  = false
                if pstate.checkBookmark() {
                    outputArray.append((t, .newline(pstate.indentLevel)))
                }
            }
            
            //                let value = t.value() as! String
            let state = (pstate.openBraces, t, u)
            
            switch state {
            case (_, .keyword("FILTER"), .lparen), (_, .keyword("BIND"), .lparen), (_, .keyword("HAVING"), .lparen):
                pstate.registerForClose()
            default:
                break
            }
            
            switch state {
            case (_, .lbrace, _):
                //                 '{' $            -> '{' NEWLINE_INDENT
                outputArray.append((t, .tokenString("\(t.sparql)")))
                outputArray.append((t, .newline(1+pstate.indentLevel)))
            case (0, _, .lbrace):
                // {openBraces=0}    $ '{'            -> $
                outputArray.append((t, .tokenString("\(t.sparql)")))
                outputArray.append((t, .spaceSeparator))
            case (_, .rbrace, _):
                // a right brace should be on a line by itself
                //                 '}' $            -> NEWLINE_INDENT '}' NEWLINE_INDENT
                outputArray.append((t, .newline(pstate.indentLevel)))
                outputArray.append((t, .tokenString("\(t.sparql)")))
                outputArray.append((t, .newline(pstate.indentLevel)))
            case (_, .keyword("EXISTS"), .lbrace), (_, .keyword("OPTIONAL"), .lbrace), (_, .keyword("UNION"), .lbrace):
                //                 EXISTS '{'        -> EXISTS SPACE_SEP
                //                 OPTIONAL '{'    -> OPTIONAL SPACE_SEP
                //                 UNION '{'        -> UNION SPACE_SEP
                outputArray.append((t, .tokenString("\(t.sparql)")))
                outputArray.append((t, .spaceSeparator))
            case (_, .comment(let c), _):
                if c.count > 0 {
                    outputArray.append((t, .tokenString("\(t.sparql)")))
                    outputArray.append((t, .newline(pstate.indentLevel)))
                }
            case(_, .bang, _):
                outputArray.append((t, .tokenString("\(t.sparql)")))
            case (_, _, .lbrace):
                // {openBraces=_}    $ '{'            -> $ NEWLINE_INDENT
                outputArray.append((t, .tokenString("\(t.sparql)")))
                outputArray.append((t, .newline(pstate.indentLevel)))
            case (_, _, .keyword("PREFIX")), (_, _, .keyword("SELECT")), (_, _, .keyword("ASK")), (_, _, .keyword("CONSTRUCT")), (_, _, .keyword("DESCRIBE")):
                // newline before these keywords
                outputArray.append((t, .tokenString("\(t.sparql)")))
                outputArray.append((t, .newline(pstate.indentLevel)))
            case (_, .keyword("GROUP"), _), (_, .keyword("HAVING"), _), (_, .keyword("ORDER"), _), (_, .keyword("LIMIT"), _), (_, .keyword("OFFSET"), _):
                // newline before, and a space after these keywords
                outputArray.append((t, .newline(pstate.indentLevel)))
                outputArray.append((t, .tokenString("\(t.sparql)")))
                outputArray.append((t, .spaceSeparator))
            case (_, .dot, _):
                // newline after all DOTs
                outputArray.append((t, .tokenString("\(t.sparql)")))
                outputArray.append((t, .newline(pstate.indentLevel)))
            case (_, .semicolon, _):
                // newline after all SEMICOLONs
                outputArray.append((t, .tokenString("\(t.sparql)")))
                outputArray.append((t, .newline(pstate.indentLevel+1)))
            case (_, .keyword("FILTER"), _), (_, .keyword("BIND"), _):
                // newline before these keywords
                //                 'FILTER' $        -> NEWLINE_INDENT 'FILTER'                { set no SPACE_SEP }
                //                 'BIND' '('        -> NEWLINE_INDENT 'BIND'                { set no SPACE_SEP }
                outputArray.append((t, .newline(pstate.indentLevel)))
                outputArray.append((t, .tokenString("\(t.sparql)")))
            case (_, .hathat, _):
                // no trailing whitespace after ^^ (it's probably followed by an IRI or PrefixName
                outputArray.append((t, .tokenString("\(t.sparql)")))
            case (_, .keyword("ASC"), _), (_, .keyword("DESC"), _):
                // no trailing whitespace after these keywords (they're probably followed by a LPAREN
                outputArray.append((t, .tokenString("\(t.sparql)")))
            case (_, _, .rparen):
                // no space between any token and a following rparen
                outputArray.append((t, .tokenString("\(t.sparql)")))
            case (_, .lparen, _):
                // no space between a lparen and any following token
                outputArray.append((t, .tokenString("\(t.sparql)")))
            case (_, .keyword(let kw), .lparen) where SPARQLLexer.validFunctionNames.contains(kw):
                //                 KEYWORD '('        -> KEYWORD                                { set no SPACE_SEP }
                outputArray.append((t, .tokenString("\(t.sparql)")))
            case (_, .prefixname, .lparen):
                // function call; supress space between function IRI and opening paren
                outputArray.append((t, .tokenString("\(t.sparql)")))
            case (_, _, .hathat):
                // no space in between any token and a ^^
                outputArray.append((t, .tokenString("\(t.sparql)")))
            default:
                //                 $ $                -> $ ' '
                outputArray.append((t, .tokenString("\(t.sparql)")))
                outputArray.append((t, .spaceSeparator))
            }
            
            switch t {
            case .dot:
                pstate.inSemicolon  = false
            case .lbrace:
                pstate.indentLevel += 1
                pstate.openBraces += 1
            case .lbracket:
                pstate.openBrackets += 1
            case .rbracket:
                pstate.openBrackets -= 1
            case .lparen:
                pstate.openParens += 1
            case .rparen:
                pstate.openParens -= 1
            default:
                break
            }
        }
        
        var tempArray: [SerializerOutput] = []
        FILTER: for i in 0..<(outputArray.count-1) {
            let (_, s1) = outputArray[i]
            let (_, s2) = outputArray[i+1]
            switch (s1, s2) {
            case (.spaceSeparator, .newline(_)), (.newline(_), .newline(_)):
                continue FILTER
            case (.newline(_), .spaceSeparator):
                outputArray[i+1] = outputArray[i]
                continue FILTER
            default:
                tempArray.append(s1)
            }
        }
        LOOP: while tempArray.count > 0 {
            if let l = tempArray.last {
                switch l {
                case .tokenString(_):
                    break LOOP
                default:
                    tempArray.removeLast()
                }
            } else {
                break
            }
        }
        
        for s in tempArray {
            switch s {
            case .newline(let indent):
                pretty += "\n"
                if indent > 0 {
                    for _ in 0..<indent {
                        pretty += "\t"
                    }
                }
            case .spaceSeparator:
                pretty += " "
            case .tokenString(let string):
                pretty += string
            }
        }
        
        print(pretty, to: &output)
    }
    
}

extension Term {
    public var sparqlTokens: AnySequence<SPARQLToken> {
        switch self.type {
        case .blank:
            return AnySequence([.bnode(self.value)])
        case .iri:
            return AnySequence([.iri(self.value)])
        case .datatype("http://www.w3.org/2001/XMLSchema#string"):
            return AnySequence<SPARQLToken>([.string1d(self.value)])
        case .datatype(let d):
            return AnySequence<SPARQLToken>([.string1d(self.value), .hathat, .iri(d)])
        case .language(let l):
            return AnySequence<SPARQLToken>([.string1d(self.value), .lang(l)])
        }
    }
}

extension Node {
    public var sparqlTokens: AnySequence<SPARQLToken> {
        switch self {
        case .variable(let name, _):
            return AnySequence([._var(name)])
        case .bound(let term):
            return term.sparqlTokens
        }
    }
}

extension TriplePattern {
    public var sparqlTokens: AnySequence<SPARQLToken> {
        var tokens = [SPARQLToken]()
        tokens.append(contentsOf: self.subject.sparqlTokens)
        
        if self.predicate == .bound(Term.rdf("type")) {
            tokens.append(.keyword("A"))
        } else {
            tokens.append(contentsOf: self.predicate.sparqlTokens)
        }
        tokens.append(contentsOf: self.object.sparqlTokens)
        tokens.append(.dot)
        return AnySequence(tokens)
    }
}

extension QuadPattern {
    public var sparqlTokens: AnySequence<SPARQLToken> {
        var tokens = [SPARQLToken]()
        tokens.append(.keyword("GRAPH"))
        tokens.append(contentsOf: self.graph.sparqlTokens)
        tokens.append(.lbrace)
        tokens.append(contentsOf: self.subject.sparqlTokens)
        if self.predicate == .bound(Term.xsd("type")) {
            tokens.append(.keyword("A"))
        } else {
            tokens.append(contentsOf: self.predicate.sparqlTokens)
        }
        tokens.append(contentsOf: self.object.sparqlTokens)
        tokens.append(.dot)
        tokens.append(.rbrace)
        return AnySequence(tokens)
    }
}

extension PropertyPath {
    public var sparqlTokens: AnySequence<SPARQLToken> {
        var tokens = [SPARQLToken]()
        switch self {
        case .link(let term):
            tokens.append(contentsOf: term.sparqlTokens)
        case .inv(let path):
            tokens.append(.hat)
            tokens.append(contentsOf: path.sparqlTokens)
        case .nps(let terms):
            tokens.append(.bang)
            tokens.append(.lparen)
            for (n, term) in terms.enumerated() {
                if n > 0 {
                    tokens.append(.or)
                }
                tokens.append(contentsOf: term.sparqlTokens)
            }
            tokens.append(.rparen)
        case .alt(let lhs, let rhs):
            tokens.append(contentsOf: lhs.sparqlTokens)
            tokens.append(.or)
            tokens.append(contentsOf: rhs.sparqlTokens)
        case .seq(let lhs, let rhs):
            tokens.append(contentsOf: lhs.sparqlTokens)
            tokens.append(.slash)
            tokens.append(contentsOf: rhs.sparqlTokens)
        case .plus(let path):
            tokens.append(.lparen)
            tokens.append(contentsOf: path.sparqlTokens)
            tokens.append(.rparen)
            tokens.append(.plus)
        case .star(let path):
            tokens.append(.lparen)
            tokens.append(contentsOf: path.sparqlTokens)
            tokens.append(.rparen)
            tokens.append(.star)
        case .zeroOrOne(let path):
            tokens.append(.lparen)
            tokens.append(contentsOf: path.sparqlTokens)
            tokens.append(.rparen)
            tokens.append(.question)
        }
        return AnySequence(tokens)
    }
}

extension Expression {
    public var needsSurroundingParentheses: Bool {
        switch self {
        case .isiri(_), .isblank(_), .isliteral(_), .isnumeric(_), .exists(_), .not(.exists(_)), .call(_):
            return false
        default:
            return true
        }
    }
    
    public func sparqlTokens() -> AnySequence<SPARQLToken> {
        var tokens = [SPARQLToken]()
        switch self {
        case .node(let n):
            return n.sparqlTokens
        case .aggregate(let a):
            return a.sparqlTokens()
        case .neg(let e):
            tokens.append(.minus)
            tokens.append(contentsOf: e.sparqlTokens())
        case .not(.exists(let lhs)):
            tokens.append(.keyword("NOT"))
            tokens.append(.keyword("EXISTS"))
            tokens.append(.lbrace)
            tokens.append(contentsOf: lhs.sparqlTokens(depth: 0))
            tokens.append(.rbrace)
        case .not(let e):
            tokens.append(.bang)
            tokens.append(contentsOf: e.sparqlTokens())
        case .isiri(let e):
            tokens.append(.keyword("ISIRI"))
            tokens.append(.lparen)
            tokens.append(contentsOf: e.sparqlTokens())
            tokens.append(.rparen)
        case .isblank(let e):
            tokens.append(.keyword("ISBLANK"))
            tokens.append(.lparen)
            tokens.append(contentsOf: e.sparqlTokens())
            tokens.append(.rparen)
        case .isliteral(let e):
            tokens.append(.keyword("ISLITERAL"))
            tokens.append(.lparen)
            tokens.append(contentsOf: e.sparqlTokens())
            tokens.append(.rparen)
        case .isnumeric(let e):
            tokens.append(.keyword("ISNUMERIC"))
            tokens.append(.lparen)
            tokens.append(contentsOf: e.sparqlTokens())
            tokens.append(.rparen)
        case .lang(let e):
            tokens.append(.keyword("LANG"))
            tokens.append(.lparen)
            tokens.append(contentsOf: e.sparqlTokens())
            tokens.append(.rparen)
        case .langmatches(let e, let p):
            tokens.append(.keyword("LANGMATCHES"))
            tokens.append(.lparen)
            tokens.append(contentsOf: e.sparqlTokens())
            tokens.append(.comma)
            tokens.append(contentsOf: p.sparqlTokens())
            tokens.append(.rparen)
        case .datatype(let e):
            tokens.append(.keyword("DATATYPE"))
            tokens.append(.lparen)
            tokens.append(contentsOf: e.sparqlTokens())
            tokens.append(.rparen)
        case .bound(let e):
            tokens.append(.keyword("BOUND"))
            tokens.append(.lparen)
            tokens.append(contentsOf: e.sparqlTokens())
            tokens.append(.rparen)
        case .intCast(let e):
            tokens.append(contentsOf: Term.xsd("integer").sparqlTokens)
            tokens.append(.lparen)
            tokens.append(contentsOf: e.sparqlTokens())
            tokens.append(.rparen)
        case .floatCast(let e):
            tokens.append(contentsOf: Term.xsd("float").sparqlTokens)
            tokens.append(.lparen)
            tokens.append(contentsOf: e.sparqlTokens())
            tokens.append(.rparen)
        case .doubleCast(let e):
            tokens.append(contentsOf: Term.xsd("double").sparqlTokens)
            tokens.append(.lparen)
            tokens.append(contentsOf: e.sparqlTokens())
            tokens.append(.rparen)
        case .eq(let lhs, let rhs):
            tokens.append(contentsOf: lhs.sparqlTokens())
            tokens.append(.equals)
            tokens.append(contentsOf: rhs.sparqlTokens())
        case .ne(let lhs, let rhs):
            tokens.append(contentsOf: lhs.sparqlTokens())
            tokens.append(.notequals)
            tokens.append(contentsOf: rhs.sparqlTokens())
        case .lt(let lhs, let rhs):
            tokens.append(contentsOf: lhs.sparqlTokens())
            tokens.append(.lt)
            tokens.append(contentsOf: rhs.sparqlTokens())
        case .le(let lhs, let rhs):
            tokens.append(contentsOf: lhs.sparqlTokens())
            tokens.append(.le)
            tokens.append(contentsOf: rhs.sparqlTokens())
        case .gt(let lhs, let rhs):
            tokens.append(contentsOf: lhs.sparqlTokens())
            tokens.append(.gt)
            tokens.append(contentsOf: rhs.sparqlTokens())
        case .ge(let lhs, let rhs):
            tokens.append(contentsOf: lhs.sparqlTokens())
            tokens.append(.ge)
            tokens.append(contentsOf: rhs.sparqlTokens())
        case .add(let lhs, let rhs):
            tokens.append(contentsOf: lhs.sparqlTokens())
            tokens.append(.plus)
            tokens.append(contentsOf: rhs.sparqlTokens())
        case .sub(let lhs, let rhs):
            tokens.append(contentsOf: lhs.sparqlTokens())
            tokens.append(.minus)
            tokens.append(contentsOf: rhs.sparqlTokens())
        case .div(let lhs, let rhs):
            tokens.append(contentsOf: lhs.sparqlTokens())
            tokens.append(.slash)
            tokens.append(contentsOf: rhs.sparqlTokens())
        case .mul(let lhs, let rhs):
            tokens.append(contentsOf: lhs.sparqlTokens())
            tokens.append(.star)
            tokens.append(contentsOf: rhs.sparqlTokens())
        case .and(let lhs, let rhs):
            tokens.append(contentsOf: lhs.sparqlTokens())
            tokens.append(.andand)
            tokens.append(contentsOf: rhs.sparqlTokens())
        case .or(let lhs, let rhs):
            tokens.append(contentsOf: lhs.sparqlTokens())
            tokens.append(.oror)
            tokens.append(contentsOf: rhs.sparqlTokens())
        case .between(let e, let lhs, let rhs):
            let expr : Expression = .and(.ge(e, lhs), .le(e, rhs))
            return expr.sparqlTokens()
        case .valuein(let e, let values):
            tokens.append(contentsOf: e.sparqlTokens())
            tokens.append(.keyword("IN"))
            tokens.append(.lparen)
            for (i, v) in values.enumerated() {
                if i > 0 {
                    tokens.append(.comma)
                }
                tokens.append(contentsOf: v.sparqlTokens())
            }
            tokens.append(.rparen)
        case .call(let f, let values):
            let term = Term(iri: f)
            tokens.append(contentsOf: term.sparqlTokens)
            tokens.append(.lparen)
            for (i, v) in values.enumerated() {
                if i > 0 {
                    tokens.append(.comma)
                }
                tokens.append(contentsOf: v.sparqlTokens())
            }
            tokens.append(.rparen)
        case .exists(let lhs):
            tokens.append(.keyword("EXISTS"))
            tokens.append(.lbrace)
            tokens.append(contentsOf: lhs.sparqlTokens(depth: 0))
            tokens.append(.rbrace)
        }
        return AnySequence(tokens)
    }
}

extension Aggregation {
    public func sparqlTokens() -> AnySequence<SPARQLToken> {
        var tokens = [SPARQLToken]()
        switch self {
        case .countAll:
            tokens.append(.keyword("COUNT"))
            tokens.append(.lparen)
            tokens.append(.star)
            tokens.append(.rparen)
        case .count(let e, let distinct):
            tokens.append(.keyword("COUNT"))
            tokens.append(.lparen)
            if distinct {
                tokens.append(.keyword("DISTINCT"))
            }
            tokens.append(contentsOf: e.sparqlTokens())
            tokens.append(.rparen)
        case .sum(let e, let distinct):
            tokens.append(.keyword("SUM"))
            tokens.append(.lparen)
            if distinct {
                tokens.append(.keyword("DISTINCT"))
            }
            tokens.append(contentsOf: e.sparqlTokens())
            tokens.append(.rparen)
        case .avg(let e, let distinct):
            tokens.append(.keyword("AVG"))
            tokens.append(.lparen)
            if distinct {
                tokens.append(.keyword("DISTINCT"))
            }
            tokens.append(contentsOf: e.sparqlTokens())
            tokens.append(.rparen)
        case .min(let e):
            tokens.append(.keyword("MIN"))
            tokens.append(.lparen)
            tokens.append(contentsOf: e.sparqlTokens())
            tokens.append(.rparen)
        case .max(let e):
            tokens.append(.keyword("MAX"))
            tokens.append(.lparen)
            tokens.append(contentsOf: e.sparqlTokens())
            tokens.append(.rparen)
        case .sample(let e):
            tokens.append(.keyword("SAMPLE"))
            tokens.append(.lparen)
            tokens.append(contentsOf: e.sparqlTokens())
            tokens.append(.rparen)
        case .groupConcat(let e, let sep, let distinct):
            tokens.append(.keyword("GROUP_CONCAT"))
            tokens.append(.lparen)
            if distinct {
                tokens.append(.keyword("DISTINCT"))
            }
            tokens.append(contentsOf: e.sparqlTokens())
            if sep != " " {
                tokens.append(.semicolon)
                tokens.append(.keyword("GROUP_CONCAT"))
                tokens.append(.semicolon)
                tokens.append(.keyword("SEPARATOR"))
                tokens.append(.equals)
                let t = Term(string: sep)
                tokens.append(contentsOf: t.sparqlTokens)
            }
            tokens.append(.rparen)
        }
        return AnySequence(tokens)
    }
}

extension Algebra {
    var serializableEquivalent: Algebra {
        switch self {
        case .unionIdentity:
            fatalError("cannot serialize the union identity in SPARQL")
        case .joinIdentity:
            return self
        case .quad(_), .triple(_), .table(_), .bgp(_):
            return self
        case .innerJoin(let lhs, let rhs):
            return .innerJoin(lhs.serializableEquivalent, rhs.serializableEquivalent)
        case .leftOuterJoin(let lhs, let rhs, let expr):
            return .leftOuterJoin(lhs.serializableEquivalent, rhs.serializableEquivalent, expr)
        case .filter(let lhs, let expr):
            return .filter(lhs.serializableEquivalent, expr)
        case .union(let lhs, let rhs):
            return .union(lhs.serializableEquivalent, rhs.serializableEquivalent)
        case .namedGraph(let lhs, let graph):
            return .namedGraph(lhs.serializableEquivalent, graph)
        case .extend(let lhs, let expr, let name):
            return .extend(lhs.serializableEquivalent, expr, name)
        case .minus(let lhs, let rhs):
            return .minus(lhs.serializableEquivalent, rhs.serializableEquivalent)
        case .project(let lhs, let names):
            return .project(lhs.serializableEquivalent, names)
        case .distinct(let lhs):
            switch lhs {
            case .slice(_), .order(_), .aggregate(_), .project(_):
                return .distinct(lhs.serializableEquivalent)
            default:
                return .distinct(.project(lhs.serializableEquivalent, lhs.inscope))
            }
        case .service(let endpoint, let lhs, let silent):
            return .service(endpoint, lhs.serializableEquivalent, silent)
        case .slice(let lhs, let offset, let limit):
            switch lhs {
            case .order(_), .aggregate(_), .project(_):
                return .slice(lhs.serializableEquivalent, offset, limit)
            default:
                return .slice(.project(lhs.serializableEquivalent, lhs.inscope), offset, limit)
            }
        case .order(let lhs, let cmps):
            switch lhs {
            case .aggregate(_), .project(_):
                return .order(lhs.serializableEquivalent, cmps)
            default:
                return .order(.project(lhs.serializableEquivalent, lhs.inscope), cmps)
            }
        case .path(_):
            return self
        case .aggregate(let lhs, let groups, let aggs):
            switch lhs {
            case .project(_):
                return .aggregate(lhs.serializableEquivalent, groups, aggs)
            default:
                fatalError("cannot serialize an aggregation whose child is not a projection operator")
            }
        case .window(let lhs, let exprs, let funcs):
            return .window(lhs.serializableEquivalent, exprs, funcs)
        case .subquery(_):
            return self
        }
    }
    
    public func sparqlQueryTokens() -> AnySequence<SPARQLToken> {
        let a = self.serializableEquivalent
        
        switch a {
        case .project(_), .aggregate(_), .order(.project(_), _), .slice(.project(_), _, _), .slice(.order(.project(_), _), _, _), .distinct(_):
            return a.sparqlTokens(depth: 0)
        default:
            let wrapped: Algebra = .project(a, a.inscope)
            return wrapped.sparqlTokens(depth: 0)
        }
    }
    
    // swiftlint:disable:next cyclomatic_complexity
    public func sparqlTokens(depth: Int) -> AnySequence<SPARQLToken> {
        switch self {
        case .unionIdentity:
            fatalError("cannot serialize the union identity as a SPARQL token sequence")
        case .joinIdentity:
            return AnySequence([.lbrace, .rbrace])
        case .quad(let q):
            return q.sparqlTokens
        case .triple(let t):
            return t.sparqlTokens
        case .bgp(let triples):
            let tokens = triples.map { $0.sparqlTokens }.flatMap { $0 }
            return AnySequence(tokens)
        case .innerJoin(let rhs, let lhs):
            let tokens = [rhs, lhs].map { $0.sparqlTokens(depth: depth) }.flatMap { $0 }
            return AnySequence(tokens)
        case .leftOuterJoin(let lhs, let rhs, let expr):
            var tokens = [SPARQLToken]()
            tokens.append(.lbrace)
            tokens.append(contentsOf: lhs.sparqlTokens(depth: depth+1))
            tokens.append(.rbrace)
            tokens.append(.keyword("OPTIONAL"))
            tokens.append(.lbrace)
            tokens.append(contentsOf: rhs.sparqlTokens(depth: depth+1))
            if expr != .node(.bound(Term.trueValue)) {
                tokens.append(.keyword("FILTER"))
                if expr.needsSurroundingParentheses {
                    tokens.append(.lparen)
                    tokens.append(contentsOf: expr.sparqlTokens())
                    tokens.append(.rparen)
                } else {
                    tokens.append(contentsOf: expr.sparqlTokens())
                }
            }
            tokens.append(.rbrace)
            return AnySequence(tokens)
        case .minus(let lhs, let rhs):
            var tokens = [SPARQLToken]()
            tokens.append(.lbrace)
            tokens.append(contentsOf: lhs.sparqlTokens(depth: depth+1))
            tokens.append(.rbrace)
            tokens.append(.keyword("MINUS"))
            tokens.append(.lbrace)
            tokens.append(contentsOf: rhs.sparqlTokens(depth: depth+1))
            tokens.append(.rbrace)
            return AnySequence(tokens)
        case .filter(let lhs, let expr):
            var tokens = [SPARQLToken]()
            tokens.append(contentsOf: lhs.sparqlTokens(depth: depth))
            tokens.append(.keyword("FILTER"))
            if expr.needsSurroundingParentheses {
                tokens.append(.lparen)
                tokens.append(contentsOf: expr.sparqlTokens())
                tokens.append(.rparen)
            } else {
                tokens.append(contentsOf: expr.sparqlTokens())
            }
            return AnySequence(tokens)
        case .union(let lhs, let rhs):
            var tokens = [SPARQLToken]()
            tokens.append(.lbrace)
            tokens.append(contentsOf: lhs.sparqlTokens(depth: depth+1))
            tokens.append(.rbrace)
            tokens.append(.keyword("UNION"))
            tokens.append(.lbrace)
            tokens.append(contentsOf: rhs.sparqlTokens(depth: depth+1))
            tokens.append(.rbrace)
            return AnySequence(tokens)
        case .namedGraph(let lhs, let graph):
            var tokens = [SPARQLToken]()
            tokens.append(.keyword("GRAPH"))
            tokens.append(contentsOf: graph.sparqlTokens)
            tokens.append(.lbrace)
            tokens.append(contentsOf: lhs.sparqlTokens(depth: depth+1))
            tokens.append(.rbrace)
            return AnySequence(tokens)
        case .service(let endpoint, let lhs, let silent):
            var tokens = [SPARQLToken]()
            tokens.append(.keyword("SERVICE"))
            if silent {
                tokens.append(.keyword("SILENT"))
            }
            tokens.append(contentsOf: endpoint.sparqlTokens)
            tokens.append(.lbrace)
            tokens.append(contentsOf: lhs.sparqlTokens(depth: depth+1))
            tokens.append(.rbrace)
            return AnySequence(tokens)
        case .extend(let lhs, let expr, let name):
            var tokens = [SPARQLToken]()
            tokens.append(contentsOf: lhs.sparqlTokens(depth: depth))
            tokens.append(.keyword("BIND"))
            tokens.append(.lparen)
            tokens.append(contentsOf: expr.sparqlTokens())
            tokens.append(.keyword("AS"))
            tokens.append(._var(name))
            tokens.append(.rparen)
            return AnySequence(tokens)
        case .table(let nodes, let rows):
            var tokens = [SPARQLToken]()
            tokens.append(.keyword("VALUES"))
            tokens.append(.lparen)
            var names = [String]()
            for n in nodes {
                guard case .variable(let name, _) = n else { fatalError() }
                tokens.append(contentsOf: n.sparqlTokens)
                names.append(name)
            }
            tokens.append(contentsOf: nodes.map { $0.sparqlTokens }.flatMap { $0 })
            tokens.append(.rparen)
            tokens.append(.lbrace)
            for row in rows {
                tokens.append(.lparen)
                for n in row {
                    if let term = n {
                        tokens.append(contentsOf: term.sparqlTokens)
                    } else {
                        tokens.append(.keyword("UNDEF"))
                    }
                }
                tokens.append(.rparen)
            }
            tokens.append(.rbrace)
            return AnySequence(tokens)
        case .project(let lhs, _), .distinct(let lhs), .slice(let lhs, _, _), .order(let lhs, _):
            var tokens = [SPARQLToken]()
            // Projection, ordering, distinct, and slice serialization happens in Query.sparqlTokens, so this just serializes the child algebra
            tokens.append(contentsOf: lhs.sparqlTokens(depth: depth+1))
            return AnySequence(tokens)
        case .path(let lhs, let path, let rhs):
            var tokens = [SPARQLToken]()
            tokens.append(contentsOf: lhs.sparqlTokens)
            tokens.append(contentsOf: path.sparqlTokens)
            tokens.append(contentsOf: rhs.sparqlTokens)
            tokens.append(.dot)
            return AnySequence(tokens)
        case .subquery(let q):
            var tokens = [SPARQLToken]()
            tokens.append(.lbrace)
            tokens.append(contentsOf: q.sparqlTokens)
            tokens.append(.rbrace)
            return AnySequence(tokens)
        case .aggregate(let lhs, let groups, let aggs):
            fatalError("TODO: implement sparqlTokens() on aggregate: \(lhs) \(groups) \(aggs)")
        case .window(let lhs, let groups, let funcs):
            fatalError("TODO: implement sparqlTokens() on window: \(lhs) \(groups) \(funcs)")
        }
    }
}

extension Query {
    public var sparqlTokens: AnySequence<SPARQLToken> {
        var tokens = [SPARQLToken]()
        // TODO: handle projection of aggregate/window functions
        // TODO: handle projection of select expressions
        switch self.form {
        case .select(.star):
            tokens.append(.keyword("SELECT"))
            if self.algebra.distinct {
                tokens.append(.keyword("DISTINCT"))
            }
            tokens.append(.star)
            tokens.append(.keyword("WHERE"))
            tokens.append(.lbrace)
            tokens.append(contentsOf: self.algebra.sparqlTokens(depth: 0))
            tokens.append(.rbrace)
        case .select(.variables(let vars)):
            tokens.append(.keyword("SELECT"))
            if self.algebra.distinct {
                tokens.append(.keyword("DISTINCT"))
            }
            for v in vars {
                let v : Node = .variable(v, binding: true)
                tokens.append(contentsOf: v.sparqlTokens)
            }
            tokens.append(.keyword("WHERE"))
            tokens.append(.lbrace)
            tokens.append(contentsOf: self.algebra.sparqlTokens(depth: 0))
            tokens.append(.rbrace)
        case .ask:
            tokens.append(.keyword("ASK"))
            tokens.append(.lbrace)
            tokens.append(contentsOf: self.algebra.sparqlTokens(depth: 0))
            tokens.append(.rbrace)
        case .describe(let nodes):
            tokens.append(.keyword("DESCRIBE"))
            for n in nodes {
                tokens.append(contentsOf: n.sparqlTokens)
            }
            tokens.append(.keyword("WHERE"))
            tokens.append(.lbrace)
            tokens.append(contentsOf: self.algebra.sparqlTokens(depth: 0))
            tokens.append(.rbrace)
        case .construct(let patterns):
            tokens.append(.keyword("CONSTRUCT"))
            tokens.append(.lbrace)
            for p in patterns {
                tokens.append(contentsOf: p.sparqlTokens)
            }
            tokens.append(.rbrace)
            tokens.append(.keyword("WHERE"))
            tokens.append(.lbrace)
            tokens.append(contentsOf: self.algebra.sparqlTokens(depth: 0))
            tokens.append(.rbrace)
        }
        
        switch self.form {
        case .select(_):
            if let cmps = self.algebra.sortComparators {
                tokens.append(.keyword("ORDER"))
                tokens.append(.keyword("BY"))
                for (asc, expr) in cmps {
                    if asc {
                        tokens.append(contentsOf: expr.sparqlTokens())
                    } else {
                        tokens.append(.keyword("DESC"))
                        tokens.append(.lparen)
                        tokens.append(contentsOf: expr.sparqlTokens())
                        tokens.append(.rparen)
                    }
                }
            }
        default:
            break
        }

        switch self.form {
        case .select(_), .construct(_):
            if let offset = self.algebra.offset {
                tokens.append(.keyword("OFFSET"))
                tokens.append(.integer("\(offset)"))
            }
            if let limit = self.algebra.limit {
                tokens.append(.keyword("LIMIT"))
                tokens.append(.integer("\(limit)"))
            }
        default:
            break
        }
        return AnySequence(tokens)
    }
}

public extension Algebra {
    var sortComparators: [SortComparator]? {
        switch self {
        case .unionIdentity, .joinIdentity:
            return nil
        case .table(_, _), .quad(_), .triple(_), .bgp(_), .innerJoin(_, _), .leftOuterJoin(_, _, _),
             .union(_, _), .minus(_, _), .service(_, _, _), .path(_, _, _),
             .aggregate(_, _, _), .window(_, _, _), .subquery(_):
            return nil
        case .filter(let child, _), .namedGraph(let child, _), .extend(let child, _, _), .project(let child, _), .slice(let child, _, _), .distinct(let child):
            return child.sortComparators
        case .order(_, let cmps):
            return cmps
        }
    }
    
    var distinct: Bool {
        switch self {
        case .distinct(_):
            return true
        case .unionIdentity, .joinIdentity:
            return false
        case .table(_, _), .quad(_), .triple(_), .bgp(_), .innerJoin(_, _), .leftOuterJoin(_, _, _),
             .filter(_, _), .union(_, _), .minus(_, _), .service(_, _, _), .path(_, _, _), .namedGraph(_, _),
             .aggregate(_, _, _), .window(_, _, _), .subquery(_), .project(_, _):
            return false
        case .extend(let child, _, _), .order(let child, _), .slice(let child, _, _):
            return child.distinct
        }
    }
    
    var limit: Int? {
        switch self {
        case .unionIdentity, .joinIdentity:
            return nil
        case .table(_, _), .quad(_), .triple(_), .bgp(_), .innerJoin(_, _), .leftOuterJoin(_, _, _),
             .filter(_, _), .union(_, _), .minus(_, _), .distinct(_), .service(_, _, _), .path(_, _, _),
             .aggregate(_, _, _), .window(_, _, _), .subquery(_):
            return nil
        case .namedGraph(let child, _), .extend(let child, _, _), .project(let child, _), .order(let child, _):
            return child.limit
        case .slice(_, _, let l):
            return l
        }
    }
    
    var offset: Int? {
        switch self {
        case .unionIdentity, .joinIdentity:
            return nil
        case .table(_, _), .quad(_), .triple(_), .bgp(_), .innerJoin(_, _), .leftOuterJoin(_, _, _),
             .filter(_, _), .union(_, _), .minus(_, _), .distinct(_), .service(_, _, _), .path(_, _, _),
             .aggregate(_, _, _), .window(_, _, _), .subquery(_):
            return nil
        case .namedGraph(let child, _), .extend(let child, _, _), .project(let child, _), .order(let child, _):
            return child.offset
        case .slice(_, let o, _):
            return o
        }
    }
}
