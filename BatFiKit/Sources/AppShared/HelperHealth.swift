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
        ///
        /// Interim rather than final: it means the helper is not answering *yet*, and the
        /// app still has an unregister/register attempt to spend on it. What that attempt
        /// settles is which of the two terminal states this becomes — `.healthy`, or
        /// `.staleRegistrationNeedsUserReset` when re-registering changes nothing.
        case registeredButUnreachable
        /// Unreachable, and a re-registration from this app has already run and made no
        /// difference — so nothing this app can do will fix it.
        ///
        /// The Background Task Management record carries a cached launch constraint (an
        /// LWCR) derived from the bundle that registered it. When that bundle is gone —
        /// a copy run once from a disk image or `~/Downloads` and then deleted, a build
        /// directory that has since been cleaned — the constraint can no longer be
        /// resolved, and every spawn dies before the helper runs a single instruction:
        ///
        ///     Requesting repair LWCR update: runs=2
        ///     Service could not initialize: Unable to get updated LWCR for
        ///         (<uuid>, (null), 0), error 0x3 - No such process
        ///     xpcproxy exited due to exit(78)
        ///     Service only ran for 0 seconds. Pushing respawn out by 10 seconds
        ///
        /// `SMAppService.unregister()` does not clear this. It marks the record disabled and
        /// leaves the item — and its poisoned constraint — in place, so the `register()`
        /// that follows logs `registerLaunchItem: found existing item: uuid=<the same one>`
        /// and returns *success* while changing nothing. The app is told the repair worked
        /// and the helper still never starts.
        ///
        /// What does clear it is `invalidateLaunchItem`, which destroys the record outright
        /// and is only reachable at uid 0 — from System Settings, when the user turns the
        /// item off. The next `register()` then mints a fresh record with a constraint that
        /// resolves. That is why this state names the user's toggle as the remedy instead of
        /// sending them somewhere to watch the app fail again.
        case staleRegistrationNeedsUserReset
        case installFailed(String)
        /// Reachable, correctly signed, and belonging to a *different* copy of the app.
        /// The one degraded state that looks perfectly healthy from every other angle:
        /// status is `.enabled`, pings succeed, and the helper doing the work is simply
        /// not this app's. See `HelperOwnership`.
        case foreignHelper(HelperOwnershipConflict)
    }

    public var isHealthy: Bool { self == .healthy }
}
