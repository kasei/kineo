//
//  Util.swift
//  PageDatabase
//
//  Created by Gregory Todd Williams on 5/26/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation

public func warn(_ items: String...) {
    for string in items {
        fputs(string, stderr)
        fputs("\n", stderr)
    }
}

public protocol LineReadable {
    func lines() -> AnyIterator<String>
}

extension String : LineReadable {
    public func lines() -> AnyIterator<String> {
        let lines = self.components(separatedBy: "\n")
        return AnyIterator(lines.makeIterator())
    }
}

public struct FileReader : LineReadable {
    let filename : String
    public init(filename: String) {
        self.filename = filename
    }
    
    public func makeIterator() -> AnyIterator<CChar> {
        let fd = open(filename, O_RDONLY)
        let blockSize = 256
        var buffer : [CChar] = [CChar](repeating: 0, count: 1+blockSize)
        var bufferBytes = 0
        var currentIndex = 0
        return AnyIterator { () -> CChar? in
            if currentIndex >= bufferBytes {
                bufferBytes = 0
                buffer.withUnsafeMutableBufferPointer { (b) -> () in
                    if let base = b.baseAddress {
                        memset(base, 0, blockSize+1)
                        bufferBytes = read(fd, base, blockSize)
                    }
                }
                //                print("read \(bufferBytes) bytes")
                if bufferBytes <= 0 {
                    return nil
                }
                currentIndex = 0
            }
            let i = currentIndex
            currentIndex += 1
            return buffer[i]
        }
    }
    
    public func lines() -> AnyIterator<String> {
        let chargen = makeIterator()
        var chars = [CChar]()
        return AnyIterator { () -> String? in
            repeat {
                if let char = chargen.next() {
                    if char == 10 {
                        chars.append(0)
                        if let line = chars.withUnsafeMutableBufferPointer({ (b) -> String? in if case .some(let ptr) = b.baseAddress { return String(validatingUTF8: ptr) } else { return nil } }) {
                            chars = []
                            return line
                        } else {
                            chars = []
                        }
                    } else {
                        chars.append(char)
                    }
                } else {
                    return nil
                }
            } while true
        }
    }
}


struct PeekableIterator<T : IteratorProtocol> : IteratorProtocol {
    typealias Element = T.Element
    
    private var generator : T
    private var bufferedElement : Element?
    internal init(generator _generator: T) {
        generator = _generator
        bufferedElement = generator.next()
    }
    
    mutating internal func next() -> Element? {
        let r = bufferedElement
        bufferedElement = generator.next()
        return r
    }
    
    internal func peek() -> Element? {
        return bufferedElement
    }

    mutating func dropWhile(filter : @noescape (Element) -> Bool) {
        while bufferedElement != nil {
            if !filter(bufferedElement!) {
                break
            }
        }
    }
}

extension String {
    static func fromCString(cs: UnsafePointer<CChar>, length : Int) -> String? {
        let size = length+1
        let b = UnsafeMutablePointer<CChar>.allocate(capacity: size)
        defer {
            b.deinitialize(count: size)
            b.deallocate(capacity: size)
        }
        b[length] = CChar(0)
        memcpy(b, cs, length)
        let s = String(validatingUTF8: b)
        return s
    }
}

extension UInt64 {
    func varint() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 9)
        var offset = 8
        var length = 0
        
        if self == 0 {
            return [0]
        }
        
        var v = self
        if v > 0x00ffffffffffffff {
            // 9-byte
            bytes[offset]	= UInt8(v % 256)
            offset -= 1
            v >>= 8
            length += 1
        }
        
        while v > 0 {
            var b : UInt8 = UInt8(v & 0x7f)
            v	>>= 7
            if offset < 8 {
                b	|= 0x80
            }
            bytes[offset]	= b
            offset -= 1
            length += 1
        }
        
        let x = bytes.suffix(length)
        return Array(x)
    }
    
    init(varintBytes bytes: [UInt8]) {
        var value : UInt64  = 0
        var b : UInt8       = 0
        for i in 0..<8 {
            b = bytes[i]
            let m = b & 0x7f
            value		= (value << 7) + UInt64(m)
            if (b & 0x80) == 0 {
                break
            }
        }
        if (b & 0x80) > 0 {
            value	= (value << 8) + UInt64(bytes[8])
        }
        self.init(value)
    }
}

