//
//  RDF.swift
//  PageDatabase
//
//  Created by Gregory Todd Williams on 5/26/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import SPARQLParser

extension TermType: BufferSerializable {
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
        switch self {
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

extension Term {
    public var dateValue: Date? {
        guard case .datatype("http://www.w3.org/2001/XMLSchema#dateTime") = self.type else { return nil }
        let lexical = self.value
        if #available (OSX 10.12, *) {
            let f = W3CDTFLocatedDateFormatter()
            return f.date(from: lexical)
        } else {
            fatalError("OSX 10.12 is required to use date functions")
        }
        
        return nil
    }
    
    public var timeZone: TimeZone? {
        guard case .datatype("http://www.w3.org/2001/XMLSchema#dateTime") = self.type else { return nil }
        let lexical = self.value
        if #available (OSX 10.12, *) {
            let f = W3CDTFLocatedDateFormatter()
            guard let ld = f.locatedDate(from: lexical) else { return nil }
            return ld.timezone
        } else {
            fatalError("OSX 10.12 is required to use date functions")
        }
        
        return nil
    }
}
