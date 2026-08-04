//
//  PowerUICharging.swift
//
//
//  Created by Adam Różyński on 12/05/2026.
//

import Foundation
import os
import Shared

actor PowerUICharging {
    static let shared = PowerUICharging()

    private let logger = Logger(subsystem: Constant.helperBundleIdentifier, category: "PowerUI Charging")
    private let client: AnyObject?
    private let clientClass: AnyClass?

    private var renewalTask: Task<Void, Never>?
    private var lastOverrideValue: UInt8 = 0

    /// The user's System Settings value, captured before BatFi first changed the limit
    /// by **any** route — the override path as well as the adopt path. Written in exactly
    /// one place, `captureUserLimitIfNeeded()`, and cleared in exactly one, a successful
    /// restore in `releaseSystemLimit()`.
    private var userSystemLimitSnapshot: Int?

    /// Whether BatFi has written its own value with `setMCLLimit:` and therefore owes the
    /// user a restore. Deliberately separate from the snapshot: the snapshot is now taken
    /// on the override path too, and an override must not make `releaseSystemLimit()`
    /// write — Apple restores the saved value when the override expires, and a write there
    /// would put an SMC-backend BatFi in the business of setting the limit it is supposed
    /// to be getting out of the way of.
    private var hasAdoptedSystemLimit = false

    /// Whether PowerUI's `clearMCLOverride` has actually been invoked in this process.
    ///
    /// An override outlives the process that set it, so a fresh BatFi cannot know from its
    /// own state whether one is outstanding. Invoking the clear is the only thing that
    /// retires one; until that has happened, a limit read back from PowerUI may be an
    /// earlier BatFi's write rather than the user's value, and must not be snapshotted.
    private var overrideClearInvoked = false

    private static let renewalInterval: Duration = .seconds(60)

    private init() {
        let frameworkPath = "/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI"
        guard dlopen(frameworkPath, RTLD_NOW | RTLD_GLOBAL) != nil else {
            self.client = nil
            self.clientClass = nil
            return
        }

        guard let cls = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type,
              let allocated = cls.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let initialized = allocated.perform(
                NSSelectorFromString("initWithClientName:"),
                with: "BatFi" as NSString
              )?.takeUnretainedValue() else {
            self.client = nil
            self.clientClass = nil
            return
        }

        self.client = initialized
        self.clientClass = cls
    }

    var isAvailable: Bool { client != nil && clientClass != nil }

    /// Whether this machine's PowerUI reports Manual Charge Limit support. Asking the
    /// framework is strictly better than inferring it from the macOS version.
    var isMCLSupported: Bool {
        guard let client, let clientClass else { return false }
        let selector = NSSelectorFromString("isMCLSupported")
        guard let method = class_getInstanceMethod(clientClass, selector) else { return false }
        typealias Query = @convention(c) (AnyObject, Selector) -> ObjCBool
        let query = unsafeBitCast(method_getImplementation(method), to: Query.self)
        return query(client, selector).boolValue
    }

    /// Values Apple accepts, measured as (80, 85, 90, 95, 100). Queried rather than
    /// hardcoded so a future macOS that widens the range works without a code change.
    func availableLimits() -> [Int] {
        guard let client, let clientClass else { return [] }
        let selector = NSSelectorFromString("availableChargeLimitsWithError:")
        guard let method = class_getInstanceMethod(clientClass, selector) else { return [] }
        typealias Query = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> NSArray?
        let query = unsafeBitCast(method_getImplementation(method), to: Query.self)
        var error: NSError?
        guard let values = query(client, selector, &error) as? [NSNumber], error == nil else { return [] }
        return values.map(\.intValue).sorted()
    }

    /// The user's own System Settings value. Note the selector returns an unsigned
    /// char, not an object.
    func currentSystemLimit() -> Int? {
        guard let client, let clientClass else { return nil }
        let selector = NSSelectorFromString("getMCLLimitWithError:")
        guard let method = class_getInstanceMethod(clientClass, selector) else { return nil }
        typealias Query = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> UInt8
        let query = unsafeBitCast(method_getImplementation(method), to: Query.self)
        var error: NSError?
        let value = query(client, selector, &error)
        guard error == nil else { return nil }
        return Int(value)
    }

    var hasActiveOverride: Bool { lastOverrideValue != 0 }

    /// Temporarily overrides the system Manual Charge Limit (System Settings → Battery → Charging).
    /// Apple stores the user's MCL in `MCLSavedTargetSoC` and restores it once the override expires.
    /// Use 100 to fully release the system limit so BatFi's SMC inhibit can act unimpeded.
    func overrideMCLTarget(_ targetSoC: UInt8) throws {
        // Before the write, never after. This is BatFi's earliest touch of the MCL under
        // an SMC backend, and once the override is in place every read of the limit is
        // BatFi's own number. Best-effort: a failed capture must not stop the override,
        // because releasing Apple's limit is what lets the SMC inhibit act at all — and a
        // capture that did not happen is simply retried the next time anything needs one.
        captureUserLimitIfNeeded()
        try invokeOverride(targetSoC)
        lastOverrideValue = targetSoC
        startRenewalTask()
    }

    /// Cancels the renewal task and attempts to clear the active override so the system snaps
    /// back to the user's saved MCL value. Client-side selector may not exist on every build —
    /// if it doesn't, the override still self-expires via `MCLOverridenUntilDate`.
    func clearMCLOverride() {
        cancelRenewalTask()
        lastOverrideValue = 0

        guard let client, let clientClass else { return }

        let selector = NSSelectorFromString("clearMCLOverride")
        guard let method = class_getInstanceMethod(clientClass, selector) else {
            // `overrideClearInvoked` deliberately stays false: nothing retired an override that
            // an earlier BatFi may have left behind, so a limit read now cannot be told
            // apart from that process's write and must not be snapshotted as the user's.
            logger.notice("clearMCLOverride selector not exposed on client; relying on natural expiry")
            return
        }

        typealias Clearer = @convention(c) (AnyObject, Selector) -> Void
        let clearer = unsafeBitCast(method_getImplementation(method), to: Clearer.self)
        clearer(client, selector)
        // The one fact a snapshot capture needs: any override outstanding on this machine,
        // including one from a BatFi that crashed while holding it, has now been told to go.
        overrideClearInvoked = true
        logger.notice("PowerUI MCL override cleared")
    }

    func mclStatus() -> MCLStatus {
        MCLStatus(
            supported: isAvailable,
            batFiHasActiveOverride: hasActiveOverride,
            lastOverrideValue: hasActiveOverride ? Int(lastOverrideValue) : nil
        )
    }

    /// Drives Apple's Manual Charge Limit. Only for the `.systemChargeLimit` backend —
    /// every other backend releases the system limit instead of setting it, and the two
    /// must never run together or the renewal task will fight this setter.
    func adoptSystemLimit(_ percentage: Int) throws {
        guard isAvailable else { throw PowerUIChargingError.frameworkUnavailable }

        let available = availableLimits()
        guard !available.isEmpty else {
            throw PowerUIChargingError.availableLimitsUnavailable
        }
        guard available.contains(percentage) else {
            throw PowerUIChargingError.limitOutOfRange(requested: percentage, available: available)
        }

        // Gate the write on a confirmed read: if we cannot learn the user's current value,
        // we must not overwrite it, because we would then have no correct value to restore.
        // Leaving the snapshot `nil` means "never captured and never written" — the next
        // call retries the capture cleanly.
        guard captureUserLimitIfNeeded() else {
            throw PowerUIChargingError.snapshotUnavailable
        }

        try adoptSystemLimitWithoutSnapshotting(percentage)
        hasAdoptedSystemLimit = true
    }

    /// Puts the user's own value back. Safe to call when nothing was ever adopted — and a
    /// no-op in that case *by design*: a snapshot taken on the override path records the
    /// user's value without BatFi ever having written one, and writing it back would make
    /// an SMC-backend BatFi a setter of the very limit it exists to get out of the way of.
    /// Only an adoption owes a restore.
    ///
    /// The snapshot is only cleared once the restore write actually succeeds, so a failed
    /// attempt (transient shutdown/backend-switch hiccup) can be retried later instead of
    /// silently forgetting the value there was to restore.
    func releaseSystemLimit() {
        guard hasAdoptedSystemLimit, let snapshot = userSystemLimitSnapshot else { return }
        do {
            try adoptSystemLimitWithoutSnapshotting(snapshot)
            hasAdoptedSystemLimit = false
            userSystemLimitSnapshot = nil
            logger.notice("Restored user's system charge limit to \(snapshot, privacy: .public)%")
        } catch {
            logger.error("Could not restore the user's system charge limit; will retry on next release: \(error, privacy: .public)")
        }
    }

    // MARK: - Private

    /// Records the user's own limit, once, at the earliest point BatFi touches the MCL by
    /// any route. Returns whether a snapshot is now held.
    ///
    /// The whole point is that the read below can never observe a BatFi write:
    ///
    /// * It runs before the write on both writing paths — ahead of
    ///   `temporarilyOverrideMCLTargetSoC:` in `overrideMCLTarget(_:)`, and ahead of
    ///   `setMCLLimit:` in `adoptSystemLimit(_:)`.
    /// * It clears any outstanding override first, so an override left behind by an
    ///   earlier BatFi that crashed while holding one is retired before the read.
    /// * It refuses outright unless both of those are established —
    ///   `SystemLimitSnapshot.readIsTrustworthy` — because a missing snapshot is retried
    ///   next pass, while a wrong one is written into a setting the user can see and then
    ///   cannot get back.
    @discardableResult
    private func captureUserLimitIfNeeded() -> Bool {
        if userSystemLimitSnapshot != nil { return true }

        // Idempotent, and only reached while no snapshot is held — so this costs one
        // selector call on the first touch, not one per status update.
        clearMCLOverride()

        guard SystemLimitSnapshot.readIsTrustworthy(
            hasActiveOverride: hasActiveOverride,
            overrideRetired: overrideClearInvoked
        ) else {
            logger.error("Refusing to record the user's system charge limit: an MCL override may still be outstanding")
            return false
        }

        guard let current = currentSystemLimit() else {
            logger.error("Could not read the user's system charge limit; not recording one")
            return false
        }

        userSystemLimitSnapshot = current
        logger.notice("Captured user's system charge limit: \(current, privacy: .public)%")
        return true
    }

    /// Raw `setMCLLimit:error:` call with no snapshotting. `adoptSystemLimit` and
    /// `releaseSystemLimit` both funnel through here so restoring the user's value can
    /// never re-capture it as a new snapshot.
    private func adoptSystemLimitWithoutSnapshotting(_ percentage: Int) throws {
        guard let client, let clientClass else {
            throw PowerUIChargingError.frameworkUnavailable
        }

        let selector = NSSelectorFromString("setMCLLimit:error:")
        guard let method = class_getInstanceMethod(clientClass, selector) else {
            throw PowerUIChargingError.selectorUnavailable("setMCLLimit:error:")
        }

        typealias Setter = @convention(c) (AnyObject, Selector, UInt8, AutoreleasingUnsafeMutablePointer<NSError?>?) -> ObjCBool
        let setter = unsafeBitCast(method_getImplementation(method), to: Setter.self)

        var error: NSError?
        let success = setter(client, selector, UInt8(percentage), &error).boolValue

        if let error {
            logger.error("setMCLLimit returned error: \(error, privacy: .public)")
            throw PowerUIChargingError.apiCallFailed(error)
        }

        if !success {
            logger.error("setMCLLimit returned false without error")
            throw PowerUIChargingError.apiCallReturnedFalse
        }

        logger.notice("System charge limit set to \(percentage, privacy: .public)%")
    }

    private func invokeOverride(_ targetSoC: UInt8) throws {
        guard let client, let clientClass else {
            throw PowerUIChargingError.frameworkUnavailable
        }

        let selector = NSSelectorFromString("temporarilyOverrideMCLTargetSoC:error:")
        guard let method = class_getInstanceMethod(clientClass, selector) else {
            throw PowerUIChargingError.selectorUnavailable("temporarilyOverrideMCLTargetSoC:error:")
        }

        typealias Setter = @convention(c) (AnyObject, Selector, UInt8, AutoreleasingUnsafeMutablePointer<NSError?>?) -> ObjCBool
        let setter = unsafeBitCast(method_getImplementation(method), to: Setter.self)

        var error: NSError?
        let success = setter(client, selector, targetSoC, &error).boolValue

        if let error {
            logger.error("temporarilyOverrideMCLTargetSoC returned error: \(error, privacy: .public)")
            throw PowerUIChargingError.apiCallFailed(error)
        }

        if !success {
            logger.error("temporarilyOverrideMCLTargetSoC returned false without error")
            throw PowerUIChargingError.apiCallReturnedFalse
        }

        logger.notice("PowerUI MCL target overridden to \(targetSoC, privacy: .public)%")
    }

    private func startRenewalTask() {
        renewalTask?.cancel()
        renewalTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.renewalInterval)
                guard !Task.isCancelled, let self else { return }
                await self.renewOverrideIfNeeded()
            }
        }
    }

    private func cancelRenewalTask() {
        renewalTask?.cancel()
        renewalTask = nil
    }

    private func renewOverrideIfNeeded() {
        let value = lastOverrideValue
        guard value != 0 else { return }
        do {
            try invokeOverride(value)
        } catch {
            logger.warning("MCL override renewal failed: \(error, privacy: .public)")
        }
    }
}

enum PowerUIChargingError: Error, CustomStringConvertible {
    case frameworkUnavailable
    case selectorUnavailable(String)
    case apiCallFailed(Error)
    case apiCallReturnedFalse
    case limitOutOfRange(requested: Int, available: [Int])
    case availableLimitsUnavailable
    case snapshotUnavailable

    var description: String {
        switch self {
        case .frameworkUnavailable: return "PowerUI framework unavailable"
        case .selectorUnavailable(let name): return "PowerUI selector unavailable: \(name)"
        case .apiCallFailed(let err): return "PowerUI API failed: \(err)"
        case .apiCallReturnedFalse: return "PowerUI API returned false"
        case .limitOutOfRange(let requested, let available):
            return "Requested system charge limit \(requested)% is not one of the available limits \(available)"
        case .availableLimitsUnavailable:
            return "Could not read the accepted system charge limit values from PowerUI, so the requested value could not be validated"
        case .snapshotUnavailable:
            return "BatFi will not change the system charge limit because it has no trustworthy record of the user's current value to restore later"
        }
    }
}
