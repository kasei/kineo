//
//  Tables.swift
//  PageDatabase
//
//  Created by Gregory Todd Williams on 5/17/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation

/**
 
 Table header:
 0  4   Cookie
 4  8   Version
 12 4   Previous PageId
 16 4   Config
 20 4   Pair count
 24 -   Payload
 
 **/


public struct TablePage<T : BufferSerializable & Comparable, U : BufferSerializable> : PageMarshalled {
    public internal(set) var pairs : [(T,U)]
    var previousPage : PageId?
    var type : DatabaseInfo.Cookie
    
    init(pairs : [(T,U)], type : DatabaseInfo.Cookie, previousPage : PageId?) {
        self.pairs = pairs
        self.type = type
        self.previousPage = previousPage
    }
    
    let cookieHeaderSize = 24
    public var serializedSize : Int {
        var size = cookieHeaderSize
        for (k,v) in self.pairs {
            size += k.serializedSize
            size += v.serializedSize
        }
        return size
    }

    public func spaceForPair(_ pair : (T,U), pageSize : Int) -> Bool {
        return self.serializedSize + pair.0.serializedSize + pair.1.serializedSize <= pageSize
    }
    
    public mutating func add(pair: (T,U)) {
        self.pairs.append(pair)
    }
    
    public static func deserialize(from buffer: UnsafePointer<Void>, status: PageStatus, mediator : RMediator) throws -> TablePage<T,U> {
        let rawMemory   = UnsafePointer<Void>(buffer)
        var ptr         = rawMemory
        let cookie      = try UInt32.deserialize(from: &ptr)
        let _           = try UInt64.deserialize(from: &ptr)
        let previous    = try UInt32.deserialize(from: &ptr)
        let _           = try UInt32.deserialize(from: &ptr)
        let count       = try UInt32.deserialize(from: &ptr)
        var payloadPtr      = ptr
        assert(ptr == rawMemory.advanced(by: 24))
        
        var pairs = [(T,U)]()
        for _ in 0..<count {
            guard let id        = try? T.deserialize(from: &payloadPtr, mediator: mediator) else { throw DatabaseError.DataError("Bad key while deserializing table") }
            guard let string    = try? U.deserialize(from: &payloadPtr, mediator: mediator) else { throw DatabaseError.DataError("Bad value while deserializing table") }
            pairs.append((id, string))
        }
        
        let prev : PageId? = (previous == 0) ? nil : PageId(previous)
        guard let type = DatabaseInfo.Cookie(rawValue: cookie) else { throw DatabaseError.DataError("Bad cookie while deserializing table") }
        return TablePage(pairs: pairs, type: type, previousPage: prev)
    }
    
    public func serialize(to rawMemory: UnsafeMutablePointer<Void>, status: PageStatus, mediator : RWMediator) throws {
        let version = mediator.version
        let pageSize = mediator.pageSize
        
        var ptr = rawMemory
        try type.rawValue.serialize(to: &ptr)
        try version.serialize(to: &ptr)
        try UInt32(previousPage ?? 0).serialize(to: &ptr)
        try UInt32(0).serialize(to: &ptr)
        let countPtr = UnsafeMutablePointer<Void>(ptr)
        try UInt32(0).serialize(to: &ptr)
        let size = ptr - rawMemory
        guard size == 24 else { fatalError() }
        
        var bytesRemaining = pageSize - 24
        var payloadPtr = UnsafeMutablePointer<Void>(rawMemory+24)
        
        // fill payload
        var successful = 0
        for (key, value) in pairs.sorted(by: { (a, b) in a.0 < b.0 }) {
            do {
                try key.serialize(to: &payloadPtr, mediator: mediator, maximumSize: bytesRemaining)
                bytesRemaining -= key.serializedSize
                try value.serialize(to: &payloadPtr, mediator: mediator, maximumSize: bytesRemaining)
                bytesRemaining -= value.serializedSize
                successful += 1
                var cptr = countPtr
                try UInt32(successful).serialize(to: &cptr)
            } catch DatabaseError.OverflowError(_) {
                throw DatabaseError.PageOverflow(successfulItems: successful)
            }
        }
    }
}

public struct TablePageIterator<T : BufferSerializable & Comparable, U : BufferSerializable> : IteratorProtocol {
    let keyType : T.Type
    let valueType : U.Type
    let table : Table<T,U>
    let type : DatabaseInfo.Cookie
    private var nextPageId : PageId?
    
    init (table : Table<T,U>, type : DatabaseInfo.Cookie, keyType: T.Type, valueType: U.Type) {
        self.table = table
        self.type = type
        self.keyType = keyType
        self.valueType = valueType
        do {
            self.nextPageId = try table.mediator.getRoot(named: table.name)
        } catch {}
    }
    
    public mutating func next() -> TablePage<T,U>? {
        if nextPageId == nil || nextPageId == 0 {
            return nil
        } else {
            do {
                guard let pid = nextPageId else { return nil }
                let (page, _) : (TablePage<T,U>, PageStatus) = try table.mediator.readPage(pid)
                nextPageId = page.previousPage
                return page
            } catch {}
        }
        return nil
    }
}

public struct TableIterator<T : BufferSerializable & Comparable, U : BufferSerializable> : IteratorProtocol {
    let keyType : T.Type
    let valueType : U.Type
    public typealias Element = (T, U)
    let table : Table<T,U>
    var buffer : [Element]
    let type : DatabaseInfo.Cookie
    private var nextPageId : PageId?
    
