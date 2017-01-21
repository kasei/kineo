//
//  Date.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 12/30/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation

@available(OSX 10.12, *)
public class W3CDTFLocatedDateFormatter : ISO8601DateFormatter {
    public struct LocatedDate {
        var date: Date
        var timezone: TimeZone
    }
    
    public func locatedDate(from string: String) -> LocatedDate? {
        guard let date = super.date(from: string) else { return nil }
        var seconds = 0
        if !string.hasSuffix("Z") {
            let tz = string.substring(from: string.index(string.endIndex, offsetBy: -6))
            let parts = tz.substring(from: tz.index(after: tz.startIndex)).components(separatedBy: ":")
            guard parts.count == 2 else { return nil }
            guard let hours = Int(parts[0]) else { return nil }
            guard let minutes = Int(parts[1]) else { return nil }
            seconds = 60 * ((60 * hours) + minutes)
            if tz.hasPrefix("-") {
                seconds = seconds * -1
            }
        }
        guard let timezone = TimeZone(secondsFromGMT: seconds) else { return nil }
        return LocatedDate(date: date, timezone: timezone)
    }
}