public protocol BufferSerializable {
    var serializedSize : Int { get }
    func serialize(to buffer: inout UnsafeMutablePointer<Void>, mediator: RWMediator?, maximumSize: Int) throws
    static func deserialize(from buffer : inout UnsafePointer<Void>, mediator: RMediator?) throws -> Self
}

extension BufferSerializable {
    func serialize(to buffer: inout UnsafeMutablePointer<Void>) throws {
        try serialize(to: &buffer, mediator: nil, maximumSize: Int.max)
    }
}

public struct Empty {
    public init() {}
}
extension Empty : Comparable {}
public func <(lhs: Empty, rhs: Empty) -> Bool { return false }

extension Empty : CustomStringConvertible {
    public var description : String { return "()" }
}
extension Empty : BufferSerializable {
    public var serializedSize : Int { return 0 }
    public func serialize(to buffer : inout UnsafeMutablePointer<Void>, mediator: RWMediator?, maximumSize: Int) throws {}
    public static func deserialize(from buffer : inout UnsafePointer<Void>, mediator : RMediator?=nil) throws -> Empty {
        return Empty()
    }

    public static func ==(lhs: Empty, rhs: Empty) -> Bool { return true }
}


extension Int : BufferSerializable {
    public var serializedSize : Int { return sizeof(Int64.self) }
    public func serialize(to buffer : inout UnsafeMutablePointer<Void>, mediator: RWMediator?, maximumSize: Int) throws {
        if serializedSize > maximumSize { throw DatabaseError.OverflowError("Cannot serialize Int in available space") }
        UnsafeMutablePointer<Int64>(buffer).pointee   = Int64(self).bigEndian
        buffer += serializedSize
    }
    
    public static func deserialize(from buffer : inout UnsafePointer<Void>, mediator : RMediator?=nil) throws -> Int {
        let i = Int(Int64(bigEndian: UnsafePointer<Int64>(buffer).pointee))
        buffer += sizeof(Int64.self)
        return i
    }
}

extension UInt64 : BufferSerializable {
    public var serializedSize : Int { return sizeof(UInt64.self) }
    public func serialize(to buffer : inout UnsafeMutablePointer<Void>, mediator: RWMediator?, maximumSize: Int) throws {
        if serializedSize > maximumSize { throw DatabaseError.OverflowError("Cannot serialize UInt64 in available space") }
        UnsafeMutablePointer<UInt64>(buffer).pointee   = self.bigEndian
        buffer += serializedSize
    }
    
    public static func deserialize(from buffer : inout UnsafePointer<Void>, mediator : RMediator?=nil) throws -> UInt64 {
        let u = UInt64(bigEndian: UnsafePointer<UInt64>(buffer).pointee)
        buffer += sizeof(UInt64.self)
        return u
    }
}

extension UInt32 : BufferSerializable {
    public var serializedSize : Int { return sizeof(UInt32.self) }
    public func serialize(to buffer : inout UnsafeMutablePointer<Void>, mediator: RWMediator?, maximumSize: Int) throws {
        if serializedSize > maximumSize { throw DatabaseError.OverflowError("Cannot serialize UInt32 in available space") }
        UnsafeMutablePointer<UInt32>(buffer).pointee   = self.bigEndian
        buffer += serializedSize
    }
    
    public static func deserialize(from buffer : inout UnsafePointer<Void>, mediator : RMediator?=nil) throws -> UInt32 {
        let u = UInt32(bigEndian: UnsafePointer<UInt32>(buffer).pointee)
        buffer += sizeof(UInt32.self)
        return u
    }
}

extension UInt16 : BufferSerializable {
    public var serializedSize : Int { return sizeof(UInt16.self) }
    public func serialize(to buffer : inout UnsafeMutablePointer<Void>, mediator: RWMediator?, maximumSize: Int) throws {
        if serializedSize > maximumSize { throw DatabaseError.OverflowError("Cannot serialize UInt16 in available space") }
        UnsafeMutablePointer<UInt16>(buffer).pointee   = self.bigEndian
        buffer += serializedSize
    }
    
