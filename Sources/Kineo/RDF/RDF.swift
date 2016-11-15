//
//  RDF.swift
//  PageDatabase
//
//  Created by Gregory Todd Williams on 5/26/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation

public enum TermType: BufferSerializable {
    case blank
    case iri
    case language(String)
    case datatype(String)

    /**

     Term type encodings (most specific wins):

     1      IRI
     2      Blank
     3      Langauge literal
     4      Datatype literal
     5      xsd:string
     6      xsd:date
     7      xsd:dateTime
     8      xsd:decimal
     9      xsd:integer
     10     xsd:float

     // top languages used in DBPedia:
     200    de
     201    en
     202    es
     203    fr
     204    ja
     205    nl
     206    pt
     207    ru

     255    en-US


     **/

    public var serializedSize: Int {
        switch (self) {
        case .datatype("http://www.w3.org/2001/XMLSchema#float"),
             .datatype("http://www.w3.org/2001/XMLSchema#integer"),
             .datatype("http://www.w3.org/2001/XMLSchema#decimal"),
             .datatype("http://www.w3.org/2001/XMLSchema#dateTime"),
             .datatype("http://www.w3.org/2001/XMLSchema#date"),
             .datatype("http://www.w3.org/2001/XMLSchema#string"):
            return 1
        case .language("de"),
             .language("en"),
             .language("en-US"),
             .language("es"),
             .language("fr"),
             .language("ja"),
             .language("nl"),
             .language("pt"),
             .language("ru"):
            return 1
        case .iri, .blank:
            return 1
        case .language(let lang):
            return 1 + lang.serializedSize
        case .datatype(let dt):
            return 1 + dt.serializedSize
        }
    }
    public func serialize(to buffer: inout UnsafeMutableRawPointer, mediator: RWMediator?, maximumSize: Int) throws {
        if serializedSize > maximumSize { throw DatabaseError.OverflowError("Cannot serialize TermType in available space") }
        switch self {
        case .language("de"):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 200
            buffer += 1
        case .language("en"):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 201
            buffer += 1
        case .language("es"):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 202
            buffer += 1
        case .language("fr"):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 203
            buffer += 1
        case .language("ja"):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 204
            buffer += 1
        case .language("nl"):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 205
            buffer += 1
        case .language("pt"):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 206
            buffer += 1
        case .language("ru"):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 207
            buffer += 1
        case .language("en-US"):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 255
            buffer += 1
        case .datatype("http://www.w3.org/2001/XMLSchema#float"):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 10
            buffer += 1
        case .datatype("http://www.w3.org/2001/XMLSchema#integer"):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 9
            buffer += 1
        case .datatype("http://www.w3.org/2001/XMLSchema#decimal"):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 8
            buffer += 1
        case .datatype("http://www.w3.org/2001/XMLSchema#dateTime"):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 7
            buffer += 1
        case .datatype("http://www.w3.org/2001/XMLSchema#date"):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 6
            buffer += 1
        case .datatype("http://www.w3.org/2001/XMLSchema#string"):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 5
            buffer += 1
        case .iri:
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 1
            buffer += 1
        case .blank:
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 2
            buffer += 1
        case .language(let l):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 3
            buffer += 1
            try l.serialize(to: &buffer)
        case .datatype(let dt):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 4
            buffer += 1
            try dt.serialize(to: &buffer)
        }
    }

    public static func deserialize(from buffer: inout UnsafeRawPointer, mediator: RMediator?=nil) throws -> TermType {
        let type = buffer.assumingMemoryBound(to: UInt8.self).pointee
        buffer += 1

        switch type {
        case 255:
            return .language("en-US")
        case 207:
            return .language("ru")
        case 206:
            return .language("pt")
        case 205:
            return .language("nl")
        case 204:
            return .language("ja")
        case 203:
            return .language("fr")
        case 202:
            return .language("es")
        case 201:
            return .language("en")
        case 200:
            return .language("de")
        case 10:
            return .datatype("http://www.w3.org/2001/XMLSchema#float")
        case 9:
            return .datatype("http://www.w3.org/2001/XMLSchema#integer")
        case 8:
            return .datatype("http://www.w3.org/2001/XMLSchema#decimal")
        case 7:
            return .datatype("http://www.w3.org/2001/XMLSchema#dateTime")
        case 6:
            return .datatype("http://www.w3.org/2001/XMLSchema#date")
        case 5:
            return .datatype("http://www.w3.org/2001/XMLSchema#string")
        case 1:
            return .iri
        case 2:
            return .blank
        case 3:
            let l   = try String.deserialize(from: &buffer)
            return .language(l)
        case 4:
            let dt  = try String.deserialize(from: &buffer)
            return .datatype(dt)
        default:
            throw DatabaseError.DataError("Unrecognized term type value \(type)")
        }
    }
}

