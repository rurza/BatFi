//
//  SystemChargeLimit.swift
//
//
//  Picking a value Apple's Manual Charge Limit will accept.
//

import Foundation

/// Rounding for Apple's Manual Charge Limit, which accepts only a short list of
/// values — measured as 80, 85, 90, 95, 100. Pure and free of PowerUI so the
/// decision can be reasoned about, and tested, without the private framework.
public enum SystemChargeLimit {
    /// The value to apply for a requested percentage, rounded **up** to the nearest
    /// accepted value.
    ///
    /// Up, never down. A limit exists to not be exceeded, so a request the mechanism
    /// cannot express has to err on the side of charging less than asked for: 55%
    /// becomes 80%, which is wrong but visible, where rounding down to nothing would
    /// charge the battery past the point the user chose. A request above the highest
    /// accepted value clamps to that value, the most the hardware can do.
    ///
    /// Returns `nil` when there are no accepted values to choose from — that means
    /// the accepted list could not be read, and the caller must report that rather
    /// than write a guess into a setting the user can see.
    public static func applicableLimit(for requested: Int, from available: [Int]) -> Int? {
        let sorted = available.sorted()
        guard let highest = sorted.last else { return nil }
        return sorted.first(where: { $0 >= requested }) ?? highest
    }
}
