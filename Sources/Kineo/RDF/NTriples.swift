//
//  NTriples.swift
//  PageDatabase
//
//  Created by Gregory Todd Williams on 6/4/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import SPARQLSyntax

extension String {
    static let unicodeScalarsNeedingNTriplesIRIEscaping : Set<UnicodeScalar> = {
        var charactersNeedingEscaping = Set<UnicodeScalar>()
        for i in 0x00...0x20 {
            charactersNeedingEscaping.insert(UnicodeScalar(i)!)
        }
        charactersNeedingEscaping.insert(UnicodeScalar(0x3c))
        charactersNeedingEscaping.insert(UnicodeScalar(0x3e))
        charactersNeedingEscaping.insert(UnicodeScalar(0x22))
        charactersNeedingEscaping.insert(UnicodeScalar(0x5c))
        charactersNeedingEscaping.insert(UnicodeScalar(0x5e))
        charactersNeedingEscaping.insert(UnicodeScalar(0x60))
        charactersNeedingEscaping.insert(UnicodeScalar(0x7b))
        charactersNeedingEscaping.insert(UnicodeScalar(0x7c))
        charactersNeedingEscaping.insert(UnicodeScalar(0x7d))
        return charactersNeedingEscaping
    }()
    
    static let unicodeScalarsNeedingNTriplesLiteralEscaping = Set<UnicodeScalar>([
        UnicodeScalar(0x22),
        UnicodeScalar(0x5c),
        UnicodeScalar(0x0a),
        UnicodeScalar(0x0d)
        ])
    
    var ntriplesStringEscaped: String {
        let needsEscaping = self.unicodeScalars.contains { String.unicodeScalarsNeedingNTriplesLiteralEscaping.contains($0) || $0.value >= 0x80 }
        if !needsEscaping {
            return self
        } else {
            var escaped = ""
            for c in self {
                switch c {
                case _ where c.unicodeScalars.first != nil && c.unicodeScalars.first!.value >= 0x80:
                    for s in c.unicodeScalars {
                        let value = s.value
                        if value <= 0xFFFF {
                            escaped += String(format: "\\u%04X", value)
                        } else {
                            escaped += String(format: "\\U%08X", value)
                        }
                    }
                case Character(UnicodeScalar(0x22)):
                    escaped += "\\\""
                case Character(UnicodeScalar(0x5c)):
                    escaped += "\\\\"
                case Character(UnicodeScalar(0x0a)):
                    escaped += "\\n"
                case Character(UnicodeScalar(0x0d)):
                    escaped += "\\r"
                default:
                    escaped.append(c)
                }
            }
            return escaped
        }
    }
    
    var ntriplesIRIEscaped: String {
        let needsEscaping = self.unicodeScalars.contains {
            $0.value <= 0x20 || String.unicodeScalarsNeedingNTriplesIRIEscaping.contains($0) || $0.value >= 0x80
        }
        if !needsEscaping {
            return self
        } else {
            var escaped = ""
            for c in self {
                switch c {
                case _ where String.unicodeScalarsNeedingNTriplesIRIEscaping.contains(c.unicodeScalars.first!),
                     _ where c.unicodeScalars.first != nil && c.unicodeScalars.first!.value >= 0x80:
                    for s in c.unicodeScalars {
                        let value = s.value
                        if value <= 0xFFFF {
                            escaped += String(format: "\\u%04X", value)
                        } else {
                            escaped += String(format: "\\U%08X", value)
                        }
                    }
                default:
                    escaped.append(c)
                }
            }
            return escaped
        }
    }
}

extension Term {
    func ntriplesData() -> Data? {
        switch self.type {
        case .iri:
            return "<\(self.value.ntriplesIRIEscaped)>".data(using: .utf8)
        case .blank:
            return "_:\(self.value)".data(using: .utf8)
        case .language(let l):
            return "\"\(value.ntriplesStringEscaped)\"@\(l)".data(using: .utf8)
        case .datatype(.string):
            return "\"\(value.ntriplesStringEscaped)\"".data(using: .utf8)
        case .datatype(let dt):
            return "\"\(value.ntriplesStringEscaped)\"^^<\(dt.value)>".data(using: .utf8)
        }
    }
    
