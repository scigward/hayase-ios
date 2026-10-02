//
//  JSONSerialization+Safe.swift
//  Hayase
//

import Foundation

extension JSONSerialization {
    /// `data(withJSONObject:)` raises an Objective-C exception, which neither `try` nor `try?` can
    /// catch, for an object that is not valid JSON: NaN or infinity, an Optional, a Date, a key that
    /// is not a string. This is nil for those instead.
    static func safeData(_ object: Any, options: WritingOptions = []) -> Data? {
        guard isValidJSONObject(object) else { return nil }
        return try? data(withJSONObject: object, options: options)
    }
}
