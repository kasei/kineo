//
//  Lexer.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 10/16/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation

public enum SPARQLParsingError : Error {
    case lexicalError(String)
    case parsingError(String)
}

public enum SPARQLToken {
    case ws
    case comment(String)
    case _nil
    case anon
    case double(String)
    case decimal(String)
    case integer(String)
    case hathat
    case lang(String)
    case lparen
    case rparen
    case lbrace
    case rbrace
    case lbracket
    case rbracket
    case equals
    case notequals
    case bang
    case le
    case ge
    case lt
    case gt
    case andand
    case oror
    case semicolon
    case dot
    case comma
    case plus
    case minus
    case star
    case slash
    case _var(String)
    case string3d(String)
    case string3s(String)
    case string1d(String)
    case string1s(String)
    case bnode(String)
    case hat
    case question
    case or
    case prefixname(String, String)
    case boolean(String)
    case keyword(String)
    case iri(String)
    
    public var isVerb : Bool {
        if isTermOrVar {
            return true
        } else {
            switch self {
            case .lparen, .hat, .bang:
                return true
            default:
                return false
            }
        }
    }
    
    public var isTerm : Bool {
        switch self {
        case .keyword("A"):
            return true
        case ._nil, .minus, .plus:
            return true
        case .integer(_), .decimal(_), .double(_), .anon, .boolean(_), .bnode(_), .iri(_), .prefixname(_, _), .string1d(_), .string1s(_), .string3d(_), .string3s(_):
            return true
        default:
            return false
        }
    }
    
    public var isTermOrVar : Bool {
        if isTerm {
            return true
        }
        
        switch self {
        case ._var(_):
            return true
        default:
            return false
        }
    }
    
    public var isNumber : Bool {
        switch self {
        case .integer(_), .decimal(_), .double(_):
            return true
        default:
            return false
        }
    }

    public var isString : Bool {
        switch self {
        case .string1d(_), .string1s(_), .string3d(_), .string3s(_):
            return true
        default:
            return false
        }
    }
    
    public var isRelationalOperator : Bool {
        switch self {
        case .lt, .le, .gt, .ge, .equals, .notequals, .andand, .oror:
            return true
        default:
            return false
        }
    }
}

extension SPARQLToken : Equatable {
    public static func ==(lhs: SPARQLToken, rhs: SPARQLToken) -> Bool {
        switch (lhs, rhs) {
        case (.comment(let a), .comment(let b)) where a == b:
            return true
        case (.double(let a), .double(let b)) where a == b:
            return true
        case (.decimal(let a), .decimal(let b)) where a == b:
            return true
        case (.integer(let a), .integer(let b)) where a == b:
            return true
        case (.lang(let a), .lang(let b)) where a == b:
            return true
        case (._var(let a), ._var(let b)) where a == b:
            return true
        case (.string3d(let a), .string3d(let b)) where a == b:
            return true
        case (.string3s(let a), .string3s(let b)) where a == b:
            return true
        case (.string1d(let a), .string1d(let b)) where a == b:
            return true
        case (.string1s(let a), .string1s(let b)) where a == b:
            return true
        case (.bnode(let a), .bnode(let b)) where a == b:
            return true
        case (.prefixname(let a, let b), .prefixname(let c, let d)) where a == c && b == d:
            return true
        case (.boolean(let a), .boolean(let b)) where a == b:
            return true
        case (.keyword(let a), .keyword(let b)) where a == b:
            return true
        case (.iri(let a), .iri(let b)) where a == b:
            return true
        case (.ws, .ws), (._nil, ._nil), (.anon, .anon), (.hathat, .hathat), (.lparen, .lparen), (.rparen, .rparen), (.lbrace, .lbrace), (.rbrace, .rbrace), (.lbracket, .lbracket), (.rbracket, .rbracket), (.equals, .equals), (.notequals, .notequals), (.bang, .bang), (.le, .le), (.ge, .ge), (.lt, .lt), (.gt, .gt), (.andand, .andand), (.oror, .oror), (.semicolon, .semicolon), (.dot, .dot), (.comma, .comma), (.plus, .plus), (.minus, .minus), (.star, .star), (.slash, .slash), (.hat, .hat), (.question, .question), (.or, .or):
            return true
        default:
            return false
        }
    }
}

public struct SPARQLLexer : IteratorProtocol {
    var source : InputStream
    var lookaheadBuffer : [UInt8]
    var errorBuffer : String
    var string : String
    var stringPos : UInt
    var line : Int
    var column : Int
    var character : UInt
    var buffer : String
    var startColumn : Int
    var startLine : Int
    var startCharacter : UInt
    var comments : Bool
    var _lookahead : SPARQLToken?
    
    private mutating func lexError(_ message : String) -> SPARQLParsingError {
        try? fillBuffer()
        let rest = buffer
        return SPARQLParsingError.lexicalError("\(message) at \(line):\(column) near '\(rest)...'")
    }

    private static let r_PNAME_LN	= "((((([A-Z]|[a-z]|[\\x{00C0}-\\x{00D6}]|[\\x{00D8}-\\x{00F6}]|[\\x{00F8}-\\x{02FF}]|[\\x{0370}-\\x{037D}]|[\\x{037F}-\\x{1FFF}]|[\\x{200C}-\\x{200D}]|[\\x{2070}-\\x{218F}]|[\\x{2C00}-\\x{2FEF}]|[\\x{3001}-\\x{D7FF}]|[\\x{F900}-\\x{FDCF}]|[\\x{FDF0}-\\x{FFFD}]|[\\x{10000}-\\x{EFFFF}])(((([_]|([A-Z]|[a-z]|[\\x{00C0}-\\x{00D6}]|[\\x{00D8}-\\x{00F6}]|[\\x{00F8}-\\x{02FF}]|[\\x{0370}-\\x{037D}]|[\\x{037F}-\\x{1FFF}]|[\\x{200C}-\\x{200D}]|[\\x{2070}-\\x{218F}]|[\\x{2C00}-\\x{2FEF}]|[\\x{3001}-\\x{D7FF}]|[\\x{F900}-\\x{FDCF}]|[\\x{FDF0}-\\x{FFFD}]|[\\x{10000}-\\x{EFFFF}]))|-|[0-9]|\\x{00B7}|[\\x{0300}-\\x{036F}]|[\\x{203F}-\\x{2040}])|[.])*(([_]|([A-Z]|[a-z]|[\\x{00C0}-\\x{00D6}]|[\\x{00D8}-\\x{00F6}]|[\\x{00F8}-\\x{02FF}]|[\\x{0370}-\\x{037D}]|[\\x{037F}-\\x{1FFF}]|[\\x{200C}-\\x{200D}]|[\\x{2070}-\\x{218F}]|[\\x{2C00}-\\x{2FEF}]|[\\x{3001}-\\x{D7FF}]|[\\x{F900}-\\x{FDCF}]|[\\x{FDF0}-\\x{FFFD}]|[\\x{10000}-\\x{EFFFF}]))|-|[0-9]|\\x{00B7}|[\\x{0300}-\\x{036F}]|[\\x{203F}-\\x{2040}]))?))?:)((([_]|([A-Z]|[a-z]|[\\x{00C0}-\\x{00D6}]|[\\x{00D8}-\\x{00F6}]|[\\x{00F8}-\\x{02FF}]|[\\x{0370}-\\x{037D}]|[\\x{037F}-\\x{1FFF}]|[\\x{200C}-\\x{200D}]|[\\x{2070}-\\x{218F}]|[\\x{2C00}-\\x{2FEF}]|[\\x{3001}-\\x{D7FF}]|[\\x{F900}-\\x{FDCF}]|[\\x{FDF0}-\\x{FFFD}]|[\\x{10000}-\\x{EFFFF}]))|[:0-9]|((?:\\\\([-~.!&'()*+,;=/?#@%_\\$]))|%[0-9A-Fa-f]{2}))(((([_]|([A-Z]|[a-z]|[\\x{00C0}-\\x{00D6}]|[\\x{00D8}-\\x{00F6}]|[\\x{00F8}-\\x{02FF}]|[\\x{0370}-\\x{037D}]|[\\x{037F}-\\x{1FFF}]|[\\x{200C}-\\x{200D}]|[\\x{2070}-\\x{218F}]|[\\x{2C00}-\\x{2FEF}]|[\\x{3001}-\\x{D7FF}]|[\\x{F900}-\\x{FDCF}]|[\\x{FDF0}-\\x{FFFD}]|[\\x{10000}-\\x{EFFFF}]))|-|[0-9]|\\x{00B7}|[\\x{0300}-\\x{036F}]|[\\x{203F}-\\x{2040}])|((?:\\\\([-~.!&'()*+,;=/?#@%_\\$]))|%[0-9A-Fa-f]{2})|[:.])*((([_]|([A-Z]|[a-z]|[\\x{00C0}-\\x{00D6}]|[\\x{00D8}-\\x{00F6}]|[\\x{00F8}-\\x{02FF}]|[\\x{0370}-\\x{037D}]|[\\x{037F}-\\x{1FFF}]|[\\x{200C}-\\x{200D}]|[\\x{2070}-\\x{218F}]|[\\x{2C00}-\\x{2FEF}]|[\\x{3001}-\\x{D7FF}]|[\\x{F900}-\\x{FDCF}]|[\\x{FDF0}-\\x{FFFD}]|[\\x{10000}-\\x{EFFFF}]))|-|[0-9]|\\x{00B7}|[\\x{0300}-\\x{036F}]|[\\x{203F}-\\x{2040}])|[:]|((?:\\\\([-~.!&'()*+,;=/?#@%_\\$]))|%[0-9A-Fa-f]{2})))?))"
    private static let r_PNAME_NS	= "(((([A-Z]|[a-z]|[\\x{00C0}-\\x{00D6}]|[\\x{00D8}-\\x{00F6}]|[\\x{00F8}-\\x{02FF}]|[\\x{0370}-\\x{037D}]|[\\x{037F}-\\x{1FFF}]|[\\x{200C}-\\x{200D}]|[\\x{2070}-\\x{218F}]|[\\x{2C00}-\\x{2FEF}]|[\\x{3001}-\\x{D7FF}]|[\\x{F900}-\\x{FDCF}]|[\\x{FDF0}-\\x{FFFD}]|[\\x{10000}-\\x{EFFFF}])(((([_]|([A-Z]|[a-z]|[\\x{00C0}-\\x{00D6}]|[\\x{00D8}-\\x{00F6}]|[\\x{00F8}-\\x{02FF}]|[\\x{0370}-\\x{037D}]|[\\x{037F}-\\x{1FFF}]|[\\x{200C}-\\x{200D}]|[\\x{2070}-\\x{218F}]|[\\x{2C00}-\\x{2FEF}]|[\\x{3001}-\\x{D7FF}]|[\\x{F900}-\\x{FDCF}]|[\\x{FDF0}-\\x{FFFD}]|[\\x{10000}-\\x{EFFFF}]))|-|[0-9]|\\x{00B7}|[\\x{0300}-\\x{036F}]|[\\x{203F}-\\x{2040}])|[.])*(([_]|([A-Z]|[a-z]|[\\x{00C0}-\\x{00D6}]|[\\x{00D8}-\\x{00F6}]|[\\x{00F8}-\\x{02FF}]|[\\x{0370}-\\x{037D}]|[\\x{037F}-\\x{1FFF}]|[\\x{200C}-\\x{200D}]|[\\x{2070}-\\x{218F}]|[\\x{2C00}-\\x{2FEF}]|[\\x{3001}-\\x{D7FF}]|[\\x{F900}-\\x{FDCF}]|[\\x{FDF0}-\\x{FFFD}]|[\\x{10000}-\\x{EFFFF}]))|-|[0-9]|\\x{00B7}|[\\x{0300}-\\x{036F}]|[\\x{203F}-\\x{2040}]))?))?:)"
    private static let r_DOUBLE     = "(([0-9]+[.][0-9]*[eE][+-]?[0-9]+)|([.][0-9]+[eE][+-]?[0-9]+)|([0-9]+[eE][+-]?[0-9]+))"
    private static let r_DECIMAL    = "[0-9]*[.][0-9]+"
    private static let r_INTEGER    = "[0-9]+"