    init (table : Table<T,U>, type : DatabaseInfo.Cookie, keyType: T.Type, valueType: U.Type) {
        self.table = table
        self.type = type
        self.keyType = keyType
        self.valueType = valueType
        self.buffer = []
        do {
            self.nextPageId = try table.mediator.getRoot(named: table.name)
        } catch {}
    }
    
    mutating func fillBuffer() -> Bool {
        if nextPageId == nil || nextPageId == 0 {
            return false
        } else {
            do {
                guard let pid = nextPageId else { return false }
                let (page, _) : (TablePage<T,U>, PageStatus) = try table.mediator.readPage(pid)
                self.buffer.append(contentsOf: page.pairs)
                nextPageId = page.previousPage
            } catch { return false }
        }
        return true
    }
    
    public mutating func next() -> Element? {
        if buffer.count > 0 {
            return buffer.popLast()
        } else if fillBuffer() {
            return buffer.popLast()
        } else {
            return nil
        }
    }
}

enum TableError : Error {
    case StopIteration
}

public struct Table<T : BufferSerializable & Comparable, U : BufferSerializable> : Sequence {
    var mediator : RMediator
    let name : String
    let type : DatabaseInfo.Cookie
    let keyType : T.Type
    let valueType : U.Type

    subscript(id: T) -> U? {
        for (key, value) in self {
            if key == id {
                return value
            }
        }
        return nil
    }

    public func pages() -> TablePageIterator<T,U> {
        return TablePageIterator(table: self, type: type, keyType: T.self, valueType: U.self)
    }
    
    public func makeIterator () -> TableIterator<T,U> {
        return TableIterator(table: self, type: type, keyType: T.self, valueType: U.self)
    }
    
    func filter(_ includeElement: @noescape(T) throws -> Bool) throws -> [U] {
        var elements = [U]()
        for (key, value) in self {
            if try includeElement(key) {
                elements.append(value)
            }
        }
        return elements
    }
    
    public func firstMatching(_ includeElement: @noescape(T,U) throws -> Bool) throws -> (T,U)? {
        var element : (T,U)? = nil
        for (key, value) in self {
            if try includeElement(key, value) {
                element = (key, value)
            }
        }
        return element
    }
    
    func filter(_ includeElement: @noescape(U) throws -> Bool) throws -> [T] {
        var elements = [T]()
        for (key, value) in self {
            if try includeElement(value) {
                elements.append(key)
            }
        }
        return elements
    }
    
    public mutating func addPairs<C : Sequence>(pairs : C) throws where C.Iterator.Element == (UInt64,String) {
        guard let m = mediator as? RWMediator else { throw DatabaseError.PermissionError("Cannot mutate table while in a read-only transaction") }
        let _ = try m.append(pairs: pairs, toTable: name)
    }
}

extension RMediator {
    public func table<T : BufferSerializable & Comparable, U: BufferSerializable>(name : String) -> Table<T, U>? {
        do {
            _ = try getRoot(named: name)
            return Table(mediator: self, name: name, type: DatabaseInfo.Cookie.tablePage, keyType: T.self, valueType: U.self)
        } catch let e {
            print("failed to construct a table struct \(e)")
            return nil
        }
    }
}

extension RWMediator {
    private func createTablePages<C : Sequence, T : BufferSerializable & Comparable, U : BufferSerializable>(type : DatabaseInfo.Cookie, previous: PageId?, forceCreation: Bool, pairs: C) throws -> PageId? where C.Iterator.Element == (T, U) {
        var previousPage : PageId? = previous
        var tablepage = TablePage<T,U>(pairs: [], type: type, previousPage: previousPage)
        for pair in pairs {
            if tablepage.spaceForPair(pair, pageSize: self.pageSize) {
                tablepage.add(pair: pair)
            } else {
                previousPage = try self.createPage(for: tablepage)
                tablepage = TablePage(pairs: [pair], type: type, previousPage: previousPage)
            }
        }
        if forceCreation || tablepage.pairs.count > 0 {
            return try self.createPage(for: tablepage)
        } else {
            return previousPage
        }
    }
    
    public func create<C : Sequence, T : BufferSerializable & Comparable, U : BufferSerializable>(table name : String, pairs : C) throws -> PageId? where C.Iterator.Element == (T,U) {
        guard pageSize > 20 else { throw DatabaseError.DataError("Cannot create table with small page size") }
        let previous : PageId? = nil
        if let pid = try createTablePages(type: DatabaseInfo.Cookie.tablePage, previous: previous, forceCreation: true, pairs: pairs) {
            self.updateRoot(name: name, page: pid)
            return pid
        } else {
            warn("*** failed to create table '\(name)'")
            return nil
        }
    }
    
    public func append<C : Sequence, T : BufferSerializable & Comparable, U : BufferSerializable>(pairs : C, toTable name : String) throws -> PageId? where C.Iterator.Element == (T,U) {
        let previous = try getRoot(named: name)
        if let pid = try createTablePages(type: DatabaseInfo.Cookie.tablePage, previous: previous, forceCreation: false, pairs: pairs) {
            self.updateRoot(name: name, page: pid)
            return pid
        } else {
            return nil
        }
    }
}

