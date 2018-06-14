//
//  IdentityMap.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 4/11/18.
//  Copyright © 2018 Gregory Todd Williams. All rights reserved.
//

import Foundation
import SPARQLSyntax

public protocol IdentityMap {
    associatedtype Item: Hashable
    associatedtype Result: Comparable, DefinedTestable
    func id(for value: Item) -> Result?
    func getOrSetID(for value: Item) throws -> Result
}

public enum PackedTermType : UInt8 {
    case blank          = 0x01
    case iri            = 0x02
    case commonIRI      = 0x03
    case language       = 0x10
    case datatype       = 0x11
    case inlinedString  = 0x12
    case boolean        = 0x13
    case date           = 0x14
    case dateTime       = 0x15
    case string         = 0x16
    case integer        = 0x18
    case int            = 0x19
    case decimal        = 0x1A
    
    init?(from id: UInt64) {
        let typebyte = UInt8(UInt64(id) >> 56)
        self.init(rawValue: typebyte)
    }
    
    var typedEmptyValue : UInt64 {
        return (UInt64(self.rawValue) << 56)
    }
    
    var idRange : Range<UInt64> {
        let value = rawValue
        let min = (UInt64(value) << 56)
        let max = (UInt64(value+1) << 56)
        return min..<max
    }
}

public protocol PackedIdentityMap : IdentityMap {}

public extension PackedIdentityMap where Item == Term, Result == UInt64 {
    /**
     
     Term ID type byte:
     
     01    0x01    0000 0001    Blank
     02    0x02    0000 0010    IRI
     03    0x03    0000 0011        common IRIs
     16    0x10    0001 0000    Language
     17    0x11    0001 0001    Datatype
     18    0x12    0001 0010        inlined xsd:string
     19    0x13    0001 0011        xsd:boolean
     20    0x14    0001 0100        xsd:date
     21    0x15    0001 0101        xsd:dateTime
     22    0x16    0001 0110        xsd:string
     24    0x18    0001 1000        xsd:integer
     25    0x19    0001 1001        xsd:int
     26    0x1A    0001 1010        xsd:decimal
     
     Prefixes:
     
     0000 0001  blank
     0000 001   iri
     0001       literal
     0001 01        date (with optional time)
     0001 1         numeric
     
     **/
    
    internal static func isIRI(id: Result) -> Bool {
        guard let type = PackedTermType(from: id) else { return false }
        return type == .iri
    }
    
    internal static func isBlank(id: Result) -> Bool {
        guard let type = PackedTermType(from: id) else { return false }
        return type == .blank
    }
    
    internal static func isLanguageLiteral(id: Result) -> Bool {
        guard let type = PackedTermType(from: id) else { return false }
        return type == .language
    }
    
    internal static func isDatatypeLiteral(id: Result) -> Bool {
        guard let type = PackedTermType(from: id) else { return false }
        return type == .datatype
    }
    
    public func unpack(id: Result) -> Item? {
        let byte = id >> 56
        let value = id & 0x00ffffffffffffff
        guard let type = PackedTermType(rawValue: UInt8(byte)) else { return nil }
        switch type {
        case .commonIRI:
            return unpack(iri: value)
        case .boolean:
            return unpack(boolean: value)
        case .date:
            return unpack(date: value)
        case .dateTime:
            return unpack(dateTime: value)
        case .inlinedString:
            return unpack(string: value)
        case .integer:
            return unpack(integer: value)
        case .int:
            return unpack(int: value)
        case .decimal:
            return unpack(decimal: value)
        default:
            return nil
        }
    }
    
    public func pack(value: Item) -> Result? {
        switch (value.type, value.value) {
        case (.iri, let v):
            return pack(iri: v)
        case (.datatype("http://www.w3.org/2001/XMLSchema#boolean"), "true"), (.datatype("http://www.w3.org/2001/XMLSchema#boolean"), "1"):
            return pack(boolean: true)
        case (.datatype("http://www.w3.org/2001/XMLSchema#boolean"), "false"), (.datatype("http://www.w3.org/2001/XMLSchema#boolean"), "0"):
            return pack(boolean: false)
        case (.datatype(.dateTime), _):
            return pack(dateTime: value)
        case (.datatype(.date), let v):
            return pack(date: v)
        case (.datatype(.string), let v):
            return pack(string: v)
        case (.datatype(.integer), let v):
            return pack(integer: v)
        case (.datatype("http://www.w3.org/2001/XMLSchema#int"), let v):
            return pack(int: v)
        case (.datatype(.decimal), let v):
            return pack(decimal: v)
        default:
            return nil
        }
    }
    
    private func pack(string: String) -> Result? {
        guard string.utf8.count <= 7 else { return nil }
        var id: UInt64 = PackedTermType.inlinedString.typedEmptyValue
        for (i, u) in string.utf8.enumerated() {
            let shift = UInt64(8 * (6 - i))
            let b: UInt64 = UInt64(u) << shift
            id += b
        }
        return id
    }
    
