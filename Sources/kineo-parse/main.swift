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

func prettyPrint(_ qfile: String, silent: Bool = false, includeComments: Bool = false) throws {
    let url = URL(fileURLWithPath: qfile)
    let sparql = try Data(contentsOf: url)
    let stream = InputStream(data: sparql)
    stream.open()
    let lexer = SPARQLLexer(source: stream, includeComments: includeComments)
    let s = SPARQLSerializer()
    let tokens: UnfoldSequence<SPARQLToken, Int> = sequence(state: 0) { (_) in return lexer.next() }
    let pretty = s.serializePretty(tokens)
    print(pretty)
}

@discardableResult
func parseQuery(_ qfile: String, silent: Bool = false, includeComments: Bool = false) throws -> Query {
    let url = URL(fileURLWithPath: qfile)
    let sparql = try Data(contentsOf: url)
    guard var p = SPARQLParser(data: sparql, includeComments: includeComments) else { fatalError("Failed to construct SPARQL parser") }
    let query = try p.parseQuery()
    let s = query.serialize()
    if !silent {
        print(s)
    }
    return query
}

func parseTokens(_ qfile: String, silent: Bool = false) throws {
    let url = URL(fileURLWithPath: qfile)
    let sparql = try Data(contentsOf: url)
    let stream = InputStream(data: sparql)
    stream.open()
    let lexer = SPARQLLexer(source: stream)
    while let t = lexer.next() {
        if !silent {
            print("\(t)")
        }
    }
}

func parseSPARQL(_ qfile: String, printTokens: Bool, silent: Bool) throws -> Int32 {
    do {
        warn("# \(qfile)")
        if pretty {
            try prettyPrint(qfile, includeComments: true)
        } else if printTokens {
            try parseTokens(qfile, silent: silent)
        } else {
            try parseQuery(qfile, silent: silent)
        }
        //print("ok")
    } catch SPARQLParsingError.parsingError(let message) {
        print("not ok \(message)")
        let s = try String(contentsOfFile: qfile, encoding: .utf8)
        print(s)
        return 255
    } catch SPARQLParsingError.lexicalError(let message) {
        print("not ok \(message)")
        let s = try String(contentsOfFile: qfile, encoding: .utf8)
        print(s)
        return 255
    }
    return 0
}

func parseSRX(_ filename: String, silent: Bool) throws -> Int32 {
    let srxParser = SPARQLXMLParser()
    let url = URL(fileURLWithPath: filename)
    let data = try Data(contentsOf: url)
    let results = try srxParser.parse(data)
    print(results.description)
    return 0
}

func parseRDF(_ filename: String, silent: Bool) throws -> Int32 {
    let syntax = RDFParser.guessSyntax(for: filename)
    let parser = RDFParser(syntax: syntax)
    let url = URL(fileURLWithPath: filename)
    _ = try parser.parse(file: filename, base: url.absoluteString) { (s, p, o) in
        let t = Triple(subject: s, predicate: p, object: o)
        print("\(t)")
    }
    return 0
}

var pretty = false
var verbose = false
var silent = false
var printTokens = false
let argscount = CommandLine.arguments.count
var args = PeekableIterator(generator: CommandLine.arguments.makeIterator())
guard let pname = args.next() else { fatalError("Missing command name") }
guard argscount >= 2 else {
    print("Usage: \(pname) [-v] query.rq")
    print("")
    exit(1)
}

Logger.shared.level = .silent
if let next = args.peek(), next.hasPrefix("-") {
    _ = args.next()
    if next == "-s" {
        silent = true
    } else if next == "-v" {
        verbose = true
    } else if next == "-t" {
        printTokens = true
    } else if next == "-p" {
        pretty = true
    }
}

guard let qfile = args.next() else { fatalError("No query file given") }

do {
    let rr = try parseRDF(qfile, silent: silent)
    exit(rr)
} catch {}

do {
    let xr = try parseSRX(qfile, silent: silent)
    exit(xr)
} catch {}

let sr = try parseSPARQL(qfile, printTokens: printTokens, silent: silent)
exit(sr)