    public static func deserialize(from buffer : inout UnsafePointer<Void>, mediator : RMediator?=nil) throws -> UInt16 {
        let u = UInt16(bigEndian: UnsafePointer<UInt16>(buffer).pointee)
        buffer += sizeof(UInt16.self)
        return u
    }
}

extension UInt8 : BufferSerializable {
    public var serializedSize : Int { return sizeof(UInt8.self) }
    public func serialize(to buffer : inout UnsafeMutablePointer<Void>, mediator: RWMediator?, maximumSize: Int) throws {
        if serializedSize > maximumSize { throw DatabaseError.OverflowError("Cannot serialize UInt8 in available space") }
        UnsafeMutablePointer<UInt8>(buffer).pointee   = self
        buffer += serializedSize
    }
    
    public static func deserialize(from buffer : inout UnsafePointer<Void>, mediator : RMediator?=nil) throws -> UInt8 {
        let u = UnsafePointer<UInt8>(buffer).pointee
        buffer += sizeof(UInt8.self)
        return u
    }
}

public enum StringBuffer : BufferSerializable {
    case inline(String)
    case large(String, PageId)
    
    public var serializedSize : Int {
        switch (self) {
        case .inline(let s):
            let utf8 = s.utf8
            let stringLength = UInt32(utf8.count + 1)
            let stringSize = stringLength.serializedSize + s.utf8.count + 1
            return 1 + stringSize
        case .large(let s, let p):
            let utf8 = s.utf8
            let stringLength = UInt32(utf8.count + 1)
            let stringSize = stringLength.serializedSize + s.utf8.count + 1
            return 1 + p.serializedSize + stringSize
        }
    }
    public func serialize(to buffer : inout UnsafeMutablePointer<Void>, mediator: RWMediator?, maximumSize: Int) throws {
        switch self {
        case .inline(let s):
            UnsafeMutablePointer<UInt8>(buffer).pointee = 1
            buffer += 1
            let utf8 = s.utf8
            let length = UInt32(utf8.count + 1)
            try length.serialize(to: &buffer)
            
            // pack string into buffer
            let chars = utf8.map { UInt8($0) }
            for c in chars {
                UnsafeMutablePointer<UInt8>(buffer).pointee = c
                buffer += sizeof(UInt8.self)
            }
            UnsafeMutablePointer<UInt8>(buffer).pointee = 0
            buffer += sizeof(UInt8.self)
        case .large(let s, let p):
            UnsafeMutablePointer<UInt8>(buffer).pointee = 2
            buffer += 1
            try p.serialize(to: &buffer)
            let utf8 = s.utf8
            let length = UInt32(utf8.count + 1)
            try length.serialize(to: &buffer)
            
            // pack string into buffer
            let chars = utf8.map { UInt8($0) }
            for c in chars {
                UnsafeMutablePointer<UInt8>(buffer).pointee = c
                buffer += sizeof(UInt8.self)
            }
            UnsafeMutablePointer<UInt8>(buffer).pointee = 0
            buffer += sizeof(UInt8.self)
        }
    }
    
    public static func deserialize(from buffer : inout UnsafePointer<Void>, mediator : RMediator?=nil) throws -> StringBuffer {
        let type = UnsafeMutablePointer<UInt8>(buffer).pointee
        buffer += 1
        
        switch type {
        case 1:
            let length = try UInt32.deserialize(from: &buffer)
            if let string = String(validatingUTF8: UnsafePointer<CChar>(buffer)) {
                assert(length == UInt32(string.utf8.count+1))
                buffer += Int(length)
                return .inline(string)
            } else {
                warn("*** Failed to deserialize UTF8 string")
                throw DatabaseError.SerializationError("Failed to deserialize UTF8 string")
            }
        case 2:
            let pid = try PageId.deserialize(from: &buffer)
            let length = try UInt32.deserialize(from: &buffer)
            if let string = String(validatingUTF8: UnsafePointer<CChar>(buffer)) {
                assert(length == UInt32(string.utf8.count+1))
                buffer += Int(length)
                return .large(string, pid)
            } else {
                warn("*** Failed to deserialize UTF8 string")
                throw DatabaseError.SerializationError("Failed to deserialize UTF8 string")
            }
        default:
            throw DatabaseError.DataError("Unrecognized string buffer type \(type)")
        }
    }
}

extension String : BufferSerializable {
    public var serializedSize : Int {
        let b = StringBuffer.inline(self)
        return b.serializedSize
    }
    
