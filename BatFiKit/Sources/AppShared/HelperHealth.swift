//
//  HelperHealth.swift
//  BatFi
//
//  The app's answer to "is the helper actually working?".
//
//  This exists because `SMAppService.Status` answers a different question than the one the
//  app kept asking of it. `.enabled` means a Background Task Management record exists — not
//  that the helper is running, reachable, or able to answer XPC. A wedged record reads
//  `.enabled` forever while every call fails at lookup, which is the state that previously
//  had no name and so could not be acted on.
//

import Foundation

/// A mirror of `SMAppService.Status`, so policy can be expressed and tested without
/// importing ServiceManagement or constructing framework enums in tests.
public enum HelperServiceStatus: Sendable, Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

public enum HelperHealth: Sendable, Equatable {
    /// Not yet determined. Distinct from `.healthy` so the first observation always verifies.
    case unknown
    /// A ping succeeded. The only state that may be treated as working.
    case healthy
    case degraded(Reason)

    public enum Reason: Sendable, Equatable {
        case notRegistered
        case requiresApproval
        /// Registered and reported `.enabled`, but unreachable over XPC. The wedged case.
        case registeredButUnreachable
        case installFailed(String)
        /// Reachable, correctly signed, and belonging to a *different* copy of the app.
        /// The one degraded state that looks perfectly healthy from every other angle:
        /// status is `.enabled`, pings succeed, and the helper doing the work is simply
        /// not this app's. See `HelperOwnership`.
        case foreignHelper(HelperOwnershipConflict)
    }

    public var isHealthy: Bool { self == .healthy }
}