    private func unpack(string value: UInt64) -> Item? {
        var buffer = value.bigEndian
        var string: String? = nil
        withUnsafePointer(to: &buffer) { (p) in
            var chars = [CChar]()
            p.withMemoryRebound(to: CChar.self, capacity: 8) { (charsptr) in
                for i in 1...7 {
                    chars.append(charsptr[i])
                }
            }
            chars.append(0)
            chars.withUnsafeBufferPointer { (q) in
                if let p = q.baseAddress {
                    string = String(utf8String: p)
                }
            }
        }
        
        if let string = string {
            return Term(value: string, type: .datatype(.string))
        }
        return nil
    }
    
    private func unpack(boolean packedBooleanValue: UInt64) -> Item? {
        let value = (packedBooleanValue > 0) ? "true" : "false"
        return Term(value: value, type: .datatype("http://www.w3.org/2001/XMLSchema#boolean"))
    }
    
    private func unpack(integer value: UInt64) -> Item? {
        return Term(value: "\(value)", type: .datatype(.integer))
    }
    
    private func unpack(int value: UInt64) -> Item? {
        return Term(value: "\(value)", type: .datatype("http://www.w3.org/2001/XMLSchema#int"))
    }
    
    private func unpack(decimal: UInt64) -> Item? {
        let scale = Int((decimal & 0x00ff000000000000) >> 48)
        let value = decimal & 0x00007fffffffffff
        let highByte = (decimal & 0x0000ff0000000000) >> 40
        let highBit = highByte & UInt64(0x80)
        guard scale >= 0 else { return nil }
        var combined = "\(value)"
        var string = ""
        while combined.count <= scale {
            // pad with leading zeros so that there is at least one digit to the left of the decimal point
            combined = "0\(combined)"
        }
        let breakpoint = combined.count - scale
        for (i, c) in combined.enumerated() {
            if i == breakpoint {
                if i == 0 {
                    string += "0."
                } else {
                    string += "."
                }
            }
            string += String(c)
        }
        if highBit > 0 {
            string = "-\(string)"
        }
        return Term(value: string, type: .datatype(.decimal))
    }
    
    private func unpack(date value: UInt64) -> Item? {
        let day     = value & 0x000000000000001f
        let months  = (value & 0x00000000001fffe0) >> 5
        let month   = months % 12
        let year    = months / 12
        let date    = String(format: "%04d-%02d-%02d", year, month, day)
        return Term(value: date, type: .datatype(.date))
    }
    
    private func unpack(dateTime value: UInt64) -> Item? {
        // ZZZZ ZZZY YYYY YYYY YYYY MMMM DDDD Dhhh hhmm mmmm ssss ssss ssss ssss
        let tzSign  = (value & 0x0080000000000000) >> 55
        let tz      = (value & 0x007e000000000000) >> 49
        let year    = (value & 0x0001fff000000000) >> 36
        let month   = (value & 0x0000000f00000000) >> 32
        let day     = (value & 0x00000000f8000000) >> 27
        let hours   = (value & 0x0000000007c00000) >> 22
        let minutes = (value & 0x00000000003f0000) >> 16
        let msecs   = (value & 0x000000000000ffff)
        let seconds = Double(msecs) / 1_000.0
        var dateTime = String(format: "%04d-%02d-%02dT%02d:%02d:%02g", year, month, day, hours, minutes, seconds)
        if tz == 0 {
            dateTime = "\(dateTime)Z"
        } else {
            let offset  = tz * 15
            var hours   = Int(offset) / 60
            let minutes = Int(offset) % 60
            if tzSign == 1 {
                hours   *= -1
            }
            dateTime = dateTime + String(format: "%+03d:%02d", hours, minutes)
        }
        return Term(value: dateTime, type: .datatype(.dateTime))
    }
    
    private func pack(decimal stringValue: String) -> Result? {
        var c = stringValue.components(separatedBy: ".")
        guard c.count == 2 else { return nil }
        let integralValue = c[0]
        var sign : UInt64 = 0
        if integralValue.hasPrefix("-") {
            sign = UInt64(0x80) << 40
            c[0] = String(integralValue[integralValue.index(integralValue.startIndex, offsetBy: 1)...])
        }
        let combined = c.joined(separator: "")
        guard let value = UInt64(combined) else { return nil }
        let scale = UInt8(c[1].count)
        guard value <= 0x00007fffffffffff else { return nil }
        guard scale >= 0 else { return nil }
        let id = PackedTermType.decimal.typedEmptyValue + (UInt64(scale) << 48) + (sign | value)
        return id
    }
    
    private func pack(boolean booleanValue: Bool) -> Result? {
        let i : UInt64 = booleanValue ? 1 : 0
        let value: UInt64 = PackedTermType.boolean.typedEmptyValue
        return value + i
    }
    
    private func pack(integer stringValue: String) -> Result? {
        guard let i = UInt64(stringValue) else { return nil }
        guard i < 0x00ffffffffffffff else { return nil }
        let value: UInt64 = PackedTermType.integer.typedEmptyValue
        return value + i
    }
    