public enum Numeric: CustomStringConvertible {
    case integer(Int)
    case decimal(Double)
    case float(Double)
    case double(Double)

    var value: Double {
        switch self {
        case .integer(let value):
            return Double(value)
        case .decimal(let value), .float(let value), .double(let value):
            return value
        }
    }

    var term: Term {
        switch self {
        case .integer(let value):
            return Term(integer: value)
        case .float(let value):
            return Term(float: value)
        case .decimal(let value):
            return Term(decimal: value)
        case .double(let value):
            return Term(double: value)
        }
    }

    public var description: String {
        switch self {
        case .integer(let i):
            return "\(i)"
        case .decimal(let value):
            return "\(value)dec"
        case .float(let value):
            return "\(value)f"
        case .double(let value):
            return "\(value)d"
        }
    }

    public static func +(lhs: Numeric, rhs: Numeric) -> Numeric {
        let value = lhs.value + rhs.value
        return nonDivResultingNumeric(value, lhs, rhs)
    }

    public static func -(lhs: Numeric, rhs: Numeric) -> Numeric {
        let value = lhs.value - rhs.value
        return nonDivResultingNumeric(value, lhs, rhs)
    }

    public static func *(lhs: Numeric, rhs: Numeric) -> Numeric {
        let value = lhs.value * rhs.value
        return nonDivResultingNumeric(value, lhs, rhs)
    }

    public static func /(lhs: Numeric, rhs: Numeric) -> Numeric {
        let value = lhs.value / rhs.value
        return divResultingNumeric(value, lhs, rhs)
    }

    public static prefix func -(num: Numeric) -> Numeric {
        switch num {
        case .integer(let value):
            return .integer(-value)
        case .decimal(let value):
            return .decimal(-value)
        case .float(let value):
            return .float(-value)
        case .double(let value):
            return .double(-value)
        }
    }
}

public extension Numeric {
    public static func ===(lhs: Numeric, rhs: Numeric) -> Bool {
        switch (lhs, rhs) {
        case (.integer(let l), .integer(let r)) where l == r:
            return true
        case (.decimal(let l), .decimal(let r)) where l == r:
            return true
        case (.float(let l), .float(let r)) where l == r:
            return true
        case (.double(let l), .double(let r)) where l == r:
            return true
        default:
            return false
        }
    }
}

private func nonDivResultingNumeric(_ value: Double, _ lhs: Numeric, _ rhs: Numeric) -> Numeric {
    switch (lhs, rhs) {
    case (.integer(_), .integer(_)):
        return .integer(Int(value))
    case (.decimal(_), .decimal(_)):
        return .decimal(value)
    case (.float(_), .float(_)):
        return .float(value)
    case (.double(_), .double(_)):
        return .double(value)
    case (.integer(_), .decimal(_)), (.decimal(_), .integer(_)):
        return .decimal(value)
    case (.integer(_), .float(_)), (.float(_), .integer(_)), (.decimal(_), .float(_)), (.float(_), .decimal(_)):
        return .float(value)
    //    case (.integer(_), .double(_)), (.double(_), .integer(_)), (.decimal(_), .double(_)), (.double(_), .decimal(_)):
    default:
        return .double(value)
    }
}

private func divResultingNumeric(_ value: Double, _ lhs: Numeric, _ rhs: Numeric) -> Numeric {
    switch (lhs, rhs) {
    case (.integer(_), .integer(_)), (.decimal(_), .decimal(_)):
        return .decimal(value)
    case (.float(_), .float(_)):
        return .float(value)
    case (.double(_), .double(_)):
        return .double(value)
    case (.integer(_), .decimal(_)), (.decimal(_), .integer(_)):
        return .decimal(value)
    case (.integer(_), .float(_)), (.float(_), .integer(_)), (.decimal(_), .float(_)), (.float(_), .decimal(_)):
        return .float(value)
    //    case (.integer(_), .double(_)), (.double(_), .integer(_)), (.decimal(_), .double(_)), (.double(_), .decimal(_)):
    default:
        return .double(value)
    }
}

extension TermType {
    func resultType(op: String, operandType rhs: TermType) -> TermType? {
        let integer = TermType.datatype("http://www.w3.org/2001/XMLSchema#integer")
        let decimal = TermType.datatype("http://www.w3.org/2001/XMLSchema#decimal")
        let float   = TermType.datatype("http://www.w3.org/2001/XMLSchema#float")
        let double  = TermType.datatype("http://www.w3.org/2001/XMLSchema#double")
        if op == "/" {
            if self == rhs && self == integer {
                return decimal
            }
        }
        switch (self, rhs) {
        case (let a, let b) where a == b:
            return a
        case (integer, decimal), (decimal, integer):
            return decimal
        case (integer, float), (float, integer), (decimal, float), (float, decimal):
            return float
        case (integer, double), (double, integer), (decimal, double), (double, decimal):
            return double
        default:
            return nil
        }
    }
}

