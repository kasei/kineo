//
//  main.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 6/24/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import Kineo

func parseAlgebra(_ qfile : String, verbose : Bool = false) throws {
    let url = URL(fileURLWithPath: qfile)
    let sparql = try Data(contentsOf: url)
    guard var p = SPARQLParser(data: sparql) else { fatalError("Failed to construct SPARQL parser") }
    let algebra = try p.parse()
    let s = algebra.serialize()
    if verbose {
        print(s)
    }
}

func parseTokens(_ qfile : String, verbose : Bool = false) throws {
    let url = URL(fileURLWithPath: qfile)
    let sparql = try Data(contentsOf: url)
    let stream = InputStream(data: sparql)
    stream.open()
    var lexer = SPARQLLexer(source: stream)
    while let t = lexer.next() {
        print("\(t)")
    }
}

var verbose = false
var printTokens = false
let _args = CommandLine.arguments
let argscount = _args.count
var args = PeekableIterator(generator: _args.makeIterator())
guard let pname = args.next() else { fatalError() }
var pageSize = 8192
guard argscount >= 2 else {
    print("Usage: \(pname) [-v] query.rq")
    print("")
    exit(1)
}


if let next = args.peek(), next.hasPrefix("-") {
    _ = args.next()
    if next == "-v" {
        verbose = true
    } else if next == "-t" {
        printTokens = true
    }
}

let startTime = getCurrentTime()
let startSecond = getCurrentDateSeconds()

guard let qfile = args.next() else { fatalError("No query file given") }
do {
    warn("\(qfile)")
    if printTokens {
        try parseTokens(qfile, verbose: verbose)
    } else {
        try parseAlgebra(qfile, verbose: verbose)
    }
} catch SPARQLParsingError.parsingError(let message) {
    print("\(message)")
    let s = try String(contentsOfFile: qfile, encoding: .utf8)
    print(s)
    exit(255)
} catch SPARQLParsingError.lexicalError(let message) {
    print("\(message)")
    let s = try String(contentsOfFile: qfile, encoding: .utf8)
    print(s)
    exit(255)
}

let endTime = getCurrentTime()
let elapsed = Double(endTime - startTime)
if verbose {
    warn("elapsed time: \(elapsed)s")
}