    private static let _variableNameRegex : NSRegularExpression = {
        guard let r = try? NSRegularExpression(pattern: "((([_]|([A-Z]|[a-z]|[\\x{00C0}-\\x{00D6}]|[\\x{00D8}-\\x{00F6}]|[\\x{00F8}-\\x{02FF}]|[\\x{0370}-\\x{037D}]|[\\x{037F}-\\x{1FFF}]|[\\x{200C}-\\x{200D}]|[\\x{2070}-\\x{218F}]|[\\x{2C00}-\\x{2FEF}]|[\\x{3001}-\\x{D7FF}]|[\\x{F900}-\\x{FDCF}]|[\\x{FDF0}-\\x{FFFD}]|[\\x{10000}-\\x{EFFFF}]))|[0-9])(([_]|([A-Z]|[a-z]|[\\x{00C0}-\\x{00D6}]|[\\x{00D8}-\\x{00F6}]|[\\x{00F8}-\\x{02FF}]|[\\x{0370}-\\x{037D}]|[\\x{037F}-\\x{1FFF}]|[\\x{200C}-\\x{200D}]|[\\x{2070}-\\x{218F}]|[\\x{2C00}-\\x{2FEF}]|[\\x{3001}-\\x{D7FF}]|[\\x{F900}-\\x{FDCF}]|[\\x{FDF0}-\\x{FFFD}]|[\\x{10000}-\\x{EFFFF}]))|[0-9]|\\x{00B7}|[\\x{0300}-\\x{036F}]|[\\x{203F}-\\x{2040}])*)", options: .anchorsMatchLines) else { fatalError() }
        return r
    }()
    
    private static let _bnodeNameRegex : NSRegularExpression = {
        guard let r = try? NSRegularExpression(pattern: "^([0-9A-Za-z_\\x{00C0}-\\x{00D6}\\x{00D8}-\\x{00F6}\\x{00F8}-\\x{02FF}\\x{0370}-\\x{037D}\\x{037F}-\\x{1FFF}\\x{200C}-\\x{200D}\\x{2070}-\\x{218F}\\x{2C00}-\\x{2FEF}\\x{3001}-\\x{D7FF}\\x{F900}-\\x{FDCF}\\x{FDF0}-\\x{FFFD}\\x{10000}-\\x{EFFFF}])(([A-Za-z_\\x{00C0}-\\x{00D6}\\x{00D8}-\\x{00F6}\\x{00F8}-\\x{02FF}\\x{0370}-\\x{037D}\\x{037F}-\\x{1FFF}\\x{200C}-\\x{200D}\\x{2070}-\\x{218F}\\x{2C00}-\\x{2FEF}\\x{3001}-\\x{D7FF}\\x{F900}-\\x{FDCF}\\x{FDF0}-\\x{FFFD}\\x{10000}-\\x{EFFFF}])|([-0-9\\x{00B7}\\x{0300}-\\x{036F}\\x{203F}-\\x{2040}]))*", options: .anchorsMatchLines) else { fatalError() }
        return r
    }()
    
    private static let _keywordRegex : NSRegularExpression = {
        guard let r = try? NSRegularExpression(pattern: "(ABS|ADD|ALL|ASC|ASK|AS|AVG|BASE|BIND|BNODE|BOUND|BY|CEIL|CLEAR|COALESCE|CONCAT|CONSTRUCT|CONTAINS|COPY|COUNT|CREATE|DATATYPE|DAY|DEFAULT|DELETE|DELETE WHERE|DESCRIBE|DESC|DISTINCT|DISTINCT|DROP|ENCODE_FOR_URI|EXISTS|FILTER|FLOOR|FROM|GRAPH|GROUP_CONCAT|GROUP|HAVING|HOURS|IF|INSERT|INSERT|DATA|INTO|IN|IRI|ISBLANK|ISIRI|ISLITERAL|ISNUMERIC|ISURI|LANGMATCHES|LANG|LCASE|LIMIT|LOAD|MAX|MD5|MINUS|MINUTES|MIN|MONTH|MOVE|NAMED|NOT|NOW|OFFSET|OPTIONAL|ORDER|PREFIX|RAND|REDUCED|REGEX|REPLACE|ROUND|SAMETERM|SAMPLE|SECONDS|SELECT|SEPARATOR|SERVICE|SHA1|SHA256|SHA384|SHA512|SILENT|STRAFTER|STRBEFORE|STRDT|STRENDS|STRLANG|STRLEN|STRSTARTS|STRUUID|STR|SUBSTR|SUM|TIMEZONE|TO|TZ|UCASE|UNDEF|UNION|URI|USING|UUID|VALUES|WHERE|WITH|YEAR)\\b", options: [.anchorsMatchLines, .caseInsensitive]) else { fatalError() }
        return r
    }()
    
    fileprivate static let _functions : Set<String> = {
        let funcs = Set(["STR", "LANG", "LANGMATCHES", "DATATYPE", "BOUND", "IRI", "URI", "BNODE", "RAND", "ABS", "CEIL", "FLOOR", "ROUND", "CONCAT", "STRLEN", "UCASE", "LCASE", "ENCODE_FOR_URI", "CONTAINS", "STRSTARTS", "STRENDS", "STRBEFORE", "STRAFTER", "YEAR", "MONTH", "DAY", "HOURS", "MINUTES", "SECONDS", "TIMEZONE", "TZ", "NOW", "UUID", "STRUUID", "MD5", "SHA1", "SHA256", "SHA384", "SHA512", "COALESCE", "IF", "STRLANG", "STRDT", "SAMETERM", "SUBSTR", "REPLACE", "ISIRI", "ISURI", "ISBLANK", "ISLITERAL", "ISNUMERIC", "REGEX"])
        return funcs
    }()
    
    fileprivate static let _aggregates : Set<String> = {
        let aggs = Set(["COUNT", "SUM", "MIN", "MAX", "AVG", "SAMPLE", "GROUP_CONCAT"])
        return aggs
    }()
    
    private static let _aRegex : NSRegularExpression = {
        guard let r = try? NSRegularExpression(pattern: "a\\b", options: .anchorsMatchLines) else { fatalError() }
        return r
    }()
    
    private static let _booleanRegex : NSRegularExpression = {
        guard let r = try? NSRegularExpression(pattern: "(true|false)\\b", options: [.anchorsMatchLines, .caseInsensitive]) else { fatalError() }
        return r
    }()
    
    private static let _multiLineAnonRegex : NSRegularExpression = {
        guard let r = try? NSRegularExpression(pattern: "(\\[|\\()[\\t\\r\\n ]*$", options: .anchorsMatchLines) else { fatalError() }
        return r
    }()
    
    private static let _pNameLNre : NSRegularExpression = {
        guard let r = try? NSRegularExpression(pattern: r_PNAME_LN, options: []) else { fatalError() }
        return r
    }()
    
    private static let _pNameNSre : NSRegularExpression = {
        guard let r = try? NSRegularExpression(pattern: r_PNAME_NS, options: []) else { fatalError() }
        return r
    }()
    
    private static let _escapedCharRegex : NSRegularExpression = {
        guard let r = try? NSRegularExpression(pattern: "\\\\(.)", options: []) else { fatalError() }
        return r
    }()
    

    private static let _alphanumRegex : NSRegularExpression = {
        guard let r = try? NSRegularExpression(pattern: "[0-9A-Fa-f]+", options: []) else { fatalError() }
        return r
    }()
    
    private static let _iriRegex : NSRegularExpression = {
        guard let r = try? NSRegularExpression(pattern: "<([^<>\"{}|^`\\x{00}-\\x{20}])*>", options: []) else { fatalError() }
        return r
    }()
    
    private static let _unescapedIRIRegex : NSRegularExpression = {
        guard let r = try? NSRegularExpression(pattern: "[^>\\\\]+", options: []) else { fatalError() }
        return r
    }()
    
    private static let _nilRegex : NSRegularExpression = {
        guard let r = try? NSRegularExpression(pattern: "[(][ \r\n\t]*[)]", options: []) else { fatalError() }
        return r
    }()
    
    private static let _doubleRegex : NSRegularExpression = {
        guard let r = try? NSRegularExpression(pattern: r_DOUBLE, options: []) else { fatalError() }
        return r
    }()
    
    private static let _decimalRegex : NSRegularExpression = {
        guard let r = try? NSRegularExpression(pattern: r_DECIMAL, options: []) else { fatalError() }
        return r
    }()
    
    private static let _integerRegex : NSRegularExpression = {
        guard let r = try? NSRegularExpression(pattern: r_INTEGER, options: []) else { fatalError() }
        return r
    }()
    
    private static let _anonRegex : NSRegularExpression = {
        guard let r = try? NSRegularExpression(pattern: "\\[[ \u{0a}\u{0d}\u{09}]*\\]", options: []) else { fatalError() }
        return r
    }()
    
    private static let _prefixOrBaseRegex : NSRegularExpression = {
        guard let r = try? NSRegularExpression(pattern: "(prefix|base)\\b", options: []) else { fatalError() }
        return r
    }()
    
    private static let _langRegex : NSRegularExpression = {
        guard let r = try? NSRegularExpression(pattern: "[a-zA-Z]+(-[a-zA-Z0-9]+)*\\b", options: []) else { fatalError() }
        return r
    }()
    
    private static let pnCharSet : CharacterSet = {
        var pn = CharacterSet()
        pn.insert(charactersIn: "a"..."z")
        pn.insert(charactersIn: "A"..."Z")

        // This is working around a bug in the swift compiler that causes a crash when U+D7FF is inserted into a CharacterSet as part of a ClosedRange.
        // Instead, we insert it directly as a single UnicodeScalar.
        guard let scalar = UnicodeScalar(0xD7FF) else { fatalError() }
        pn.insert(scalar)

        let ranges : [(Int, Int)] = [
            (0xC0, 0xD6),
            (0xD8, 0xF6),
            (0xF8, 0xFF),
            (0x370, 0x37D),
            (0x37F, 0x1FFF),
            (0x200C, 0x200D),
            (0x2070, 0x218F),
            (0x2C00, 0x2FEF),
            (0x3001, 0xD7FE), // U+D7FF should be included here
            (0xF900, 0xFDCF),
            (0xFDF0, 0xFFFD),
            (0x10000, 0xEFFFF),
        ]
        for bounds in ranges {
            guard let mn = UnicodeScalar(bounds.0) else { fatalError() }
            guard let mx = UnicodeScalar(bounds.1) else { fatalError() }
            let range = mn...mx
            pn.insert(charactersIn: range)
        }
        return pn
    }()
   
    public init(source : InputStream) {
        self.source = source
        self.lookaheadBuffer = []
        self.errorBuffer = ""
        self.string = ""
        self.stringPos = 0
        self.line = 1
        self.column = 1
        self.character = 0
        self.buffer = ""
        self.startColumn = -1
        self.startLine = -1
        self.startCharacter = 0
        self.comments = true
        self._lookahead = nil
    }
    
    mutating func readUnicodeEscape(length : Int) throws -> [UInt8] {
        var charbuffer = [UInt8](repeating: 0, count: length)
        let read = source.read(&charbuffer, maxLength: length)
        guard read == length else { throw lexError("Failed to read unicode escape") }
        guard let hex = String(bytes: charbuffer, encoding: .utf8) else { throw lexError("Failed to read unicode escape") }
        guard let codepoint = Int(hex, radix: 16), let us = UnicodeScalar(codepoint) else {
            throw lexError("Invalid unicode codepoint: \(hex)")
        }
        let s = String(us)
        let u = Array(s.utf8)
        return u
    }
    
    mutating func fillBuffer() throws {
        guard source.hasBytesAvailable else { return }
        guard buffer.characters.count == 0 else { return }
        var bytes = [UInt8]()
        var charbuffer : [UInt8] = [0]
        LOOP: while true {
            let read = source.read(&charbuffer, maxLength: 1)
            guard read != -1 else { print("\(source.streamError)"); break }
            guard read > 0 else { break }
            
            if charbuffer[0] == 0x5c {
                // backslash; check for \u or \U escapes
                let read = source.read(&charbuffer, maxLength: 1)
                guard read != -1 else { print("\(source.streamError)"); break }
                guard read > 0 else { break }
                
                switch charbuffer[0] {
                case 0x75: // \u
                    try bytes.append(contentsOf: readUnicodeEscape(length: 4))
                case 0x55: // \U
                    try bytes.append(contentsOf: readUnicodeEscape(length: 8))
                default:
                    bytes.append(0x5c)
                    bytes.append(charbuffer[0])
                }
            } else {
                bytes.append(charbuffer[0])
            }
            
            if charbuffer[0] == 0x0a || charbuffer[0] == 0x0d {
                if let s = String(bytes: bytes, encoding: .utf8) {
                    let trimmed = s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    if trimmed.hasSuffix("[") || trimmed.hasSuffix("(") {
                        continue
                    }
                }
                break
            }
        }
        
        guard let s = String(bytes: bytes, encoding: .utf8) else { return }
        buffer = s
    }
    
