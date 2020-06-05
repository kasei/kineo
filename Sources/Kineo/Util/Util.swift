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
        let j = f.firstIndex(of: " ") ?? f.endIndex
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

    static func fill(buffer: inout [CChar], from fd: Int32, blockSize: Int) -> Int? {
        var bufferBytes = 0
        var _buffer: [CChar] = [CChar](repeating: 0, count: 1+blockSize)
        _buffer.withUnsafeMutableBufferPointer { (b) -> () in
            if let base = b.baseAddress {
                memset(base, 0, blockSize+1)
                bufferBytes = read(fd, base, blockSize)
            }
        }
        //                print("read \(bufferBytes) bytes")
        if bufferBytes <= 0 {
            return nil
        }
        buffer.append(contentsOf: _buffer.prefix(upTo: bufferBytes))
        return bufferBytes
    }
    
    public func lines() -> AnyIterator<String> {
        let fd = open(filename, O_RDONLY)
        let blockSize = 4096
        var buffer = [CChar]()
        
        var end = false
        return AnyIterator { () -> String? in
            LOOP: repeat {
                if end {
                    return nil
                }
                if let index = buffer.firstIndex(of: 10) {
                    let d = Data(bytes: buffer, count: index)
                    guard let s = String(data: d, encoding: .utf8) else {
                        return nil
                    }
                    buffer.removeFirst(index+1)
                    return s
                }

                guard let _ = Self.fill(buffer: &buffer, from: fd, blockSize: blockSize) else {
                    // return last line
                    let d = Data(bytes: buffer, count: buffer.count)
                    end = true
                    buffer = []
                    return String(data: d, encoding: .utf8)
                }
            } while true
        }
    }
}

public struct ConcatenatingIterator<I: IteratorProtocol, J: IteratorProtocol>: IteratorProtocol where I.Element == J.Element {
    public typealias Element = I.Element
    var lhs: I
    var rhs: J
    var lhsClosed: Bool
    
    public init(_ lhs: I, _ rhs: J) {
        self.lhs = lhs
        self.rhs = rhs
        self.lhsClosed = false
    }
    
    public mutating func next() -> Element? {
        if !lhsClosed {
            if let i = lhs.next() {
                return i
            } else {
                lhsClosed = true
            }
        }
        return rhs.next()
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
