//
//  FilePageDatabase.swift
//  PageDatabase
//
//  Created by Gregory Todd Williams on 5/16/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

/**

 Database header:
 0  4   Cookie 'p.DB'
 4  12  Version
 12 16  Page size
 16 20  Pair count
 20 -   <string,int> pairs payload

 **/

import Foundation

public struct DatabaseHeaderPage: PageMarshalled {
    let version: Version
    var roots: [(String, PageId)]
    init(version: Version, roots: [(String, PageId)]) {
        self.version = version
        self.roots = roots
    }

    public static func deserializeHeaderMetadata(from buffer: UnsafeRawPointer, status: PageStatus) throws -> (UInt32, Version, Int) {
        let rawMemory = buffer.assumingMemoryBound(to: UInt8.self)
        let cookie = UInt32(bigEndian: rawMemory.withMemoryRebound(to: UInt32.self, capacity: 1) { $0[0] })
        let version = UInt64(bigEndian: rawMemory.withMemoryRebound(to: UInt64.self, capacity: 2) { $0[1] })
        let pageSize = UInt32(bigEndian: rawMemory.withMemoryRebound(to: UInt32.self, capacity: 4) { $0[3] })
        return (cookie, version, Int(pageSize))
    }

    public static func deserialize(from buffer: UnsafeRawPointer, status: PageStatus, mediator: RMediator) throws -> DatabaseHeaderPage {
        let (cookie, version, _) = try self.deserializeHeaderMetadata(from: buffer, status: status)
        let rawMemory = buffer.assumingMemoryBound(to: UInt8.self)
        guard cookie == DatabaseInfo.Cookie.databaseHeader.rawValue else { throw DatabaseError.DataError("Table page has bad header cookie") }
        let count = UInt32(bigEndian: rawMemory.withMemoryRebound(to: UInt32.self, capacity: 5) { $0[4] })
        var payloadPtr = UnsafeRawPointer(rawMemory+20)

        var roots = [(String, PageId)]()
        for _ in 0..<count {
            let string  = try String.deserialize(from: &payloadPtr)
            let pid     = try UInt32.deserialize(from: &payloadPtr)
            roots.append((string, PageId(pid)))
        }
        return DatabaseHeaderPage(version: version, roots: roots)
    }

    public func serialize(to buffer: UnsafeMutableRawPointer, status: PageStatus, mediator: RWMediator) throws {
        let pageSize = mediator.pageSize
        try self.serialize(to: buffer, status: status, pageSize: pageSize)
    }

    public func serialize(to buffer: UnsafeMutableRawPointer, status: PageStatus, pageSize: Int) throws {
        buffer.bindMemory(to: UInt8.self, capacity: pageSize).withMemoryRebound(to: UInt8.self, capacity: pageSize) { (p) in
            for i in 0..<pageSize {
                p[i] = 0
            }
        }
        var ptr = buffer
        try DatabaseInfo.Cookie.databaseHeader.rawValue.serialize(to: &ptr)
        try version.serialize(to: &ptr)

        precondition(pageSize >= _sizeof(UInt32.self))
        try UInt32(pageSize).serialize(to: &ptr)

        precondition(pageSize >= _sizeof(UInt32.self))

        try UInt32(roots.count).serialize(to: &ptr)

        var totalBytes = 16
        for (string, page) in roots {
            //            print("root name: '\(string)'")
            precondition(UInt64(page) <= UInt64(UInt32.max))

            totalBytes += string.serializedSize
            guard totalBytes <= pageSize else { throw DatabaseUpdateError.rollback }
            try string.serialize(to: &ptr)

            totalBytes += UInt32(page).serializedSize
            guard totalBytes <= pageSize else { throw DatabaseUpdateError.rollback }
            try UInt32(page).serialize(to: &ptr)
        }
    }
}

public final class FilePageDatabase: Database {
    public typealias ReadMediator = FilePageRMediator
    public typealias UpdateMediator = FilePageRWMediator

    public let pageSize: Int
    public var pageCount: Int
    internal let fd: CInt
    var nextPageId: Int

