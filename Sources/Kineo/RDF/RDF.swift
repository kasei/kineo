//
//  RDF.swift
//  PageDatabase
//
//  Created by Gregory Todd Williams on 5/26/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import SPARQLSyntax

public enum RDFTriplePosition {
    case subject
    case predicate
    case object
}

public class RDFSerializationConfiguration {
    public enum SerializationError: Error {
        case unrecognizedFileType(String)
        case unrecognizedFormat(String)
    }
    
    public struct ParserContext: RDFPushParser {
        public var mediaTypes: Set<String>
        public var parser: RDFPushParser
        public var mediaType: String
        
        public init() {
            fatalError("RDFSerializationConfiguration.ParserContext() must not be called directly")
        }
        
        public init(parser: RDFParser, mediaType: String) {
            self.parser = parser
            self.mediaType = mediaType
            self.mediaTypes = []
        }
        
        public func parse(string: String, mediaType: String, base: String? = nil, handleTriple: @escaping TripleHandler) throws -> Int {
            return try parser.parse(string: string, mediaType: mediaType, base: base, handleTriple: handleTriple)
        }
        
        public func parse(string: String, base: String? = nil, handleTriple: @escaping TripleHandler) throws -> Int {
            return try parser.parse(string: string, mediaType: mediaType, base: base, handleTriple: handleTriple)
        }
        
        public func parseFile(_ filename: String, mediaType: String, base: String? = nil, handleTriple: @escaping TripleHandler) throws -> Int {
            return try parser.parseFile(filename, mediaType: mediaType, base: base, handleTriple: handleTriple)
        }
        
        public func parseFile(_ filename: String, base: String? = nil, handleTriple: @escaping TripleHandler) throws -> Int {
            return try parser.parseFile(filename, mediaType: mediaType, base: base, handleTriple: handleTriple)
        }
    }
    
    public static let shared = { () -> RDFSerializationConfiguration in
        let c = RDFSerializationConfiguration()
        c.registerSerializer(NTriplesSerializer.self, withType: "text/n-triples", extensions: [".nt"], mediaTypes: [])
        c.registerSerializer(TurtleSerializer.self, withType: "text/turtle", extensions: [".ttl"], mediaTypes: [])
        
        c.registerParser(RDFParserCombined.self, withType: "text/turtle", extensions: [".ttl"], mediaTypes: [])
        c.registerParser(RDFParserCombined.self, withType: "text/n-triples", extensions: [".nt"], mediaTypes: [])
        c.registerParser(RDFParserCombined.self, withType: "application/rdf+xml", extensions: [".rdf"], mediaTypes: [])
        return c
    }()
    
    var parserFileExtensions: [String: (RDFParser.Type, String)]
    var parserMediaTypes: [String: (RDFParser.Type, String)]
    var serializerFileExtensions: [String: (RDFSerializer.Type, String)]
    var serializerMediaTypes: [String: (RDFSerializer.Type, String)]
    internal init() {
        parserFileExtensions = [:]
        parserMediaTypes = [:]
        serializerFileExtensions = [:]
        serializerMediaTypes = [:]
    }
    
    public func registerParser(_ c: RDFParser.Type, withType type: String, extensions: [String], mediaTypes types: [String]) {
        for ext in extensions {
            parserFileExtensions[ext] = (c, type)
        }
        
        parserMediaTypes[type] = (c, type)
        for t in types {
            parserMediaTypes[t] = (c, type)
        }
    }
    
    public func registerSerializer(_ c: RDFSerializer.Type, withType type: String, extensions: [String], mediaTypes types: [String]) {
        for ext in extensions {
            serializerFileExtensions[ext] = (c, type)
        }
        
        serializerMediaTypes[type] = (c, type)
        for t in types {
            serializerMediaTypes[t] = (c, type)
        }
    }
    
    public func serializerFor(type: String) -> RDFSerializer? {
        for (k, v) in serializerMediaTypes {
            if type.hasPrefix(k) {
                let (c, _) = v
                return c.init()
            }
        }
        return nil
    }
    
    public func serializerFor(filename: String) -> RDFSerializer? {
        for (k, v) in serializerFileExtensions {
            if filename.hasSuffix(k) {
                let (c, _) = v
                return c.init()
            }
        }
        return nil
    }
    
    public func expectedSerializerFor(filename: String) throws -> RDFSerializer? {
        guard let s = serializerFor(filename: filename) else {
            throw SerializationError.unrecognizedFileType("Failed to determine appropriate serializer for file: \(filename)")
        }
        return s
    }
    

    public func parserFor(type: String) -> ParserContext? {
        for (k, v) in parserMediaTypes {
            if type.hasPrefix(k) {
                let (c, type) = v
                let p = c.init()
                return ParserContext(parser: p, mediaType: type)
            }
        }
        return nil
    }
    
    public func expectedParserFor(filename: String) throws -> ParserContext {
        guard let p = parserFor(filename: filename) else {
            throw SerializationError.unrecognizedFileType("Failed to determine appropriate parser for file: \(filename)")
        }
        return p
    }
    