extension TermType: Hashable {
    public var hashValue: Int {
        switch (self) {
        case .blank:
            return 0
        case .iri:
            return 1
        case .datatype(let d):
            return 2 ^ d.hashValue
        case .language(let l):
            return 3 ^ l.hashValue
        }
    }

    public static func ==(lhs: TermType, rhs: TermType) -> Bool {
        switch (lhs, rhs) {
        case (.iri, .iri), (.blank, .blank):
            return true
        case (.language(let l), .language(let r)):
            return l == r
        case (.datatype(let l), .datatype(let r)):
            return l == r
        default:
            return false
        }
    }
}

public struct Term: CustomStringConvertible {
    public var value: String
    public var type: TermType

    static func rdf(_ local: String) -> Term {
        return Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#\(local)", type: .iri)
    }

    static func xsd(_ local: String) -> Term {
        return Term(value: "http://www.w3.org/2001/XMLSchema#\(local)", type: .iri)
    }

    public init(value: String, type: TermType) {
        self.value  = value
        self.type   = type
    }

    public init(integer value: Int) {
        self.value = "\(value)"
        self.type = .datatype("http://www.w3.org/2001/XMLSchema#integer")
    }

    public init(float value: Double) {
        self.value = "\(value)"
        // TODO: fix the lexical form for xsd:float
        self.type = .datatype("http://www.w3.org/2001/XMLSchema#float")
    }

    public init(double value: Double) {
        self.value = "\(value)"
        // TODO: fix the lexical form for xsd:double
        self.type = .datatype("http://www.w3.org/2001/XMLSchema#double")
    }

    public init(decimal value: Double) {
        self.value = String(format: "%f", value)
        self.type = .datatype("http://www.w3.org/2001/XMLSchema#decimal")
    }

    public init?(numeric value: Double, type: TermType) {
        self.type = type
        switch type {
        case .datatype("http://www.w3.org/2001/XMLSchema#float"),
             .datatype("http://www.w3.org/2001/XMLSchema#double"):
            self.value = "\(value)"
        case .datatype("http://www.w3.org/2001/XMLSchema#decimal"):
            self.value = String(format: "%f", value)
        case .datatype("http://www.w3.org/2001/XMLSchema#integer"):
            let i = Int(value)
            self.value = "\(i)"
        default:
            return nil
        }
    }

    public var description: String {
        switch type {
//        case .iri where value == "http://www.w3.org/1999/02/22-rdf-syntax-ns#type":
//            return "a"
        case .iri:
            return "<\(value)>"
        case .blank:
            return "_:\(value)"
        case .language(let lang):
            let escaped = value.replacingOccurrences(of:"\"", with: "\\\"")
            return "\"\(escaped)\"@\(lang)"
        case .datatype("http://www.w3.org/2001/XMLSchema#string"):
            let escaped = value.replacingOccurrences(of:"\"", with: "\\\"")
            return "\"\(escaped)\""
        case .datatype("http://www.w3.org/2001/XMLSchema#float"):
            let s = "\(value)"
            if s.contains("e") {
                return s
            } else {
                return "\(s)e0"
            }
        case .datatype("http://www.w3.org/2001/XMLSchema#integer"), .datatype("http://www.w3.org/2001/XMLSchema#decimal"), .datatype("http://www.w3.org/2001/XMLSchema#boolean"):
            return "\(value)"
        case .datatype(let dt):
            let escaped = value.replacingOccurrences(of:"\"", with: "\\\"")
            return "\"\(escaped)\"^^<\(dt)>"
        }
    }

    static let trueValue = Term(value: "true", type: .datatype("http://www.w3.org/2001/XMLSchema#boolean"))
    static let falseValue = Term(value: "false", type: .datatype("http://www.w3.org/2001/XMLSchema#boolean"))
}

extension Term: BufferSerializable {
    public var serializedSize: Int {
        return type.serializedSize + value.serializedSize
    }
    public func serialize(to buffer: inout UnsafeMutableRawPointer, mediator: RWMediator?, maximumSize: Int) throws {
        if serializedSize > maximumSize { throw DatabaseError.OverflowError("Cannot serialize Term in available space") }
        try type.serialize(to: &buffer)
        try value.serialize(to: &buffer)
    }

