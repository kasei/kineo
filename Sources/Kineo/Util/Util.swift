//
//  Util.swift
//  PageDatabase
//
//  Created by Gregory Todd Williams on 5/26/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import CoreFoundation
import SPARQLSyntax

public func _sizeof<T>(_ value: T.Type) -> Int {
    return MemoryLayout<T>.size
}

public func warn(_ items: String...) {
    for string in items {
        fputs(string, stderr)
        fputs("\n", stderr)
    }
}

public func callStackCallers(_ maxLength: Int, _ skip: Int = 0) -> String {
    let symbols = Thread.callStackSymbols.map { (v) -> String in
        let i = v.index(v.startIndex, offsetBy: 59)
        let f = String(v[i...])
        let j = f.index(of: " ") ?? f.endIndex
        let name = String(f[..<j])
        return name
    }
    let callers = symbols.dropFirst(skip).prefix(maxLength).joined(separator: ", ")
    return callers
}

public protocol LineReadable {
    func lines() -> AnyIterator<String>
}

extension String: LineReadable {
    public func lines() -> AnyIterator<String> {
        let lines = self.components(separatedBy: "\n")
        return AnyIterator(lines.makeIterator())
    }
}

public struct FileReader: LineReadable {
    let filename: String
    public init(filename: String) {
        self.filename = filename
    }

    public func makeIterator() -> AnyIterator<CChar> {
        let fd = open(filename, O_RDONLY)
        let blockSize = 256
        var buffer: [CChar] = [CChar](repeating: 0, count: 1+blockSize)
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
                    if chars.count > 0 {
                        chars.append(0)
                        if let line = chars.withUnsafeMutableBufferPointer({ (b) -> String? in if case .some(let ptr) = b.baseAddress { return String(validatingUTF8: ptr) } else { return nil } }) {
                            chars = []
                            return line
                        }
                    }
                    return nil
                }
            } while true
        }
    }
}

public struct PeekableIterator<T: IteratorProtocol> : IteratorProtocol {
    public typealias Element = T.Element
    private var generator: T
    private var bufferedElement: Element?
    public  init(generator: T) {
        self.generator = generator
        bufferedElement = self.generator.next()
    }

    public mutating func next() -> Element? {
        let r = bufferedElement
        bufferedElement = generator.next()
        return r
    }

    public func peek() -> Element? {
        return bufferedElement
    }

    mutating func dropWhile(filter: (Element) -> Bool) {
        while bufferedElement != nil {
            if !filter(bufferedElement!) {
                break
            }
            _ = next()
        }
    }

    mutating public func elements() -> [Element] {
        var elements = [Element]()
        while let e = next() {
            elements.append(e)
        }
        return elements
    }
}

//extension String {
//    static func fromCString(cs: UnsafePointer<CChar>, length: Int) -> String? {
//        let size = length+1
//        let b = UnsafeMutablePointer<CChar>.allocate(capacity: size)
//        defer {
//            b.deinitialize(count: size)
//            b.deallocate(capacity: size)
//        }
//        b[length] = CChar(0)
//        memcpy(b, cs, length)
//        let s = String(validatingUTF8: b)
//        return s
//    }
//}

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
            var b: UInt8 = UInt8(v & 0x7f)
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
        var value: UInt64  = 0
        var b: UInt8       = 0
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
    var serializedSize: Int { get }
    func serialize(to buffer: inout UnsafeMutableRawPointer, mediator: PageRWMediator?, maximumSize: Int) throws
    static func deserialize(from buffer: inout UnsafeRawPointer, mediator: PageRMediator?) throws -> Self
}

extension BufferSerializable {
    func serialize(to buffer: inout UnsafeMutableRawPointer) throws {
        try serialize(to: &buffer, mediator: nil, maximumSize: Int.max)
    }
}

public struct Empty {
    public init() {}
}
extension Empty: Comparable {}
public func < (lhs: Empty, rhs: Empty) -> Bool { return false }

extension Empty: CustomStringConvertible {
    public var description: String { return "()" }
}
extension Empty: BufferSerializable {
    public var serializedSize: Int { return 0 }
    public func serialize(to buffer: inout UnsafeMutableRawPointer, mediator: PageRWMediator?, maximumSize: Int) throws {}
    public static func deserialize(from buffer: inout UnsafeRawPointer, mediator: PageRMediator?=nil) throws -> Empty {
        return Empty()
    }