    func printNTriplesString<T: TextOutputStream>(to stream: inout T) {
        switch self.type {
        case .iri:
            stream.write("<")
            stream.write(self.value.ntriplesIRIEscaped)
            stream.write("> ")
        case .blank:
            stream.write("_:")
            stream.write(self.value)
            stream.write(" ")
        case .language(let l):
            stream.write("\"")
            stream.write(self.value.ntriplesStringEscaped)
            stream.write("\"@")
            stream.write(l)
            stream.write(" ")
        case .datatype(.string):
            stream.write("\"")
            stream.write(self.value.ntriplesStringEscaped)
            stream.write("\" ")
        case .datatype(let dt):
            stream.write("\"")
            stream.write(self.value.ntriplesStringEscaped)
            stream.write("\"^^<")
            stream.write(dt.value)
            stream.write("> ")
        }
    }
}

open class NTriplesSerializer : RDFSerializer {
    public var canonicalMediaType = "application/n-triples"
    
    public init() {
        
    }
    
    public func serialize(_ triple: Triple, to data: inout Data) throws {
        for t in triple {
            guard let termData = t.ntriplesData() else {
                throw SerializationError.encodingError("Failed to encode term as utf-8: \(t)")
            }
            data.append(termData)
            data.append(0x20)
        }
        data.append(contentsOf: [0x2e, 0x0a]) // dot newline
    }
    
    public func serialize<T: TextOutputStream, S: Sequence>(_ triples: S, to stream: inout T) throws where S.Element == Triple {
        for triple in triples {
            for t in triple {
                t.printNTriplesString(to: &stream)
            }
            stream.write(".\n")
        }
    }

    public func serialize<S: Sequence>(_ triples: S) throws -> Data where S.Element == Triple {
        var d = Data()
        for t in triples {
            try serialize(t, to: &d)
        }
        return d
    }
}

open class NTriplesParser<T: LineReadable> : Sequence {
    var blanks: [String:Term]
    let reader: T
    public init(reader: T) {
        self.reader = reader
        self.blanks = [:]
    }

    func parseBlank<T>(_ generator: inout PeekableIterator<T>) -> Term? where T.Element == UnicodeScalar {
        guard generator.next() == .some("_") else { return nil }
        guard generator.next() == .some(":") else { return nil }
        var label = ""
        repeat {
            switch generator.peek() {
            case .some("\t"), .some(" "), .none:
                _ = generator.next()
                if let b = blanks[label] {
                    return b
                } else {
                    let id = NSUUID().uuidString
                    let b = Term(value: id, type: .blank)
                    blanks[label] = b
                    return b
                }
            case .some(let c):
                label.append(String(c))
                _ = generator.next()
            }
        } while true
    }

    func parseEscape<T>(_ generator: inout PeekableIterator<T>, allowEChars: Bool = true) -> UnicodeScalar? where T.Element == UnicodeScalar {
        guard let c = generator.next() else { return nil }
        switch c {
        case "t" where allowEChars:
            return "\t"
        case "n" where allowEChars:
            return "\n"
        case "r" where allowEChars:
            return "\r"
        case "\"" where allowEChars:
            return "\""
        case "\\" where allowEChars:
            return "\\"
        case "u":
            return parseHex(&generator, length: 4)
        case "U":
            return parseHex(&generator, length: 8)
        default:
            return nil
        }
    }

    func parseHex<T>(_ generator: inout PeekableIterator<T>, length: Int) -> UnicodeScalar? where T.Element == UnicodeScalar {
        var value: UInt32 = 0
        var string = ""
        for _ in 0..<length {
            guard let c = generator.next() else { return nil }
            guard let char = String(c).uppercased().unicodeScalars.first else { return nil }
            string.append(String(char))
            if char >= "A" && char <= "F" {
                value = 16 * value + 10 + char.value - 65
            } else if char >= "0" && char <= "9" {
                value = 16 * value + char.value - 48
            } else {
                return nil
            }
        }
        return UnicodeScalar(value)
    }