    public mutating func next() -> SPARQLToken? {
        do {
            return try getToken()
        } catch {
            return nil
        }
    }

    mutating func peekToken() throws -> SPARQLToken? {
        if let t = _lookahead {
            return t
        } else {
            _lookahead = try _getToken()
            return _lookahead
        }
    }
    
    mutating func getToken() throws -> SPARQLToken? {
        if let t = _lookahead {
            _lookahead = nil
            return t
        } else {
            return try _getToken()
        }
    }
    
    mutating func _getToken() throws -> SPARQLToken? {
        while true {
            try fillBuffer()
            guard var c = try peekChar() else { return nil }
            
            self.startColumn = column
            self.startLine = line
            self.startCharacter = character
            
            if c == " " || c == "\t" || c == "\n" || c == "\r" {
                while c == " " || c == "\t" || c == "\n" || c == "\r" {
                    getChar()
                    if let cc = try peekChar() {
                        c = cc
                    } else {
                        return nil
                    }
                }
                continue
            } else if c == "#" {
                while c != "\n" && c != "\r" {
                    getChar()
                    if let cc = try peekChar() {
                        c = cc
                    } else {
                        return nil
                    }
                }
                continue
            }
            
            let bufferLength = NSMakeRange(0, buffer.characters.count)

            let nil_range = SPARQLLexer._nilRegex.rangeOfFirstMatch(in: buffer, options: [], range: bufferLength)
            if nil_range.location == 0 {
                try read(length: nil_range.length)
                return ._nil
            }
            
            let anon_range = SPARQLLexer._anonRegex.rangeOfFirstMatch(in: buffer, options: [], range: bufferLength)
            if anon_range.location == 0 {
                try read(length: anon_range.length)
                return .anon
            }
            
            switch c {
            case ",":
                getChar()
                return .comma
            case ".":
                getChar()
                return .dot
            case "=":
                getChar()
                return .equals
            case "{":
                getChar()
                return .lbrace
            case "[":
                getChar()
                return .lbracket
            case "(":
                getChar()
                return .lparen
            case "-":
                getChar()
                return .minus
            case "+":
                getChar()
                return .plus
            case "}":
                getChar()
                return .rbrace
            case "]":
                getChar()
                return .rbracket
            case ")":
                getChar()
                return .rparen
            case ";":
                getChar()
                return .semicolon
            case "/":
                getChar()
                return .slash
            case "*":
                getChar()
                return .star
            default:
                break
            }
            
            let us = UnicodeScalar("\(c)")!
            if SPARQLLexer.pnCharSet.contains(us) {
                if let t = try getPName() {
                    return t
                }
            }
            
            switch c {
            case "@":
                return try getLanguage()
            case "<":
                return try getIRIRefOrRelational()
            case "?", "$":
                return try getVariable()
            case "!":
                return try getBang()
            case ">":
                return try getIRIRefOrRelational()
            case "|":
                return try getOr()
            case "'":
                return try getSingleLiteral()
            case "\"":
                return try getDoubleLiteral()
            case "_":
                return try getBnode()
            case ":":
                 return try getPName()
            default:
                break
            }
            
            
            let double_range = SPARQLLexer._doubleRegex.rangeOfFirstMatch(in: buffer, options: [], range: bufferLength)
            if double_range.location == 0 {
                let value = try read(length: double_range.length)
                return .double(value)
            }
            
            let decimal_range = SPARQLLexer._decimalRegex.rangeOfFirstMatch(in: buffer, options: [], range: bufferLength)
            if decimal_range.location == 0 {
                let value = try read(length: decimal_range.length)
                return .decimal(value)
            }
            
            let integer_range = SPARQLLexer._integerRegex.rangeOfFirstMatch(in: buffer, options: [], range: bufferLength)
            if integer_range.location == 0 {
                let value = try read(length: integer_range.length)
                return .integer(value)
            }
            
            if c == "^" {
                if buffer.hasPrefix("^^") {
                    try read(word: "^^")
                    return .hathat
                } else {
                    try read(word: "^")
                    return .hat
                }
            }
            
            if buffer.hasPrefix("&&") {
                try read(word: "&&")
                return .andand
            }
            
            return try getKeyword()
        }
    }
    
    mutating func getKeyword() throws -> SPARQLToken? {
        let bufferLength = NSMakeRange(0, buffer.characters.count)
        let keyword_range = SPARQLLexer._keywordRegex.rangeOfFirstMatch(in: buffer, options: [], range: bufferLength)
        if keyword_range.location == 0 {
            let value = try read(length: keyword_range.length)
            return .keyword(value.uppercased())
        }
        
        let a_range = SPARQLLexer._aRegex.rangeOfFirstMatch(in: buffer, options: [], range: bufferLength)
        if a_range.location == 0 {
            try getChar(expecting: "a")
            return .keyword("A")
        }

        let bool_range = SPARQLLexer._booleanRegex.rangeOfFirstMatch(in: buffer, options: [], range: bufferLength)
        if bool_range.location == 0 {
            let value = try read(length: bool_range.length)
            return .boolean(value.lowercased())
        }
        
        throw lexError("Expecting keyword")
    }
    mutating func getVariable() throws -> SPARQLToken? {
        getChar()
        let bufferLength = NSMakeRange(0, buffer.characters.count)
        let variable_range = SPARQLLexer._variableNameRegex.rangeOfFirstMatch(in: buffer, options: [], range: bufferLength)
        if variable_range.location == 0 {
            let value = try read(length: variable_range.length)
            return ._var(value)
        } else {
            throw lexError("Expecting variable name")
        }
    }
    mutating func getSingleLiteral() throws -> SPARQLToken? {
        var chars = [Character]()
        if buffer.hasPrefix("''") {
            try read(word: "'''")
            var quote_count = 0
            while true {
                if buffer.characters.count == 0 {
                    try fillBuffer()
                    if buffer.characters.count == 0 {
                        if quote_count >= 3 {
                            for _ in 0..<(quote_count-3) {
                                chars.append("'")
                            }
                            return .string3s(String(chars))
                        }
                        throw lexError("Found EOF in string literal")
                    }
                }
                
                guard let c = try peekChar() else {
                    if quote_count >= 3 {
                        for _ in 0..<(quote_count-3) {
                            chars.append("'")
                        }
                        return .string3s(String(chars))
                    }
                    throw lexError("Found EOF in string literal")
                }
                
                if c == "'" {
                    getChar()
                    quote_count += 1
                } else {
                    if quote_count > 0 {
                        if quote_count >= 3 {
                            for _ in 0..<(quote_count-3) {
                                chars.append("'")
                            }
                            return .string3s(String(chars))
                        }
                        for _ in 0..<quote_count {
                            chars.append("'")
                        }
                        quote_count = 0
                    }
                    if c == "\\" {
                        try chars.append(getEscapedChar())
                    } else {
                        chars.append(getChar())
                    }
                }
            }
        } else {
            try getChar(expecting: "'")
            while true {
                if buffer.characters.count == 0 {
                    try fillBuffer()
                    if buffer.characters.count == 0 {
                        throw lexError("Found EOF in string literal")
                    }
                }
                
                guard let c = try peekChar() else {
                    throw lexError("Found EOF in string literal")
                }
                
                if c == "'" {
                    break
                } else if c == "\\" {
                    try chars.append(getEscapedChar())
                } else {
                    let cc = getChar()
                    chars.append(cc)
                }
            }
            try getChar(expecting: "'")
            return .string1s(String(chars))
        }
    }
    
    mutating func getEscapedChar() throws -> Character {
        try getChar(expecting: "\\")
        let c = try getExpectedChar()
        switch c {
        case "r":
            return "\r"
        case "n":
            return "\n"
        case "t":
            return "\t"
        case "\\":
            return "\\"
        case "'":
            return "'"
        case "\"":
            return "\""
        case "u":
            let hex = try read(length: 4)
            guard let codepoint = Int(hex, radix: 16), let s = UnicodeScalar(codepoint) else {
                throw lexError("Invalid unicode codepoint: \(hex)")
            }
            let c = Character(s)
            return c
        case "U":
            let hex = try read(length: 8)
            guard let codepoint = Int(hex, radix: 16), let s = UnicodeScalar(codepoint) else {
                throw lexError("Invalid unicode codepoint: \(hex)")
            }
            let c = Character(s)
            return c
        default:
            throw lexError("Unexpected escape sequence \\\(c)")
        }
    }

    mutating func getPName() throws -> SPARQLToken? {
        let bufferLength = NSMakeRange(0, buffer.characters.count)
        let range = SPARQLLexer._pNameLNre.rangeOfFirstMatch(in: buffer, options: [], range: bufferLength)
        if range.location == 0 {
            var pname = try read(length: range.length)
            if pname.contains("\\") {
                var chars = [Character]()
                var i = pname.characters.makeIterator()
                while let c = i.next() {
                    if c == "\\" {
                        guard let cc = i.next() else { throw lexError("Invalid prefixedname escape") }
                        let escapable = CharacterSet(charactersIn: "_~.-!$&'()*+,;=/?#@%")
                        guard let us = UnicodeScalar("\(cc)"), escapable.contains(us) else {
                            throw lexError("Character cannot be escaped in a prefixedname: '\(cc)'")
                        }
                        chars.append(c)
                    } else {
                        chars.append(c)
                    }
                }
                pname = String(chars)
            }
            
            var values = pname.components(separatedBy: ":")
            if values.count != 2 {
                let pn = values[0]
                let ln = values.suffix(from: 1).joined(separator: ":")
                values = [pn, ln]
            }
            return .prefixname(values[0], values[1])
        } else {
            let range = SPARQLLexer._pNameNSre.rangeOfFirstMatch(in: buffer, options: [], range: bufferLength)
            if range.location == 0 {
                let pname = try read(length: range.length)
                let values = pname.components(separatedBy: ":")
                return .prefixname(values[0], values[1])
            } else {
                return nil
            }
        }
    }
    mutating func getOr() throws -> SPARQLToken? {
        if buffer.hasPrefix("||") {
            try read(word: "||")
            return .oror
        } else {
            try getChar(expecting: "|")
            return .or
        }
    }
    
    mutating func getLanguage() throws -> SPARQLToken? {
        try getChar(expecting: "@")
        let bufferLength = NSMakeRange(0, buffer.characters.count)

        let prefixOrBase_range = SPARQLLexer._prefixOrBaseRegex.rangeOfFirstMatch(in: buffer, options: [], range: bufferLength)
        let lang_range = SPARQLLexer._langRegex.rangeOfFirstMatch(in: buffer, options: [], range: bufferLength)
        if prefixOrBase_range.location == 0 {
            let value = try read(length: prefixOrBase_range.length)
            return .keyword(value.uppercased())
        } else if lang_range.location == 0 {
            let value = try read(length: lang_range.length)
            return .lang(value.lowercased())
        } else {
            throw lexError("Expecting language")
        }
    }
    
    mutating func getIRIRefOrRelational() throws -> SPARQLToken? {
        let bufferLength = NSMakeRange(0, buffer.characters.count)
        let range = SPARQLLexer._iriRegex.rangeOfFirstMatch(in: buffer, options: [], range: bufferLength)
        if range.location == 0 {
            try getChar(expecting: "<")
            var chars = [Character]()
            while true {
                guard let c = try peekChar() else { break }
                if c == "\\" {
                    try chars.append(getEscapedChar())
                } else if c == ">" {
                    break
                } else {
                    chars.append(getChar())
                }
            }
            try getChar(expecting: ">")
            
            let iri = String(chars)
            return .iri(iri)
        } else if buffer.hasPrefix("<") {
            try getChar(expecting: "<")
            guard let c = try peekChar() else { throw lexError("Expecting relational expression near EOF") }
            if c == "=" {
                getChar()
                return .le
            } else {
                return .lt
            }
        } else {
            try getChar(expecting: ">")
            guard let c = try peekChar() else { throw lexError("Expecting relational expression near EOF") }
            if c == "=" {
                getChar()
                return .ge
            } else {
                return .gt
            }
        }
    }