    private func pack(int stringValue: String) -> Result? {
        guard let i = UInt64(stringValue) else { return nil }
        guard i <= 2147483647 else { return nil }
        let value: UInt64 = PackedTermType.int.typedEmptyValue
        return value + i
    }
    
    private func pack(date stringValue: String) -> Result? {
        let values = stringValue.components(separatedBy: "-").map { Int($0) }
        guard values.count == 3 else { return nil }
        if let y = values[0], let m = values[1], let d = values[2] {
            guard y <= 5000 else { return nil }
            let months  = 12 * y + m
            var value   = PackedTermType.date.typedEmptyValue
            value       += UInt64(months << 5)
            value       += UInt64(d)
            return value
        } else {
            return nil
        }
    }
    
    private func pack(dateTime term: Term) -> Result? {
        // ZZZZ ZZZY YYYY YYYY YYYY MMMM DDDD Dhhh hhmm mmmm ssss ssss ssss ssss
        guard let date = term.dateValue else {
            return nil
        }
        guard let tz = term.timeZone else {
            return nil
        }
        let calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents(in: utc, from: date)
        
        guard let _year = components.year,
            let _month = components.month,
            let _day = components.day,
            let _hours = components.hour,
            let _minutes = components.minute,
            let _seconds = components.second else { return nil }
        let year : UInt64 = UInt64(_year)
        let month : UInt64 = UInt64(_month)
        let day : UInt64 = UInt64(_day)
        let hours : UInt64 = UInt64(_hours)
        let minutes : UInt64 = UInt64(_minutes)
        let seconds : UInt64 = UInt64(_seconds)
        let msecs : UInt64   = seconds * 1_000
        let offsetSeconds = tz.secondsFromGMT()
        let tzSign : UInt64 = (offsetSeconds < 0) ? 1 : 0
        let offsetMinutes : UInt64 = UInt64(abs(offsetSeconds) / 60)
        let offset : UInt64  = offsetMinutes / 15

        // guard against overflow values
        guard offset >= 0 && offset < 0x7f else { return nil }
        guard year >= 0 && year < 0x1fff else { return nil }
        guard month >= 0 && month < 0xf else { return nil }
        guard day >= 0 && day < 0x1f else { return nil }
        guard hours >= 0 && hours < 0x1f else { return nil }
        guard minutes >= 0 && minutes < 0x3f else { return nil }
        guard seconds >= 0 && seconds < 0xffff else { return nil }

        var value   = PackedTermType.dateTime.typedEmptyValue
        value       |= (tzSign << 55)
        value       |= (offset << 49)
        value       |= (year << 36)
        value       |= (month << 32)
        value       |= (day << 27)
        value       |= (hours << 22)
        value       |= (minutes << 16)
        value       |= (msecs)
        
        return value
    }
    
    private func unpack(iri value: UInt64) -> Item? {
        switch value {
        case 1:
            return Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", type: .iri)
        case 2:
            return Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#List", type: .iri)
        case 3:
            return Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#Resource", type: .iri)
        case 4:
            return Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#first", type: .iri)
        case 5:
            return Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest", type: .iri)
        case 6:
            return Term(value: "http://www.w3.org/2000/01/rdf-schema#comment", type: .iri)
        case 7:
            return Term(value: "http://www.w3.org/2000/01/rdf-schema#label", type: .iri)
        case 8:
            return Term(value: "http://www.w3.org/2000/01/rdf-schema#seeAlso", type: .iri)
        case 9:
            return Term(value: "http://www.w3.org/2000/01/rdf-schema#isDefinedBy", type: .iri)
        case 256..<512:
            return Term(value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#_\(value-256)", type: .iri)
        default:
            return nil
        }
    }
    
    private func pack(iri: String) -> Result? {
        let mask    = PackedTermType.commonIRI.typedEmptyValue
        switch iri {
        case "http://www.w3.org/1999/02/22-rdf-syntax-ns#type":
            return mask + 1
        case "http://www.w3.org/1999/02/22-rdf-syntax-ns#List":
            return mask + 2
        case "http://www.w3.org/1999/02/22-rdf-syntax-ns#Resource":
            return mask + 3
        case "http://www.w3.org/1999/02/22-rdf-syntax-ns#first":
            return mask + 4
        case "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest":
            return mask + 5
        case "http://www.w3.org/2000/01/rdf-schema#comment":
            return mask + 6
        case "http://www.w3.org/2000/01/rdf-schema#label":
            return mask + 7
        case "http://www.w3.org/2000/01/rdf-schema#seeAlso":
            return mask + 8
        case "http://www.w3.org/2000/01/rdf-schema#isDefinedBy":
            return mask + 9
        case _ where iri.hasPrefix("http://www.w3.org/1999/02/22-rdf-syntax-ns#_"):
            let c = iri.components(separatedBy: "_")
            guard c.count == 2 else { return nil }
            guard let value = UInt64(c[1]) else { return nil }
            if value >= 0 && value < 256 {
                return mask + 0x100 + value
            }
        default:
            break
        }
        return nil
    }
}