    func parseIRI<T>(_ generator: inout PeekableIterator<T>) -> Term? where T.Element == UnicodeScalar {
        guard generator.next() == .some("<") else { warn("***"); return nil }
        var label = ""
        repeat {
            switch generator.peek() {
            case .some(">"), .none:
                _ = generator.next()
                return Term(value: label, type: .iri)
            case .some("\\"):
                _ = generator.next()
                if let c = parseEscape(&generator, allowEChars: false) {
                    label.append(String(c))
                } else {
                    return nil
                }
            case .some(let c):
                label.append(String(c))
                _ = generator.next()
            }
        } while true
    }

    func parseLang<T>(_ generator: inout PeekableIterator<T>) -> TermType? where T.Element == UnicodeScalar {
        guard generator.next() == .some("@") else { return nil }
        var label = ""
        repeat {
            switch generator.peek() {
            case .some(let c) where c == "-" || (c >= "A" && c <= "Z") || (c >= "a" && c <= "z"):
                label.append(String(c))
                _ = generator.next()
            default:
                _ = generator.next()
                return .language(label)
            }
        } while true
    }

    func parseLiteral<T>(_ generator: inout PeekableIterator<T>) -> Term? where T.Element == UnicodeScalar {
        guard generator.next() == .some("\"") else { warn("***"); return nil }
        var label = ""
        repeat {
            switch generator.peek() {
            case .some("\\"):
                _ = generator.next()
                if let c = parseEscape(&generator) {
                    label.append(String(c))
                } else {
                    return nil
                }
            case .some("\""), .none:
                _ = generator.next()
                if generator.peek() == .some("@") {
                    guard let lang = parseLang(&generator) else { return nil }
                    return Term(value: label, type: lang)
                } else if generator.peek() == .some("^") {
                    guard generator.next() == .some("^") else { return nil }
                    guard generator.next() == .some("^") else { return nil }
                    guard let dt = parseIRI(&generator) else { return nil }
                    return Term(value: label, type: .datatype(TermDataType(stringLiteral: dt.value)))
                } else {
                    return Term(value: label, type: .datatype(.string))
                }
            case .some(let c):
                label.append(String(c))
                _ = generator.next()
            }
        } while true
    }

    func parseTerm<T>(_ chars: inout PeekableIterator<T>) -> Term? where T.Element == UnicodeScalar {
        repeat {
            if let c = chars.peek() {
                switch c {
                case " ", "\t":
                    _ = chars.next()
                    continue
                case "_":
                    guard let t = parseBlank(&chars) else { return nil }
                    return t
                case "<":
                    guard let t = parseIRI(&chars) else { return nil }
                    return t
                case "\"":
                    guard let t = parseLiteral(&chars) else { return nil }
                    return t
                default:
                    return nil
                }
            } else {
                return nil
            }
        } while true
    }

    public func parseQuad(line: String, graph: Term) -> Quad? {
        guard let t = parseTriple(line: line) else { return nil }
        return Quad(subject: t.subject, predicate: t.predicate, object: t.object, graph: graph)
    }

    public func parseTriple(line: String) -> Triple? {
        var chars = PeekableIterator(generator: line.unicodeScalars.makeIterator())
        chars.dropWhile { $0 == " " || $0 == "\t" }
        if chars.peek() == "#" { return nil }
        var terms: [Term] = []
        repeat {
            guard let t = parseTerm(&chars) else { return nil }
            terms.append(t)
        } while terms.count != 3
        return Triple(subject: terms[0], predicate: terms[1], object: terms[2])
    }

    public func makeIterator() -> AnyIterator<Triple> {
        let fr = self.reader
        let lines = fr.lines()
        return AnyIterator { () -> Triple? in
            repeat {
                guard let line = lines.next() else { return nil }
                if let t = self.parseTriple(line: line) {
                    return t
                }
            } while true
        }
    }
}

