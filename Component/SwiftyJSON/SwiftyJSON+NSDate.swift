//
//  SwiftyJSON+NSDate.swift
//  FinalProject
//
//  Created by Tieria C.Monk on 8/12/16.
//

import Foundation
import SwiftyJSON

extension JSON {
    public var date: Date? {
        get {
            if let str = self.string {
                return JSON.jsonDateFormatter.date(from: str)
            }
            return nil
        }
    }

    private static let jsonDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        return fmt
    }()
}