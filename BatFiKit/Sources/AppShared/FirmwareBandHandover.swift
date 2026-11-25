//
//  FirmwareBandHandover.swift
//
//
//  Which band the app measures and names under `.firmwareRange`: the one the firmware was
//  actually handed, never merely the one asked for.
//
//  With sailing on, the app asks the helper for a band reaching down to the resume level.
//  The client can quietly send the one-value call in its place — a helper too old for the
//  range call, a version it cannot read, a range the helper already refused — and the
//  firmware then keeps today's band. Measuring and naming the asked-for band in that case
//  would say "on hold until below 70%" while the firmware resumes at 75, and count a battery
//  at 72% with a load the adapter cannot cover as held while the firmware is charging.
//
//  In `AppShared` because `AppCore` has no test target.
//

import Foundation
import Shared

public struct FirmwareBandHandover: Equatable, Sendable {
    /// What the helper was last told.
    private enum Told: Equatable, Sendable {
        /// The band down to `resumeLevel` went out.
        case range(limit: Int, resumeLevel: Int)
        /// The one-value call went out: today's band.
        case limitOnly
    }

    /// Nil until a call has gone out in this process.
    private var lastTold: Told?

    public init() {}

    /// Records a call that went out. `resumeLevel` is the one asked for, nil for the one-value
    /// call; `call` is the one the client reports actually sending.
    public mutating func record(limit: Int, resumeLevel: Int?, call: ChargeRangeCallPolicy.Call) {
        if let resumeLevel, call == .range {
            lastTold = .range(limit: limit, resumeLevel: resumeLevel)
        } else {
            lastTold = .limitOnly
        }
    }

    /// The resume level of the band to measure and name, or nil for today's band.
    ///
    /// The requested level only where exactly that band went out last. Sailing off (no
    /// request), a fallback to the one-value call, a band for other levels, and no call yet in
    /// this process all give today's band: a hold is never claimed that was not handed over.
    public func bandResumeLevel(limit: Int, requestedResumeLevel: Int?) -> Int? {
        guard let requestedResumeLevel,
              lastTold == .range(limit: limit, resumeLevel: requestedResumeLevel)
        else { return nil }
        return requestedResumeLevel
    }
}
