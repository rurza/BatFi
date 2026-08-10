//
//  SMCService.swift
//
//
//  Created by Adam Różyński on 29/03/2024.
//

import Foundation
import os
import Sentry
import Shared

actor SMCService {
    private lazy var logger = Logger(subsystem: Constant.helperBundleIdentifier, category: "SMC Service")
    /// Mirrors the driver connection, and is the only thing that may close it.
    /// `currentBackend()` refuses to cache a resolution unless this is true, so the
    /// flag and the connection must never disagree — a flag left true over a closed
    /// connection lets a racing request probe a dead driver and cache `.unsupported`.
    private var smcIsOpened = false {
        didSet {
            if !smcIsOpened && oldValue {
                SMCKit.close()
            }
        }
    }

    static let shared = SMCService()

    private init() { }

    private var cachedBackend: ChargeBackend?
    private var cachedBackendFirmware: String?

    /// What `applyChargeLimit` last put in place. Two jobs: diagnostics, so the UI can say
    /// which limit is really in effect, and the short-circuit that keeps `setMCLLimit:`
    /// from being rewritten on every status update. Only written by the
    /// `.systemChargeLimit` backend: the SMC backends apply the user's value exactly, so
    /// there is nothing to explain. `.firmwareRange` does hold state of its own — see
    /// `firmwareRangeArmed` and `appliedFirmwareRange` below — but it is not *this* state,
    /// because Apple's Manual Charge Limit is not what it holds.
    ///
    /// **Invariant: this is nil whenever BatFi does not hold the system limit.** It is
    /// cleared by every route that ends that ownership — the SMC arm of
    /// `applyChargeLimit`, `restoreSystemDefaults()`, and `invalidateBackendCache()`,
    /// which runs whenever the resolved backend is dropped. That is what stops the
    /// short-circuit wedging: it can only suppress a write while the exact limit it
    /// records is still in force.
    private var appliedSystemLimit: AppliedChargeLimit?

    /// Whether this process has written the firmware band and still owes a release.
    ///
    /// **The obligation, and it must not need the backend to say so.** The band is the one
    /// piece of charge control that lives in hardware between calls: the firmware enforces
    /// it with no BatFi process running, and nothing in System Settings shows it. The
    /// release used to be gated on `currentBackend() == .firmwareRange` alone, but that
    /// cache is dropped on every SMC write failure and every `smcChargingStatus()` throw,
    /// and the re-probe can answer for some keys and not others over a degrading connection
    /// — resolving `.systemChargeLimit` or `.unsupported` on a machine whose band is armed
    /// at 80%. `restoreSystemDefaults()` would then complete with no failures, take its
    /// early return past `resetIfPossible()` — the only unconditional `bfF0 = 0` — and
    /// leave the user's Mac permanently capped by a limit they can neither see nor remove.
    ///
    /// Same shape as `PowerUICharging.hasAdoptedSystemLimit`: only the thing that armed it
    /// owes a release, and it owes it whatever the backend later says.
    ///
    /// Set *before* the engage sequence runs, not after, so a sequence that throws part-way
    /// still records the obligation — the first write in it is `bfF0 = 0x00`, but a throw
    /// on that very write leaves an earlier band untouched and armed. Cleared only where
    /// the release actually landed. Deliberately **not** cleared by
    /// `invalidateBackendCache()`, unlike the short-circuit below: that runs on failure
    /// paths, and forgetting an obligation there is the exact hole this closes.
    private var firmwareRangeArmed = false

    /// The percentage the band was last armed at, or nil when the next pass should write
    /// again. The `.firmwareRange` equivalent of `AppliedChargeLimit.needsWrite`, and it is
    /// a short-circuit only — never the release obligation, which is the flag above.
    ///
    /// `applyChargeLimit` runs on every status update, and `engageSequence` *begins* by
    /// writing `bfF0 = 0x00` — so re-running it when nothing changed opens a real
    /// unrestricted window on every pass, forever, on hardware nobody can test, and a
    /// helper killed between the first and last write leaves the band off with nothing
    /// reporting it. It is also the one plausible brake on a write → `IOPSNotification` →
    /// `powerSourceChanges` → `applyChargeLimit` → write feedback loop on firmware that
    /// raises a power-source change per SMC charge write.
    ///
    /// Cleared by every route that casts doubt on the band being in force, in the same
    /// places `appliedSystemLimit` is cleared. Clearing only ever causes an extra write,
    /// never a suppressed one.
    private var appliedFirmwareRange: Int?

    /// Closes the driver connection through the flag rather than behind its back:
    /// `Listener`'s quit handler calls this directly, and a request racing that
    /// handler has to see `smcIsOpened == false`. Closing is the `didSet`'s job.
    func close() {
        smcIsOpened = false
    }

    /// Resolves the charge-control mechanism from the firmware's key table.
    ///
    /// Cached against the firmware token, not the macOS version, and re-probed when
    /// that token changes. This is the case a user hits by updating macOS, taking the
    /// new firmware, then downgrading macOS again — the OS moves, the firmware does
    /// not, and the cache follows the firmware.
    func currentBackend() async -> ChargeBackend {
        let firmware = SystemFirmware.version()
        if let cachedBackend, cachedBackendFirmware == firmware {
            return cachedBackend
        }

        await openSMCIfNeeded()
        // openSMCIfNeeded() cannot fail loudly — it exhausts its retries and returns
        // with smcIsOpened still false. Probing over a dead connection makes every key
        // look absent, which resolves to .unsupported and would then be cached against
        // this machine's real firmware token, pinning a resident daemon to "no charge
        // control" for its whole life over one transient open failure. Fail this call
        // only; the next one retries the open.
        guard smcIsOpened else {
            logger.error("SMC is not open; refusing to cache a backend resolution")
            return .unsupported
        }

        let capabilities = SMCKit.probeCapabilities(ChargeBackendResolver.probedKeys)
        // Asked of PowerUI rather than inferred from the macOS version, for the same
        // reason the SMC keys are probed: what the machine reports is the only thing
        // that is true on it. The resolver ranks this last, so it is only reached when
        // no SMC key works.
        let backend = ChargeBackendResolver.resolve(
            capabilities,
            systemChargeLimitSupported: await PowerUICharging.shared.isMCLSupported
        )

        let summary = capabilities.keys.sorted().joined(separator: ", ")
        logger.notice("""
        Charge backend resolved to \(backend.rawValue, privacy: .public) \
        on firmware \(firmware ?? "unknown", privacy: .public); usable keys: \(summary, privacy: .public)
        """)

        cachedBackend = backend
        cachedBackendFirmware = firmware
        return backend
    }

    func setChargingMode(_ message: SMCChargingCommand) async throws {
        let inhibitCharging: Bool
        let forceDischarge: Bool

        switch message {
        case .forceDischarging:
            forceDischarge = true
            inhibitCharging = false
            logger.notice("Handling force discharge")
        case .auto:
            forceDischarge = false
            inhibitCharging = false
            logger.notice("Handling enable charge")
        case .inhibitCharging:
            forceDischarge = false
            inhibitCharging = true
            logger.notice("Handling inhibit charging")
        }

        logger.notice("Setting SMC charging status")
        await openSMCIfNeeded()

        // Deliberately ahead of the SMC writes, and outside the `do`, for two reasons that
        // both still hold. Under `.unsupported` every write below still throws, so a
        // reconcile placed downstream could never run on the machines its clearing arm
        // exists for. And under `.systemChargeLimit` the reconcile is what guarantees BatFi
        // is not holding an override while `applyChargeLimit` sets the limit — a guarantee
        // that must not become conditional on an SMC write succeeding. Same
        // MCL-first-then-SMC shape as `restoreSystemDefaults()`.
        await reconcileMCLOwnership(for: message)

        do {
            try await enableCharging(!inhibitCharging)
            try await enableForceDischarge(forceDischarge)
        } catch SMCError.noChargeControlMechanism {
            // Not a driver failure and not something a re-probe can fix — it is the
            // resolver's own verdict about this firmware, reached over a connection that
            // was open. Resetting keys, dropping the resolution and closing the connection
            // here would do all three on every mode change, forever, on a machine where
            // the app now takes a mode decision on every status update.
            self.logger.error("No usable charge control mechanism on this firmware; charging mode not changed")
            throw SMCError.noChargeControlMechanism
        } catch {
            self.logger.critical("SMC writing error: \(error)")
            self.resetIfPossible()
            invalidateBackendCache()
            smcIsOpened = false
            throw error
        }
    }

    /// Decides, in one place, which of the two mutually exclusive things BatFi may do
    /// with Apple's Manual Charge Limit.
    ///
    /// Under an SMC backend BatFi **releases** the system limit — overrides it to 100 —
    /// so its own inhibit is the only thing holding charge back. Under
    /// `.systemChargeLimit` BatFi **sets** it instead, via `applyChargeLimit`, and must
    /// not also hold a temporary override: the 60-second renewal task behind that
    /// override would keep writing 100 over the adopted value and the user's limit
    /// would oscillate. One branch on one backend, rather than two independent
    /// conditionals, is what makes holding both states unrepresentable.
    ///
    /// That branch is `ChargeBackend.writesMCLOverride` itself, not a restatement of
    /// which backends it covers. `SystemLimitSnapshot.readIsTrustworthy` reads the same
    /// property to decide whether a limit read could be BatFi's own write, and the two
    /// answers disagreeing is how BatFi would record its own number as the user's saved
    /// limit. There is one answer, so they cannot.
    ///
    /// Runs *before* the SMC writes in `setChargingMode`, not after, and must stay there.
    ///
    /// It has to, for `.unsupported`: `enableCharging` still throws there, so a reconcile
    /// placed after it never runs on the machines the clearing arm is for. `enableCharging`
    /// no longer throws under `.systemChargeLimit` — but that is not a reason to move this,
    /// because the ordering is load-bearing for that backend too: the clearing arm is what
    /// keeps BatFi from holding an override while `applyChargeLimit` is setting the limit,
    /// and one MCL owner at a time must not depend on an SMC write succeeding first.
    ///
    /// And it is safe for the SMC arm: that arm only acts on `.auto`, where both writes
    /// move the same way — toward "allow charging" — so releasing Apple's limit first
    /// merely leaves BatFi's own inhibit holding charge back a moment longer, the more
    /// restrictive of the two transient states. The reverse (Apple's limit released while
    /// BatFi still inhibits) is not reachable, because `.auto` writes no inhibit.
    private func reconcileMCLOwnership(for message: SMCChargingCommand) async {
        guard await PowerUICharging.shared.isMCLSupported else { return }

        // Bound rather than switched on inline so the resolved value can be handed to
        // `PowerUICharging`, which decides whether a limit read could be BatFi's own
        // override and must answer that from the machine's real backend, not an assumption.
        let backend = await currentBackend()
        if backend.writesMCLOverride {
            // An SMC backend owns charging; get Apple's limit out of the way.
            guard message == .auto else { return }
            do {
                try await PowerUICharging.shared.overrideMCLTarget(100, under: backend)
            } catch {
                logger.error("PowerUI MCL override failed: \(error, privacy: .public)")
            }
        } else {
            // BatFi either owns the system limit (`.systemChargeLimit`) or has no
            // mechanism at all (`.unsupported`). Either way it must not hold a temporary
            // override. Cleared unconditionally rather than only when this process knows
            // it set one: an override outlives the process that started it, so a BatFi
            // that restarted onto a different backend has to clear one it has no memory of.
            await PowerUICharging.shared.clearMCLOverride()
        }
    }

    /// Applies a charge limit using whichever mechanism this firmware supports.
    ///
    /// Returns the limit actually applied, which may be higher than requested when the
    /// system limit is in use — it cannot go below 80%. The SMC backends express a limit
    /// as an inhibit rather than a number, and apply the requested value exactly, so
    /// under those this only reports the request back.
    func applyChargeLimit(_ percentage: Int) async throws -> Int {
        // Bound for the same reason as in `reconcileMCLOwnership`: the `.systemChargeLimit`
        // arm hands the resolved backend to `adoptSystemLimit`, which needs it to decide
        // whether BatFi could be reading back its own MCL override.
        let backend = await currentBackend()
        switch backend {
        case .firmwareRange:
            // Handed back for the same reason as the inhibit backends below: a re-probe can
            // flip this machine from `.systemChargeLimit` to here — a firmware token change,
            // or a `bf**` probe that failed transiently and then succeeded — and forgetting
            // an adopted limit without releasing it would strand Apple's Manual Charge Limit
            // at BatFi's value. Done before the band write, so a throwing write cannot be
            // what strands it. `releaseSystemLimit` self-guards on the snapshot.
            await PowerUICharging.shared.releaseSystemLimit()
            // The charge-limit request goes back for the same reason and is *more* dangerous
            // to strand: it is a persistent, root-owned preference that survives the process,
            // so one left behind here would cap an SMC-backend Mac at a value nothing in
            // BatFi's UI still refers to.
            await ManualChargeLimitDefaults.shared.release()
            appliedSystemLimit = nil
            // The needs-write short-circuit, and it matters more here than it does under
            // `.systemChargeLimit`, where the same guard is applied and explained.
            // `engageSequence` opens with `bfF0 = 0x00`, so an unguarded re-run disarms the
            // band and re-arms it several times a minute for the life of the process — a
            // genuine unrestricted window on every pass, and a helper killed between the
            // first and last write leaves the band **off** with nothing reporting it. It is
            // also the one plausible brake on a write → `IOPSNotification` →
            // `powerSourceChanges` → `applyChargeLimit` → write feedback loop on firmware
            // that raises a power-source change per SMC charge write.
            guard appliedFirmwareRange != percentage else { return percentage }
            // Recorded before the writes, so a sequence that throws part-way still leaves
            // the release owed. Erring toward "BatFi owes a release" costs one write that
            // fails harmlessly; erring the other way is C1.
            firmwareRangeArmed = true
            do {
                try applyFirmwareRange(percentage)
            } catch {
                // The short-circuit, unlike the obligation, is cleared. "Write again next
                // pass" is the safe direction; "suppress the write that would restore the
                // limit" is not.
                appliedFirmwareRange = nil
                throw error
            }
            appliedFirmwareRange = percentage
            // The band's upper bound is the user's number exactly — see
            // `FirmwareChargeRange.band(forLimit:)`, which derives only the lower bound —
            // so the request is what is in force, including below 80%.
            return percentage
        case .chte, .legacyCH0BC:
            // Handled by the existing inhibit path, which applies the requested value
            // exactly. Anything the system-limit backend left behind is handed back first:
            // a re-probe can flip this machine from `.systemChargeLimit` to an SMC backend
            // (a firmware token change, or a `CHTE` probe that failed transiently and then
            // succeeded), and forgetting the adopted limit without releasing it would strand
            // Apple's Manual Charge Limit at BatFi's value — visible in System Settings, and
            // silently capping every later SMC-driven limit above it. `releaseSystemLimit`
            // self-guards on the snapshot, so this is a no-op on machines that never adopted.
            await PowerUICharging.shared.releaseSystemLimit()
            // And BatFi's charge-limit request with it: this backend drives the SMC, so a
            // request left standing would hold a second, invisible ceiling underneath it.
            await ManualChargeLimitDefaults.shared.release()
            // Any note from an earlier resolution goes with it, so diagnostics cannot claim
            // a raised limit under a backend that never raises one.
            appliedSystemLimit = nil
            // And the band goes back the same way, for the mirror-image reason. The
            // `.firmwareRange` arm above releases the *system limit* precisely so a backend
            // flip cannot strand it; nothing released the *band* on a flip in the other
            // direction, so both mechanisms could be in force at once — the "one owner"
            // invariant broken in the one direction nobody guarded.
            releaseFirmwareRangeIfStranded()
            return percentage
        case .systemChargeLimit:
            releaseFirmwareRangeIfStranded()
            // `applyChargeLimit` runs on every status update — roughly once a minute for
            // the life of the process — and `setMCLLimit:` mutates a control the user can
            // see and touch in System Settings. Rewriting the value already in force buys
            // nothing, so don't.
            //
            // Compared on the **request** rather than on the whole outcome, which is what
            // `AppliedChargeLimit.needsWrite` does and why it is not used here. What a
            // request resolves to is no longer a pure function of it — `setMCLLimit:`
            // decides, and may refuse — so a request that fell back to another value would
            // differ from the outcome recorded for it and be retried on every pass, for the
            // life of the process, on exactly the machines where the write does not work.
            //
            // Safe here in a way it would not be inside `PowerUICharging.adoptSystemLimit`,
            // where skipping the write would also skip the snapshot capture: this field is
            // non-nil only *after* a successful adopt, which is after the user's value was
            // captured. The guard can therefore never fire before a snapshot exists. If an
            // adopt throws the field stays as it was, so the next pass writes again.
            if let inForce = appliedSystemLimit, inForce.requested == percentage {
                // Above the floor the adopt stands on its own and nothing else touches it.
                // Below it, the limit lives in a policy PowerUIAgent owns — and powerd
                // retires that policy whenever Apple's charge limit changes underneath — so
                // "already applied" cannot be assumed here, only checked. Skipping the check
                // is how a limit silently reverts and stays reverted for the life of the
                // process.
                if inForce.applied >= ChargeLimitRange.systemChargeLimitLowest {
                    return inForce.applied
                }
                if await ManualChargeLimitDefaults.shared.isSatisfied(percentage) {
                    return inForce.applied
                }
                logger.notice("Charge limit no longer holds \(percentage, privacy: .public)%; re-applying")
            }
            // The temporary override belongs to the SMC backends and is dropped before
            // adopting anything. Its renewal task would otherwise write 100 over the
            // value set below, and while it is live the user's own saved limit reads
            // back as the overridden one.
            await PowerUICharging.shared.clearMCLOverride()
            do {
                // The value the user actually asked for, unrounded. Asking is the only way
                // to learn what this machine's limit really accepts: a list read from
                // `availableChargeLimitsWithError:` cannot contradict itself, while the
                // setter can, and does on firmware whose range differs from the picker's.
                try await PowerUICharging.shared.adoptSystemLimit(percentage, under: backend)
                // PowerUI took it, so BatFi's own request must not be left standing: a lower
                // value from an earlier sub-80 request would go on capping charge below the
                // limit now in force.
                await ManualChargeLimitDefaults.shared.release()
                appliedSystemLimit = AppliedChargeLimit(requested: percentage, applied: percentage)
                return percentage
            } catch {
                // Refused — and on every machine measured so far that means the value is
                // below 80. That floor is validation inside `PowerUI.framework`, which loads
                // into *this* process; it is not a limit of PowerUIAgent, of powerd, or of
                // the firmware. Asking the agent directly, in the terms it already reads, has
                // no such floor. See `ManualChargeLimitDefaults` for the measurements.
                do {
                    // One write, no dance. `MCLFeatureState` switches Apple's charge limit on
                    // and `mclLimitValue` carries the number, both in the same domain, so
                    // there is no enable-then-write ordering to get wrong and nothing here
                    // calls `setMCLLimit:`.
                    //
                    // That last point is what retires the re-assertion write-fight seen
                    // earlier: `setMCLLimit:` mutates a control powerd owns, so calling it on
                    // every pass made powerd rewrite its policy, which BatFi then read as
                    // drift and corrected — a loop measured at roughly one round every three
                    // seconds. Writing only the defaults leaves powerd nothing to argue with,
                    // and `apply` no-ops when the limit is already the one in force.
                    try await ManualChargeLimitDefaults.shared.apply(limit: percentage)
                    logger.notice("System limit refused \(percentage, privacy: .public)%; applied it through the charge-limit defaults instead")
                    appliedSystemLimit = AppliedChargeLimit(requested: percentage, applied: percentage)
                    return percentage
                } catch let defaultsError {
                    logger.error("Charge limit \(percentage, privacy: .public)% via defaults failed: \(defaultsError, privacy: .public); falling back to the values PowerUI accepts")
                }
                // **Never raise the limit above what the user asked for.** Rounding a refused
                // 60% up to 80% does not approximate the request, it inverts it: the Mac then
                // charges *past* the value the user set, which is the one thing a charge limit
                // exists to prevent. Observed doing exactly that — dropping the limit from 65%
                // to 60% started charging, because one transient refusal was answered with 80%.
                //
                // The rounding rule that used to live here was written when 80 was a hard floor
                // and there was nothing else to offer. There is now: the defaults channel
                // applies the user's real value, so a refusal from it is a transient failure,
                // not a statement about the machine. Nothing is written, the request stands,
                // and the next pass tries again — `appliedSystemLimit` is deliberately left as
                // it was so the re-assertion check still sees drift and re-applies.
                //
                // Clamping *down* does not arise: no measured firmware refuses a value for
                // being too low, and the one that refuses 60 refuses everything below 80, so
                // there is no lower accepted value to clamp to.
                logger.error("Could not put \(percentage, privacy: .public)% in force; leaving the limit alone rather than raising it, and retrying on the next pass")
                throw error
            }
        case .unsupported:
            // Before the throw, not after it: a band armed by this process while the probe
            // still resolved `.firmwareRange` is exactly what a degrading connection can
            // strand, and this arm is where that flip lands.
            releaseFirmwareRangeIfStranded()
            logger.error("No usable charge control mechanism on this firmware")
            throw SMCError.noChargeControlMechanism
        }
    }

    /// Clears the PowerUI MCL override (so the user's saved System Settings limit comes back),
    /// hands back any limit BatFi adopted, and sets SMC back to auto-charge. Used on app quit
    /// and when the user disables BatFi's charge management.
    func restoreSystemDefaults() async throws {
        // Both directions of MCL ownership are handed back, in this order: the temporary
        // override goes first so its renewal task cannot fire between the two calls and
        // write 100 over the value being restored. `releaseSystemLimit` guards itself on
        // whether a limit was ever adopted, so it is safe under every backend — this is
        // the path that gives the user their System Settings value back on quit, and it
        // must not be reachable only from the backend that set it.
        if await PowerUICharging.shared.isMCLSupported {
            await PowerUICharging.shared.clearMCLOverride()
        }
        await PowerUICharging.shared.releaseSystemLimit()
        // The one release that must never be skipped. Unlike every SMC write and unlike
        // Apple's own limit, the charge-limit request is persistent state in root's
        // preference domain that outlives BatFi entirely — so a request still standing when
        // BatFi is quit or uninstalled leaves the user's Mac capped with nothing left on the
        // machine that knows how to undo it.
        await ManualChargeLimitDefaults.shared.release()
        appliedSystemLimit = nil

        logger.notice("Restoring SMC defaults (auto charge, force discharge off)")
        await openSMCIfNeeded()

        // Attempted independently rather than as one all-or-nothing block. The two
        // writes target disjoint keys with no precedence between them, so failing fast
        // protects nothing — it only picks which of the two safety writes gets stranded.
        // It also cost the caller: `ChargingManager.disengage()` skips its own
        // `updateChargingMode(.charging)` when this throws, so an early throw left the
        // app's in-memory mode stale against hardware `resetIfPossible()` had already
        // put back.
        var failures: [any Error] = []

        // Force discharge is still released first, and for the original reason: it is
        // the only state that can drain the battery while the Mac sits on AC, and with
        // the charge write upstream one transient throw skipped the release entirely and
        // left the machine discharging until BatFi was relaunched. Nothing below may
        // strand it — which is now true even when this very write is the one that fails.
        do {
            try await enableForceDischarge(false)
        } catch {
            logger.critical("SMC writing error while releasing force discharge: \(error)")
            failures.append(error)
        }

        // The firmware-managed band is the one piece of charge control an SMC backend leaves
        // armed in hardware between calls, so it is the one that has to be handed back
        // explicitly here. `enableCharging(true)` below does **not** clear it — under that
        // backend a charging-mode change writes nothing, which is precisely what lets the
        // band hold across sleep — so without this write, quitting BatFi or turning charge
        // management off would leave a macOS 27 Mac capped by a limit the user can no longer
        // see, change, or remove short of reinstalling BatFi.
        //
        // Attempted independently, like the two writes either side of it: the keys are
        // disjoint and there is no precedence between them, so failing fast here would only
        // pick which safety write gets stranded.
        do {
            try await releaseFirmwareRangeIfHeld()
        } catch {
            logger.critical("SMC writing error while releasing the firmware charge range: \(error)")
            failures.append(error)
        }

        // Then again, unconditionally and unreported. `appliedFirmwareRange` is
        // process-local, so a helper that was restarted — killed by jetsam, crashed, or
        // simply relaunched by launchd — has no memory of a band that is still armed in the
        // firmware, and the backend re-probe is exactly the thing that can answer wrongly
        // over a degrading connection. This is the same bargain `resetIfPossible()` already
        // makes for the same guarantee: one throwing write per quit on firmware with no
        // `bfF0`, in exchange for never leaving a Mac capped by a limit nothing can see.
        //
        // Swallowed rather than added to `failures` deliberately: on every Mac shipping
        // today this write throws because the key is absent, and reporting that as a failed
        // restore would tell the entire existing fleet the restore did not complete.
        for step in FirmwareChargeRange.releaseSequence {
            try? perform(step)
        }
        firmwareRangeArmed = false
        appliedFirmwareRange = nil

        do {
            try await enableCharging(true)
        } catch {
            logger.critical("SMC writing error while re-enabling charging: \(error)")
            failures.append(error)
        }

        // Still throws, so callers learn the restore was incomplete — but only after
        // both writes have had their turn. Both errors are already logged above; the
        // first is the one surfaced.
        guard let firstFailure = failures.first else { return }
        resetIfPossible()
        invalidateBackendCache()
        smcIsOpened = false
        throw firstFailure
    }

    func mclStatus() async -> MCLStatus {
        if await PowerUICharging.shared.isMCLSupported {
            return await PowerUICharging.shared.mclStatus()
        }
        return MCLStatus(supported: false, batFiHasActiveOverride: false, lastOverrideValue: nil)
    }

    /// Snapshot for bug reports: resolved backend, firmware token, the firmware's own
    /// `CHNC` reason for not charging, MCL status, the limit actually applied — which is
    /// not always the one asked for — and which of the two key-independent features this
    /// firmware can still do. Decoded and reported only — no control flow branches on
    /// `CHNC`, since which bit a `CHTE` inhibit raises has not been confirmed on hardware.
    ///
    /// `forceDischargeAvailable` is answered from the key table and from nothing else.
    /// That is the point of it: `CHIE` survives on firmware that has dropped `CHTE`, so a
    /// machine on `.systemChargeLimit` can still run on battery, and inferring it from the
    /// backend would take a working feature down with the one that broke.
    ///
    /// `magSafeLEDAvailable` is answered from the key table and from nothing else either.
    /// It means "the LED can be driven", which is what the discharge blink needs and which
    /// no backend takes away. Whether the *green light* can be driven is a narrower
    /// question, and it is asked where it belongs: `ChargingDiagnostics.magSafeGreenLightAvailable`.
    ///
    /// Both of those, and the `bfF0` read, are reported as **nil when the driver connection
    /// never opened** — the same rule `currentBackend()` states and enforces twelve lines
    /// above, applied here because this function probes too. `openSMCIfNeeded()` cannot
    /// fail loudly; it exhausts its retries and returns with `smcIsOpened` still false, and
    /// probing over a dead connection makes every key look absent. Two of these flags are
    /// *acted on* rather than merely reported — `MagSafeColorManager` writes the user's
    /// green-light setting off on one of them — so a two-second driver hiccup answering
    /// `false` is a permanently destroyed setting on a perfectly healthy Mac.
    func chargingDiagnostics() async -> ChargingDiagnostics {
        let backend = await currentBackend()
        let firmwareVersion = SystemFirmware.version()

        await openSMCIfNeeded()
        guard smcIsOpened else {
            logger.error("SMC is not open; reporting the probed capabilities as unknown")
            return ChargingDiagnostics(
                backend: backend.rawValue,
                firmwareVersion: firmwareVersion,
                notChargingReasons: [],
                mcl: await mclStatus(),
                forceDischargeAvailable: nil,
                magSafeLEDAvailable: nil,
                firmwareRangeIsArmed: nil,
                appliedChargeLimit: appliedSystemLimit?.applied,
                chargeLimitWasRaised: appliedSystemLimit?.wasRaised ?? false,
                requestedChargeLimit: appliedSystemLimit?.requested
            )
        }

        // Read defensively: CHNC may be absent on some firmware, and a diagnostics call
        // that throws is worse than useless. Absent or unreadable reports no reasons.
        let reasons: [String]
        if let bytes = try? SMCKit.readData(.notChargingReason) {
            let raw: [UInt8] = [
                bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7
            ]
            reasons = NotChargingReason.decode(raw).map(\.rawValue)
        } else {
            reasons = []
        }

        let mcl = await mclStatus()

        // The same function `enableForceDischarge` switches on, so "available" here means
        // precisely "there is a mechanism that write path would use".
        let forceDischargeAvailable = forceDischargeMechanism() != nil
        // Presence, not shape, and unlike force discharge that is the right test. No ACLC
        // encoding has been measured across the fleet, this flag gates nothing on its own —
        // it is reported — and the LED write path already fails loudly: it reads the key
        // back and throws when the value does not decode. A guessed shape here could only
        // claim a working LED is missing.
        //
        // Deliberately *not* narrowed by the backend. "Can the LED be driven" is one
        // question and "can BatFi tell it when charging is held back" is another, and only
        // the second is lost under `.firmwareRange`. Answering them with one flag took the
        // discharge blink — which runs off BatFi's own `.forceDischarge` mode, written
        // through `CHIE` and fully known on this firmware — down with the green light.
        let magSafeLEDAvailable = SMCKit.probeCapability(for: .magSafeLED) != nil

        // The `bfF0` read, moved here out of `isChargingEnabled`, where it was answering
        // the wrong question. "Is the band armed" is a fact about the *limit*, not about
        // whether charging is being held back this second, and this is where facts about
        // the limit are reported. Nil on every other backend, and on a read failure —
        // absent is not the same as off, and a diagnostics call must not throw.
        let firmwareRangeIsArmed: Bool?
        switch backend {
        case .firmwareRange:
            if let data = try? SMCKit.readData(.firmwareRangeActivation) {
                firmwareRangeIsArmed = FirmwareChargeRange.rangeIsEngaged(activation: data.0)
            } else {
                logger.error("Failed to read the firmware charge range activation key")
                firmwareRangeIsArmed = nil
            }
        case .chte, .legacyCH0BC, .systemChargeLimit, .unsupported:
            firmwareRangeIsArmed = nil
        }

        return ChargingDiagnostics(
            backend: backend.rawValue,
            firmwareVersion: firmwareVersion,
            notChargingReasons: reasons,
            mcl: mcl,
            forceDischargeAvailable: forceDischargeAvailable,
            magSafeLEDAvailable: magSafeLEDAvailable,
            firmwareRangeIsArmed: firmwareRangeIsArmed,
            appliedChargeLimit: appliedSystemLimit?.applied,
            chargeLimitWasRaised: appliedSystemLimit?.wasRaised ?? false,
            // Sent beside the applied value because a raise alone does not say which kind
            // of raise it was: a request below the mechanism's floor clamped up to it, or
            // one above the floor rounded up to the next accepted step. They need
            // different words, and only the requested value can tell them apart.
            requestedChargeLimit: appliedSystemLimit?.requested
        )
    }

    /// Best-effort return to a safe state after a write error.
    ///
    /// Invariant: **every key any engage path can write must be cleared here.** This
    /// is the last line of defence — callers use `try?` and one of them runs as the
    /// app exits, so a key left engaged here stays engaged. `CHIE` was missing from
    /// this list while `enableForceDischarge` wrote it, which is exactly how a Mac
    /// could be left draining on AC after a failed restore.
    func resetIfPossible() {
        // Try to reset new firmware keys first
        try? SMCKit.writeData(.inhibitCharging3, byte0: 0, byte1: 0, byte2: 0, byte3: 0)
        try? SMCKit.writeData(.disableCharging3, uint8: 0)

        // Also reset old firmware keys
        try? SMCKit.writeData(.disableCharging1, uint8: 0)
        try? SMCKit.writeData(.disableCharging2, uint8: 0)
        try? SMCKit.writeData(.inhibitCharging1, uint8: 0)
        try? SMCKit.writeData(.inhibitCharging2, uint8: 0)

        // The macOS 27-era firmware-managed range, and it belongs here rather than at the
        // top even though it is the one piece of state that outlives the process. Ordering
        // inside a safety net matters: `CHIE`/`CH0I` are the keys whose stale state can
        // leave a Mac *discharging on AC*, so they must not be queued behind a write to a
        // key this code has deliberately not probed.
        //
        // Unprobed is the operative word. The rule everywhere else on this branch is "never
        // touch a `bf**` key you have not shape-matched", because `bfD0` exists on Tahoe
        // firmware as a read-only `hex_`/2 key with an unrelated meaning. This is the one
        // place that escapes it, on purpose: reset runs from failure paths where the
        // resolved backend is exactly what is in doubt, a band left armed by a crashed
        // helper keeps being enforced with nothing running that can clear it, and a write
        // to an absent key throws into the `try?` and costs nothing.
        //
        // Replayed from `FirmwareChargeRange.releaseSequence`, the same list
        // `releaseFirmwareRange()` performs, so this cannot come to clear less than the
        // release path does.
        for step in FirmwareChargeRange.releaseSequence {
            try? perform(step)
        }
    }

    /// Drops the resolved backend so the next call re-probes.
    ///
    /// Called from every failure path that can have resolved one: a probe run over a
    /// connection that is already degrading can answer for some keys and not others,
    /// and that partial table resolves to a backend this firmware does not have —
    /// cached against the machine's real firmware token, which pins it for the life of
    /// the daemon and makes every later call fail on a key that was never really
    /// missing. The MagSafe LED and power-distribution paths never reach the resolver,
    /// so they have nothing to drop.
    private func invalidateBackendCache() {
        cachedBackend = nil
        cachedBackendFirmware = nil
        // The applied-limit note is scoped to the backend that produced it. Dropping the
        // resolution means the next `applyChargeLimit` may land on a different mechanism,
        // and the short-circuit in its `.systemChargeLimit` arm must not carry a claim
        // made under the old one across that boundary — it would suppress the write that
        // re-establishes the limit. Clearing here also fails safe: every path that gets
        // here is a failure path, and the safe direction is always "write again".
        appliedSystemLimit = nil
        // The band's short-circuit is dropped for the same reason — the next
        // `applyChargeLimit` may land on a different mechanism, and suppressing the write
        // that re-establishes the band across that boundary is the one direction that
        // fails unsafely.
        //
        // Note this does **not** drop the release obligation. `firmwareRangeArmed` is
        // untouched here, deliberately: this function runs on failure paths, and a failure
        // path is exactly where forgetting that a band is armed in hardware turns into a
        // Mac left permanently capped.
        appliedFirmwareRange = nil
    }

    func smcChargingStatus() async throws -> SMCChargingStatus {
        logger.notice("Checking SMC status")
        await openSMCIfNeeded()
        do {
            logger.notice("Getting disable charging status")
            // Shape-checked rather than read-and-catch, and independently of the charge
            // backend — CHIE outlives CHTE on newer firmware.
            // CHIE and the legacy CH0I/CH0J all use 0 for "adapter connected". They do NOT
            // share one engaged value — CHIE is written 0x08 here (see
            // SMCKey.forceDischargeEngagedValue) but other tools have observed 0x20 as a
            // second isolated state for the same key — so we test for "not connected"
            // rather than matching one specific engaged byte. Both arms use the same test
            // deliberately: the write side is asymmetric, and letting the two read arms
            // diverge from each other (or from the write) is how this drifted out of sync
            // before.
            let forceDischarging: Bool
            if forceDischargeKeyIsUsable(.disableCharging3, writable: false), let data = try? SMCKit.readData(.disableCharging3) {
                forceDischarging = data.0 != 0
            } else if forceDischargeKeyIsUsable(.disableCharging1, writable: false), let data = try? SMCKit.readData(.disableCharging1) {
                forceDischarging = data.0 != 0
            } else {
                forceDischarging = false
                logger.error("Failed to read disable charging status")
            }

            logger.notice("Getting charging enabled status")
            let chargingEnabled = try await isChargingEnabled()
            
            logger.notice("Getting lid closed status")
            // Read defensively, like `CHNC` in `chargingDiagnostics()`, and for a sharper
            // reason: this key is not guaranteed to exist on every firmware, and a throw
            // here took the whole status read down with it. That read is where the app's
            // charging mode comes from, so a machine missing this one key never left
            // `ChargingMode.initial` — the same trap the power-source stream had to be
            // hardened against. A lid nobody could read is reported as unknown; the app
            // already has a path for that.
            let lidClosed: Bool?
            if let data = try? SMCKit.readData(SMCKey.lidClosed) {
                lidClosed = data.0 == 01
            } else {
                lidClosed = nil
                logger.error("Failed to read the lid state; reporting it as unknown")
            }

            return SMCChargingStatus(
                forceDischarging: forceDischarging,
                inhitbitCharging: !chargingEnabled,
                lidClosed: lidClosed
            )
        } catch {
            // Cleared here too, not only on the write paths: isChargingEnabled() above
            // resolves — and caches — a backend, and status is polled continuously while
            // writes happen only when the user changes mode. Without this, a resolution
            // made over a degrading connection would be re-read, fail, and be re-read
            // again for the life of the daemon with no write ever arriving to clear it.
            invalidateBackendCache()
            smcIsOpened = false
            throw error
        }
    }

    func magsafeLEDColor(_ option: MagSafeLEDOption) async throws -> MagSafeLEDOption {
        logger.notice("Setting MagSafe LED color")
        await openSMCIfNeeded()
        do {
            try SMCKit.writeData(SMCKey.magSafeLED, uint8: option.rawValue)
            let data = try SMCKit.readData(.magSafeLED)
            guard let option = MagSafeLEDOption(rawValue: data.0) else {
                throw SMCError.canNotCreateMagSafeLEDOption
            }
            return option
        } catch {
            smcIsOpened = false
            throw error
        }
    }

    func magsafeLEDColor() async throws -> MagSafeLEDOption {
        logger.notice("Getting MagSafe LED color")
        await openSMCIfNeeded()
        do {
            let data = try SMCKit.readData(.magSafeLED)
            guard let option = MagSafeLEDOption(rawValue: data.0) else {
                throw SMCError.canNotCreateMagSafeLEDOption
            }
            return option
        } catch {
            smcIsOpened = false
            throw error
        }
    }

    func getPowerDistribution() async throws -> PowerDistributionInfo {
        logger.notice("Getting power distribution")
        await openSMCIfNeeded()
        do {
            let rawBatteryPower = try SMCKit.readData(SMCKey.batteryPower)
            let rawExternalPower = try SMCKit.readData(SMCKey.externalPower)

            var batteryPower = Float(fromBytes: (rawBatteryPower.0, rawBatteryPower.1, rawBatteryPower.2, rawBatteryPower.3))
            var externalPower = Float(fromBytes: (rawExternalPower.0, rawExternalPower.1, rawExternalPower.2, rawExternalPower.3))

            if abs(batteryPower) < 0.01 {
                batteryPower = 0
            }
            if externalPower < 0.01 {
                externalPower = 0
            }

            let systemPower = batteryPower + externalPower

            return PowerDistributionInfo(batteryPower: batteryPower, externalPower: externalPower, systemPower: systemPower)
        } catch {
            smcIsOpened = false
            throw error
        }
    }


    private func openSMCIfNeeded() async {
        guard !self.smcIsOpened else { return  }

        logger.notice("Opening SMC...")
        await attemptToOpenSMC(withRetryAttempts: 3)
    }

    private func attemptToOpenSMC(withRetryAttempts attempts: Int) async {
        var currentAttempt = 0

        while currentAttempt < attempts {
            do {
                try await openSMC()
                self.smcIsOpened = true
                return
            } catch {
                currentAttempt += 1
                if currentAttempt < attempts {
                    logger.error("Failed to open SMC, retrying... (\(currentAttempt)/\(attempts))")
                    try? await Task.sleep(for: .seconds(1))
                } else {
                    logger.error("Failed to open SMC after \(attempts) attempts. Giving up...")
                    logger.critical("SMC opening error: \(error)")
                    SentrySDK.capture(error: error)
                    return
                }
            }
        }
    }

    private func openSMC() async throws {
        logger.notice("Attempting to open SMC...")
        try SMCKit.open()
        logger.notice("SMC successfully opened!")
    }
    
    func isChargingEnabled() async throws -> Bool {
        logger.notice("Checking if charging is enabled")
        await openSMCIfNeeded()
        
        switch await currentBackend() {
        case .firmwareRange:
            // The question this answers is "is BatFi holding charge back with an inhibit",
            // and here — exactly as under `.systemChargeLimit` below — the answer is a flat
            // no. BatFi writes no inhibit under this backend at all: it hands the firmware
            // a band and steps back, and `enableCharging(_:)` is a no-op in both
            // directions. `true` is the accurate report.
            //
            // Reading `bfF0` here was the mistake, and it is worth naming precisely because
            // it looks so reasonable. `bfF0 == 0x02` means **a limit is in force**, which
            // is a different fact from **charging is being held back right now** — and once
            // the band became permanently armed the two stopped even correlating. The read
            // made this return `false` for the life of the process, which flows into
            // `SMCChargingStatus.inhitbitCharging` and is the *first* thing
            // `ChargingManager.fetchAndUpdateAppChargingState` branches on, so the app
            // resolved its mode to `.inhibit` unconditionally on this firmware — including
            // while the battery charged from 40% toward an 80% limit.
            //
            // The `bfF0` read is not lost: `chargingDiagnostics()` performs it and reports
            // it as `firmwareRangeIsArmed`, which is where a fact about the *band* belongs.
            logger.notice("Firmware charge range: BatFi holds no inhibit, charging is enabled")
            return true
        case .chte:
            let data = try SMCKit.readData(.inhibitCharging3)
            let isEnabled = data.0 == 0
            logger.notice("CHTE: charging enabled = \(isEnabled)")
            return isEnabled
        case .legacyCH0BC:
            let data = try SMCKit.readData(.inhibitCharging1)
            let isEnabled = data.0 == 0
            logger.notice("CH0B: charging enabled = \(isEnabled)")
            return isEnabled
        case .systemChargeLimit:
            // The question this answers is "is BatFi holding charge back with an inhibit",
            // and under Apple's Manual Charge Limit the answer is a flat no — there is no
            // inhibit key, `enableCharging` writes nothing, and the firmware stops at the
            // limit by itself. `true` is the accurate report, not a convenient one.
            //
            // Throwing here was not merely inaccurate, it was fatal to the whole backend.
            // This is reached from `smcChargingStatus()`, whose catch drops the backend
            // cache and closes the driver connection — so the status poll re-probed the
            // entire key table every 30 seconds, undoing the caching `setChargingMode`'s
            // fix above restores. Worse, `smcChargingStatus()` is the *only* thing that
            // moves the app off `ChargingMode.initial`, and `ChargingManager.updateStatus`
            // returns early while the mode is `.initial`. A throw here therefore pinned
            // the app in `.initial` for its whole life on precisely this firmware: no
            // charge limit applied, no mode decision ever taken, and after 30 seconds the
            // "BatFi can't read battery information" notification.
            logger.notice("System charge limit backend: BatFi holds no inhibit, charging is enabled")
            return true
        case .unsupported:
            // The question this answers is "is BatFi holding charge back with an inhibit",
            // and here — as under the two arms above — the answer is a flat no. BatFi
            // writes nothing on this firmware at all, so `true` is the accurate report.
            //
            // Throwing was not merely inaccurate, it was self-defeating. This is reached
            // from `smcChargingStatus()`, which rethrows, which
            // `ChargingManager.fetchAndUpdateAppChargingState` catches without setting a
            // mode — so the app stayed in `.initial` forever, `updateStatus` returned
            // early on every pass, and `ChargeControlDisclosure`'s `.unsupported` arm,
            // whose entire purpose is to tell *this* user the truth, never rendered. What
            // they got instead was "BatFi can't read battery information / macOS isn't
            // reporting the battery details BatFi needs", which blames a battery read for
            // a missing charge-control key.
            //
            // The honest failure has not been lost, it has been moved to where it belongs:
            // `applyChargeLimit` and `enableCharging` still throw
            // `SMCError.noChargeControlMechanism` here, so nothing pretends a limit or an
            // inhibit was put in force.
            logger.notice("No charge control mechanism on this firmware; BatFi holds no inhibit")
            return true
        }
    }
    
    func enableCharging(_ enable: Bool) async throws {
        if enable {
            logger.notice("Enabling charging")
        } else {
            logger.notice("Inhibit charging")
        }
        await openSMCIfNeeded()
        let enableByte: UInt8 = enable ? 0 : 1

        switch await currentBackend() {
        case .firmwareRange:
            // **A no-op that succeeds, in both directions**, and the same treatment
            // `.systemChargeLimit` gets below for the same reason: the mechanism owns the
            // charging decision. BatFi hands the firmware a band once, in `applyChargeLimit`,
            // and steps back; the firmware then decides moment to moment whether to charge,
            // and goes on deciding while the Mac is asleep with no BatFi process running.
            //
            // Releasing the band on the "enable" arm is the one thing that must not happen
            // here, however natural it looks. `ChargingManager.updateStatus` applies the
            // limit and *then* takes a mode decision, so a release would disarm the band in
            // the very pass that armed it, on every pass where the battery sits below the
            // limit — and the machine would sleep with nothing in force. That would leave
            // macOS 27 users with a backend that displaces Apple's charge limit while
            // enforcing strictly less than it. The release belongs to
            // `restoreSystemDefaults()`, which reaches it explicitly.
            //
            // The empty sequence is stated in `Shared`, where a test can see it, rather than
            // as a bare `break` here: `onlyTheReleasePathClearsActivation` fails the moment
            // a write is added to it.
            for step in FirmwareChargeRange.chargingModeChangeSequence {
                try perform(step)
            }
            // Inhibiting deserves a word of its own. It is not expressible as a band, so
            // this arm succeeds without honouring it — the same gap `.systemChargeLimit`
            // has. Hot-battery protection and inhibit-on-sleep route through here and will
            // not take effect below the limit. That is a disclosure the user is owed, not a
            // write to invent.
            if enable {
                logger.notice("Charging mode is governed by the firmware charge range; the band stays in force")
            } else {
                logger.notice("Charging mode is governed by the firmware charge range; it cannot pause charging below the limit")
            }
        case .chte:
            try SMCKit.writeData(.inhibitCharging3, byte0: enableByte, byte1: 0, byte2: 0, byte3: 0)
            logger.notice("Inhibit charging changed using CHTE")
        case .legacyCH0BC:
            try SMCKit.writeData(.inhibitCharging1, uint8: enableByte)
            try SMCKit.writeData(.inhibitCharging2, uint8: enableByte)
            logger.notice("Inhibit charging changed using CH0B/CH0C")
        case .systemChargeLimit:
            // Not a failure, and deliberately no longer grouped with `.unsupported`.
            // Under Apple's Manual Charge Limit BatFi does not drive the charging mode at
            // all: control is expressed as a *limit*, applied by `applyChargeLimit`, and
            // the firmware decides on its own when to stop. There is simply no
            // inhibit/allow write to make, so succeeding is the accurate answer and
            // throwing was a lie about a write that was never owed.
            //
            // It is also load-bearing. A throw here propagates out of `setChargingMode`,
            // whose catch resets the SMC keys, drops the backend cache and closes the
            // driver connection — on every mode change, on exactly the firmware this
            // backend exists for. And it propagates out of `restoreSystemDefaults()`,
            // where `ChargingManager.disengage()` reads it as "restore failed" and skips
            // both its own charging-mode update and its sleep-assertion release. Neither
            // of those had anything to do with an SMC write that was never needed.
            logger.notice("Charging mode is governed by the system charge limit; no SMC write needed")
        case .unsupported:
            // Still loud, and must stay that way: here there is genuinely no mechanism,
            // and reporting honestly is the design. `setChargingMode` recognizes this
            // particular error and does not treat it as a driver failure — see its catch.
            logger.error("No usable charge control mechanism on this firmware")
            throw SMCError.noChargeControlMechanism
        }
    }

    /// Performs one step of a firmware-range sequence.
    ///
    /// The `SMCKey` comes from the step's own shape key, so a sequence physically cannot
    /// name one key and write another, and the write length comes from the size the
    /// resolver verified against this firmware.
    ///
    /// Short byte arrays are padded out because `SMCKit.writeData` takes four; the driver
    /// only sends `info.size` of them, so the padding lands nowhere — that is what lets the
    /// one-byte activation write and the four-byte bound writes share a path.
    private func perform(_ step: FirmwareRangeWrite) throws {
        func byte(_ index: Int) -> UInt8 { index < step.bytes.count ? step.bytes[index] : 0 }
        try SMCKit.writeData(
            SMCKey(step.key),
            byte0: byte(0),
            byte1: byte(1),
            byte2: byte(2),
            byte3: byte(3)
        )
    }

    /// Hands the firmware a charge band.
    ///
    /// The steps, their order and their bytes are decided by
    /// `FirmwareChargeRange.engageSequence` — deactivate, upper, lower, activate, with the
    /// percentages little-endian against the house convention. This performs them and does
    /// not decide them: the order is a firmware requirement nobody here has the hardware to
    /// observe being violated, so it lives where a test can read it.
    private func applyFirmwareRange(_ limit: Int) throws {
        for step in FirmwareChargeRange.engageSequence(forLimit: limit) {
            try perform(step)
        }
        let band = FirmwareChargeRange.band(forLimit: limit)
        logger.notice("""
        Firmware charge range set to \(band.lower, privacy: .public)-\(band.upper, privacy: .public)%
        """)
    }

    /// Hands back the firmware-managed band on the one backend that holds one.
    ///
    /// The single place the release decision is taken. `restoreSystemDefaults()` calls this
    /// unconditionally and this switch answers whether there is anything to release, rather
    /// than the caller deciding — the same shape as `releaseSystemLimit()` self-guarding on
    /// its snapshot, and for the same reason: a hand-back that only the backend which set
    /// something can reach is a hand-back that a restarted BatFi cannot make.
    ///
    /// The other arms are genuinely nothing to do, not omissions. The inhibit backends are
    /// released by `enableCharging(true)`, Apple's limit by `releaseSystemLimit()` and
    /// `clearMCLOverride()` upstream, and `.unsupported` never armed anything. Writing
    /// `bfF0` on firmware that has no such key would throw, and `restoreSystemDefaults()`
    /// would report a failed restore on machines where the restore was complete.
    ///
    /// **`appliedFirmwareRange` is the second half of the condition, and it is the half
    /// that must not be removed.** The backend answer alone was not sufficient: the cache
    /// is dropped on every SMC write failure, and one flaky `kSMCGetKeyInfo` during the
    /// re-probe resolves this machine to something else while its band is still armed in
    /// hardware. Asking the process that armed it is the only question a degrading
    /// connection cannot answer wrongly.
    private func releaseFirmwareRangeIfHeld() async throws {
        // The backend is left unasked when the flag already settles it, which is not only
        // a saving: `currentBackend()` is a nine-key re-probe whenever the cache was
        // invalidated, and this runs on the quit path against a watchdog.
        let owed = FirmwareChargeRange.releaseIsOwed(
            armedByThisProcess: firmwareRangeArmed,
            resolvedBackend: firmwareRangeArmed ? nil : await currentBackend()
        )
        guard owed else { return }
        try releaseFirmwareRange()
    }

    /// Hands back a band this process armed while a different backend is now in force.
    ///
    /// Best-effort and non-throwing: it runs from the non-`.firmwareRange` arms of
    /// `applyChargeLimit`, where the caller's job is to put a limit in place and where a
    /// failure to tidy up an older mechanism must not abort that. A failure leaves
    /// `appliedFirmwareRange` set, so the next pass — and `restoreSystemDefaults()` — try
    /// again.
    private func releaseFirmwareRangeIfStranded() {
        guard firmwareRangeArmed else { return }
        logger.notice("Backend no longer resolves to the firmware charge range; releasing the band BatFi armed")
        do {
            try releaseFirmwareRange()
        } catch {
            logger.critical("Failed to release a stranded firmware charge range: \(error)")
        }
    }

    /// Takes the band out of force. A single write — the bounds mean nothing while the
    /// activation key is off — driven by the same list `resetIfPossible()` replays, so the
    /// release and the safety net cannot come to clear different keys.
    private func releaseFirmwareRange() throws {
        for step in FirmwareChargeRange.releaseSequence {
            try perform(step)
        }
        // Only after the write landed. A throw leaves the obligation recorded, which is
        // what makes the next attempt happen at all.
        firmwareRangeArmed = false
        appliedFirmwareRange = nil
        logger.notice("Firmware charge range released")
    }

    /// Whether the firmware exposes a force-discharge key in the shape this code needs.
    ///
    /// Existence is not enough to gate on. `probeCapability` only promises a non-zero
    /// size, and a same-named key of another shape — or a read-only one — accepts the
    /// write and ignores it, so "Run on Battery" would report success while the battery
    /// never discharged. Same rule the backend resolver applies to `CHTE`/`CH0B`/`CH0C`.
    ///
    /// The shapes themselves live in `ForceDischargeKeyShape`, in `Shared`, where the
    /// test suite can reach them — `CHIE`'s accepted encodings are measured facts about
    /// real firmware, and a change to them has to break a test rather than the fleet.
    /// This function only turns the `SMCKey` into a probed capability and asks.
    private func forceDischargeKeyIsUsable(_ key: SMCKey, writable: Bool) -> Bool {
        guard let capability = SMCKit.probeCapability(for: key) else { return false }
        return ForceDischargeKeyShape.isUsable(capability, writable: writable)
    }

    /// The write mechanisms "Run on Battery" can be driven through, in preference order.
    private enum ForceDischargeMechanism {
        /// `CHIE`. Current firmware, *including* firmware that has dropped `CHTE` — which
        /// is the whole reason this is resolved separately from `ChargeBackend`.
        case chie
        /// `CH0I` + `CH0J`, the Intel-era pair.
        case legacyCH0IJ
    }

    /// Which force-discharge mechanism this firmware exposes, or nil for none.
    ///
    /// The single place that answer is worked out. `enableForceDischarge` switches on it
    /// to pick the keys to write, and `chargingDiagnostics()` asks the same function
    /// whether the feature exists at all — so the flag the UI renders and the write path
    /// it describes cannot disagree. Encoding "is force discharge available" a second
    /// time, next to a write path that decides it independently, is exactly the failure
    /// this shape rules out.
    ///
    /// Probed independently of the charge backend, and shape-checked through
    /// `ForceDischargeKeyShape` rather than on key presence: a same-named key of another
    /// shape, or a read-only one, accepts the write and ignores it, so "Run on Battery"
    /// would report success while the battery never discharged.
    private func forceDischargeMechanism() -> ForceDischargeMechanism? {
        if forceDischargeKeyIsUsable(.disableCharging3, writable: true) { return .chie }
        // Gated on CH0I, the same key smcChargingStatus() gates its legacy read on, so
        // both paths agree on which key backs this mechanism and on the shape it has to
        // have. They are not the same test, and must not be: the read gate asks for
        // `writable: false`, this one for `writable: true`, so a readable-but-not-writable
        // CH0I still backs a status read while being refused as a write target. That is
        // the intended asymmetry — a write the firmware accepts and ignores is exactly
        // the silent failure this gate exists to prevent. CH0I and CH0J ship as a pair;
        // if CH0J were somehow absent its write throws loudly rather than reporting a
        // discharge that never engaged.
        if forceDischargeKeyIsUsable(.disableCharging1, writable: true) { return .legacyCH0IJ }
        return nil
    }

    /// Engages or releases force discharge.
    ///
    /// **Asymmetric where no mechanism exists, on purpose.** Engaging is something the
    /// user asked for, so a machine that cannot do it must fail loudly rather than
    /// pretend. Releasing is not a request, it is a safety write — and on firmware with
    /// no usable `CHIE`/`CH0I` there is no engaged state to clear, so there is nothing to
    /// fail at. Throwing there was actively harmful: `enableForceDischarge(false)` is
    /// called unconditionally from both `setChargingMode` and `restoreSystemDefaults()`,
    /// so a throw would propagate out of both on every mode change — undoing, on exactly
    /// the `.systemChargeLimit` firmware this whole backend exists for, the work that
    /// stopped those two functions failing.
    func enableForceDischarge(_ enable: Bool) async throws {
        if enable {
            logger.notice("Force discharge")
        } else {
            logger.notice("Turn off force discharge")
        }
        await openSMCIfNeeded()
        func engageByte(for key: SMCKey) -> UInt8 { enable ? key.forceDischargeEngagedValue : 0 }

        switch forceDischargeMechanism() {
        case .chie:
            try SMCKit.writeData(.disableCharging3, uint8: engageByte(for: .disableCharging3))
            logger.notice("Force discharge changed using CHIE")
        case .legacyCH0IJ:
            // `try`, not `try?`. The status read trusts `CH0I` alone, so a silently failed
            // `CH0I` write beside a successful `CH0J` one reports "not discharging" while
            // the adapter is isolated. It is safe to be loud here because
            // `forceDischargeMechanism()` selected this arm by shape-matching `CH0I` as
            // *writable*, so a throw is a real failure rather than an absent key.
            try SMCKit.writeData(.disableCharging1, uint8: engageByte(for: .disableCharging1))
            try SMCKit.writeData(.disableCharging2, uint8: engageByte(for: .disableCharging2))
            logger.notice("Force discharge changed using CH0I/CH0J")
        case nil:
            guard enable else {
                // Release with nothing to release. Not a failure, and saying so is what
                // keeps the callers above working on this firmware.
                logger.notice("No force discharge mechanism on this firmware; nothing to release")
                return
            }
            logger.error("No usable force discharge mechanism on this firmware")
            throw SMCError.keyNotFound(code: "CHIE")
        }
    }
}
