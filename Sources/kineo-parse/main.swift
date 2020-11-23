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

enum KineoParseError: Error {
    case fileDoesNotExist
}

func prettyPrint(_ data: Data, silent: Bool = false, includeComments: Bool = false) throws {
    let stream = InputStream(data: data)
    stream.open()
    let lexer = try SPARQLLexer(source: stream, includeComments: includeComments)
    let s = SPARQLSerializer(prettyPrint: true)
    let tokens: UnfoldSequence<SPARQLToken, Int> = sequence(state: 0) { (_) in return lexer.next() }
    let pretty = s.serialize(tokens)
    print(pretty)
}

@discardableResult
func parseQuery(_ data: Data, simplify: Bool, silent: Bool = false, includeComments: Bool = false) throws -> Query {
    guard var p = SPARQLParser(data: data, includeComments: includeComments) else { fatalError("Failed to construct SPARQL parser") }
    var query = try p.parseQuery()
    if simplify {
        let r = SPARQLQueryRewriter()
        query = try r.simplify(query: query)
    }
    let s = query.serialize()
    if !silent {
        print(s)
    }
    return query
}

func parseTokens(_ data: Data, silent: Bool = false) throws {
    let stream = InputStream(data: data)
    stream.open()
    let lexer = try SPARQLLexer(source: stream)
    while let t = lexer.next() {
        if !silent {
            print("\(t)")
        }
    }
}

func parseSPARQL(_ filename: String, printTokens: Bool, pretty: Bool, simplify: Bool, silent: Bool) throws -> Int32 {
    let data: Data
    if filename == "-" {
        let fh = FileHandle.standardInput
        data = fh.readDataToEndOfFile()
    } else {
        let url = URL(fileURLWithPath: filename)
        let path = url.absoluteString
        let manager = FileManager.default
        if manager.fileExists(atPath: path) {
            data = try Data(contentsOf: url)
        } else {
            data = filename.data(using: .utf8)!
        }
    }

    do {
        if pretty {
            try prettyPrint(data, includeComments: true)
        } else if printTokens {
            try parseTokens(data, silent: silent)
        } else {
            try parseQuery(data, simplify: simplify, silent: silent)
        }
        //print("ok")
    } catch SPARQLSyntaxError.parsingError(let message) {
        //        print("not ok \(message)")
        //        let s = String(data: data, encoding: .utf8)!
        //        print(s)
                throw SerializationError.parsingError(message)
        //        return 255
    } catch SerializationError.parsingError(let message) {
//        print("not ok \(message)")
//        let s = String(data: data, encoding: .utf8)!
//        print(s)
        throw SerializationError.parsingError(message)
//        return 255
    } catch let e {
        print("not ok \(e)")
        let s = String(data: data, encoding: .utf8)!
        print(s)
//        throw e
        return 255
    }
    return 0
}

func parseSRX(_ filename: String, silent: Bool) throws -> Int32 {
    let srxParser = SPARQLXMLParser()
    let data: Data
    if filename == "-" {
        let fh = FileHandle.standardInput
        data = fh.readDataToEndOfFile()
    } else {
        let url = URL(fileURLWithPath: filename)
        data = try Data(contentsOf: url)
    }
    let results = try srxParser.parse(data)
    print(results.description)
    return 0
}

func parseRDF(_ filename: String, silent: Bool) throws -> Int32 {
    let defaultGraph = Term(iri: "tag:kasei.us,2018:default-graph")
    let syntax = RDFParserCombined.guessSyntax(filename: filename)
    let parser = RDFParserCombined()
    let url = URL(fileURLWithPath: filename)
//    let path = url.absoluteString
    let manager = FileManager.default
    guard manager.fileExists(atPath: filename) else {
        throw KineoParseError.fileDoesNotExist
    }
    _ = try parser.parse(file: filename, syntax: syntax, defaultGraph: defaultGraph, base: url.absoluteString) { (s, p, o, g) in
        let q = Quad(subject: s, predicate: p, object: o, graph: g)
        print("\(q)")
    }
    return 0
}

