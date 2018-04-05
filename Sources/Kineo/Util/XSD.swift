//
//  XSD.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 4/5/18.
//  Copyright © 2018 Gregory Todd Williams. All rights reserved.
//

import Foundation

public enum NumericValue: CustomStringConvertible {
    case integer(Int)
    case decimal(Double)
    case float(Double)
    case double(Double)
    
    var value: Double {
        switch self {
        case .integer(let value):
            return Double(value)
        case .decimal(let value), .float(let value), .double(let value):
            return value
        }
    }
    
    var absoluteValue: NumericValue {
        if value >= 0.0 {
            return self
        } else {
            return self * .integer(-1)
        }
    }
    
    var round: NumericValue {
        var v = value
        if value < 0 {
            v += 0.5
        }
        v.round(.toNearestOrAwayFromZero)
        switch self {
        case .decimal(_):
            return .decimal(v)
        case .float(_):
            return .float(v)
        case .double(_):
            return .double(v)
        default:
            return self
        }
    }
    
    var ceil: NumericValue {
        var v = value
        v.round(.up)
        switch self {
        case .decimal(_):
            return .decimal(v)
        case .float(_):
            return .float(v)
        case .double(_):
            return .double(v)
        default:
            return self
        }
    }
    
    var floor: NumericValue {
        var v = value
        v.round(.down)
        switch self {
        case .decimal(_):
            return .decimal(v)
        case .float(_):
            return .float(v)
        case .double(_):
            return .double(v)
        default:
            return self
        }
    }
    
    var term: Term {
        switch self {
        case .integer(let value):
            return Term(integer: value)
        case .float(let value):
            return Term(float: value)
        case .decimal(let value):
            return Term(decimal: value)
        case .double(let value):
            return Term(double: value)
        }
    }
    
    public var description: String {
        switch self {
        case .integer(let i):
            return "\(i)"
        case .decimal(let value):
            return "\(value)dec"
        case .float(let value):
            return "\(value)f"
        case .double(let value):
            return "\(value)d"
        }
    }
    
    public static func + (lhs: NumericValue, rhs: NumericValue) -> NumericValue {
        let value = lhs.value + rhs.value
        return nonDivResultingNumeric(value, lhs, rhs)
    }
    
    public static func - (lhs: NumericValue, rhs: NumericValue) -> NumericValue {
        let value = lhs.value - rhs.value
        return nonDivResultingNumeric(value, lhs, rhs)
    }
    
    public static func * (lhs: NumericValue, rhs: NumericValue) -> NumericValue {
        let value = lhs.value * rhs.value
        return nonDivResultingNumeric(value, lhs, rhs)
    }
    
    public static func / (lhs: NumericValue, rhs: NumericValue) -> NumericValue {
        let value = lhs.value / rhs.value
        return divResultingNumeric(value, lhs, rhs)
    }
    
    public static prefix func - (num: NumericValue) -> NumericValue {
        switch num {
        case .integer(let value):
            return .integer(-value)
        case .decimal(let value):
            return .decimal(-value)
        case .float(let value):
            return .float(-value)
        case .double(let value):
            return .double(-value)
        }
    }
}

public extension NumericValue {
    public static func === (lhs: NumericValue, rhs: NumericValue) -> Bool {
        switch (lhs, rhs) {
        case (.integer(let l), .integer(let r)) where l == r:
            return true
        case (.decimal(let l), .decimal(let r)) where l == r:
            return true
        case (.float(let l), .float(let r)) where l == r:
            return true
        case (.double(let l), .double(let r)) where l == r:
            return true
        default:
            return false
        }
    }
}

private func nonDivResultingNumeric(_ value: Double, _ lhs: NumericValue, _ rhs: NumericValue) -> NumericValue {
    switch (lhs, rhs) {
    case (.integer(_), .integer(_)):
        return .integer(Int(value))
    case (.decimal(_), .decimal(_)):
        return .decimal(value)
    case (.float(_), .float(_)):
        return .float(value)
    case (.double(_), .double(_)):
        return .double(value)
    case (.integer(_), .decimal(_)), (.decimal(_), .integer(_)):
        return .decimal(value)
    case (.integer(_), .float(_)), (.float(_), .integer(_)), (.decimal(_), .float(_)), (.float(_), .decimal(_)):
        return .float(value)
    //    case (.integer(_), .double(_)), (.double(_), .integer(_)), (.decimal(_), .double(_)), (.double(_), .decimal(_)):
    default:
        return .double(value)
    }
}

private func divResultingNumeric(_ value: Double, _ lhs: NumericValue, _ rhs: NumericValue) -> NumericValue {
    switch (lhs, rhs) {
    case (.integer(_), .integer(_)), (.decimal(_), .decimal(_)):
        return .decimal(value)
    case (.float(_), .float(_)):
        return .float(value)
    case (.double(_), .double(_)):
        return .double(value)
    case (.integer(_), .decimal(_)), (.decimal(_), .integer(_)):
        return .decimal(value)
    case (.integer(_), .float(_)), (.float(_), .integer(_)), (.decimal(_), .float(_)), (.float(_), .decimal(_)):
        return .float(value)
    //    case (.integer(_), .double(_)), (.double(_), .integer(_)), (.decimal(_), .double(_)), (.double(_), .decimal(_)):
    default:
        return .double(value)
    }
}