    public init?(_ filename: String, size preferredPageSize: Int = 4096) {
        var st: stat = stat()
        fd = open(filename, O_RDWR|O_CREAT, 0o666)
        nextPageId = -1
        let s = fstat(fd, &st)
        guard s == 0 else { return nil }
        var size = Int(st.st_size)
        if size == 0 {
            let version: Version = 0
            pageSize = preferredPageSize
            let b = UnsafeMutableRawPointer.allocate(byteCount: pageSize, alignment: 0)
            do {
                let header = DatabaseHeaderPage(version: version, roots: [("sys", 0)])
                try header.serialize(to: b, status: .unassigned, pageSize: pageSize)
            } catch { return nil }
            guard pwrite(fd, b, pageSize, 0) != -1 else { return nil }
            size = pageSize
            pageCount = 1
//            b.deinitialize(count: pageSize)
            b.deallocate()
        } else {
            let b = UnsafeMutableRawPointer.allocate(byteCount: 16, alignment: 4)
            defer {
//                b.deinitialize(count: 16)
                b.deallocate()
            }
            let sr = pread(fd, b, 16, off_t(0))
            guard sr == 16 else { return nil }
            do {
                let (cookie, _, preferredPageSize) = try DatabaseHeaderPage.deserializeHeaderMetadata(from: b, status: .clean(0))
                guard cookie == DatabaseInfo.Cookie.databaseHeader.rawValue else { return nil }
                pageSize = preferredPageSize
                guard size % pageSize == 0 else { return nil }
                pageCount = (size / pageSize)
            } catch {
                return nil
            }
        }

        nextPageId = pageCount
    }

    public func read(cb callback: (ReadMediator) throws -> ()) rethrows {
        let r = FilePageRMediator(database: self)
        #if os (OSX)
            try autoreleasepool { try callback(r) }
        #else
            try callback(r)
        #endif
    }

    public func update(version: Version, cb callback: (UpdateMediator) throws -> ()) throws {
        let w = FilePageRWMediator(database: self, version: version)
        #if os (OSX)
            let caughtError = autoreleasepool { () -> Error? in
                do {
                    try callback(w)
        //            print("need to commit \(w.pages.count) pages")
                    try w.commit()
                } catch DatabaseUpdateError.rollback {
                } catch let e {
                    return e
                }
                return nil
            }
            if let error = caughtError {
                throw error
            }
        #else
            do {
                try callback(w)
                //            print("need to commit \(w.pages.count) pages")
                try w.commit()
            } catch DatabaseUpdateError.rollback {
            }
        #endif
    }

    internal func reservePageId() -> PageId {
        let r = nextPageId
        nextPageId += 1
        return r
    }
}

open class FilePageRMediator: RMediator {
    public typealias Database = FilePageDatabase

    var database: FilePageDatabase
    public var pageSize: Int { return database.pageSize }
    public var pageCount: Int { return database.pageCount }
    internal var pageObjects: [PageId:PageMarshalled]
    internal var readBuffer: UnsafeMutableRawPointer
    init(database: FilePageDatabase) {
        self.database = database
        pageObjects = [:]
        readBuffer = UnsafeMutableRawPointer.allocate(byteCount: database.pageSize, alignment: 0)
    }

    deinit {
        readBuffer.deallocate()
    }

    public var rootNames: [String] {
        let pageSize = self.pageSize
        precondition(pageSize >= 16)
        guard let page: (DatabaseHeaderPage, PageStatus) = try? readPage(0) else { fatalError("error while finding root pages") }
        let (header, _) = page
        let names = header.roots.map { $0.0 }
        return names
    }

    public func getRoot(named name: String) throws -> PageId {
        let pageSize = self.pageSize
        precondition(pageSize >= 16)
        guard let page: (DatabaseHeaderPage, PageStatus) = try? readPage(0) else { fatalError("error while finding root pages") }
        let (header, _) = page
        for (n, pid) in header.roots {
            if name == n {
                return pid
            }
        }
        throw DatabaseError.DataError("No root found with given name '\(name)'")
    }

    public func readPage<M: PageMarshalled>(_ page: PageId) throws -> (M, PageStatus) {
        if let o = pageObjects[page] as? M {
            //                print("Got cached page object for pid \(page)")
            return (o, .clean(page))
        } else {
            //        print("readPage(\(page))")
            let offset = off_t(pageSize * page)
            let sr = pread(database.fd, readBuffer, pageSize, offset)
            if sr == pageSize {
                //            print("Read \(sr) bytes for page \(page)")
                if let o = try? M.deserialize(from: readBuffer, status: .clean(page), mediator: self) {
                    //                print("Setting cached page object for pid \(page)")
                    pageObjects[page] = o
                    return (o, .clean(page))
                } else {
                    throw DatabaseError.DataError("Cannot coerce page object to type \(M.self)")
                }
            } else {
                throw DatabaseError.DataError("Failed to read \(pageSize) bytes for page \(page)")
            }
        }
    }