    public static func == (lhs: Empty, rhs: Empty) -> Bool { return true }
}

extension Int: BufferSerializable {
    public var serializedSize: Int { return _sizeof(Int64.self) }
    public func serialize(to buffer: inout UnsafeMutableRawPointer, mediator: PageRWMediator?, maximumSize: Int) throws {
        if serializedSize > maximumSize { throw DatabaseError.OverflowError("Cannot serialize Int in available space") }
        buffer.assumingMemoryBound(to: Int64.self).pointee = Int64(self).bigEndian
        buffer += serializedSize
    }

    public static func deserialize(from buffer: inout UnsafeRawPointer, mediator: PageRMediator?=nil) throws -> Int {
        let i = Int(Int64(bigEndian: buffer.assumingMemoryBound(to: Int64.self).pointee))
        buffer += _sizeof(Int64.self)
        return i
    }
}

extension Int {
    public init(zigzag n: Int) {
        self.init((n >> 1) ^ (-(n & 1)))
    }
    
    public var zigzag : Int {
        return (self << 1) ^ (self >> 31)
    }
}

extension UInt64: BufferSerializable {
    public var serializedSize: Int { return _sizeof(UInt64.self) }
    public func serialize(to buffer: inout UnsafeMutableRawPointer, mediator: PageRWMediator?, maximumSize: Int) throws {
        if serializedSize > maximumSize { throw DatabaseError.OverflowError("Cannot serialize UInt64 in available space") }
        buffer.assumingMemoryBound(to: UInt64.self).pointee = self.bigEndian
        buffer += serializedSize
    }

    public static func deserialize(from buffer: inout UnsafeRawPointer, mediator: PageRMediator?=nil) throws -> UInt64 {
        let u = UInt64(bigEndian: buffer.assumingMemoryBound(to: UInt64.self).pointee)
        buffer += _sizeof(UInt64.self)
        return u
    }
}

extension UInt32: BufferSerializable {
    public var serializedSize: Int { return _sizeof(UInt32.self) }
    public func serialize(to buffer: inout UnsafeMutableRawPointer, mediator: PageRWMediator?, maximumSize: Int) throws {
        if serializedSize > maximumSize { throw DatabaseError.OverflowError("Cannot serialize UInt32 in available space") }
        buffer.assumingMemoryBound(to: UInt32.self).pointee = self.bigEndian
        buffer += serializedSize
    }

    public static func deserialize(from buffer: inout UnsafeRawPointer, mediator: PageRMediator?=nil) throws -> UInt32 {
        let u = UInt32(bigEndian: buffer.assumingMemoryBound(to: UInt32.self).pointee)
        buffer += _sizeof(UInt32.self)
        return u
    }
}

extension UInt16: BufferSerializable {
    public var serializedSize: Int { return _sizeof(UInt16.self) }
    public func serialize(to buffer: inout UnsafeMutableRawPointer, mediator: PageRWMediator?, maximumSize: Int) throws {
        if serializedSize > maximumSize { throw DatabaseError.OverflowError("Cannot serialize UInt16 in available space") }
        buffer.assumingMemoryBound(to: UInt16.self).pointee = self.bigEndian
        buffer += serializedSize
    }

    public static func deserialize(from buffer: inout UnsafeRawPointer, mediator: PageRMediator?=nil) throws -> UInt16 {
        let u = UInt16(bigEndian: buffer.assumingMemoryBound(to: UInt16.self).pointee)
        buffer += _sizeof(UInt16.self)
        return u
    }
}

extension UInt8: BufferSerializable {
    public var serializedSize: Int { return _sizeof(UInt8.self) }
    public func serialize(to buffer: inout UnsafeMutableRawPointer, mediator: PageRWMediator?, maximumSize: Int) throws {
        if serializedSize > maximumSize { throw DatabaseError.OverflowError("Cannot serialize UInt8 in available space") }
        buffer.assumingMemoryBound(to: UInt8.self).pointee = self
        buffer += serializedSize
    }