    public static func deserialize(from buffer: inout UnsafeRawPointer, mediator: RMediator?=nil) throws -> Term {
        do {
            let type    = try TermType.deserialize(from: &buffer)
            let value   = try String.deserialize(from: &buffer)
            let term    = Term(value: value, type: type)
            return term
        } catch let e {
            throw e
        }
    }
}

extension Term: Hashable {
    public var hashValue: Int {
        return self.value.hashValue
    }
}

extension Term: Comparable {
    public var isNumeric: Bool {
        switch type {
        case .datatype("http://www.w3.org/2001/XMLSchema#integer"),
             .datatype("http://www.w3.org/2001/XMLSchema#decimal"),
             .datatype("http://www.w3.org/2001/XMLSchema#float"),
             .datatype("http://www.w3.org/2001/XMLSchema#double"):
            return true
        default:
            return false
        }
    }

    public var numeric: Numeric? {
        switch type {
        case .datatype("http://www.w3.org/2001/XMLSchema#integer"):
            if let i = Int(value) {
                return .integer(i)
            } else {
                return nil
            }
        case .datatype("http://www.w3.org/2001/XMLSchema#decimal"):
            return .decimal(numericValue)
        case .datatype("http://www.w3.org/2001/XMLSchema#float"):
            return .float(numericValue)
        case .datatype("http://www.w3.org/2001/XMLSchema#double"):
            return .double(numericValue)
        default:
            return nil
        }

    }
    public var numericValue: Double {
        switch type {
        case .datatype("http://www.w3.org/2001/XMLSchema#integer"):
            return Double(value) ?? 0.0
        case .datatype("http://www.w3.org/2001/XMLSchema#decimal"),
             .datatype("http://www.w3.org/2001/XMLSchema#float"),
             .datatype("http://www.w3.org/2001/XMLSchema#double"):
            return Double(value) ?? 0.0
        default:
            fatalError("Cannot compute a numeric value for term of type \(type)")
        }
    }

    public static func <(lhs: Term, rhs: Term) -> Bool {
        if lhs.isNumeric && rhs.isNumeric {
            return lhs.numericValue < rhs.numericValue
        }
        switch (lhs.type, rhs.type) {
        case (let a, let b) where a == b:
            if lhs.isNumeric {
                return lhs.numericValue < rhs.numericValue
            }
            return lhs.value < rhs.value
        case (.blank, _):
            return true
        case (.iri, .language(_)), (.iri, .datatype(_)):
            return true
        case (.language(_), .datatype(_)):
            return true
        default:
            return false
        }
    }
}

extension Term: Equatable {
    public static func ==(lhs: Term, rhs: Term) -> Bool {
        if lhs.isNumeric && rhs.isNumeric {
            return lhs.numericValue == rhs.numericValue
        }
        switch (lhs.type, rhs.type) {
        case (.iri, .iri), (.blank, .blank):
            return lhs.value == rhs.value
        case (.language(let l), .language(let r)) where l == r:
            return lhs.value == rhs.value
        case (.datatype(let l), .datatype(let r)) where l == r:
            return lhs.value == rhs.value
        default:
            return false
        }
    }
}

public struct Triple: CustomStringConvertible {
    public var subject: Term
    public var predicate: Term
    public var object: Term
    public var description: String {
        return "\(subject) \(predicate) \(object) ."
    }
}

extension Triple: Sequence {
    public func makeIterator() -> IndexingIterator<[Term]> {
        return [subject, predicate, object].makeIterator()
    }
}

public struct Quad: CustomStringConvertible {
    public var subject: Term
    public var predicate: Term
    public var object: Term
    public var graph: Term
    public init(subject: Term, predicate: Term, object: Term, graph: Term) {
        self.subject = subject
        self.predicate = predicate
        self.object = object
        self.graph = graph
    }
    public var description: String {
        return "\(subject) \(predicate) \(object) \(graph) ."
    }
}

extension Quad: Sequence {
    public func makeIterator() -> IndexingIterator<[Term]> {
        return [subject, predicate, object, graph].makeIterator()
    }
}

public enum Node {
    case bound(Term)
    case variable(String, binding: Bool)

    func bind(_ variable: String, to replacement: Node) -> Node {
        switch self {
        case .variable(variable, _):
            return replacement
        default:
            return self
        }
    }
}

extension Node: Equatable {
    public static func ==(lhs: Node, rhs: Node) -> Bool {
        switch (lhs, rhs) {
        case (.bound(let l), .bound(let r)) where l == r:
            return true
        case (.variable(let l, _), .variable(let r, _)) where l == r:
            return true
        default:
            return false
        }
    }
}

extension Node: CustomStringConvertible {
    public var description: String {
        switch self {
        case .bound(let t):
            return t.description
        case .variable(let name, _):
            return "?\(name)"
        }
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