    mutating func getDoubleLiteral() throws -> SPARQLToken? {
        var chars = [Character]()
        if buffer.hasPrefix("\"\"\"") {
            try read(word: "\"\"\"")
            var quote_count = 0
            while true {
                if buffer.characters.count == 0 {
                    try fillBuffer()
                    if buffer.characters.count == 0 {
                        if quote_count >= 3 {
                            for _ in 0..<(quote_count-3) {
                                chars.append("\"")
                            }
                            return .string3d(String(chars))
                        }
                        throw lexError("Found EOF in string literal")
                    }
                }
                
                guard let c = try peekChar() else {
                    if quote_count >= 3 {
                        for _ in 0..<(quote_count-3) {
                            chars.append("\"")
                        }
                        return .string3d(String(chars))
                    }
                    throw lexError("Found EOF in string literal")
                }
                
                if c == "\"" {
                    getChar()
                    quote_count += 1
                } else {
                    if quote_count > 0 {
                        if quote_count >= 3 {
                            for _ in 0..<(quote_count-3) {
                                chars.append("\"")
                            }
                            return .string3d(String(chars))
                        }
                        for _ in 0..<quote_count {
                            chars.append("\"")
                        }
                        quote_count = 0
                    }
                    if c == "\\" {
                        try chars.append(getEscapedChar())
                    } else {
                        chars.append(getChar())
                    }
                }
            }
        } else {
            try getChar(expecting: "\"")
            while true {
                if buffer.characters.count == 0 {
                    try fillBuffer()
                    if buffer.characters.count == 0 {
                        throw lexError("Found EOF in string literal")
                    }
                }
                
                guard let c = try peekChar() else {
                    throw lexError("Found EOF in string literal")
                }
                
                if c == "\"" {
                    break
                } else if c == "\\" {
                    try chars.append(getEscapedChar())
                } else {
                    let cc = getChar()
                    chars.append(cc)
                }
            }
            try getChar(expecting: "\"")
            return .string1d(String(chars))
        }
    }
    
    mutating func getBnode() throws -> SPARQLToken? {
        try read(word: "_:")
        let bufferLength = NSMakeRange(0, buffer.characters.count)
        let bnode_range = SPARQLLexer._bnodeNameRegex.rangeOfFirstMatch(in: buffer, options: [], range: bufferLength)
        if bnode_range.location == 0 {
            let value = try read(length: bnode_range.length)
            return .bnode(value)
        } else {
            throw lexError("Expecting blank node name")
        }
    }
    
    mutating func getBang() throws -> SPARQLToken? {
        if buffer.hasPrefix("!=") {
            try read(word: "!=")
            return .notequals
        } else {
            try getChar(expecting: "!")
            return .bang
        }
    }

    mutating func peekChar() throws -> Character? {
        try fillBuffer()
        return buffer.characters.first
    }
   
    @discardableResult
    mutating func getChar() -> Character {
        let c = buffer.characters.first!
        buffer = buffer.substring(from: buffer.index(buffer.startIndex, offsetBy: 1))
        self.character += 1
        if c == "\n" {
            self.line += 1
            self.column = 1
        } else {
            self.column += 1
        }
        return c
    }
    
    @discardableResult
    mutating func getExpectedChar() throws -> Character {
        guard let c = buffer.characters.first else {
            throw lexError("Unexpected EOF")
        }
        buffer = buffer.substring(from: buffer.index(buffer.startIndex, offsetBy: 1))
        self.character += 1
        if c == "\n" {
            self.line += 1
            self.column = 1
        } else {
            self.column += 1
        }
        return c
    }
    
    @discardableResult
    mutating func getChar(expecting: Character) throws -> Character {
        let c = getChar()
        guard c == expecting else {
            throw lexError("Expecting '\(expecting)' but got '\(c)'")
        }
        return c
    }
    
    mutating func getCharFillBuffer() throws -> Character? {
        try fillBuffer()
        guard buffer.characters.count > 0 else { return nil }
        let c = buffer.characters.first!
        buffer = buffer.substring(from: buffer.index(buffer.startIndex, offsetBy: 1))
        self.character += 1
        if c == "\n" {
            self.line += 1
            self.column = 1
        } else {
            self.column += 1
        }
        return c
    }
    
    mutating func read(word: String) throws {
        try fillBuffer()
        if buffer.characters.count < word.characters.count {
            throw lexError("Expecting '\(word)' but not enough read-ahead data available")
        }
        
        let index = buffer.index(buffer.startIndex, offsetBy: word.characters.count)
        guard buffer.hasPrefix(word) else {
            throw lexError("Expecting '\(word)' but found '\(buffer.substring(to: index))'")
        }
        
        buffer = buffer.substring(from: index)
        self.character += UInt(word.characters.count)
        for c in word.characters {
            if c == "\n" {
                self.line += 1
                self.column = 1
            } else {
                self.column += 1
            }
        }
    }
    
    @discardableResult
    mutating func read(length: Int) throws -> String {
        try fillBuffer()
        if buffer.characters.count < length {
            throw lexError("Expecting \(length) characters but not enough read-ahead data available")
        }

        let index = buffer.index(buffer.startIndex, offsetBy: length)
        let s = buffer.substring(to: index)
        buffer = buffer.substring(from: index)
        self.character += UInt(length)
        for c in s.characters {
            if c == "\n" {
                self.line += 1
                self.column = 1
            } else {
                self.column += 1
            }
        }
        return s
    }
}

private func joinReduction(lhs : Algebra, rhs : Algebra) -> Algebra {
    if case .joinIdentity = lhs {
        return rhs
    } else {
        return .innerJoin(lhs, rhs)
    }
}

private enum UnfinishedAlgebra {
    case filter(Expression)
    case optional(Algebra)
    case minus(Algebra)
    case bind(Expression, String)
    case finished(Algebra)
    
    func finish(_ args : inout [Algebra]) -> Algebra {
        switch self {
        case .bind(let e, let name):
            let algebra : Algebra = args.reduce(.joinIdentity, joinReduction)
            args = []
            return .extend(algebra, e, name)
        case .filter(let e):
            let algebra : Algebra = args.reduce(.joinIdentity, joinReduction)
            args = []
            return .filter(algebra, e)
        case .minus(let a):
            let algebra : Algebra = args.reduce(.joinIdentity, joinReduction)
            args = []
            return .minus(algebra, a)
        case .optional(.filter(let a, let e)):
            let algebra : Algebra = args.reduce(.joinIdentity, joinReduction)
            args = []
            return .leftOuterJoin(algebra, a, e)
        case .optional(let a):
            let e : Expression = .node(.bound(Term.trueValue))
            let algebra : Algebra = args.reduce(.joinIdentity, joinReduction)
            args = []
            return .leftOuterJoin(algebra, a, e)
        case .finished(let a):
            return a
        }
    }
}

public struct SPARQLParser {
    var lexer : SPARQLLexer
    var prefixes : [String:String]
    var bnodes : [String:Term]
    var base : String?
    var tokenLookahead : SPARQLToken?
    var freshCounter = AnyIterator(sequence(first: 1) { $0 + 1 })
    
    private mutating func parseError(_ message : String) -> SPARQLParsingError {
        try? lexer.fillBuffer()
        let rest = lexer.buffer
        return SPARQLParsingError.parsingError("\(message) at \(lexer.line):\(lexer.column) near '\(rest)...'")
    }
    
    public init(lexer : SPARQLLexer, prefixes : [String:String] = [:], base : String? = nil) {
        self.lexer = lexer
        self.prefixes = prefixes
        self.base = base
        self.bnodes = [:]
    }
    
    public init?(string : String, prefixes : [String:String] = [:], base : String? = nil) {
        guard let data = string.data(using: .utf8) else { return nil }
        let stream = InputStream(data: data)
        stream.open()
        let lexer = SPARQLLexer(source: stream)
        self.init(lexer: lexer, prefixes: prefixes, base: base)
    }
    
    public init?(data : Data, prefixes : [String:String] = [:], base : String? = nil) {
        let stream = InputStream(data: data)
        stream.open()
        let lexer = SPARQLLexer(source: stream)
        self.init(lexer: lexer, prefixes: prefixes, base: base)
    }
    
    private mutating func bnode(named name : String? = nil) -> Term {
        if let name = name, let term = self.bnodes[name] {
            return term
        } else {
            guard let id = freshCounter.next() else { fatalError("No fresh variable available") }
            let b = Term(value: "b\(id)", type: .blank)
            if let name = name {
                self.bnodes[name] = b
            }
            return b
        }
    }
    
    private mutating func peekToken() -> SPARQLToken? {
        if tokenLookahead == nil {
            tokenLookahead = self.lexer.next()
        }
        return tokenLookahead
    }
    
    private mutating func peekExpectedToken() throws -> SPARQLToken {
        guard let t = peekToken() else {
            throw parseError("Unexpected EOF")
        }
        return t
    }
    
    private mutating func nextExpectedToken() throws -> SPARQLToken {
        guard let t = nextToken() else {
            throw parseError("Unexpected EOF")
        }
        return t
    }
    
    @discardableResult
    private mutating func nextToken() -> SPARQLToken? {
        if let t = tokenLookahead {
            tokenLookahead = nil
            return t
        } else {
            return self.lexer.next()
        }
    }
    
    private mutating func peek(token: SPARQLToken) throws -> Bool {
        guard let t = peekToken() else { return false }
        if t == token {
            return true
        } else {
            return false
        }
    }
    
    @discardableResult
    private mutating func attempt(token: SPARQLToken) throws -> Bool {
        if try peek(token: token) {
            nextToken()
            return true
        } else {
            return false
        }
    }
    
    private mutating func expect(token: SPARQLToken) throws {
        guard let t = nextToken() else {
            throw parseError("Expected \(token) but got EOF")
        }
        guard t == token else {
            throw parseError("Expected \(token) but got \(t)")
        }
        return
    }
        
    public mutating func parse() throws -> Algebra {
        try parsePrologue()
        
        let t = try peekExpectedToken()
        guard case .keyword(let kw) = t else { throw parseError("Expected query method not found") }
        
        var algebra : Algebra
        switch kw {
        case "SELECT":
            algebra = try parseSelectQuery()
        case "CONSTRUCT":
            algebra = try parseConstructQuery()
        case "DESCRIBE":
            algebra = try parseDescribeQuery()
        case "ASK":
            algebra = try parseAskQuery()
        default:
            throw parseError("Expected query method not found: \(kw)")
        }
        
        return algebra
    }
    

    private mutating func parsePrologue() throws {
        while true {
            if try attempt(token: .keyword("PREFIX")) {
                let pn = try nextExpectedToken()
                guard case .prefixname(let name, "") = pn else { throw parseError("Expected prefix name but found \(pn)") }
                let iri = try nextExpectedToken()
                guard case .iri(let value) = iri else { throw parseError("Expected prefix IRI but found \(iri)") }
                self.prefixes[name] = value
            } else if try attempt(token: .keyword("BASE")) {
                let iri = try nextExpectedToken()
                guard case .iri(let value) = iri else { throw parseError("Expected BASE IRI but found \(iri)") }
                self.base = value
            } else {
                break
            }
        }
    }
    
    private mutating func parseSelectQuery() throws -> Algebra {
        try expect(token: .keyword("SELECT"))
        var distinct = false
        var star = false
        var projection : [String]? = nil
        var aggregationExpressions = [String:Aggregation]()
        var projectExpressions = [(Expression, String)]()
        
        if try attempt(token: .keyword("DISTINCT")) || attempt(token: .keyword("REDUCED")) {
            distinct = true
        }
        
        if try attempt(token: .star) {
            star = true
        } else {
            projection = []
            LOOP: while true {
                let t = try peekExpectedToken()
                switch t {
                case .lparen:
                    try expect(token: .lparen)
                    var expression = try parseExpression()
                    if expression.hasAggregation {
                        expression = expression.removeAggregations(freshCounter, mapping: &aggregationExpressions)
                    }
                    try expect(token: .keyword("AS"))
                    let node = try parseVar()
                    guard case .variable(let name, binding: _) = node else {
                        throw parseError("Expecting project expressions variable but got \(node)")
                    }
                    try expect(token: .rparen)
                    projectExpressions.append((expression, name))
                    projection?.append(name)
                case ._var(let name):
                    nextToken()
                    projection?.append(name)
                default:
                    break LOOP
                }
            }
        }
        
        let dataset = try parseDatasetClauses() // TODO
        try attempt(token: .keyword("WHERE"))
        var algebra = try parseGroupGraphPattern()
        
        let values = try parseValuesClause()
        algebra = try parseSolutionModifier(algebra: algebra, distinct: distinct, projection: projection, projectExpressions: projectExpressions, aggregation: aggregationExpressions, valuesBlock: values)
        
        if star {
            // TODO: verify that the query does not perform aggregation
        }
        
        return algebra
    }
    
