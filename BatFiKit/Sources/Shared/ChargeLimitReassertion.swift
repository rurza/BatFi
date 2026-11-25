//
//  ChargeLimitReassertion.swift
//
//
//  What a charge-limit request waiting on powerd should do on each poll tick.
//
//  Here, and not inside the actor that runs the loop, for the reason
//  `FirmwareRangeKeyShape` is here: `Server` has no test target and `Shared` is reachable
//  from the one that exists. The decision below was wrong in a way no type checker or
//  reviewer caught, and it took a log capture of two live requests to see it.
//

import Foundation

/// A single request's identity. Monotonic, so "newer" is decidable without a clock and
/// without comparing the limits themselves — two requests for different limits are the
/// interesting case, and two for the same limit never race (the caller joins them).
public typealias ChargeLimitRequestID = UInt64

public enum ChargeLimitReassertion {
    /// What the waiting request should do now.
    public enum Step: Equatable, Sendable {
        /// A newer request has taken over. Stop — and in particular do **not** write.
        case superseded
        /// powerd is enforcing this request. Done.
        case adopted
        /// The request is no longer in the preference domain, so PowerUIAgent has nothing
        /// to read. Write it again.
        case rewriteRequest
        /// Written, not yet adopted. Adoption is slow; wait.
        case keepWaiting
    }

    /// - Parameters:
    ///   - requested: the limit this request is waiting on.
    ///   - requestID: this request's identity.
    ///   - latestRequestID: the newest request the mechanism has seen.
    ///   - enforcedLimit: the `soclimit` powerd currently holds, or nil for no policy.
    ///   - writtenRequest: the value currently in the preference domain, or nil.
    public static func step(
        requested: Int,
        requestID: ChargeLimitRequestID,
        latestRequestID: ChargeLimitRequestID,
        enforcedLimit: Int?,
        writtenRequest: Int?
    ) -> Step {
        // First, and ahead of adoption on purpose. A superseded request can be looking at
        // its own value in force — powerd adopted the stale 65% nine seconds after adopting
        // 70% — and reporting that as success records a limit the user has already moved
        // away from as the one applied. Nothing this request could see makes it the current
        // answer any more.
        guard requestID == latestRequestID else { return .superseded }
        if enforcedLimit == requested { return .adopted }
        if writtenRequest != requested { return .rewriteRequest }
        return .keepWaiting
    }
}
