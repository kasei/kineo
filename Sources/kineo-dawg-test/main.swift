//
//  main.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 6/24/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import SPARQLSyntax
import Kineo

@discardableResult
func handle(result: SPARQLTestRunner.TestResult) -> Bool {
    switch result {
    case let .success(iri):
        print("ok # \(iri)")
        return true
    case let .failure(iri, reason):
        print("failed # \(iri): \(reason)")
        return false
    }
}

var verbose = false
let argscount = CommandLine.arguments.count
var args = PeekableIterator(generator: CommandLine.arguments.makeIterator())
guard let pname = args.next() else { fatalError("Missing command name") }
guard argscount >= 2 else {
    print("Usage: \(pname) [-v] PATH TEST")
    print("")
    exit(1)
}

var syntaxTest = false
while true {
    if let next = args.peek() {
        if next == "-v" {
            _ = args.next()
            verbose = true
        } else if next == "-s" {
            _ = args.next()
            syntaxTest = true
        } else {
            break
        }
    } else {
        break
    }
}

guard let path = args.next() else { fatalError("Missing path") }
let sparqlPath = URL(fileURLWithPath: path)
var testRunner = SPARQLTestRunner()
testRunner.verbose = verbose

if let testIRI = args.next() {
    testRunner.verbose = true
    if testRunner.verbose {
        print("Running test: \(testIRI)")
    }
    if syntaxTest {
        let result = try testRunner.runSyntaxTest(iri: testIRI, inPath: sparqlPath)
        handle(result: result)
    } else {
        let result = try testRunner.runEvaluationTest(iri: testIRI, inPath: sparqlPath)
        handle(result: result)
    }
} else {
    if testRunner.verbose {
        print("Running tests in: \(sparqlPath)")
    }
    var total = 0
    var passed = 0
    if syntaxTest {
        let results = try testRunner.runSyntaxTests(inPath: sparqlPath, testType: nil)
        total = results.count
        for result in results {
            passed += handle(result: result) ? 1 : 0
        }
    } else {
        let results = try testRunner.runEvaluationTests(inPath: sparqlPath, testType: nil)
        total = results.count
        for result in results {
            passed += handle(result: result) ? 1 : 0
        }
    }
    print("Passed \(passed)/\(total)")
}