    private mutating func parseConstructQuery() throws -> Algebra {
        try expect(token: .keyword("CONSTRUCT"))
        var pattern = [TriplePattern]()
        var hasTemplate = false
        if try peek(token: .lbrace) {
            hasTemplate = true
            pattern = try parseConstructTemplate()
        }
        let dataset = try parseDatasetClauses() // TODO
        try expect(token: .keyword("WHERE"))
        var algebra = try parseGroupGraphPattern()
        
        if !hasTemplate {
            switch algebra {
            case .triple(let triple):
                pattern = [triple]
            case .bgp(let triples):
                pattern = triples
            default:
                throw parseError("Unexpected construct template: \(algebra)")
            }
        }
        
        algebra = try parseSolutionModifier(algebra: algebra, distinct: true, projection: nil, projectExpressions: [], aggregation: [:], valuesBlock: nil)
        return .construct(algebra, pattern)
    }

    private mutating func parseDescribeQuery() throws -> Algebra {
        try expect(token: .keyword("DESCRIBE"))
        var star = false
        var describe = [Node]()
        if try attempt(token: .star) {
            star = true
        } else {
            let node = try parseVarOrIRI()
            describe.append(node)
            
            while let t = try peekToken() {
                if t.isTerm {
                    describe.append(try parseVarOrIRI())
                } else if case ._var(_) = t {
                    describe.append(try parseVarOrIRI())
                } else {
                    break
                }
            }
        }
        
        let dataset = try parseDatasetClauses() // TODO
        try attempt(token: .keyword("WHERE"))
        let ggp : Algebra
        if try peek(token: .lbrace) {
            ggp = try parseGroupGraphPattern()
        } else {
            ggp = .joinIdentity
        }
        
        if star {
            
        }
        
        var algebra : Algebra = .describe(ggp, describe)
        algebra = try parseSolutionModifier(algebra: algebra, distinct: true, projection: nil, projectExpressions: [], aggregation: [:], valuesBlock: nil)
        
        return algebra
    }
    
    private mutating func parseConstructTemplate() throws -> [TriplePattern] {
        try expect(token: .lbrace)
        if try attempt(token: .rbrace) {
            return []
        } else {
            let tmpl = try parseTriplesBlock()
            try expect(token: .rbrace)
            return tmpl
        }
    }
    
    private mutating func parseTriplesBlock() throws -> [TriplePattern] {
        let sameSubj = try parseTriplesSameSubject()
        var t = try peekExpectedToken()
        if t == .none || t != .some(.dot) {
            return sameSubj
        } else {
            try expect(token: .dot)
            t = try peekExpectedToken()
            if t.isTermOrVar {
                let more = try parseTriplesBlock()
                return sameSubj + more
            } else {
                return sameSubj
            }
        }
    }
    
    private mutating func parseAskQuery() throws -> Algebra {
        try expect(token: .keyword("ASK"))
        let dataset = try parseDatasetClauses() // TODO
        try attempt(token: .keyword("WHERE"))
        let ggp = try parseGroupGraphPattern()
        return .ask(ggp)
    }

    private mutating func parseDatasetClauses() throws -> Any? { // TODO: figure out the return type here
        var named = [Term]()
        var unnamed = [Term]()
        while try attempt(token: .keyword("FROM")) {
            let namedIRI = try attempt(token: .keyword("NAMED"))
            let iri = try parseIRI()
            if namedIRI {
                named.append(iri)
            } else {
                unnamed.append(iri)
            }
        }
        return nil;
        fatalError("implement \(named) \(unnamed)")
    }

    private mutating func parseGroupGraphPattern() throws -> Algebra {
        try expect(token: .lbrace)
        var algebra : Algebra
        
        if try peek(token: .keyword("SELECT")) {
            algebra = try parseSubSelect()
        } else {
            algebra = try parseGroupGraphPatternSub()
        }

        try expect(token: .rbrace)
        return algebra
    }

    private mutating func parseSubSelect() throws -> Algebra {
        try expect(token: .keyword("SELECT"))

        var distinct = false
        var star = false
        var projection : [String]? = nil
        var aggregationExpressions = [String:Aggregation]()
        var projectExpressions = [(Expression, String)]()
        
        if try attempt(token: .keyword("DISTINCT")) || attempt(token: .keyword("REDUCED")) {
            distinct = true
        }

        if try attempt(token: .star) {
            star = true
        } else {
            projection = []
            LOOP: while true {
                let t = try peekExpectedToken()
                switch t {
                case .lparen:
                    try expect(token: .lparen)
                    var expression = try parseExpression()
                    if expression.hasAggregation {
                        expression = expression.removeAggregations(freshCounter, mapping: &aggregationExpressions)
                    }
                    try expect(token: .keyword("AS"))
                    let node = try parseVar()
                    guard case .variable(let name, binding: _) = node else {
                        throw parseError("Expecting project expressions variable but got \(node)")
                    }
                    try expect(token: .rparen)
                    projectExpressions.append((expression, name))
                    projection?.append(name)
                case ._var(let name):
                    nextToken()
                    projection?.append(name)
                default:
                    break LOOP
                }
            }
        }
        
        try attempt(token: .keyword("WHERE"))
        var algebra = try parseGroupGraphPattern()

        let values = try parseValuesClause()
        
        algebra = try parseSolutionModifier(algebra: algebra, distinct: distinct, projection: projection, projectExpressions: projectExpressions, aggregation: aggregationExpressions, valuesBlock: values)

        if star {
            // TODO: verify that the query does not perform aggregation
        }
        
        return algebra
    }
    
    private mutating func parseGroupCondition(_ algebra : inout Algebra) throws -> Node? {
        var node : Node
        if try attempt(token: .lparen) {
            let expr = try parseExpression()
            if try attempt(token: .keyword("AS")) {
                node = try parseVar()
                guard case .variable(let name, binding: _) = node else {
                    throw parseError("Expecting GROUP variable name but got \(node)")
                }
                algebra = .extend(algebra, expr, name)
            } else {
                guard let c = freshCounter.next() else { fatalError("No fresh variable available") }
                let name = ".group-\(c)"
                algebra = .extend(algebra, expr, name)
                node = .variable(name, binding: true)
            }
            try expect(token: .rparen)
            return node
        } else {
            guard let t = try peekToken() else { return nil }
            if case ._var(_) = t {
                node = try parseVar()
                guard case .variable(_) = node else {
                    throw parseError("Expecting GROUP variable but got \(node)")
                }
                return node
            } else {
                let expr = try parseBuiltInCall()
                guard let c = freshCounter.next() else { fatalError("No fresh variable available") }
                let name = ".group-\(c)"
                algebra = .extend(algebra, expr, name)
                node = .variable(name, binding: true)
                return node
            }
        }
    }

    private mutating func parseOrderCondition() throws -> Algebra.SortComparator? {
        var ascending = true
        var forceBrackettedExpression = false
        if try attempt(token: .keyword("ASC")) {
            forceBrackettedExpression = true
        } else if try attempt(token: .keyword("DESC")) {
            forceBrackettedExpression = true
            ascending = false
        }
        
        var expr : Expression
        guard let t = peekToken() else { return nil }
        if try forceBrackettedExpression || peek(token: .lparen) {
            expr = try parseBrackettedExpression()
        } else if case ._var(_) = t {
            expr = try .node(parseVarOrTerm())
        } else if let e = try? parseConstraint() {
            expr = e
        } else {
            return nil
        }
        // TODO: need to return nil when there are no more order conditions without consuming tokens in parseConstraint()
        
        return (ascending, expr)
    }
    
    private mutating func parseConstraint() throws -> Expression {
        if try peek(token: .lparen) {
            return try parseBrackettedExpression()
        } else {
            let t = try peekExpectedToken()
            switch t {
            case .iri(_), .prefixname(_, _):
                return try parseFunctionCall()
            default:
                let expr = try parseBuiltInCall()
                return expr
            }
        }
    }
    
    private mutating func parseFunctionCall() throws -> Expression {
        let expr = try parseIRIOrFunction()
        guard case .call(_) = expr else {
            throw parseError("Expecting function call but got \(expr)")
        }
        return expr
    }

    private mutating func parseSolutionModifier(algebra a: Algebra, distinct : Bool, projection : [String]?, projectExpressions: [(Expression, String)], aggregation : [String:Aggregation], valuesBlock : Algebra?) throws -> Algebra {
        var algebra = a
        let aggregations = aggregation.map { ($0.1, $0.0) }
        if try attempt(token: .keyword("GROUP")) {
            try expect(token: .keyword("BY"))
            var groups = [Expression]()
            while let n = try? parseGroupCondition(&algebra), let node = n {
                groups.append(.node(node))
            }
            algebra = .aggregate(algebra, groups, aggregations)
        } else if (aggregations.count > 0) { // if algebra contains aggregation
            algebra = .aggregate(algebra, [], aggregations)
        }

        algebra = projectExpressions.reduce(algebra) { .extend($0, $1.0, $1.1) }

        if try attempt(token: .keyword("HAVING")) {
            let e = try parseConstraint()
            algebra = .filter(algebra, e)
        }

        if let values = valuesBlock {
            algebra = .innerJoin(algebra, values)
        }
        
        var sortConditions : [Algebra.SortComparator] = []
        if try attempt(token: .keyword("ORDER")) {
            try expect(token: .keyword("BY"))
            while true {
                guard let c = try parseOrderCondition() else { break }
                sortConditions.append(c)
            }
        }
        
        if let projection = projection {
            // TODO: verify that we're not projecting a non-grouped variable when using aggregation
            // TODO: verify that we're not projecting a variable more than once
            // TODO: add projection for aggregate variables
            algebra = .project(algebra, projection)
        }
        
        if sortConditions.count > 0 {
            algebra = .order(algebra, sortConditions)
        }

        
        if try attempt(token: .keyword("LIMIT")) {
            let limit = try parseInteger()
            if try attempt(token: .keyword("OFFSET")) {
                let offset = try parseInteger()
                algebra = .slice(algebra, offset, limit)
            } else {
                algebra = .slice(algebra, nil, limit)
            }
        } else if try attempt(token: .keyword("OFFSET")) {
            let offset = try parseInteger()
            if try attempt(token: .keyword("LIMIT")) {
                let limit = try parseInteger()
                algebra = .slice(algebra, offset, limit)
            } else {
                algebra = .slice(algebra, offset, nil)
            }
        }
        
        /**
    
    t   = [self peekNextNonCommentToken];
    if (t && t.type == KEYWORD) {
        id<GTWTerm> limit, offset;
        if ([t.value isEqualToString: @"LIMIT"]) {
            [self parseExpectedTokenOfType:KEYWORD withValue:@"LIMIT" withErrors:errors];
            ASSERT_EMPTY(errors);
            
            t   = [self parseExpectedTokenOfType:INTEGER withErrors:errors];
            ASSERT_EMPTY(errors);
            limit    = (GTWLiteral*) [self tokenAsTerm:t withErrors:errors];
            
            t   = [self parseOptionalTokenOfType:KEYWORD withValue:@"OFFSET"];
            if (t) {
                t   = [self parseExpectedTokenOfType:INTEGER withErrors:errors];
                ASSERT_EMPTY(errors);
                offset    = (GTWLiteral*) [self tokenAsTerm:t withErrors:errors];
            }
        } else if ([t.value isEqualToString: @"OFFSET"]) {
            [self parseExpectedTokenOfType:KEYWORD withValue:@"OFFSET" withErrors:errors];
            ASSERT_EMPTY(errors);

            t   = [self parseExpectedTokenOfType:INTEGER withErrors:errors];
            ASSERT_EMPTY(errors);
            offset    = (GTWLiteral*) [self tokenAsTerm:t withErrors:errors];
            
            t   = [self parseOptionalTokenOfType:KEYWORD withValue:@"LIMIT"];
            if (t) {
                t   = [self parseExpectedTokenOfType:INTEGER withErrors:errors];
                ASSERT_EMPTY(errors);
                limit    = (GTWLiteral*) [self tokenAsTerm:t withErrors:errors];
            }
        }

        if (distinct) {
            algebra = [[SPKTree alloc] initWithType:kAlgebraDistinct arguments:@[algebra]];
        }
        
        if (limit || offset) {
            if (!limit)
                limit   = [[GTWLiteral alloc] initWithValue:@"-1" datatype:@"http://www.w3.org/2001/XMLSchema#integer"];
            if (!offset)
                offset   = [[GTWLiteral alloc] initWithValue:@"0" datatype:@"http://www.w3.org/2001/XMLSchema#integer"];
            algebra   = [[SPKTree alloc] initWithType:kAlgebraSlice arguments:@[
                          algebra,
                          [[SPKTree alloc] initLeafWithType:kTreeNode value: offset],
                          [[SPKTree alloc] initLeafWithType:kTreeNode value: limit],
                      ]];
        }
    } else {
        if (distinct) {
            algebra = [[SPKTree alloc] initWithType:kAlgebraDistinct arguments:@[algebra]];
        }
    }
    
    return algebra;

 **/
        return algebra
    }
    
