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
    ///
    /// **Process-local, and that is load-bearing, not an accident.** `SystemLimitSnapshot`'s
    /// rule guards against BatFi *overrides* only; an adopt from a process that died without
    /// restoring is trusted by the next process, which is harmless precisely because that
    /// process has no record of the user's earlier value to overwrite. Persisting this
    /// across launches turns that into a data-loss path — see the scope note on
    /// `SystemLimitSnapshot`, which has to be widened first.
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
    /// but only where BatFi could have written one at all, see `canWriteOverride` and
    /// `ChargeBackend.writesMCLOverride`.
    ///
    /// Measured on shipping macOS: `PowerUISmartChargeClient` exposes
    /// `temporarilyOverrideMCLTargetSoC:error:` and **no** clear selector of any spelling,
    /// so on those builds this stays false for the life of the process.
    private var overrideClearInvoked = false

    /// Whether *this* process has written an override that nothing has retired since.
    ///
    /// Deliberately not `hasActiveOverride`, which only says whether the renewal task is
    /// still holding one up. Those two came apart the moment a clear could find no
    /// selector to call: that path stops the renewals and zeroes `lastOverrideValue`, but
    /// the override it could not clear stands until `MCLOverridenUntilDate` passes. Reading
    /// the limit in that window returns BatFi's number, so it is this flag — not the
    /// renewal state — that the snapshot rule has to consult.
    ///
    /// Set by every **attempted** override write — before the selector is called, and not
    /// rolled back when the call reports failure — and cleared only where the clear
    /// selector actually ran.
    ///
    /// Attempted rather than succeeded on purpose. The flag's only job is to block a
    /// snapshot that might be reading BatFi's own number, and `temporarilyOverrideMCLTargetSoC:`
    /// is a private API whose failure semantics nobody has measured: a call that applied the
    /// override but returned an error or `false` would, if the flag were set afterwards,
    /// leave BatFi believing no override stands and free to record one as the user's saved
    /// limit. "We may have written one" is the only safe reading, and its cost is a refused
    /// snapshot that the next pass retries.
    private var overrideWriteUnretired = false

    /// Whether the snapshot refusal has already been surfaced.
    ///
    /// By the time the refusal is decided, its inputs are properties of this build of
    /// PowerUI and of a backend cached against a firmware token that does not move, rather
    /// than of the moment. Logging it per call would repeat one unchanging sentence on
    /// every status update, forever, which is exactly the noise it is warning about.
    private var hasReportedSnapshotRefusal = false

    /// Whether the absent clear selector has already been reported.
    ///
    /// Same reasoning, and now on a hot path: whether this build of PowerUI exposes
    /// `clearMCLOverride` is fixed for the life of the process (absent on every shipping
    /// macOS measured), while under `.systemChargeLimit` `reconcileMCLOwnership` calls
    /// `clearMCLOverride()` on every `setChargingMode` — roughly once a minute, forever.
    /// One unchanging sentence a minute, in the logs of exactly the machines whose bug
    /// reports matter most.
    private var hasReportedMissingClearSelector = false

    /// Whether a snapshot has actually been refused, as opposed to merely being refusable.
    ///
    /// Recorded rather than recomputed on demand, and that distinction matters:
    /// `SystemLimitSnapshot.readIsTrustworthy` needs the backend in force, which this actor
    /// is told at the call rather than holding. Only a refusal that happened is worth
    /// telling the user about.
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

    /// Whether Apple's charge limit is currently switched **on**.
    ///
    /// Load-bearing for the sub-80 path: powerd only honours a `ChargeCtrlPolicy` while the
    /// feature is enabled, and re-enabling it when it is already on makes powerd rewrite its
    /// own policy — which is drift BatFi would then "correct", writing again, forever.
    var isMCLCurrentlyEnabled: Bool {
        guard let client, let clientClass else { return false }
        let selector = NSSelectorFromString("isMCLCurrentlyEnabled:")
        guard let method = class_getInstanceMethod(clientClass, selector) else { return false }
        typealias Query = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> ObjCBool
        let query = unsafeBitCast(method_getImplementation(method), to: Query.self)
        var error: NSError?
        let value = query(client, selector, &error).boolValue
        return error == nil && value
    }

    /// Switches Apple's charge limit **on** without setting a value.
    ///
    /// Deliberately not `adoptSystemLimit`, and the difference is the whole point: that one
    /// calls `setMCLLimit:`, which makes powerd rewrite its own policy to the value passed —
    /// the write-fight. `enableMCL:` takes no value at all (`B24@0:8^@16` — BOOL return plus
    /// `NSError**`), so it can only make PowerUIAgent re-evaluate, which is precisely what
    /// the sub-80 path needs after writing the preference that carries the number.
    ///
    /// **Not** required to make a sub-80 limit take: the preference write plus the defaults
    /// notification is sufficient on its own, measured. An earlier reading of this as
    /// mandatory was an artifact of a six-second poll — PowerUIAgent can take tens of seconds
    /// to adopt, so the call that happened to precede a late adoption looked like its cause.
    ///
    /// Kept, and called, for the one case that is a genuine precondition: Apple's charge
    /// limit switched off entirely, where there is nothing to honour a policy at all. Gated
    /// on `isMCLCurrentlyEnabled` so a settled machine never reaches it.
    @discardableResult
    func enableMCL() -> Bool {
        guard let client, let clientClass else { return false }
        let selector = NSSelectorFromString("enableMCL:")
        guard let method = class_getInstanceMethod(clientClass, selector) else {
            logger.error("enableMCL: selector not exposed on client")
            return false
        }
        typealias Invoke = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> ObjCBool
        let invoke = unsafeBitCast(method_getImplementation(method), to: Invoke.self)
        var error: NSError?
        let succeeded = invoke(client, selector, &error).boolValue
        if succeeded {
            logger.notice("Apple's charge limit switched on")
        } else {
            logger.error("enableMCL: failed: \(error?.localizedDescription ?? "no error", privacy: .public)")
        }
        return succeeded
    }

    /// Values Apple accepts, measured as (80, 85, 90, 95, 100). Queried rather than
    /// hardcoded so a future macOS that widens the range works without a code change.
    ///
    /// The floor is corroborated against the setter itself, not just read off this list:
    /// on macOS 27 (26A5388g) `setMCLLimit:error:` refuses 50 with
    /// `PowerUISmartChargingErrorDomain` code 4 while accepting 80 and 85, and
    /// `temporarilyOverrideMCLTargetSoC:error:` refuses 75 with the same code. So this list
    /// does describe the accepted range — but it is no longer *trusted* to, because a list
    /// and a setter can disagree and only one of them decides. `adoptSystemLimit` asks the
    /// setter and falls back to this list when refused.
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
    ///
    /// `backend` is the backend the caller resolved, passed rather than assumed so the
    /// snapshot rule sees the machine's real answer. By construction it is an SMC backend
    /// — this is only reached from that arm of `reconcileMCLOwnership` — which is exactly
    /// the case where the rule must keep refusing.
    func overrideMCLTarget(_ targetSoC: UInt8, under backend: ChargeBackend) throws {
        // Before the write, never after. This is BatFi's earliest touch of the MCL under
        // an SMC backend, and once the override is in place every read of the limit is
        // BatFi's own number. Best-effort: a failed capture must not stop the override,
        // because releasing Apple's limit is what lets the SMC inhibit act at all — and a
        // capture that did not happen is simply retried the next time anything needs one.
        captureUserLimitIfNeeded(under: backend)
        try invokeOverride(targetSoC)
        lastOverrideValue = targetSoC
        startRenewalTask()
    }

    /// Cancels the renewal task and attempts to clear the active override so the system snaps
    /// back to the user's saved MCL value.
    ///
    /// The clear selector does not exist on shipping macOS — measured on 26.6, where the
    /// override selector is present and no clear of any spelling is — so on those builds
    /// this call **retires nothing**. What it still does is real and is the only thing
    /// ending the override there: cancelling the renewal task stops BatFi re-arming the
    /// override every 60 seconds, after which it lapses on its own at
    /// `MCLOverridenUntilDate`. Callers that read the limit in that window must consult
    /// `overrideWriteUnretired`, not the renewal state.
    func clearMCLOverride() {
        cancelRenewalTask()
        lastOverrideValue = 0

        guard let client, let clientClass else { return }

        let selector = NSSelectorFromString("clearMCLOverride")
        guard let method = class_getInstanceMethod(clientClass, selector) else {
            // Neither `overrideClearInvoked` nor `overrideWriteUnretired` moves: nothing
            // retired an override that this process, or an earlier BatFi, may have left
            // behind. That only blocks a snapshot where such a write is possible at all —
            // which is what `canWriteOverride` and `ChargeBackend.writesMCLOverride` decide.
            if !hasReportedMissingClearSelector {
                hasReportedMissingClearSelector = true
                logger.notice("clearMCLOverride selector not exposed on client; relying on natural expiry")
            }
            return
        }

        typealias Clearer = @convention(c) (AnyObject, Selector) -> Void
        let clearer = unsafeBitCast(method_getImplementation(method), to: Clearer.self)
        clearer(client, selector)
        // The one fact a snapshot capture needs: any override outstanding on this machine,
        // including one from a BatFi that crashed while holding it, has now been told to go.
        overrideClearInvoked = true
        overrideWriteUnretired = false
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
    ///
    /// The caller passes the backend it resolved rather than this assuming
    /// `.systemChargeLimit`, so the snapshot rule is answered from what the machine really
    /// reported.
    func adoptSystemLimit(_ percentage: Int, under backend: ChargeBackend) throws {
        guard isAvailable else { throw PowerUIChargingError.frameworkUnavailable }

        // **Deliberately not gated on `availableLimits()`.** It used to be, which made the
        // floor unfalsifiable: the call that would have revealed the real constraint was
        // never made, so `availableChargeLimitsWithError:` could only ever confirm itself.
        //
        // The setter is the authority. `adoptSystemLimitWithoutSnapshotting` turns a
        // genuine refusal into `apiCallFailed`/`apiCallReturnedFalse` and `SMCService`
        // catches that and falls back to the list, so nothing is lost by asking first —
        // and asking is what established that the 80 floor is Apple's rather than BatFi's
        // (`setMCLLimit:` refuses 50 with code 4 on macOS 27, and the override selector
        // refuses 75 the same way). Had the range ever widened, this would have found out;
        // the gate never would.

        // Gate the write on a confirmed read: if we cannot learn the user's current value,
        // we must not overwrite it, because we would then have no correct value to restore.
        // Leaving the snapshot `nil` means "never captured and never written" — the next
        // call retries the capture cleanly.
        guard captureUserLimitIfNeeded(under: backend) else {
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
        // Belt and braces against a snapshot that cannot be restored. The capture guard makes
        // a sub-80 value unrecordable, so this should be unreachable — but a snapshot taken by
        // an earlier build, before that guard existed, is still sitting in a running helper,
        // and `setMCLLimit:` refuses sub-80. Retrying is what makes it pathological: the
        // snapshot is cleared only on success, so without this it fails identically on every
        // release for the life of the process. Dropping it is strictly better than looping —
        // the value is not restorable by any route, and clearing BatFi's charge-limit request
        // returns the Mac to the user's System Settings value anyway.
        guard snapshot >= ChargeLimitRange.systemChargeLimitLowest else {
            logger.error("Discarding an unrestorable system charge limit snapshot of \(snapshot, privacy: .public)%; it is below what setMCLLimit: accepts and cannot have been the user's value")
            hasAdoptedSystemLimit = false
            userSystemLimitSnapshot = nil
            return
        }
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
    /// The whole point is that the read below can never observe a write *this* process
    /// made, nor an override any earlier BatFi left behind:
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
    /// The refusal is narrowed to the case where a BatFi override is actually possible and
    /// cannot be retired on demand: the override selector is present, the clear selector is
    /// absent, **and** the backend in force is one BatFi writes overrides under. Drop any
    /// one of those and no BatFi write can be standing in front of the read.
    ///
    /// The third condition is what keeps the feature alive on the machines it exists for.
    /// Shipping macOS exposes the override selector and no clear, so the first two are
    /// satisfied on every Mac — and requiring only those refused forever on macOS 27
    /// firmware, where `.systemChargeLimit` is the only mechanism there is. BatFi writes an
    /// override solely from the SMC arm of `reconcileMCLOwnership`, so under
    /// `.systemChargeLimit` it never writes one; and the backend follows the firmware,
    /// which is stable across processes on a given Mac, so no earlier BatFi wrote one
    /// either. Nothing can have poisoned the read, and the refusal cost the whole feature.
    ///
    /// The mixed machine — an SMC backend resolved *and* a Manual Charge Limit present —
    /// is the case that still refuses, and must: there BatFi genuinely writes an override
    /// it genuinely cannot clear.
    ///
    /// What it does **not** establish is that an *adopt* by an earlier process is not in
    /// front of the read: `setMCLLimit:` never expires and nothing here retires it. Sound
    /// only while `userSystemLimitSnapshot` stays process-local — see the scope note on
    /// `SystemLimitSnapshot`.
    @discardableResult
    private func captureUserLimitIfNeeded(under backend: ChargeBackend) -> Bool {
        if userSystemLimitSnapshot != nil { return true }

        // Idempotent, and only reached while no snapshot is held — so this costs one
        // selector call on the first touch, not one per status update.
        clearMCLOverride()

        guard SystemLimitSnapshot.readIsTrustworthy(
            // The write this process made, not the renewal state: `clearMCLOverride()`
            // above zeroes `lastOverrideValue` whether or not it found anything to call,
            // and an override it could not clear is still in front of the read below.
            hasUnretiredOverride: overrideWriteUnretired,
            canWriteOverride: canWriteOverride,
            backendWritesOverrides: backend.writesMCLOverride,
            overrideRetired: overrideClearInvoked
        ) else {
            // Surfaced to the app on every status read, unlike the log line below: the
            // user needs the pane to keep saying why no limit is in force, not to have
            // said it once into a log they will never open.
            snapshotRefused = true
            // Said once, not per poll: the inputs are near enough fixed for the life of the
            // process — which selectors this build exposes, and a backend cached against a
            // firmware token that does not move. Repeating it would put one unchanging
            // sentence in the log every status update, forever.
            if !hasReportedSnapshotRefusal {
                hasReportedSnapshotRefusal = true
                logger.error("""
                BatFi will not record this Mac's system charge limit as the user's own value. Under \
                the \(backend.rawValue, privacy: .public) backend BatFi writes an MCL override of its \
                own, and this build of PowerUI exposes no way to clear one — so an override, from \
                this process or from an earlier BatFi that died holding one, may still be standing in \
                front of the read, and a limit read now could be that write rather than the user's \
                setting. Writing it back later would overwrite a value the user cannot get back, so \
                the limit is left alone.
                """)
            }
            return false
        }

        guard let current = currentSystemLimit() else {
            logger.error("Could not read the user's system charge limit; not recording one")
            return false
        }

        // **A sub-80 reading is never the user's own value.** System Settings offers only
        // 80/85/90/95/100, so nothing the user can do produces a lower one — but
        // `getMCLLimitWithError:` reports the *preference* the charge-limit defaults carry,
        // which is how BatFi's own sub-80 request reads back here. Measured: it returned 62
        // while powerd was still enforcing 80.
        //
        // Recording that as the user's setting is unrecoverable in two ways at once. The
        // user's real value is lost, and the restore can never succeed either, because
        // `setMCLLimit:` refuses sub-80 — and since the snapshot is cleared only on a
        // successful restore, it would fail identically on every release for the life of the
        // process. That is exactly what was observed: `code=4` on each teardown.
        //
        // Refusing here is safe for the sub-80 path itself: `adoptSystemLimit` turns this into
        // `snapshotUnavailable`, and `SMCService` already catches any adopt failure and falls
        // through to the defaults channel, which is what applies the limit anyway.
        guard current >= ChargeLimitRange.systemChargeLimitLowest else {
            if !hasReportedSnapshotRefusal {
                hasReportedSnapshotRefusal = true
                logger.error("""
                BatFi will not record \(current, privacy: .public)% as the user's own system charge \
                limit: System Settings cannot express a value below \
                \(ChargeLimitRange.systemChargeLimitLowest, privacy: .public)%, so this is BatFi's \
                own charge-limit request reading back rather than the user's setting. Recording it \
                would lose the user's real value and leave a restore that can never succeed.
                """)
            }
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

        // Set *before* the call, and not rolled back if it fails. Here rather than in
        // `overrideMCLTarget` so the renewal path is covered by the same line — and ahead
        // of the write because this flag's only job is to block a snapshot that might be
        // reading BatFi's own number. A call that applied the override but reported an
        // error or `false` would, set afterwards, leave BatFi believing no override stands
        // and free to record one as the user's value. "We may have written one" is the safe
        // reading; only a clear that actually runs ends it.
        overrideWriteUnretired = true

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