    public func _pageBufferPointer(_ page: PageId, cb callback: (UnsafeMutableRawPointer) -> ()) throws {
        let offset = off_t(pageSize * page)
        let sr = pread(database.fd, readBuffer, pageSize, offset)
        if sr == pageSize {
            callback(readBuffer)
        } else {
            throw DatabaseError.DataError("Failed to read \(pageSize) bytes for page \(page)")
        }
    }

    public func _pageInfo(page: PageId) -> (String, String, PageId?)? {
        var r: (String, String, PageId?)? = nil
        _ = try? self._pageBufferPointer(page) { (p) in
            do {
                var ptr         = UnsafeRawPointer(p)
                let cookie      = try UInt32.deserialize(from: &ptr)
                let version     = try Version.deserialize(from: &ptr)
                let _           = try UInt32.deserialize(from: &ptr)
                let config2     = try UInt32.deserialize(from: &ptr)
                let date = getDateString(seconds: version)
                var prev: PageId? = nil
                if page > 0 && config2 > 0 {
                    prev = PageId(config2)
                }

                var type: String
                if let c = DatabaseInfo.Cookie(rawValue: cookie) {
                    type = "\(c)"
                } else {
                    type = "????"
                }
                r = (type, date, prev)
            } catch {}
        }
        return r
    }
}

open class FilePageRWMediator: FilePageRMediator, RWMediator {
    public typealias Database = FilePageDatabase
    private var roots: [String:PageId]
    private var dirty: [PageId:PageMarshalled]
    private var newPages: Set<PageId>
    public let version: Version

    init(database: FilePageDatabase, version: Version) {
        roots = [:]
        dirty = [:]
        newPages = Set()
        self.version = version
        super.init(database: database)
    }

    internal func commit() throws {
        var maxPage = database.pageCount-1
        let writeBuffer = UnsafeMutableRawPointer.allocate(byteCount: pageSize, alignment: 0)
        defer {
//            writeBuffer.deinitialize(count: pageSize)
            writeBuffer.deallocate()
        }
        for (page, object) in dirty {
            pageObjects.removeValue(forKey: page)
            if page > maxPage {
                maxPage = page
            }
            let offset = off_t(pageSize * page)
            try object.serialize(to: writeBuffer, status: .dirty(page), mediator: self)
            let bw = pwrite(database.fd, writeBuffer, pageSize, offset)
            guard bw == pageSize else { throw DatabaseUpdateError.rollback }
        }
        let pageCount = maxPage + 1
        if pageCount != database.pageCount {
//            print("updating database page count to \(pageCount)")
            database.pageCount = pageCount
        }

        let pairs = try rootNames.map {
            ($0, try getRoot(named: $0))
        }

        let header = DatabaseHeaderPage(version: version, roots: pairs)
        try header.serialize(to: writeBuffer, status: .dirty(0), pageSize: pageSize)
        let bw = pwrite(database.fd, writeBuffer, pageSize, 0)
        guard bw == pageSize else { throw DatabaseUpdateError.rollback }

        newPages = Set()
        dirty = [:]
    }

    public func addRoot(name: String, page: PageId) {
        roots[name] = page
    }

    public func updateRoot(name: String, page: PageId) {
        roots[name] = page
    }

    public func createPage<M: PageMarshalled>(for object: M) throws -> PageId {
        let pid = database.reservePageId()
        dirty[pid] = object
        newPages.insert(pid)
        return pid
    }

    public func update<M: PageMarshalled>(page: PageId, with object: M) throws {
        pageObjects.removeValue(forKey: page)
        dirty[page] = object
    }

    public override var rootNames: [String] {
        var r = super.rootNames
        r += roots.keys
        let s = Set(r)
        let a = Array(s)
        return a.sorted()
    }

    public override func getRoot(named name: String) throws -> PageId {
        if let pid = roots[name] {
            return pid
        }
        return try super.getRoot(named: name)
    }

    override public func readPage<M: PageMarshalled>(_ page: PageId) throws -> (M, PageStatus) {
        if let object = dirty[page] {
            if let m = object as? M {
                return (m, .dirty(page))
            } else {
                throw DatabaseError.DataError("Cannot coerce dirty page object to type \(M.self)")
            }
        } else {
            return try super.readPage(page)
        }
    }
}