    public static func deserialize(from buffer: inout UnsafeRawPointer, mediator: PageRMediator?=nil) throws -> UInt8 {
        let u = buffer.assumingMemoryBound(to: UInt8.self).pointee
        buffer += _sizeof(UInt8.self)
        return u
    }
}

public enum StringBuffer: BufferSerializable {
    case inline(String)
    case large(String, PageId)

    public var serializedSize: Int {
        switch self {
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
    public func serialize(to buffer: inout UnsafeMutableRawPointer, mediator: PageRWMediator?, maximumSize: Int) throws {
        switch self {
        case .inline(let s):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 1
            buffer += 1
            let utf8 = s.utf8
            let length = UInt32(utf8.count + 1)
            try length.serialize(to: &buffer)

            // pack string into buffer
            let chars = utf8.map { UInt8($0) }
            for c in chars {
                buffer.assumingMemoryBound(to: UInt8.self).pointee = c
                buffer += _sizeof(UInt8.self)
            }
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 0
            buffer += _sizeof(UInt8.self)
        case .large(let s, let p):
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 2
            buffer += 1
            try p.serialize(to: &buffer)
            let utf8 = s.utf8
            let length = UInt32(utf8.count + 1)
            try length.serialize(to: &buffer)

            // pack string into buffer
            let chars = utf8.map { UInt8($0) }
            for c in chars {
                buffer.assumingMemoryBound(to: UInt8.self).pointee = c
                buffer += _sizeof(UInt8.self)
            }
            buffer.assumingMemoryBound(to: UInt8.self).pointee = 0
            buffer += _sizeof(UInt8.self)
        }
    }

    public static func deserialize(from buffer: inout UnsafeRawPointer, mediator: PageRMediator?=nil) throws -> StringBuffer {
        let type = buffer.assumingMemoryBound(to: UInt8.self).pointee
        buffer += 1

        switch type {
        case 1:
            let length = try UInt32.deserialize(from: &buffer)
            if let string = String(validatingUTF8: buffer.assumingMemoryBound(to: CChar.self)) {
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
            if let string = String(validatingUTF8: buffer.assumingMemoryBound(to: CChar.self)) {
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

extension String: BufferSerializable {
    public var serializedSize: Int {
        let b = StringBuffer.inline(self)
        return b.serializedSize
    }

    public func serialize(to buffer: inout UnsafeMutableRawPointer, mediator: PageRWMediator?, maximumSize: Int) throws {
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

    public static func deserialize(from buffer: inout UnsafeRawPointer, mediator: PageRMediator?=nil) throws -> String {
        let b = try StringBuffer.deserialize(from: &buffer)
        guard case .inline(let s) = b else { throw DatabaseError.SerializationError("Failed to deserialize inline string buffer") }
        return s
    }
}

public func getCurrentDateSeconds() -> UInt64 {
    var startTime: time_t
    startTime = time(nil)
    return UInt64(startTime)
}

public func getCurrentTime() -> CFAbsoluteTime {
    return CFAbsoluteTimeGetCurrent()
}

public func getDateString(seconds: UInt64) -> String {
    var tt = time_t(Int(seconds))
    let tm = gmtime(&tt)
    let size = 33
    let b = UnsafeMutablePointer<Int8>.allocate(capacity: size)
    defer {
        b.deinitialize(count: size)
        b.deallocate()
    }
    strftime(b, 32, "%Y-%m-%dT%H:%M:%SZ", tm)
    let date = String(validatingUTF8: b) ?? ""
    return date
}

internal func serializationCode<T: BufferSerializable>(from type: T.Type) -> UInt16 {
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

internal func serializationCode<T: BufferSerializable, U: BufferSerializable>(_ key: T.Type, _ value: U.Type) -> UInt32 {
    let t = UInt32(serializationCode(from: key))
    let u = UInt32(serializationCode(from: value))
    return (t << 16) | u
}

internal func pairName(_ code: UInt32) -> String {
    let rhs = UInt16(code & 0xffff)
    let lhs = UInt16(code >> 16)
    return "\(typeName(lhs)) -> \(typeName(rhs))"
}

internal func typeName(_ code: UInt16) -> String {
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

extension Array {
    // Binary search for the first index of the array not passing the supplied predicate:
    //   let a = [0, 0, 1, 1, 2, 3, 4, 4, 5, 6, 6, 7, 8]
    //   let j = firstIndexNotMatching { $0 < 4 }
    //   assert(j == 6)
    public func firstIndexNotMatching(predicate: (Element) -> Bool) -> Int {
        var low = 0
        var high = self.count
        while low < high {
            let midIndex = low + (high - low)/2
            if predicate(self[midIndex]) {
                low = midIndex + 1
            } else {
                high = midIndex
            }
        }
        return low
    }
    
    public mutating func insertSorted(_ element: Element, isOrderedBefore: (Element, Element) -> Bool) {
        if count == 0 {
            self.append(element)
        } else {
            let index = firstIndexNotMatching { !isOrderedBefore(element, $0) }
            self.insert(element, at: index)
        }
    }
}

public func myprintf(_ format: String, _ arguments: CVarArg...) {
    _ = withVaList(arguments) {
        vprintf(format, $0)
    }
}

extension PageRMediator {
    public func printTreeDOT(name: String) {
        var buffer = [PageId]()
        if let pid = try? self.getRoot(named: name) {
            buffer.append(pid)
        }
        
        print("digraph graphname {")
        var seen = Set<PageId>()
        while buffer.count > 0 {
            if let pid = buffer.popLast() {
                if seen.contains(pid) {
                    continue
                } else if let children = self.printTreeDOT(page: pid) {
                    buffer += children
                    seen.insert(pid)
                }
            }
        }
        for name in self.rootNames {
            if let pid = try? self.getRoot(named: name) {
                if seen.contains(pid) {
                    print("r\(pid) [label=\"\(name)\", style=bold, shape=diamond]")
                    print("r\(pid) -> p\(pid)")
                }
            }
        }
        print("}")
    }
    
    public func printTreeDOT(pages: [PageId]) {
        print("digraph graphname {")
        var seen = Set<PageId>()
        for pid in pages {
            if let _ = self.printTreeDOT(page: pid) {
                seen.insert(pid)
            }
        }
        for name in self.rootNames {
            if let pid = try? self.getRoot(named: name) {
                if seen.contains(pid) {
                    print("r\(pid) [label=\"\(name)\", style=bold, shape=diamond]")
                    print("r\(pid) -> p\(pid)")
                }
            }
        }
        print("}")
    }
    
    private func printTreeDOT(page pid: PageId) -> [PageId]? {
        do {
            guard let fm = self as? FilePageRMediator else { fatalError("Cannot serialize trees to DOT with this database mediator") }
            guard let (_, date, _) = fm._pageInfo(page: pid) else { fatalError("Failed to get info for page \(pid)") }
            let (node, _) : (TreeNode<Empty, Empty>, PageStatus) = try self.readPage(pid)
            let nodeName = "p\(pid)"
            var attributes = [String]()
            var label: String
            switch node {
            case .leafNode(let l):
                let type = pairName(l.typeCode)
                label = "[\(pid)] \(type) leaf (\(l.pairs.count) pairs) \(date)"
                attributes.append("label=\"\(label)\"")
                attributes.append("shape=box")
                print("\(nodeName) [\(attributes.joined(separator: ", "))]")
                return []
            case .internalNode(let i):
                let type = pairName(i.typeCode)
                label = "[\(pid)] \(type) internal (\(i.pairs.count) children, \(i.totalCount) total) \(date)"
                attributes.append("label=\"\(label)\"")
                print("\(nodeName) [\(attributes.joined(separator: ", "))]")
                var children = [PageId]()
                if i.typeCode == termIntType {
                    let (typed, _) : (TreeNode<Term, PageId>, PageStatus) = try self.readPage(pid)
                    if case .internalNode(let typedi) = typed {
                        for (k, cpid) in typedi.pairs {
                            children.append(cpid)
                            let esc = String("\(k)".map { $0 == "\"" ? "'" : $0 })
                            let child = "p\(cpid)"
                            print("\(nodeName) -> \(child) [label=\"\(esc)\"]")
                        }
                    }
                } else if i.typeCode == intIntType {
                    let (typed, _) : (TreeNode<UInt64, PageId>, PageStatus) = try self.readPage(pid)
                    if case .internalNode(let typedi) = typed {
                        for (k, cpid) in typedi.pairs {
                            children.append(cpid)
                            let esc = String("\(k)".map { $0 == "\"" ? "'" : $0 })
                            let child = "p\(cpid)"
                            print("\(nodeName) -> \(child) [label=\"\(esc)\"]")
                        }
                    }
                } else if i.typeCode == quadIntType {
                    let (typed, _) : (TreeNode<IDQuad<UInt64>, PageId>, PageStatus) = try self.readPage(pid)
                    if case .internalNode(let typedi) = typed {
                        for (k, cpid) in typedi.pairs {
                            children.append(cpid)
                            let esc = String("\(k)".map { $0 == "\"" ? "'" : $0 })
                            let child = "p\(cpid)"
                            print("\(nodeName) -> \(child) [label=\"\(esc)\"]")
                        }
                    }
                }
                return children
            }
        } catch {}
        return nil
    }
    
    public func debugTreePage(_ pid: PageId) {
        do {
            let (node, _) : (TreeNode<Empty, Empty>, PageStatus) = try self.readPage(pid)
            switch node {
            case .leafNode(let l):
                let date = getDateString(seconds: l.version)
                print("Tree node on page \(pid)")
                print("    Type          : LEAF")
                print("    Modified      : \(date)")
                print("    Pair count    : \(l.pairs.count)")
                if l.typeCode == intEmptyType {
                    let (typed, _) : (TreeNode<UInt64, Empty>, PageStatus) = try self.readPage(pid)
                    if case .leafNode(let typedl) = typed {
                        for (k, _) in typedl.pairs {
                            print("        - \(k)")
                        }
                    }
                } else if l.typeCode == termIntType {
                    let (typed, _) : (TreeNode<Term, PageId>, PageStatus) = try self.readPage(pid)
                    if case .leafNode(let typedl) = typed {
                        for (k, v) in typedl.pairs {
                            print("        - \(k): \(v)")
                        }
                    }
                } else if l.typeCode == intTermType {
                    let (typed, _) : (TreeNode<PageId, Term>, PageStatus) = try self.readPage(pid)
                    if case .leafNode(let typedl) = typed {
                        for (k, v) in typedl.pairs {
                            print("        - \(k): \(v)")
                        }
                    }
                } else if l.typeCode == intIntType {
                    let (typed, _) : (TreeNode<UInt64, PageId>, PageStatus) = try self.readPage(pid)
                    if case .leafNode(let typedl) = typed {
                        for (k, v) in typedl.pairs {
                            print("        - \(k): \(v)")
                        }
                    }
                } else if l.typeCode == quadIntType {
                    let (typed, _) : (TreeNode<IDQuad<UInt64>, PageId>, PageStatus) = try self.readPage(pid)
                    if case .leafNode(let typedl) = typed {
                        for (k, v) in typedl.pairs {
                            print("        - \(k): \(v)")
                        }
                    }
                }
            case .internalNode(let i):
                let date = getDateString(seconds: i.version)
                print("Tree node on page \(pid)")
                print("    Type          : INTERNAL")
                print("    Modified      : \(date)")
                print("    Pointer count: \(i.pairs.count)")
                if i.typeCode == termIntType {
                    let (typed, _) : (TreeNode<Term, PageId>, PageStatus) = try self.readPage(pid)
                    if case .internalNode(let typedi) = typed {
                        for (k, cpid) in typedi.pairs {
                            print("        - \(k): Page \(cpid)")
                        }
                    }
                } else if i.typeCode == intIntType {
                    let (typed, _) : (TreeNode<UInt64, PageId>, PageStatus) = try self.readPage(pid)
                    if case .internalNode(let typedi) = typed {
                        for (k, cpid) in typedi.pairs {
                            print("        - \(k): Page \(cpid)")
                        }
                    }
                } else if i.typeCode == quadIntType {
                    let (typed, _) : (TreeNode<IDQuad<UInt64>, PageId>, PageStatus) = try self.readPage(pid)
                    if case .internalNode(let typedi) = typed {
                        for (k, cpid) in typedi.pairs {
                            print("        - \(k): Page \(cpid)")
                        }
                    }
                }
            }
        } catch {}
    }
}