    public func parserFor(filename: String) -> ParserContext? {
        for (k, v) in parserFileExtensions {
            if filename.hasSuffix(k) {
                let (c, type) = v
                let p = c.init()
                return ParserContext(parser: p, mediaType: type)
            }
        }
        return nil
    }
}

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
        case .datatype(.float),
             .datatype(.integer),
             .datatype(.decimal),
             .datatype(.dateTime),
             .datatype(.date),
             .datatype(.string):
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
            return 1 + dt.value.serializedSize
        }
    }
    public func serialize(to buffer: inout UnsafeMutableRawPointer, mediator: PageRWMediator?, maximumSize: Int) throws {
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
        case .datatype(.float):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 10
            buffer += 1
        case .datatype(.integer):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 9
            buffer += 1
        case .datatype(.decimal):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 8
            buffer += 1
        case .datatype(.dateTime):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 7
            buffer += 1
        case .datatype(.date):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 6
            buffer += 1
        case .datatype(.string):
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
            try dt.value.serialize(to: &buffer)
        }
    }
    
    public static func deserialize(from buffer: inout UnsafeRawPointer, mediator: PageRMediator?=nil) throws -> TermType {
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
            return .datatype(.float)
        case 9:
            return .datatype(.integer)
        case 8:
            return .datatype(.decimal)
        case 7:
            return .datatype(.dateTime)
        case 6:
            return .datatype(.date)
        case 5:
            return .datatype(.string)
        case 1:
            return .iri
        case 2:
            return .blank
        case 3:
            let l   = try String.deserialize(from: &buffer)
            return .language(l)
        case 4:
            let dt  = try String.deserialize(from: &buffer)
            return .datatype(TermDataType(stringLiteral: dt))
        default:
            throw DatabaseError.DataError("Unrecognized term type value \(type)")
        }
    }
}

extension Term: BufferSerializable {
    public var serializedSize: Int {
        return type.serializedSize + value.serializedSize
    }
    public func serialize(to buffer: inout UnsafeMutableRawPointer, mediator: PageRWMediator?, maximumSize: Int) throws {
        if serializedSize > maximumSize { throw DatabaseError.OverflowError("Cannot serialize Term in available space") }
        try type.serialize(to: &buffer)
        try value.serialize(to: &buffer)
    }
    
    public static func deserialize(from buffer: inout UnsafeRawPointer, mediator: PageRMediator?=nil) throws -> Term {
        do {
            let type    = try TermType.deserialize(from: &buffer)
            let value   = try String.deserialize(from: &buffer)
            let term    = Term(canonicalValue: value, type: type)
            return term
        } catch let e {
            throw e
        }
    }
}

extension Term {
    public var booleanValue: Bool? {
        guard case .datatype(.boolean) = self.type else {
            return nil
        }
        let lexical = self.value
        if lexical == "true" || lexical == "1" {
            return true
        } else {
            return false
        }
    }
    
    public var dateValue: Date? {
        guard case .datatype(let dt) = self.type else {
            return nil
        }
        let lexical = self.value
        if dt.value == Namespace.xsd.dateTime {
            if #available (OSX 10.12, *) {
                let f = W3CDTFLocatedDateFormatter()
                f.formatOptions.remove(.withTimeZone)
                
                let d = f.date(from: lexical)
                return d
            } else {
                warn("MacOS 10.12 is required to use date functions")
                return nil
            }
        } else if dt.value == Namespace.xsd.date {
            if #available (OSX 10.12, *) {
                let f = W3CDTFLocatedDateFormatter()
                f.formatOptions = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate]
                
                let d = f.date(from: lexical)
                return d
            } else {
                warn("MacOS 10.12 is required to use date functions")
                return nil
            }
        } else if dt.value == Namespace.xsd.time {
            if #available (OSX 10.12, *) {
                var v = lexical
                var tz: TimeZone? = nil
                if v.hasSuffix("Z") {
                    v = String(v.dropLast())
                    tz = TimeZone(secondsFromGMT: 0)
                } else if v.contains("-") {
                    fatalError("TODO: implement timezone support for xsd:time")
                } else if v.contains("+") {
                    fatalError("TODO: implement timezone support for xsd:time")
                }
                let parts = v.split(separator: ":")
                guard parts.count == 3 else {
                    return nil
                }
                guard let h = Int(parts[0]), let m = Int(parts[1]), let s = Double(parts[2]) else {
                    return nil
                }

                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                let seconds = Int(s)
                let nanoseconds = Int((s - Double(seconds)) / 1_000_000_000.0)
                let components = DateComponents(timeZone: tz, hour: h, minute: m, second: seconds, nanosecond: nanoseconds)
                return calendar.date(from: components)
            } else {
                warn("MacOS 10.12 is required to use date functions")
                return nil
            }
        }
        return nil
    }
    
    public var timeZone: TimeZone? {
        guard case .datatype(.dateTime) = self.type else { return nil }
        let lexical = self.value
        if #available (OSX 10.12, *) {
            let f = W3CDTFLocatedDateFormatter()
            guard let ld = f.locatedDate(from: lexical) else { return nil }
            return ld.timezone
        } else {
            warn("MacOS 10.12 is required to use date functions")
            return nil
        }
    }
}

extension RDFPushParser {
    public func parseFile<Q: MutableQuadStoreProtocol>(_ filename: String, mediaType: String, base: String? = nil, into store: Q, graph: Term, version: Version) throws -> Int {
        let p = try RDFSerializationConfiguration.shared.expectedParserFor(filename: filename)

        var quads = [Quad]()
        let count = try p.parser.parseFile(filename, mediaType: mediaType, base: base) { (s, p, o) in
            let q = Quad(subject: s, predicate: p, object: o, graph: graph)
            quads.append(q)
        }
        
        try store.load(version: version, quads: quads)
        return count
    }
}
