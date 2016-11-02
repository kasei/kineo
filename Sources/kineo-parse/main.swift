//
//  main.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 6/24/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import Kineo

var verbose = false
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

if let next = args.peek(), next == "-v" {
    _ = args.next()
    verbose = true
}

let startTime = getCurrentTime()
let startSecond = getCurrentDateSeconds()
var count = 0

guard let qfile = args.next() else { fatalError("No query file given") }
warn("\(qfile)")
let url = URL(fileURLWithPath: qfile)
let sparql = try Data(contentsOf: url)
guard var p = SPARQLParser(data: sparql) else { fatalError("Failed to construct SPARQL parser") }
let algebra = try p.parse()
let s = algebra.serialize()
count = 1
if verbose {
    print(s)
}

let endTime = getCurrentTime()
let elapsed = Double(endTime - startTime)
let tps = Double(count) / elapsed
if verbose {
    warn("elapsed time: \(elapsed)s (\(tps)/s)")
}


