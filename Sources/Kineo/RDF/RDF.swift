//
//  RDF.swift
//  PageDatabase
//
//  Created by Gregory Todd Williams on 5/26/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation

public enum TermType : BufferSerializable {
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
    
    public var serializedSize : Int {
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
    public func serialize(to buffer : inout UnsafeMutablePointer<Void>, mediator: RWMediator?, maximumSize: Int) throws {
        if serializedSize > maximumSize { throw DatabaseError.OverflowError("Cannot serialize TermType in available space") }
        switch self {
        case .language("de"):
            UnsafeMutablePointer<UInt8>(buffer).pointee = 200
            buffer += 1
        case .language("en"):
            UnsafeMutablePointer<UInt8>(buffer).pointee = 201
            buffer += 1
        case .language("es"):
            UnsafeMutablePointer<UInt8>(buffer).pointee = 202
            buffer += 1
        case .language("fr"):
            UnsafeMutablePointer<UInt8>(buffer).pointee = 203
            buffer += 1
        case .language("ja"):
            UnsafeMutablePointer<UInt8>(buffer).pointee = 204
            buffer += 1
        case .language("nl"):
            UnsafeMutablePointer<UInt8>(buffer).pointee = 205
            buffer += 1
        case .language("pt"):
            UnsafeMutablePointer<UInt8>(buffer).pointee = 206
            buffer += 1
        case .language("ru"):
            UnsafeMutablePointer<UInt8>(buffer).pointee = 207
            buffer += 1
        case .language("en-US"):
            UnsafeMutablePointer<UInt8>(buffer).pointee = 255
            buffer += 1
        case .datatype("http://www.w3.org/2001/XMLSchema#float"):
            UnsafeMutablePointer<UInt8>(buffer).pointee = 10
            buffer += 1
        case .datatype("http://www.w3.org/2001/XMLSchema#integer"):
            UnsafeMutablePointer<UInt8>(buffer).pointee = 9
            buffer += 1
        case .datatype("http://www.w3.org/2001/XMLSchema#decimal"):
            UnsafeMutablePointer<UInt8>(buffer).pointee = 8
            buffer += 1
        case .datatype("http://www.w3.org/2001/XMLSchema#dateTime"):
            UnsafeMutablePointer<UInt8>(buffer).pointee = 7
            buffer += 1
        case .datatype("http://www.w3.org/2001/XMLSchema#date"):
            UnsafeMutablePointer<UInt8>(buffer).pointee = 6
            buffer += 1
        case .datatype("http://www.w3.org/2001/XMLSchema#string"):
            UnsafeMutablePointer<UInt8>(buffer).pointee = 5
            buffer += 1
        case .iri:
            UnsafeMutablePointer<UInt8>(buffer).pointee = 1
            buffer += 1
        case .blank:
            UnsafeMutablePointer<UInt8>(buffer).pointee = 2
            buffer += 1
        case .language(let l):
            UnsafeMutablePointer<UInt8>(buffer).pointee = 3
            buffer += 1
            try l.serialize(to: &buffer)
        case .datatype(let dt):
            UnsafeMutablePointer<UInt8>(buffer).pointee = 4
            buffer += 1
            try dt.serialize(to: &buffer)
        }
    }

    public static func deserialize(from buffer : inout UnsafePointer<Void>, mediator : RMediator?=nil) throws -> TermType {
        let type = UnsafeMutablePointer<UInt8>(buffer).pointee
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

public func ==(lhs: TermType, rhs: TermType) -> Bool {
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

public struct Term : CustomStringConvertible {
    public init(value : String, type : TermType) {
        self.value  = value
        self.type   = type
    }
    
    public init(integer value: Int) {
        self.value = "\(value)"
        self.type = .datatype("http://www.w3.org/2001/XMLSchema#integer")
    }
    
    public init(float value: Double) {
        self.value = "\(value)"
        self.type = .datatype("http://www.w3.org/2001/XMLSchema#float")
    }
    
    var value : String
    var type : TermType
    public var description : String {
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
        case .datatype("http://www.w3.org/2001/XMLSchema#integer"), .datatype("http://www.w3.org/2001/XMLSchema#float"), .datatype("http://www.w3.org/2001/XMLSchema#decimal"), .datatype("http://www.w3.org/2001/XMLSchema#boolean"):
            return "\(value)"
        case .datatype(let dt):
            let escaped = value.replacingOccurrences(of:"\"", with: "\\\"")
            return "\"\(escaped)\"^^<\(dt)>"
        }
    }
    
    static let trueValue = Term(value: "true", type: .datatype("http://www.w3.org/2001/XMLSchema#boolean"))
    static let falseValue = Term(value: "false", type: .datatype("http://www.w3.org/2001/XMLSchema#boolean"))
}

extension Term : BufferSerializable {
    public var serializedSize : Int {
        return type.serializedSize + value.serializedSize
    }
    public func serialize(to buffer : inout UnsafeMutablePointer<Void>, mediator: RWMediator?, maximumSize: Int) throws {
        if serializedSize > maximumSize { throw DatabaseError.OverflowError("Cannot serialize Term in available space") }
        try type.serialize(to: &buffer)
        try value.serialize(to: &buffer)
    }
    
    public static func deserialize(from buffer : inout UnsafePointer<Void>, mediator : RMediator?=nil) throws -> Term {
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

extension Term : Hashable {
    public var hashValue: Int {
        return self.value.hashValue
    }
}

extension Term : Comparable {
    var isNumeric : Bool {
        switch type {
        case .datatype("http://www.w3.org/2001/XMLSchema#integer"), .datatype("http://www.w3.org/2001/XMLSchema#float"):
            return true
        default:
            return false
        }
    }
    
    var numericValue : Double {
        switch type {
        case .datatype("http://www.w3.org/2001/XMLSchema#integer"):
            return Double(value) ?? 0.0
        case .datatype("http://www.w3.org/2001/XMLSchema#float"), .datatype("http://www.w3.org/2001/XMLSchema#decimal"):
            return Double(value) ?? 0.0
        default:
            fatalError()
        }
    }
}

public func <(lhs: Term, rhs: Term) -> Bool {
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

extension Term : Equatable {}
public func ==(lhs: Term, rhs: Term) -> Bool {
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

public struct Triple : CustomStringConvertible {
    public var subject : Term
    public var predicate : Term
    public var object : Term
    public var description : String {
        return "\(subject) \(predicate) \(object) ."
    }
}

extension Triple : Sequence {
    public func makeIterator() -> IndexingIterator<[Term]> {
        return [subject, predicate, object].makeIterator()
    }
}

public struct Quad : CustomStringConvertible {
    public var subject : Term
    public var predicate : Term
    public var object : Term
    public var graph : Term
    public init(subject: Term, predicate: Term, object: Term, graph: Term) {
        self.subject = subject
        self.predicate = predicate
        self.object = object
        self.graph = graph
    }
    public var description : String {
        return "\(subject) \(predicate) \(object) \(graph) ."
    }
}

extension Quad : Sequence {
    public func makeIterator() -> IndexingIterator<[Term]> {
        return [subject, predicate, object, graph].makeIterator()
    }
}

public enum Node {
    case bound(Term)
    case variable(String)
}