/**
 Parse the supplied RDF files and assign each unique RDF term an integer ID such that the
 ordering of IDs corresponds to the terms' ordering according to the sorting rules of SPARQL.
 
 - parameter files: Filenames of Turtle or N-Triples files to parse.
 */
func sortParse(files: [String]) throws -> (Int, [Int:Term]) {
    var count   = 0
    var blanks = Set<Term>()
    var iris = Set<Term>()
    var literals = Set<Term>()
    let manager = FileManager.default
    for filename in files {
        #if os (OSX)
        guard let path = NSURL(fileURLWithPath: filename).absoluteString else { throw DatabaseError.DataError("Not a valid graph path: \(filename)") }
        #else
        let path = NSURL(fileURLWithPath: filename).absoluteString
        guard manager.fileExists(atPath: path) else {
            throw KineoParseError.fileDoesNotExist
        }
        
        #endif
        let graph   = Term(value: path, type: .iri)
        
        iris.insert(graph)
        
        let parser = RDFParserCombined()
        count = try parser.parse(file: filename, defaultGraph: graph, base: graph.value) { (s, p, o, g) in
            for term in [s, p, o, g] {
                switch term.type {
                case .iri:
                    iris.insert(term)
                case .blank:
                    blanks.insert(term)
                default:
                    literals.insert(term)
                }
            }
        }
        warn("\r\(count) triples parsed")
    }
    
    let blanksCount = blanks.count
    let irisAndBlanksCount = iris.count + blanksCount
    
    var mapping = [Int:Term]()
    for (i, term) in blanks.enumerated() { // blanks don't have inherent ordering amongst themselves
        mapping[i] = term
    }
    for (i, term) in iris.sorted().enumerated() {
        mapping[i + blanksCount] = term
    }
    for (i, term) in literals.sorted().enumerated() {
        mapping[i + irisAndBlanksCount] = term
    }
    return (count, mapping)
}

var pretty = false
var verbose = false
var silent = false
var printTokens = false
var lint = false
var sort = false
var simplify = false
let argscount = CommandLine.arguments.count
var args = PeekableIterator(generator: CommandLine.arguments.makeIterator())
guard let pname = args.next() else { fatalError("Missing command name") }
guard argscount >= 2 else {
    print("Usage: \(pname) [-v] query.rq")
    print("""
        Usage:
        
            \(pname) [OPTIONS] data.ttl
            \(pname) [OPTIONS] query.rq

        Options:
        
        -i
                Apply simplification rewriting the parsed query before
                printing the resulting query algebra.
        
        -p
                Reformat (pretty-print) the input SPARQL query.
        
        -s
                Silent Mode. Suppress non-critical output.
        
        -S
                Sort the terms from the input RDF document and print them
                in SPARQL-sorted order.
        
        -t
                Print the lexical tokens of the input SPARQL query.
        
        -v
                Print verbose output.

        
        """)
    exit(1)
}

Logger.shared.level = .silent
if let next = args.peek(), next.hasPrefix("-") {
    _ = args.next()
    if next == "-s" {
        silent = true
    } else if next == "-S" {
        sort = true
    } else if next == "-v" {
        verbose = true
    } else if next == "-t" {
        printTokens = true
    } else if next == "-p" {
        pretty = true
    } else if next == "-i" {
        simplify = true
    }
}

guard let qfile = args.next() else { fatalError("No query file given") }
do {
    if sort {
        let files = [qfile] + args.elements()
        let (_, terms) = try sortParse(files: files)
        for i in terms.keys.sorted() {
            if let term = terms[i] {
                print("\(i)\t\(term)")
            }
        }
        exit(0)
    } else {
        let sr = try parseSPARQL(qfile, printTokens: printTokens, pretty: pretty, simplify: simplify, silent: silent)
        
        exit(sr)
    }
} catch {}

do {
    let xr = try parseSRX(qfile, silent: silent)
    exit(xr)
} catch {}

let rr = try parseRDF(qfile, silent: silent)
exit(rr)
