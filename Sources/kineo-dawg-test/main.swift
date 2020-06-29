//
//  main.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 6/24/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import SPARQLSyntax
import DiomedeQuadStore
import Kineo

@discardableResult
func handle<M: MutableQuadStoreProtocol>(config: String, result: SPARQLTestRunner<M>.TestResult) -> Bool {
    switch result {
    case let .success(iri, configuration):
        let c = [config, configuration].filter { $0 != ""}.joined(separator: ", ")
        print("ok # \(iri) (\(c))")
        return true
    case let .failure(iri, configuration, reason):
        let c = [config, configuration].filter { $0 != ""}.joined(separator: ", ")
        print("not ok # \(iri): \(reason) (\(c))")
        return false
    }
}

enum TestType {
    case syntax
    case evaluation
}

func run<M: MutableQuadStoreProtocol>(config: String, path: String, testType: TestType, engines: (simple: Bool, plan: Bool), newStore: @escaping () -> M) throws {
    let sparqlPath = URL(fileURLWithPath: path)
    var testRunner = SPARQLTestRunner(newStore: newStore)
    testRunner.testSimpleQueryEvaluation = engines.simple
    testRunner.testQueryPlanEvaluation = engines.plan
    testRunner.verbose = verbose
    testRunner.requireTestApproval = false

    if let testIRI = args.next() {
        testRunner.verbose = true
        if testRunner.verbose {
            print("Running test: \(testIRI)")
        }
        switch testType {
        case .syntax:
            let result = try testRunner.runSyntaxTest(iri: testIRI, inPath: sparqlPath)
            handle(config: config, result: result)
        case .evaluation:
            let result = try testRunner.runEvaluationTest(iri: testIRI, inPath: sparqlPath)
            handle(config: config, result: result)
        }
    } else {
        if testRunner.verbose {
            print("Running tests in: \(sparqlPath)")
        }
        var total = 0
        var passed = 0
        switch testType {
        case .syntax:
            let results = try testRunner.runSyntaxTests(inPath: sparqlPath, testType: nil)
            total = results.count
            for result in results {
                passed += handle(config: config, result: result) ? 1 : 0
            }
        case .evaluation:
            let results = try testRunner.runEvaluationTests(inPath: sparqlPath, testType: nil)
            total = results.count
            for result in results {
                passed += handle(config: config, result: result) ? 1 : 0
            }
        }
        print("Passed \(passed)/\(total)")
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

enum TestStore {
    case memory
    case diomede
}

var evaluationEngines = (simple: true, plan: true)
var testStore : TestStore = .memory
var testType : TestType = .evaluation
while true {
    if let next = args.peek() {
        if next == "-v" {
            _ = args.next()
            verbose = true
        } else if next == "-d" {
            _ = args.next()
            testStore = .diomede
        } else if next == "-m" {
            _ = args.next()
            testStore = .memory
        } else if next == "-s" {
            _ = args.next()
            testType = .syntax
        } else if next == "-S" {
            // only run the simple query evaluator
            _ = args.next()
            evaluationEngines.plan = false
        } else if next == "-P" {
            // only run the query plan evaluator
            _ = args.next()
            evaluationEngines.simple = false
        } else {
            break
        }
    } else {
        break
    }
}

guard let path = args.next() else { fatalError("Missing path") }

switch testStore {
case .memory:
    try run(config: "Memory", path: path, testType: testType, engines: evaluationEngines) { return MemoryQuadStore() }
case .diomede:
    var files = [URL]()
    let f = FileManager.default
    try run(config: "Diomede", path: path, testType: testType, engines: evaluationEngines) { () -> DiomedeQuadStore in
        let dir = f.temporaryDirectory
        let filename = "kineo-test-\(UUID().uuidString).db"
        let path = dir.appendingPathComponent(filename)
        files.append(path)
        guard let store = DiomedeQuadStore(path: path.path, create: true) else { fatalError() }
        return store
    }
    
    #if os(macOS)
    for filename in files {
        try? f.trashItem(at: filename, resultingItemURL: nil)
    }
    #endif
}
