//
//  InhibitWriteFailures.swift
//
//
//  How long "Inhibit Charging" is kept claiming a pause the SMC will not take.
//
//  On the backends that pause on demand the pause is an SMC inhibit, written on the pass
//  after the click, and shown from the click. A write that fails is retried by the next pass,
//  as it always was; one that keeps failing leaves the battery charging under "Charging
//  paused", so after a short run the pause is ended and the real state shows.
//
//  Here rather than in `ChargingManager` because `AppCore` has no test target.
//

import Foundation

public struct InhibitWriteFailures: Equatable, Sendable {
    /// Consecutive failed writes for one pause after which it is ended.
    public static let threshold = 3

    private var pause: UserTempChargingMode?
    private var count = 0

    public init() {}

    /// Records one pass's inhibit write for `pause`, and returns whether the pause is to end.
    public mutating func record(succeeded: Bool, for pause: UserTempChargingMode) -> Bool {
        if self.pause != pause {
            self.pause = pause
            count = 0
        }
        guard !succeeded else {
            count = 0
            return false
        }
        count += 1
        guard count >= Self.threshold else { return false }
        count = 0
        return true
    }
}
