//
//  main.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 6/24/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import Kineo

func prettyPrint(_ qfile: String, silent: Bool = false, includeComments: Bool = false) throws {
    let url = URL(fileURLWithPath: qfile)
    let sparql = try Data(contentsOf: url)
    let stream = InputStream(data: sparql)
    stream.open()
    var lexer = SPARQLLexer(source: stream, includeComments: includeComments)
    let s = SPARQLSerializer()
    let tokens: UnfoldSequence<SPARQLToken, Int> = sequence(state: 0) { (_) in return lexer.next() }
    let pretty = s.serializePretty(tokens)
    print(pretty)
}

@discardableResult
func parseAlgebra(_ qfile: String, silent: Bool = false, includeComments: Bool = false) throws -> Algebra {
    let url = URL(fileURLWithPath: qfile)
    let sparql = try Data(contentsOf: url)
    guard var p = SPARQLParser(data: sparql, includeComments: includeComments) else { fatalError("Failed to construct SPARQL parser") }
    let algebra = try p.parse()
    let s = algebra.serialize()
    if !silent {
        print(s)
    }
    return algebra
}

func parseTokens(_ qfile: String, silent: Bool = false) throws {
    let url = URL(fileURLWithPath: qfile)
    let sparql = try Data(contentsOf: url)
    let stream = InputStream(data: sparql)
    stream.open()
    var lexer = SPARQLLexer(source: stream)
    while let t = lexer.next() {
        if !silent {
            print("\(t)")
        }
    }
}

var pretty = false
var verbose = false
var silent = false
var printTokens = false
let argscount = CommandLine.arguments.count
var args = PeekableIterator(generator: CommandLine.arguments.makeIterator())
guard let pname = args.next() else { fatalError("Missing command name") }
var pageSize = 8192
guard argscount >= 2 else {
    print("Usage: \(pname) [-v] query.rq")
    print("")
    exit(1)
}


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

let startTime = getCurrentTime()
let startSecond = getCurrentDateSeconds()

guard let qfile = args.next() else { fatalError("No query file given") }
do {
    warn("# \(qfile)")
    if pretty {
        try prettyPrint(qfile, includeComments: true)
    } else if printTokens {
        try parseTokens(qfile, silent: silent)
    } else {
        try parseAlgebra(qfile, silent: silent)
    }
    //print("ok")
} catch SPARQLParsingError.parsingError(let message) {
    print("not ok \(message)")
    let s = try String(contentsOfFile: qfile, encoding: .utf8)
    print(s)
    exit(255)
} catch SPARQLParsingError.lexicalError(let message) {
    print("not ok \(message)")
    let s = try String(contentsOfFile: qfile, encoding: .utf8)
    print(s)
    exit(255)
}

let endTime = getCurrentTime()
let elapsed = Double(endTime - startTime)
if verbose {
    warn("elapsed time: \(elapsed)s")
}