    private mutating func parseValuesClause() throws -> Algebra? {
        if try attempt(token: .keyword("VALUES")) {
            return try parseDataBlock()
        }
        return nil
    }
    
//    private mutating func parseQuads() throws -> [QuadPattern] { fatalError() }
//    private mutating func triplesByParsingTriplesTemplate() throws -> [TriplePattern] { fatalError() }

    private mutating func parseGroupGraphPatternSub() throws -> Algebra {
        var args = [Algebra]()
        var ok = true
        var allowTriplesBlock = true
        while ok {
            let t = try peekExpectedToken()
            if t.isTermOrVar {
                if !allowTriplesBlock {
                    break
                }
                let algebra = try triplesByParsingTriplesBlock()
                allowTriplesBlock = false
                args.append(contentsOf: algebra)
            } else {
                switch t {
                case .lparen, .lbracket, ._var, .iri(_), .anon, .prefixname(_, _), .bnode(_), .string1d(_), .string1s(_), .string3d(_), .string3s(_), .boolean(_), .double(_), .decimal(_), .integer(_):
                    if !allowTriplesBlock {
                        break
                    }
                    let algebra = try triplesByParsingTriplesBlock()
                    allowTriplesBlock = false
                    args.append(contentsOf: algebra)
                case .lbrace, .keyword(_):
                    guard let unfinished = try treeByParsingGraphPatternNotTriples() else {
                        throw parseError("Could not parse GraphPatternNotTriples in GroupGraphPatternSub (near \(t))")
                    }
                    
                    // TODO: this isn't right. it needs to be a post-processing step to allow filters to be applied late, but things like BIND and OPTIONAL to close immediately
                    let algebra = unfinished.finish(&args)
                    allowTriplesBlock = true
                    args.append(algebra)
                    try attempt(token: .dot)
                default:
                    ok = false
                }
            }
        }
        
        let reordered = args // TODO: try reorderTrees(args)
        // TODO: try checkForSharedBlanksInPatterns(reordered)
        // TODO: the algebra should allow n-ary groups, not just binary joins
        
        return reordered.reduce(.joinIdentity, joinReduction)
    }
    
    private mutating func parseBind() throws -> UnfinishedAlgebra {
        try expect(token: .keyword("BIND"))
        try expect(token: .lparen)
        let expr = try parseNonAggregatingExpression()
        try expect(token: .keyword("AS"))
        let node = try parseVar()
        try expect(token: .rparen)
        guard case .variable(let name, binding: _) = node else {
            throw parseError("Expecting BIND variable but got \(node)")
        }
        return .bind(expr, name)
    }
    
    private mutating func parseInlineData() throws -> Algebra {
        try expect(token: .keyword("VALUES"))
        return try parseDataBlock()
    }

    //[62]  	DataBlock	  ::=  	InlineDataOneVar | InlineDataFull
    //[63]  	InlineDataOneVar	  ::=  	Var '{' DataBlockValue* '}'
    //[64]  	InlineDataFull	  ::=  	( NIL | '(' Var* ')' ) '{' ( '(' DataBlockValue* ')' | NIL )* '}'
    private mutating func parseDataBlock() throws -> Algebra {
        var t = try peekExpectedToken()
        if case ._var(_) = t {
            let node = try parseVar()
            guard case .variable(let name, binding: _) = node else {
                throw parseError("Expecting variable but got \(node)")
            }
            try expect(token: .lbrace)
            let values = try parseDataBlockValues()
            try expect(token: .rbrace)
            
            let results = values.flatMap { $0 }.map {
                TermResult(bindings: [name: $0])
            }
            return .table([node], results)
        } else {
            var vars = [Node]()
            var names = [String]()
            if case ._nil = t {
                try expect(token: t)
            } else {
                try expect(token: .lparen)
                t = try peekExpectedToken()
                while case ._var(let name) = t {
                    try expect(token: t)
                    vars.append(.variable(name, binding: true))
                    names.append(name)
                    t = try peekExpectedToken()
                }
                try expect(token: .rparen)
            }
            try expect(token: .lbrace)
            var results = [TermResult]()
            
            while try peek(token: .lparen) || peek(token: ._nil) {
                var bindings = [String:Term]()
                if try attempt(token: .lparen) {
                    let values = try parseDataBlockValues()
                    try expect(token: .rparen)
                    for (name, term) in zip(names, values) {
                        if let term = term {
                            bindings[name] = term
                        }
                    }
                } else {
                    try expect(token: ._nil)
                }
                let result = TermResult(bindings: bindings)
                results.append(result)
            }
            try expect(token: .rbrace)
            return .table(vars, results)
       }
    }
    
    //[65]  	DataBlockValue	  ::=  	iri |	RDFLiteral |	NumericLiteral |	BooleanLiteral |	'UNDEF'
    private mutating func parseDataBlockValues() throws -> [Term?] {
        var t = try peekExpectedToken()
        var values = [Term?]()
        while t == .keyword("UNDEF") || t.isTerm {
            if try attempt(token: .keyword("UNDEF")) {
                values.append(nil)
            } else {
                t = try nextExpectedToken()
                let node = try tokenAsTerm(t)
                guard case .bound(let term) = node else {
                    throw parseError("Expecting term but got \(node)")
                }
                values.append(term)
            }
            t = try peekExpectedToken()
        }
        return values
    }
    
    private mutating func parseTriplesSameSubject() throws -> [TriplePattern] {
        let t = try peekExpectedToken()
        if t.isTermOrVar {
            let subj = try parseVarOrTerm()
            return try parsePropertyListNotEmpty(for: subj)
        } else if t == .lparen || t == .lbracket {
            let (subj, triples) = try parseTriplesNodeAsNode()
            let more = try parsePropertyList(subject: subj)
            return triples + more
        } else {
            return []
        }
    }
    
    private mutating func parsePropertyList(subject: Node) throws -> [TriplePattern] {
        let t = try peekExpectedToken()
        guard t.isVerb else { return [] }
        return try parsePropertyListNotEmpty(for: subject)
    }
    
    private mutating func parsePropertyListNotEmpty(for subject: Node) throws -> [TriplePattern] {
        let algebras = try parsePropertyListPathNotEmpty(for: subject)
        var triples = [TriplePattern]()
        for algebra in algebras {
            switch simplifyPath(algebra) {
            case .triple(let tp):
                triples.append(tp)
            case .bgp(let tps):
                triples.append(contentsOf: tps)
            default:
                throw parseError("Expected triple pattern but found \(algebra)")
            }
        }
        return triples
    }

    private mutating func triplesArrayByParsingTriplesSameSubjectPath() throws -> [Algebra] {
        let t = try peekExpectedToken()
        if t.isTermOrVar {
            let subject = try parseVarOrTerm()
            let propertyObjectTriples = try parsePropertyListPathNotEmpty(for: subject)
            // TODO: should propertyObjectTriples be able to be nil here? It could in the original code...
            return propertyObjectTriples
        } else {
            var triples = [Algebra]()
            let (subject, nodeTriples) = try parseTriplesNodePathAsNode()
            triples.append(contentsOf: nodeTriples)
            let propertyObjectTriples = try parsePropertyListPath(for: subject)
            triples.append(contentsOf: propertyObjectTriples)
            return triples
        }
    }

    private mutating func parseExpressionList() throws -> [Expression] {
        let t = try peekExpectedToken()
        if case ._nil = t {
            try expect(token: t)
            return []
        } else {
            try expect(token: .lparen)
            let expr = try parseExpression()
            var exprs = [expr]
            while try attempt(token: .comma) {
                let expr = try parseExpression()
                exprs.append(expr)
            }
            try expect(token: .rparen)
            return exprs
        }
    }
    
    private mutating func parsePropertyListPath(for subject: Node) throws -> [Algebra] {
        let t = try peekExpectedToken()
        guard t.isVerb else { return [] }
        return try parsePropertyListPathNotEmpty(for: subject)
    }
    
    private mutating func parsePropertyListPathNotEmpty(for subject: Node) throws -> [Algebra] {
        var t = try peekExpectedToken()
        var verb : PropertyPath? = nil
        var varpred : Node? = nil
        if case ._var(_) = t {
            varpred = try parseVerbSimple()
        } else {
            verb = try parseVerbPath()
        }
        
        let (objectList, triples) = try parseObjectListPathAsNodes()
        var propertyObjects = triples
        for o in objectList {
            if let verb = verb {
                propertyObjects.append(.path(subject, verb, o))
            } else {
                propertyObjects.append(.triple(TriplePattern(subject: subject, predicate: varpred!, object: o)))
            }
        }
        
        LOOP: while try attempt(token: .semicolon) {
            t = try peekExpectedToken()
            var verb : PropertyPath? = nil
            var varpred : Node? = nil
            switch t {
            case ._var(_):
                varpred = try parseVerbSimple()
            case .keyword("A"), .lparen, .hat, .bang, .iri(_), .prefixname(_, _):
                verb = try parseVerbPath()
            default:
                break LOOP
            }
            
            let (objectList, triples) = try parseObjectListPathAsNodes()
            propertyObjects.append(contentsOf: triples)
            for o in objectList {
                if let verb = verb {
                    propertyObjects.append(.path(subject, verb, o))
                } else {
                    propertyObjects.append(.triple(TriplePattern(subject: subject, predicate: varpred!, object: o)))
                }
            }
        }
        
        return propertyObjects
    }

    private mutating func parseVerbPath() throws -> PropertyPath {
        return try parsePath()
    }
    
    private mutating func parseVerbSimple() throws -> Node {
        return try parseVar()
    }
    
    private mutating func parseObjectListPathAsNodes() throws -> ([Node], [Algebra]) {
        var (node, triples) = try parseObjectPathAsNode()
        var objects = [node]
        
        while try attempt(token: .comma) {
            let (node, moretriples) = try parseObjectPathAsNode()
            triples.append(contentsOf: moretriples)
            objects.append(node)
        }
        
        return (objects, triples)
    }

    private mutating func parsePath() throws -> PropertyPath {
        return try parsePathAlternative()
    }
    
    private mutating func parsePathAlternative() throws -> PropertyPath {
        var path = try parsePathSequence()
        while try attempt(token: .or) {
            let alt = try parsePathSequence()
            path = .alt(path, alt)
        }
        return path
    }
    
    private mutating func parsePathSequence() throws -> PropertyPath {
        var path = try parsePathEltOrInverse()
        while try attempt(token: .slash) {
            let seq = try parsePathEltOrInverse()
            path = .seq(path, seq)
        }
        return path
    }
    
    private mutating func parsePathElt() throws -> PropertyPath {
        let elt = try parsePathPrimary()
        if try attempt(token: .question) {
            return .zeroOrOne(elt)
        } else if try attempt(token: .star) {
            return .star(elt)
        } else if try attempt(token: .plus) {
            return .plus(elt)
        } else {
            return elt
        }
    }

    private mutating func parsePathEltOrInverse() throws -> PropertyPath {
        if try attempt(token: .hat) {
            let path = try parsePathElt()
            return .inv(path)
        } else {
            return try parsePathElt()
        }
    }
    
    private mutating func parsePathPrimary() throws -> PropertyPath {
        if try attempt(token: .lparen) {
            let path = try parsePath()
            try expect(token: .rparen)
            return path
        } else if try attempt(token: .keyword("A")) {
            let term = Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", type: .iri)
            return .link(term)
        } else if try attempt(token: .bang) {
            return try parsePathNegatedPropertySet()
        } else {
            let term = try parseIRI()
            return .link(term)
        }
    }
    private mutating func parsePathNegatedPropertySet() throws -> PropertyPath {
        if try attempt(token: .lparen) {
            let path = try parsePathOneInPropertySet()
            guard case .link(let iri) = path else {
                throw parseError("Expected NPS IRI but found \(path)")
            }
            var iris = [iri]
            while try attempt(token: .or) {
                let rhs = try parsePathOneInPropertySet()
                guard case .link(let iri) = rhs else {
                    throw parseError("Expected NPS IRI but found \(path)")
                }
                iris.append(iri)
            }
            try expect(token: .rparen)
            return .nps(iris)
        } else {
            let path = try parsePathOneInPropertySet()
            guard case .link(let iri) = path else {
                throw parseError("Expected NPS IRI but found \(path)")
            }
            return .nps([iri])
        }
    }
    
