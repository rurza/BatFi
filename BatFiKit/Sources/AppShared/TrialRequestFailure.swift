//
//  TrialRequestFailure.swift
//  BatFi
//
//  Why asking the licence server for a trial did not give one.
//

import Foundation
import L10n

/// Asking the licence server for a trial failed. Nothing is stored after any of these.
public enum TrialRequestFailure: LocalizedError, Equatable, Sendable {
    /// Too many new trials from this network today (HTTP 429). Reporting a trial that already
    /// exists is never throttled.
    case throttled
    /// The server refused the request (HTTP 400): malformed, unknown app, no trial offered, or
    /// a bad fingerprint.
    case refused
    /// Anything else: another status, no network, a timeout, an answer that does not verify
    /// or decode or is not this Mac's, or a serial that cannot be read.
    case unavailable

    /// The failure an HTTP status is, or nil for 200.
    public init?(status: Int) {
        switch status {
        case 200: return nil
        case 429: self = .throttled
        case 400: self = .refused
        default: self = .unavailable
        }
    }

    /// Any error met while asking: a `TrialRequestFailure` stays what it is, everything else
    /// is `.unavailable`.
    public init(_ error: any Error) {
        self = error as? TrialRequestFailure ?? .unavailable
    }

    public var errorDescription: String? {
        switch self {
        case .throttled: L10n.Trial.errorThrottled
        case .refused, .unavailable: L10n.Trial.errorNotStarted
        }
    }
}
