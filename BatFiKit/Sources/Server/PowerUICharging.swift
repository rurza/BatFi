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
    /// earlier BatFi's write rather than the user's value, and must not be snapshotted —
    /// but only on a build where BatFi could have written one at all, see `canWriteOverride`.
    private var overrideClearInvoked = false

    /// Whether the snapshot refusal has already been surfaced.
    ///
    /// By the time the refusal is decided, both of its inputs are properties of this build
    /// of PowerUI rather than of the moment, so the answer cannot change while the process
    /// lives. Logging it per call would repeat one unchanging sentence on every status
    /// update, forever, which is exactly the noise it is warning about.
    private var hasReportedSnapshotRefusal = false

    /// Whether a snapshot has actually been refused, as opposed to merely being refusable.
    ///
    /// Recorded rather than recomputed on demand, and that distinction matters. Asking
    /// `SystemLimitSnapshot.readIsTrustworthy` at an arbitrary moment answers "no" before
    /// anything has touched the MCL at all — `overrideClearInvoked` is still false — even
    /// though the first real write clears the override first and then succeeds. Only a
    /// refusal that happened is worth telling the user about.
    private var snapshotRefused = false

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

    /// Whether BatFi is able to write an MCL override on this machine at all — that is,
    /// whether this build of PowerUI exposes the selector `overrideMCLTarget(_:)` writes
    /// through. It is a property of the framework, so it is the same answer for every
    /// BatFi process that has ever run here.
    ///
    /// Load-bearing for the snapshot rule: if BatFi cannot write an override, no override
    /// of BatFi's can be standing in front of a limit read, in this process or in one that
    /// died holding one, and there is nothing for `clearMCLOverride` to retire.
    private var canWriteOverride: Bool {
        guard client != nil, let clientClass else { return false }
        let selector = NSSelectorFromString("temporarilyOverrideMCLTargetSoC:error:")
        return class_getInstanceMethod(clientClass, selector) != nil
    }

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
            // an earlier BatFi may have left behind. That only blocks a snapshot on a build
            // that also exposes the *override* selector — where such a write is possible in
            // the first place — which is what `canWriteOverride` decides.
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
            // What every reader of this field actually asks — does this machine have a
            // Manual Charge Limit — not merely whether the framework loaded. Those are two
            // questions, and `isAvailable` answers the wrong one: it is true on every Mac
            // that can dlopen PowerUI, including all the ones with no MCL at all.
            // `SMCService.mclStatus()` gating on `isMCLSupported` before delegating here is
            // what kept the delivered value honest; now it is belt and braces rather than
            // the only thing standing between a direct caller and a false claim.
            supported: isMCLSupported,
            batFiHasActiveOverride: hasActiveOverride,
            lastOverrideValue: hasActiveOverride ? Int(lastOverrideValue) : nil,
            // The system's own percentage, so the app can stop guessing at it. The
            // conflict warning in the Charging pane used to key on "BatFi holds no
            // override", a proxy for this number that was adopted only because the number
            // did not cross the boundary — and that fired on every Mac where BatFi had
            // simply not written an override yet, whatever the limit really was.
            systemLimit: currentSystemLimit(),
            snapshotRefused: snapshotRefused
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
    /// * Where neither of those can be established it refuses —
    ///   `SystemLimitSnapshot.readIsTrustworthy` — because a missing snapshot is retried
    ///   next pass, while a wrong one is written into a setting the user can see and then
    ///   cannot get back.
    ///
    /// The refusal is narrowed to the one build shape where a BatFi override is actually
    /// possible and cannot be retired on demand: override selector present, clear selector
    /// absent. On a build with no override selector at all there is nothing that could
    /// have poisoned the read, so refusing would protect nothing and would disable the
    /// whole `.systemChargeLimit` backend for the life of the process.
    @discardableResult
    private func captureUserLimitIfNeeded() -> Bool {
        if userSystemLimitSnapshot != nil { return true }

        // Idempotent, and only reached while no snapshot is held — so this costs one
        // selector call on the first touch, not one per status update.
        clearMCLOverride()

        guard SystemLimitSnapshot.readIsTrustworthy(
            hasActiveOverride: hasActiveOverride,
            canWriteOverride: canWriteOverride,
            overrideRetired: overrideClearInvoked
        ) else {
            // Surfaced to the app on every status read, unlike the log line below: the
            // user needs the pane to keep saying why no limit is in force, not to have
            // said it once into a log they will never open.
            snapshotRefused = true
            // Said once, not per poll: both inputs are fixed for the life of the process by
            // the time we get here — `clearMCLOverride()` above has already zeroed this
            // process's override, so what is left is which selectors this build exposes.
            if !hasReportedSnapshotRefusal {
                hasReportedSnapshotRefusal = true
                logger.error("""
                BatFi will not set a system charge limit on this Mac: it cannot first record the \
                user's own value. This build of PowerUI can set an MCL override but exposes no way \
                to clear one, so an override left behind by an earlier BatFi cannot be retired and \
                a limit read now could be that write rather than the user's setting. Restoring it \
                on quit would overwrite a value the user cannot get back, so the limit is left alone.
                """)
            }
            return false
        }

        guard let current = currentSystemLimit() else {
            logger.error("Could not read the user's system charge limit; not recording one")
            return false
        }

        userSystemLimitSnapshot = current
        // Whatever was refused before, it is not being refused now, and the pane must stop
        // saying so. Cheap insurance rather than a reachable state today: the refusal's
        // inputs are fixed for the life of the process by the time it is decided.
        snapshotRefused = false
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
