//
//  Log.swift
//  CryptoSwift
//
//  Created by Gregory Todd Williams on 4/18/18.
//

import Foundation

final public class Logger {
    public enum LogLevel {
        case trace
        case warn
        case error
        case silent
    }
    struct Frame {
        var number: Int
        var name: String
        var level: LogLevel
        var counts: [String:Int]
    }
    public static let shared = Logger()
    
    public var level: LogLevel {
        get {
            return self.stack.last?.level ?? .silent
        }
        
        set {
            let i = self.stack.index(before: self.stack.endIndex)
            self.stack[i].level = newValue
        }
    }
    
    var counter: Int
    var stack: [Frame]
    init() {
        counter = 0
        stack = []
        stack.append(newFrame(name: "root"))
    }
    
    private func newFrame(name n: String?) -> Frame {
        let name = n ?? "Frame \(counter)"
        let f = Frame(number: counter, name: name, level: .error, counts: [:])
        counter += 1
        return f
    }
    
    public func push(name: String? = nil) {
        let f = newFrame(name: name)
        self.stack.append(f)
    }
    
    public func printSummary() {
        let f = self.stack.last!
        print("Popped logger frame '\(f.name)' {")
        for (item, count) in f.counts.sorted(by: { $0.value > $1.value }) {
            print(String(format: "%9d: \(item)", count))
        }
        print("}")
    }
    
    public func pop(printSummary summarize: Bool = false) {
        guard self.stack.count > 0 else { fatalError("Attempt to pop last logger stack frame") }
        if summarize {
            printSummary()
        }
        self.stack.removeLast()
    }
    
    public func count(for item: String) -> Int {
        return self.stack.last!.counts[item, default: 0]
    }
    
    public func incrementCallStack(_ item: String) {
        let callers = callStackCallers(5, 1)
        increment("\(item) [\(callers)]")
    }
    public func increment(_ item: String) {
        let i = self.stack.count-1
        self.stack[i].counts[item, default: 0] += 1
    }
    
    public func trace(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        switch self.stack.last!.level {
        case .trace, .warn, .error:
            print(items, separator: separator, terminator: terminator)
        default:
            break
        }
    }
    
    public func warn(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        switch self.stack.last!.level {
        case .warn, .error:
            print(items, separator: separator, terminator: terminator)
        default:
            break
        }
    }
    
    public func error(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        switch self.stack.last!.level {
        case .error:
            print(items, separator: separator, terminator: terminator)
        default:
            break
        }
    }
}
