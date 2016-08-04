//
//  Database.swift
//  PageDatabase
//
//  Created by Gregory Todd Williams on 5/11/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

public enum DatabaseUpdateError : Error {
    case retry
    case rollback
}

public enum DatabaseError: Error {
    case KeyError(String)
    case DataError(String)
    case PermissionError(String)
    case FailedCommit
    case PageOverflow(successfulItems : Int)
    case SerializationError(String)
    case OverflowError(String)
}

public protocol PageMarshalled {
    static func deserialize(from: UnsafePointer<Void>, status: PageStatus, mediator : RMediator) throws -> Self
    func serialize(to: UnsafeMutablePointer<Void>, status: PageStatus, mediator : RWMediator) throws
}

public typealias PageId = Int
public typealias Version = UInt64

public enum PageStatus {
    case unassigned
    case clean(PageId)
    case dirty(PageId)
}

public protocol RMediator {
    var pageSize : Int { get }
    var pageCount : Int { get }
    var rootNames : [String] { get }
    func getRoot(named name : String) throws -> PageId
    func readPage<M : PageMarshalled>(_ page : PageId) throws -> (M, PageStatus)
}

public protocol RWMediator : RMediator {
    var version : Version { get }
    func addRoot(name : String, page : PageId)
    func updateRoot(name : String, page : PageId)
    func createPage<M : PageMarshalled>(for : M) throws -> PageId
    func update<M : PageMarshalled>(page : PageId, with : M) throws
}

public protocol Database {
    associatedtype ReadMediator
    associatedtype UpdateMediator
    var pageSize : Int { get }
    var pageCount : Int { get }
    func read(cb : @noescape (mediator : ReadMediator) -> ()) throws
    func update(version : Version, cb : @noescape (mediator : UpdateMediator) throws -> ()) throws
}

public class DatabaseInfo {
    public enum Cookie : UInt32 {
        case databaseHeader     = 0x702e4442 // 'p.DB'
        case intStringTable     = 0x54426973 // 'TBis'
        case internalTreeNode   = 0x54524569 // 'TREi'
        case leafTreeNode       = 0x5452456c // 'TREl'
    }
}

extension DatabaseInfo.Cookie : CustomStringConvertible {
    public var description : String {
        switch self {
        case .databaseHeader:
            return "Database Header"
        case .intStringTable:
            return "Table (Int -> String)"
        case .internalTreeNode:
            return "Tree Node (Internal)"
        case .leafTreeNode:
            return "Tree Node (Leaf)"
        }
    }
}