    private mutating func parsePathOneInPropertySet() throws -> PropertyPath {
        let t = try peekExpectedToken()
        if t == .hat {
            switch t {
            case .keyword("A"):
                return .inv(.link(Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", type: .iri)))
            default:
                let iri = try parseIRI()
                return .inv(.link(iri))
            }
        } else if case .keyword("A") = t{
            return .link(Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", type: .iri))
        } else {
            let iri = try parseIRI()
            return .link(iri)
        }
     /**
 
             SPKSPARQLToken* t   = [self peekNextNonCommentToken];
    if (t.type == HAT) {
        [self nextNonCommentToken];
        t   = [self peekNextNonCommentToken];
        if (t.type == KEYWORD && [t.value isEqualToString: @"A"]) {
            [self nextNonCommentToken];
            id<GTWTerm> term    = [[GTWIRI alloc] initWithValue:@"http://www.w3.org/1999/02/22-rdf-syntax-ns#type"];
            id<SPKTree> path    = [[SPKTree alloc] initWithType:kTreeNode value: term arguments:nil];
            return [[SPKTree alloc] initWithType:kPathInverse arguments:@[path]];
        } else {
            id<SPKTree> path    = [self parseIRIWithErrors: errors];
            return [[SPKTree alloc] initWithType:kPathInverse arguments:@[path]];
        }
    } else if (t.type == KEYWORD && [t.value isEqualToString: @"A"]) {
        [self nextNonCommentToken];
        id<GTWTerm> term    = [[GTWIRI alloc] initWithValue:@"http://www.w3.org/1999/02/22-rdf-syntax-ns#type"];
        return [[SPKTree alloc] initWithType:kTreeNode value: term arguments:nil];
    } else if (t.type == NIL) {
        return [self errorMessage:@"Expecting IRI but found NIL" withErrors:errors];
    } else {
        return [self parseIRIWithErrors: errors];
    }

 
 **/
    }

    private mutating func parseObjectPathAsNode() throws -> (Node, [Algebra]) {
        return try parseGraphNodePathAsNode()
    }

    private mutating func parseTriplesNodeAsNode() throws -> (Node, [TriplePattern]) {
        if try peek(token: .lparen) {
            return try triplesByParsingCollectionAsNode()
        } else {
            return try parseBlankNodePropertyListAsNode()
        }
    }

    private mutating func parseBlankNodePropertyListAsNode() throws -> (Node, [TriplePattern]) {
        let (node, patterns) = try parseBlankNodePropertyListPathAsNode()
        var triples = [TriplePattern]()
        for p in patterns {
            switch simplifyPath(p) {
            case .triple(let t):
                triples.append(t)
            case .bgp(let ts):
                triples.append(contentsOf: ts)
            default:
                throw parseError("Unexpected template triple: \(p)")
            }
        }
        return (node, triples)
    }
    
    private mutating func parseTriplesNodePathAsNode() throws -> (Node, [Algebra]) {
        if try peek(token: .lparen) {
            return try triplesByParsingCollectionPathAsNode()
        } else {
            return try parseBlankNodePropertyListPathAsNode()
        }
    }
    
    private mutating func parseBlankNodePropertyListPathAsNode() throws -> (Node, [Algebra]) {
        try expect(token: .lbracket)
        let node : Node = .bound(bnode())
        let path = try parsePropertyListPathNotEmpty(for: node)
        try expect(token: .rbracket)
        return (node, path)
    }
    
    private mutating func triplesByParsingCollectionAsNode() throws -> (Node, [TriplePattern]) {
        let (node, patterns) = try triplesByParsingCollectionPathAsNode()
        var triples = [TriplePattern]()
        for p in patterns {
            switch p {
            case .triple(let t):
                triples.append(t)
            case .bgp(let ts):
                triples.append(contentsOf: ts)
            default:
                throw parseError("Unexpected template triple: \(p)")
            }
        }
        return (node, triples)
    }
    
    private mutating func triplesByParsingCollectionPathAsNode() throws -> (Node, [Algebra]) {
        try expect(token: .lparen)
        let (node, graphNodePath) = try parseGraphNodePathAsNode()
        var triples = graphNodePath
        var nodes = [node]
        while try !peek(token: .rparen) {
            let (node, graphNodePath) = try parseGraphNodePathAsNode()
            triples.append(contentsOf: graphNodePath)
            nodes.append(node)
        }
        try expect(token: .rparen)
        
        let bnode = self.bnode()
        var list = bnode
        
        let rdffirst = Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#first", type: .iri)
        let rdfrest = Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest", type: .iri)
        let rdfnil = Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#nil", type: .iri)
        
        var patterns = [TriplePattern]()
        if nodes.count > 0 {
            for (i, o) in nodes.enumerated() {
                let triple = TriplePattern(subject: .bound(list), predicate: .bound(rdffirst), object: o)
                patterns.append(triple)
                if i == (nodes.count-1) {
                    let triple = TriplePattern(subject: .bound(list), predicate: .bound(rdfrest), object: .bound(rdfnil))
                    patterns.append(triple)
                } else {
                    let newlist = self.bnode()
                    let triple = TriplePattern(subject: .bound(list), predicate: .bound(rdfrest), object: .bound(newlist))
                    patterns.append(triple)
                    list = newlist
                }
            }
            triples.append(.bgp(patterns))
        } else {
            let triple = TriplePattern(subject: .bound(list), predicate: .bound(rdffirst), object: .bound(rdfnil))
            triples.append(.bgp([triple]))
        }
        return (.bound(bnode), triples)
    }

//    private mutating func parseGraphNodeAsNode() throws -> (Node, [Algebra]) { fatalError() }

    private mutating func parseGraphNodePathAsNode() throws -> (Node, [Algebra]) {
        let t = try peekExpectedToken()
        if t.isTermOrVar {
            let node = try parseVarOrTerm()
            return (node, [])
        } else {
            return try parseTriplesNodePathAsNode()
        }
    }
    
    private mutating func parseVarOrTerm() throws -> Node {
        let t = try nextExpectedToken()
        return try tokenAsTerm(t)
    }
    
    private mutating func parseVarOrIRI() throws -> Node {
        let node = try parseVarOrTerm()
        if case .variable(_) = node {
        } else if case .bound(let term) = node, term.type == .iri {
        } else {
            throw parseError("Expected variable but found \(node)")
        }
        return node
    }
    
    private mutating func parseVar() throws -> Node {
        let t = try nextExpectedToken()
        let node = try tokenAsTerm(t)
        guard case .variable(_) = node else {
            throw parseError("Expected variable but found \(node)")
        }
        return node
    }
    
    private mutating func parseNonAggregatingExpression() throws -> Expression {
        let expr = try parseExpression()
        guard !expr.hasAggregation else {
            throw parseError("Unexpected aggregation in BIND expression")
        }
        return expr
    }
    
    private mutating func parseExpression() throws -> Expression {
        return try parseConditionalOrExpression()
    }
    
    private mutating func parseConditionalOrExpression() throws -> Expression {
        var expr = try parseConditionalAndExpression()
        while try attempt(token: .oror) {
            let rhs = try parseConditionalAndExpression()
            expr = .or(expr, rhs)
        }
        return expr
    }
    
    private mutating func parseConditionalAndExpression() throws -> Expression {
        var expr = try parseValueLogical()
        while try attempt(token: .andand) {
            let rhs = try parseValueLogical()
            expr = .and(expr, rhs)
        }
        return expr
    }

    private mutating func parseValueLogical() throws -> Expression {
        return try parseRelationalExpression()
    }
    
    private mutating func parseRelationalExpression() throws -> Expression {
        let expr = try parseNumericExpression()
        let t = try peekExpectedToken()
        switch t {
        case .equals, .notequals, .lt, .gt, .le, .ge:
            nextToken()
            let rhs = try parseNumericExpression()
            if t == .equals {
                return .eq(expr, rhs)
            } else if t == .notequals {
                return .ne(expr, rhs)
            } else if t == .lt {
                return .lt(expr, rhs)
            } else if t == .gt {
                return .gt(expr, rhs)
            } else if t == .le {
                return .le(expr, rhs)
            } else {
                return .ge(expr, rhs)
            }
        case .keyword("IN"):
            nextToken()
            let exprs = try parseExpressionList()
            return .valuein(expr, exprs)
        case .keyword("NOT"):
            nextToken()
            try expect(token: .keyword("IN"))
            let exprs = try parseExpressionList()
            return .not(.valuein(expr, exprs))
        default:
            return expr
        }
        /**
            id<SPKTree> expr    = [self parseNumericExpressionWithErrors:errors];
    SPKSPARQLToken* t   = [self peekNextNonCommentToken];
    if (t && (t.type == EQUALS || t.type == NOTEQUALS || t.type == LT || t.type == GT || t.type == LE || t.type == GE)) {
        [self nextNonCommentToken];
        id<SPKTree> rhs  = [self parseNumericExpressionWithErrors:errors];
        ASSERT_EMPTY(errors);
        SPKTreeType type;
        switch (t.type) {
            case EQUALS:
                type    = kExprEq;
                break;
            case NOTEQUALS:
                type    = kExprNeq;
                break;
            case LT:
                type    = kExprLt;
                break;
            case GT:
                type    = kExprGt;
                break;
            case LE:
                type    = kExprLe;
                break;
            case GE:
                type    = kExprGe;
                break;
            default:
                return nil;
        }
        if (!(expr && rhs)) {
            return [self errorMessage:@"Failed to parse relational expression" withErrors:errors];
        }
        expr    = [[SPKTree alloc] initWithType:type arguments:@[expr, rhs]];
    } else if (t && t.type == KEYWORD && [t.value isEqualToString: @"IN"]) {
        [self nextNonCommentToken];
        id<SPKTree> list    = [self parseExpressionListWithErrors: errors];
        ASSERT_EMPTY(errors);
        return [[SPKTree alloc] initWithType:kExprIn arguments:@[expr, list]];
    } else if (t && t.type == KEYWORD && [t.value isEqualToString: @"NOT"]) {
        [self nextNonCommentToken];
        [self parseExpectedTokenOfType:KEYWORD withValue:@"IN" withErrors:errors];
        ASSERT_EMPTY(errors);
        id<SPKTree> list    = [self parseExpressionListWithErrors: errors];
        ASSERT_EMPTY(errors);
        return [[SPKTree alloc] initWithType:kExprNotIn arguments:@[expr, list]];
    }
    return expr;

 **/
    }
    
    
    private mutating func parseNumericExpression() throws -> Expression {
        return try parseAdditiveExpression()
    }
    
    private mutating func parseAdditiveExpression() throws -> Expression {
        var expr = try parseMultiplicativeExpression()
        var t = try peekExpectedToken()
        while t == .plus || t == .minus {
            try expect(token: t)
            let rhs = try parseMultiplicativeExpression()
            if t == .plus {
                expr = .add(expr, rhs)
            } else {
                expr = .sub(expr, rhs)
            }
            t = try peekExpectedToken()
        }
        return expr
    }
    
    private mutating func parseMultiplicativeExpression() throws -> Expression {
        var expr = try parseUnaryExpression()
        var t = try peekExpectedToken()
        while t == .star || t == .slash {
            try expect(token: t)
            let rhs = try parseUnaryExpression()
            if t == .star {
                expr = .mul(expr, rhs)
            } else {
                expr = .div(expr, rhs)
            }
            t = try peekExpectedToken()
        }
        return expr
    }
    
    private mutating func parseUnaryExpression() throws -> Expression {
        if try attempt(token: .bang) {
            let expr = try parsePrimaryExpression()
            return .not(expr)
        } else if try attempt(token: .plus) {
            let expr = try parsePrimaryExpression()
            return expr
        } else if try attempt(token: .minus) {
            let expr = try parsePrimaryExpression()
            if case .node(.bound(let term)) = expr, term.isNumeric, let value = term.numeric {
                let neg = .integer(0) - value
                return .node(.bound(neg.term))
            }
            return .neg(expr)
        } else {
            let expr = try parsePrimaryExpression()
            return expr
        }
    }
    
    private mutating func parsePrimaryExpression() throws -> Expression {
        if try peek(token: .lparen) {
            return try parseBrackettedExpression()
        } else {
            let t = try peekExpectedToken()
            switch t {
            case .iri(_), .prefixname(_, _):
                return try parseIRIOrFunction()
            case ._nil, .anon, .bnode(_):
                throw parseError("Expected PrimaryExpression term (IRI, Literal, or Var) but found \(t)")
            case _ where t.isTermOrVar:
                return try .node(parseVarOrTerm())
            default:
                let expr = try parseBuiltInCall()
                return expr
            }
        }
    }
    
    private mutating func parseIRIOrFunction() throws -> Expression {
        let iri = try parseIRI()
        if try attempt(token: ._nil) {
            return .call(iri.value, [])
        } else if try attempt(token: .lparen) {
            if try attempt(token: .rparen) {
                return .call(iri.value, [])
            } else {
                try attempt(token: .keyword("DISTINCT"))
                let expr = try parseExpression()
                var args = [expr]
                while try attempt(token: .comma) {
                    let expr = try parseExpression()
                    args.append(expr)
                }
                try expect(token: .rparen)
                return .call(iri.value, args)
            }
        } else {
            return .node(.bound(iri))
        }
    }
    
    private mutating func parseBrackettedExpression() throws -> Expression {
        try expect(token: .lparen)
        let expr = try parseExpression()
        try expect(token: .rparen)
        return expr
    }
    
    private mutating func parseBuiltInCall() throws -> Expression {
        let t = try peekExpectedToken()
        switch t {
        case .keyword(let kw) where SPARQLLexer._aggregates.contains(kw):
            let agg = try parseAggregate()
            return .aggregate(agg)
        case .keyword("NOT"):
            try expect(token: t)
            try expect(token: .keyword("EXISTS"))
            let ggp = try parseGroupGraphPattern()
            fatalError("implement NOT EXISTS \(ggp)")
        case .keyword("EXISTS"):
            try expect(token: t)
            let ggp = try parseGroupGraphPattern()
            fatalError("implement EXISTS \(ggp)")
        case .keyword(let kw) where SPARQLLexer._functions.contains(kw):
            try expect(token: t)
            var args = [Expression]()
            if try !attempt(token: ._nil) {
                try expect(token: .lparen)
                let expr = try parseExpression()
                args.append(expr)
                while try attempt(token: .comma) {
                    let expr = try parseExpression()
                    args.append(expr)
                }
                try expect(token: .rparen)
            }
            return .call(kw, args)
        default:
            throw parseError("Expected built-in function call but found \(t)")
        }
    }
    
    private mutating func parseAggregate() throws -> Aggregation {
        let t = try nextExpectedToken()
        guard case .keyword(let name) = t else {
            throw parseError("Expected aggregate name but found \(t)")
        }
        
        switch name {
        case "COUNT":
            try expect(token: .lparen)
            let distinct = try attempt(token: .keyword("DISTINCT"))
            let agg : Aggregation
            if try attempt(token: .star) {
                agg = .countAll(distinct)
            } else {
                let expr = try parseNonAggregatingExpression()
                agg = .count(expr, distinct)
            }
            try expect(token: .rparen)
            return agg
        case "SUM":
            try expect(token: .lparen)
            let distinct = try attempt(token: .keyword("DISTINCT"))
            let expr = try parseNonAggregatingExpression()
            let agg : Aggregation = .sum(expr, distinct)
            try expect(token: .rparen)
            return agg
        case "MIN":
            try expect(token: .lparen)
            let _ = try attempt(token: .keyword("DISTINCT"))
            let expr = try parseNonAggregatingExpression()
            let agg : Aggregation = .min(expr)
            try expect(token: .rparen)
            return agg
        case "MAX":
            try expect(token: .lparen)
            let _ = try attempt(token: .keyword("DISTINCT"))
            let expr = try parseNonAggregatingExpression()
            let agg : Aggregation = .max(expr)
            try expect(token: .rparen)
            return agg
        case "AVG":
            try expect(token: .lparen)
            let distinct = try attempt(token: .keyword("DISTINCT"))
            let expr = try parseNonAggregatingExpression()
            let agg : Aggregation = .avg(expr, distinct)
            try expect(token: .rparen)
            return agg
        case "SAMPLE":
            try expect(token: .lparen)
            let distinct = try attempt(token: .keyword("DISTINCT"))
            let expr = try parseNonAggregatingExpression()
            let agg : Aggregation = .sample(expr)
            try expect(token: .rparen)
            return agg
        case "GROUP_CONCAT":
            try expect(token: .lparen)
            let distinct = try attempt(token: .keyword("DISTINCT"))
            let expr = try parseNonAggregatingExpression()
            
            var sep = " "
            if try attempt(token: .semicolon) {
                try expect(token: .keyword("SEPARATOR"))
                try expect(token: .equals)
                let t = try nextExpectedToken()
                let node = try tokenAsTerm(t)
                guard case .bound(let term) = node, case .datatype("http://www.w3.org/2001/XMLSchema#string") = term.type else {
                    throw parseError("Expected GROUP_CONCAT SEPARATOR but found \(node)")
                }
                sep = term.value
            }
            let agg : Aggregation = .groupConcat(expr, sep, distinct)
            try expect(token: .rparen)
            return agg
        default:
            throw parseError("Unrecognized aggregate name '\(name)'")
        }
    /**
 
     SPKSPARQLToken* t   = [self parseExpectedTokenOfType:KEYWORD withErrors:errors];
    ASSERT_EMPTY(errors);
    } else if ([t.value isEqualToString: @"GROUP_CONCAT"]) {
        [self parseExpectedTokenOfType:LPAREN withErrors:errors];
        ASSERT_EMPTY(errors);
        SPKSPARQLToken* d   = [self parseOptionalTokenOfType:KEYWORD withValue:@"DISTINCT"];
        id<SPKTree> expr    = [self parseExpressionWithErrors:errors];
        ASSERT_EMPTY(errors);
        
        SPKSPARQLToken* sc  = [self parseOptionalTokenOfType:SEMICOLON];
        NSString* separator = @" ";
        if (sc) {
            [self parseExpectedTokenOfType:KEYWORD withValue:@"SEPARATOR" withErrors:errors];
            ASSERT_EMPTY(errors);
            [self parseExpectedTokenOfType:EQUALS withErrors:errors];
            ASSERT_EMPTY(errors);
            SPKSPARQLToken* t   = [self nextNonCommentToken];
            id<GTWTerm> str     = [self tokenAsTerm:t withErrors:errors];
            ASSERT_EMPTY(errors);
            
            separator   = str.value;
        }
        id<SPKTree> agg     = [[SPKTree alloc] initWithType:kExprGroupConcat value: @[@(d ? YES : NO), separator] arguments:@[expr]];
        [self parseExpectedTokenOfType:RPAREN withErrors:errors];
        ASSERT_EMPTY(errors);
        [self addSeenAggregate:agg];
        return agg;
    }

 **/
    
    
    }
    
    private mutating func parseIRI() throws -> Term {
        let t = try nextExpectedToken()
        let node = try tokenAsTerm(t)
        guard case .bound(let term) = node, case .iri(_) = term.type else {
            throw parseError("Bad path IRI: \(node)")
        }
        return term
    }

    private mutating func triplesByParsingTriplesBlock() throws -> [Algebra] {
        var sameSubj = try triplesArrayByParsingTriplesSameSubjectPath()
        let t = peekToken()
        if t == .none || t != .some(.dot) {
            
        } else {
            try expect(token: .dot)
            let t = try peekExpectedToken()
            if t.isTermOrVar {
                let more = try triplesByParsingTriplesBlock()
                sameSubj += more
            }
        }
        
        return Array(sameSubj.map { simplifyPath($0) })
    }
    
    private func simplifyPath(_ algebra : Algebra) -> Algebra {
        guard case .path(let s, .link(let iri), let o) = algebra else { return algebra }
        let node : Node = .bound(iri)
        let triple = TriplePattern(subject: s, predicate: node, object: o)
        return .triple(triple)
    }
    
    private mutating func treeByParsingGraphPatternNotTriples() throws -> UnfinishedAlgebra? {
        let t = try peekExpectedToken()
        if case .keyword("OPTIONAL") = t {
            try expect(token: t)
            let ggp = try parseGroupGraphPattern()
            return .optional(ggp)
        } else if case .keyword("MINUS") = t {
            try expect(token: t)
            let ggp = try parseGroupGraphPattern()
            return .minus(ggp)
        } else if case .keyword("GRAPH") = t {
            try expect(token: t)
            let node = try parseVarOrIRI()
            let ggp = try parseGroupGraphPattern()
            return .finished(.namedGraph(ggp, node))
        } else if case.keyword("SERVICE") = t {
            try expect(token: t)
            let silent = try attempt(token: .keyword("SILENT"))
            let node = try parseVarOrIRI()
            let ggp = try parseGroupGraphPattern()
            return .finished(.service(node, ggp, silent))
        } else if case .keyword("FILTER") = t {
            try expect(token: t)
            let expression = try parseConstraint()
            return .filter(expression)
        } else if case .keyword("VALUES") = t {
            let data = try parseInlineData()
            return .finished(data)
        } else if case .keyword("BIND") = t {
            return try parseBind()
        } else if case .keyword(_) = t {
            throw parseError("Expecting KEYWORD but got \(t)")
        } else if case .lbrace = t {
            var ggp = try parseGroupGraphPattern()
            while try attempt(token: .keyword("UNION")) {
                let rhs = try parseGroupGraphPattern()
                ggp = .union(ggp, rhs)
            }
            return .finished(ggp)
        } else {
            let t = try peekExpectedToken()
            throw parseError("Expecting group graph pattern but got \(t)")
        }
    }
    
    private mutating func tokenAsTerm(_ t : SPARQLToken) throws -> Node {
        switch t {
        case ._nil:
            return .bound(Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#nil", type: .iri))
        case ._var(let name):
            return .variable(name, binding: true)
        case .iri(let value):
            var iri = value
            if let base = base {
                guard let b = URL(string: base), let i = URL(string: value, relativeTo: b) else {
                    throw parseError("Failed to resolve IRI against base IRI")
                }
                iri = i.absoluteString
            }
            return .bound(Term(value: iri, type: .iri))
        case .prefixname(let pn, let ln):
            guard let ns = self.prefixes[pn] else {
                throw parseError("Use of undeclared prefix '\(pn)'")
            }
            var iri = ns + ln
            if let base = base {
                guard let b = URL(string: base), let i = URL(string: iri, relativeTo: b) else {
                    throw parseError("Failed to resolve prefixed name against base IRI")
                }
                iri = i.absoluteString
            }
            return .bound(Term(value: iri, type: .iri))
        case .anon:
            return .bound(bnode())
        case .keyword("A"):
            return .bound(Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", type: .iri))
        case .boolean(let value):
            return .bound(Term(value: value, type: .datatype("http://www.w3.org/2001/XMLSchema#boolean")))
        case .decimal(let value):
            return .bound(Term(value: value, type: .datatype("http://www.w3.org/2001/XMLSchema#decimal")))
        case .double(let value):
            return .bound(Term(value: value, type: .datatype("http://www.w3.org/2001/XMLSchema#double")))
        case .integer(let value):
            return .bound(Term(value: value, type: .datatype("http://www.w3.org/2001/XMLSchema#integer")))
        case .bnode(let name):
            let term = bnode(named: name)
            return .bound(term)
        case .string1d(let value), .string1s(let value), .string3d(let value), .string3s(let value):
            if try attempt(token: .hathat) {
                let t = try nextExpectedToken()
                let dt = try tokenAsTerm(t)
                guard case .bound(let dtterm) = dt else {
                    throw parseError("Expecting datatype but found '\(dt)'")
                }
                guard case .iri = dtterm.type else {
                    throw parseError("Expecting datatype IRI but found '\(dtterm)'")
                }
                return .bound(Term(value: value, type: .datatype(dtterm.value)))
            } else {
                let t = try peekExpectedToken()
                if case .lang(let lang) = t {
                    return .bound(Term(value: value, type: .language(lang)))
                }
            }
            return .bound(Term(value: value, type: .datatype("http://www.w3.org/2001/XMLSchema#string")))
        case .plus:
            let t = try nextExpectedToken()
            return try tokenAsTerm(t)
        case .minus:
            let t = try nextExpectedToken()
            let node = try tokenAsTerm(t)
            guard case .bound(let term) = node, term.isNumeric, let value = term.numeric else {
                throw parseError("Cannot negate \(node)")
            }
            let neg = .integer(0) - value
            return .bound(neg.term)
        default:
            throw parseError("Expecting term but got \(t)")
        }
    }
    
    mutating private func parseInteger() throws -> Int {
        let l = try nextExpectedToken()
        let t = try tokenAsTerm(l)
        guard case .bound(let term) = t, case .datatype("http://www.w3.org/2001/XMLSchema#integer") = term.type else {
            throw parseError("Expecting integer but found \(t)")
        }
        guard let limit = Int(term.value) else {
            throw parseError("Failed to parse integer value from \(term)")
        }
        return limit
    }
}
