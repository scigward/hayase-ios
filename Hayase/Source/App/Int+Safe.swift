//
//  Int+Safe.swift
//  Hayase
//

import Foundation

extension Int {
    /// A truncating conversion that cannot trap, for values that come from the network, an
    /// extension or a player: `Int(_:)` traps on NaN, infinity and anything out of range. NaN reads
    /// as 0 and the rest clamps to ±1e15, which leaves room to add and multiply the result.
    init(safe value: Double) {
        guard !value.isNaN else { self = 0; return }
        self = Int(max(-1e15, min(1e15, value)))
    }
}