    public func serialize(to buffer: inout UnsafeMutablePointer<Void>, mediator: RWMediator?, maximumSize: Int) throws {
        let b = StringBuffer.inline(self)
        if b.serializedSize < maximumSize {
            try b.serialize(to: &buffer)
        } else {
//            let bytes = self.utf8
//            let end = bytes.endIndex
//            let pos = bytes.startIndex.advanceBy(maximumSize-1)
//            let head = bytes.prefix(through: pos)
//            let tail = bytes.suffix(from: pos)
            
//            guard let mediator = mediator else { throw DatabaseError.OverflowError("Cannot serialize String in available space") }
            fatalError("*** Unimplemented: page-spilling for strings")
        }
    }

    public static func deserialize(from buffer : inout UnsafePointer<Void>, mediator : RMediator?=nil) throws -> String {
        let b = try StringBuffer.deserialize(from: &buffer)
        guard case .inline(let s) = b else { throw DatabaseError.SerializationError("Failed to deserialize inline string buffer") }
        return s
    }
}

public func getCurrentDateSeconds() -> UInt64 {
    var startTime : time_t
    startTime = time(nil)
    return UInt64(startTime)
}

public func getDateString(seconds : UInt64) -> String {
    var tt = time_t(Int(seconds))
    let tm = gmtime(&tt)
    let size = 33
    let b = UnsafeMutablePointer<Int8>.allocate(capacity: size)
    defer {
        b.deinitialize(count: size)
        b.deallocate(capacity: size)
    }
    strftime(b, 32, "%Y-%m-%dT%H:%M:%SZ", tm)
    let date = String(validatingUTF8: b) ?? ""
    return date
}

internal func serializationCode<T : BufferSerializable>(from type: T.Type) -> UInt16 {
    if type == UInt8.self {
        return 0x0001
    } else if type == UInt16.self {
        return 0x0002
    } else if type == UInt32.self {
        return 0x0003
    } else if type == UInt64.self || type == Int.self {
        return 0x0004
    } else if type == String.self {
        return 0x0010
    } else if type == Empty.self {
        return 0x0020
    } else if type == Term.self {
        return 0x0040
    } else if type == IDQuad<UInt64>.self {
        return 0x0100 + serializationCode(from: UInt64.self)
    } else {
        warn("*** unrecognized type for serialization: \(type)")
        return 0xffff
    }
}

let termIntType = UInt32(0x00400004)
let intTermType = UInt32(0x00040040)
let intIntType = UInt32(0x00040004)
let intEmptyType = UInt32(0x00040020)
let quadIntType = UInt32(0x01040004)

internal func serializationCode<T : BufferSerializable, U : BufferSerializable>(_ key : T.Type, _ value : U.Type) -> UInt32 {
    let t = UInt32(serializationCode(from: key))
    let u = UInt32(serializationCode(from: value))
    return (t << 16) | u
}

internal func pairName(_ code : UInt32) -> String {
    let rhs = UInt16(code & 0xffff)
    let lhs = UInt16(code >> 16)
    return "\(typeName(lhs)) -> \(typeName(rhs))"
}

internal func typeName(_ code : UInt16) -> String {
    switch code {
    case 0x0001:
        return "UInt8"
    case 0x0002:
        return "UInt16"
    case 0x0003:
        return "UInt32"
    case 0x0004:
        return "UInt64"
    case 0x0010:
        return "String"
    case 0x0020:
        return "Empty"
    case 0x0040:
        return "Term"
    case 0x0104:
        return "IDQuad<UInt64>"
    default:
        print(String(format: "unknown type code %08x", code))
        return String(format: "(unknown %x)", code)
    }
}

public extension Array {
    public mutating func insertSorted(_ element : Element, isOrderedBefore: @noescape (Element, Element) -> Bool) {
        if count == 0 {
            self.append(element)
        } else {
            // TODO: improve this using a binary search and an insert
            var index = count
            for i in 0..<count {
                if isOrderedBefore(element, self[i]) {
                    index = i
                    break
                }
            }
            self.insert(element, at: index)
        }
    }
}

public func myprintf(_ format: String, _ arguments: CVarArg...) {
    _ = withVaList(arguments) {
        vprintf(format, $0)
    }
}