open class NTriplesPatternParser<T: LineReadable> : NTriplesParser<T> {
    public override init(reader: T) {
        super.init(reader: reader)
    }
    func parseVariable<T>(_ generator: inout PeekableIterator<T>) -> String? where T.Element == UnicodeScalar {
        guard generator.next() == .some("?") else { return nil }
        var label = ""
        repeat {
            switch generator.peek() {
            case .some("\t"), .some(" "), .none:
                _ = generator.next()
                return label
            case .some(let c):
                label.append(String(c))
                _ = generator.next()
            }
        } while true
    }

    public func patternIterator() -> AnyIterator<QuadPattern> {
        let fr = self.reader
        let lines = fr.lines()
        return AnyIterator { () -> QuadPattern? in
            LINE: repeat {
                guard let line = lines.next() else { return nil }
                var chars = PeekableIterator(generator: line.unicodeScalars.makeIterator())
                chars.dropWhile { $0 == " " || $0 == "\t" }
                if chars.peek() == "#" { continue LINE }
                var nodes: [Node] = []
                repeat {
                    if let t = self.parseTerm(&chars) {
                        nodes.append(.bound(t))
                    } else if let s = self.parseVariable(&chars) {
                        nodes.append(.variable(s, binding: !s.hasPrefix(".")))
                    } else {
                        continue LINE
                    }
                } while nodes.count != 4
                return QuadPattern(subject: nodes[0], predicate: nodes[1], object: nodes[2], graph: nodes[3])
            } while true
        }
    }

    public func parseNodes(chars: inout PeekableIterator<AnyIterator<UnicodeScalar>>, count: Int) -> [Node]? {
        var nodes = [Node]()
        repeat {
            chars.dropWhile { $0 == " " || $0 == "\t" }
            if chars.peek() == "#" { return nil }
            if let t = parseTerm(&chars) {
                nodes.append(.bound(t))
            } else if let s = parseVariable(&chars) {
                nodes.append(.variable(s, binding: !s.hasPrefix(".")))
            } else {
                return nil
            }
        } while nodes.count < count
        return nodes
    }

    public func parseNode(line: String) -> Node? {
        let view = AnyIterator(line.unicodeScalars.makeIterator())
        var chars = PeekableIterator(generator: view)
        guard let nodes = parseNodes(chars: &chars, count: 1) else { return nil }
        guard nodes.count == 1 else { return nil }
        return nodes[0]
    }

    public func parseQuadPattern(line: String) -> QuadPattern? {
        var chars = PeekableIterator(generator: line.unicodeScalars.makeIterator())
        chars.dropWhile { $0 == " " || $0 == "\t" }
        if chars.peek() == "#" { return nil }
        var nodes: [Node] = []
        repeat {
            if let t = parseTerm(&chars) {
                nodes.append(.bound(t))
            } else if let s = parseVariable(&chars) {
                nodes.append(.variable(s, binding: !s.hasPrefix(".")))
            } else {
                return nil
            }
        } while nodes.count != 4
        chars.dropWhile { $0 == " " || $0 == "." }
        guard chars.peek() == nil else { return nil }
        return QuadPattern(subject: nodes[0], predicate: nodes[1], object: nodes[2], graph: nodes[3])
    }

    public func parseTriplePattern(line: String) -> TriplePattern? {
        var chars = PeekableIterator(generator: line.unicodeScalars.makeIterator())
        chars.dropWhile { $0 == " " || $0 == "\t" }
        if chars.peek() == "#" { return nil }
        var nodes: [Node] = []
        repeat {
            if let t = parseTerm(&chars) {
                nodes.append(.bound(t))
            } else if let s = parseVariable(&chars) {
                nodes.append(.variable(s, binding: !s.hasPrefix(".")))
            } else {
                return nil
            }
        } while nodes.count != 3
        chars.dropWhile { $0 == " " || $0 == "." }
        guard chars.peek() == nil else { return nil }
        return TriplePattern(subject: nodes[0], predicate: nodes[1], object: nodes[2])
    }
}

extension NTriplesSerializer : SPARQLSerializable {
    public func serialize(_ results: QueryResult<[TermResult], [Triple]>) throws -> Data {
        switch results {
        case .triples(let triples):
            return try serialize(triples)
        default:
            throw SerializationError.encodingError("SPARQL results cannot be serialized as N-Triples")
        }
    }
}
