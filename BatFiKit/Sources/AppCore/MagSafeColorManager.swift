//
//  MagSafeColorManager.swift
//
//
//  Created by Adam on 16/07/2023.
//

import AppShared
import AsyncAlgorithms
import Clients
import DefaultsKeys
import Dependencies
import Foundation
import os
import Shared

public actor MagSafeColorManager {
    private lazy var logger = Logger(category: "MagSafe Color Manager")
    @Dependency(\.magSafeLEDColor) private var magSafeLEDColor
    @Dependency(\.defaults) private var defaults
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.suspendingClock) private var suspendingClock
    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Dependency(\.chargingClient) private var chargingClient

    public init() {}

    /// Whether `setUpObserving()` has already run.
    private var isObserving = false

    public func setUpObserving() {
        // Once only. The task below is never retained, so a second call added a
        // second observer rather than replacing the first, and `setUpTheApp()` calls
        // this from two places. Same flaw as `ChargingManager.setUpObserving()`.
        guard !isObserving else { return }
        isObserving = true
        Task {
            for await ((greenLight, blinkWhenDischarging, limit), (mode, powerState)) in
                combineLatest(
                    combineLatest(
                        defaults.observe(.showGreenLightMagSafeWhenInhibiting),
                        defaults.observe(.blinkMagSafeWhenDischarging),
                        defaults.observe(.chargeLimit)
                    ),
                    combineLatest(
                        appChargingState.appChargingModeDidChage(),
                        powerSourceClient.powerSourceChanges()
                    )
                )
                    .debounce(for: .seconds(1), clock: AnyClock(self.suspendingClock))
            {
                await updateMagsafeLEDIndicator(
                    showGreenLightWhenInhibiting: greenLight,
                    blinkWhenDischarging: blinkWhenDischarging,
                    powerState: powerState,
                    chargingMode: mode,
                    limit: limit
                )
            }
        }
    }

    public func appWillQuit() async {
        await resetMagSafeColor()
    }

    /// Whether the helper has answered "can the green light be driven on this Mac", and
    /// what it said. Nil until it has answered once; a failed or unreachable helper leaves
    /// it nil so the question is asked again rather than answered by guessing.
    private var magSafeGreenLightIsAvailable: Bool?

    /// The resolved charge backend, memoized for the life of the process — the same memo,
    /// and the same justification, as `ChargingManager.cachedChargeBackend`: a backend is a
    /// property of the firmware, and firmware is reflashed only by a macOS install, which
    /// restarts this process.
    ///
    /// It is here to keep `systemChargeLimitIsHoldingCharge` off the wire. That question is
    /// only meaningful under `.systemChargeLimit`, but it was gated on the *mode* alone —
    /// and `.charging` is the steady state of a plugged-in Mac below its limit. So on a
    /// plain `.chte` Mac with the green light on, every LED pass made an XPC round trip
    /// into `SMCService.chargingDiagnostics()`, which opens the SMC, reads `CHNC`, queries
    /// PowerUI and probes three more keys — and `SMCService` is an actor, so each of those
    /// serialized ahead of `applyChargeLimit`, `setChargingMode` and
    /// `restoreSystemDefaults`.
    private var cachedChargeBackend: ChargeBackend?

    /// Turns the green-light setting off **in `Defaults`** on a Mac where BatFi cannot tell
    /// when charge is being held back, rather than merely declining to act on it.
    ///
    /// Persisted because a stored `true` is a loaded gun: it outlives a firmware update, so
    /// one left on is one that re-arms the feature for any reader that does not
    /// independently ask the same question — and the settings pane is a reader too. Writing
    /// the answer where every reader already looks means it is stated once and cannot drift
    /// back on.
    ///
    /// **Which answers are durable enough to persist is not decided here.**
    /// `MagSafeGreenLightSetting.action` decides it, and the rule is that only the resolved
    /// backend justifies a write: a key probe that came back "absent" can have come back
    /// that way because the driver connection was briefly unavailable, and this write is
    /// not reversible from the UI. That arm suppresses the light for the session and asks
    /// again next launch instead.
    ///
    /// **Touches exactly one key.** `blinkMagSafeWhenDischarging` is not this function's to
    /// disable: it fires on BatFi's own `.forceDischarge` mode, written through `CHIE`,
    /// which works on this firmware and is known exactly. Sweeping it in here would switch
    /// off a working indicator for a feature that still works, on the same argument the
    /// disclosure copy is careful never to make.
    ///
    /// Asked at most once per launch, and only while there is something to disarm: after
    /// the write the default is false, so the guard below short-circuits with no XPC call
    /// for the life of the process. On a Mac where the green light works the answer is
    /// cached on the first pass and never asked again either.
    ///
    /// - Returns: whether it just turned the setting off, so the caller can leave the rest
    ///   of this pass alone.
    private func disarmGreenLightSettingIfUnavailable() async -> Bool {
        guard magSafeGreenLightIsAvailable == nil else { return false }
        guard defaults.value(.showGreenLightMagSafeWhenInhibiting) else { return false }
        // A helper that is unreachable leaves the answer unknown and the question open,
        // which is the safe direction — the alternative is switching a user's setting off
        // because the helper was slow to start.
        guard let diagnostics = try? await chargingClient.chargingDiagnostics() else { return false }
        let backend = ChargeBackend(rawValue: diagnostics.backend)
        if let backend { cachedChargeBackend = backend }
        switch MagSafeGreenLightSetting.action(
            magSafeLEDAvailable: diagnostics.magSafeLEDAvailable,
            backend: backend
        ) {
        case .leaveAlone:
            // Records `true` only when the answer really was "it works". An unknown stays
            // nil, so the next pass asks again rather than caching a non-answer.
            if diagnostics.magSafeGreenLightAvailable == true {
                magSafeGreenLightIsAvailable = true
            }
            return false
        case .suppressForThisSession:
            magSafeGreenLightIsAvailable = false
            logger.notice("The MagSafe LED key did not answer; not driving the green light this session")
            return false
        case .disablePermanently:
            magSafeGreenLightIsAvailable = false
            logger.notice("The green light can't be driven on this Mac; turning that setting off for good")
            defaults.setValue(.showGreenLightMagSafeWhenInhibiting, value: false)
            return true
        }
    }

    private func updateMagsafeLEDIndicator(
        showGreenLightWhenInhibiting: Bool,
        blinkWhenDischarging: Bool,
        powerState: PowerState,
        chargingMode: AppChargingMode,
        limit: Int
    ) async {
        // Ahead of everything else. On a Mac where the green light cannot be driven this
        // clears that one setting and the pass stops here: the values it was handed are the
        // old ones, and acting on them would light the LED once more on a machine whose
        // charging state BatFi cannot mirror. Writing the default is itself a change the
        // observing loop is watching, so it re-runs immediately with the setting off — and
        // the discharge blink, untouched, keeps working on the very next pass.
        let justDisarmed = await disarmGreenLightSettingIfUnavailable()
        guard !justDisarmed else { return }
        // The setting can still read `true` while the light is known not to work: the
        // suppress arm above deliberately leaves the user's value alone when the reason is
        // a probe that may simply not have run. Fold that in here rather than there, so
        // every green-light test below asks the same question.
        let showGreenLightWhenInhibiting = showGreenLightWhenInhibiting && magSafeGreenLightIsAvailable != false
        let appMode = chargingMode.mode
        let currentMagSafeLEDOption = try? await magSafeLEDColor.currentMagSafeLEDOption()
        if let currentMagSafeLEDOption = currentMagSafeLEDOption {
            logger.debug("Current MagSafe LED Option: \(currentMagSafeLEDOption)")
        } else {
            logger.warning("Current MagSafe LED Option is nil")
        }
        // Bound on its own line rather than folded into the `||` below: the right-hand
        // side of a short-circuiting operator is an autoclosure, which cannot be async.
        // The cheap short-circuit still happens — inside the helper, which answers false
        // without an XPC call in every mode but `.charging`.
        let systemLimitHoldsCharge = await systemChargeLimitIsHoldingCharge(
            appMode: appMode,
            showGreenLightWhenInhibiting: showGreenLightWhenInhibiting
        )
        let holdingCharge = appMode == .inhibit || systemLimitHoldsCharge
        if holdingCharge,
           showGreenLightWhenInhibiting,
           currentMagSafeLEDOption.isDifferentThan(.green) {
            logger.debug("Should change the color of MagSafe to green")
            do {
                _ = try await magSafeLEDColor.changeMagSafeLEDColor(.green)
                logger.debug("Color changed! 🎉")
            } catch {}
        } else if appMode == .forceDischarge, blinkWhenDischarging, currentMagSafeLEDOption.isDifferentThan(.errorOnce) {
            logger.debug("Should blink the LED and turn it off")
            _ = try? await magSafeLEDColor.changeMagSafeLEDColor(.errorOnce)
        } else if currentMagSafeLEDOption.isDifferentThan(.reset) &&
                    !(appMode == .forceDischarge && blinkWhenDischarging) && !(holdingCharge && showGreenLightWhenInhibiting)
        {
            await resetMagSafeColor()
        }
    }

    /// Whether Apple's own Manual Charge Limit is holding charge back right now.
    ///
    /// The second, additional signal behind the green light — not a replacement for
    /// BatFi's own inhibit flag, which still decides the colour on every SMC machine and
    /// is left byte-for-byte alone. It exists because under `.systemChargeLimit` BatFi
    /// holds no inhibit at all: the firmware stops at the limit by itself, so the app's
    /// own mode is silent about it and the LED would never go green on that firmware.
    /// `ChargingDiagnostics.systemChargeLimitIsHoldingCharge` is the attribution — the
    /// resolved backend plus the firmware's own `CHNC` bit 24 — and it is false under
    /// every other backend, which is what makes adding it here safe.
    ///
    /// Only asked in `.charging`, the one mode where the answer can change anything, and
    /// only when the green light is switched on at all — it costs an XPC round trip on a
    /// path that runs on every power-state change:
    /// - `.inhibit` already decides green on its own.
    /// - `.forceDischarge` must keep blinking. `CHNC` bit 24 can be set while the battery
    ///   is deliberately draining, and the green arm is tested first, so consulting this
    ///   there would turn a blink into a steady green.
    /// - `.initial` is "no decision taken yet", and must not produce one here either.
    private func systemChargeLimitIsHoldingCharge(
        appMode: ChargingMode,
        showGreenLightWhenInhibiting: Bool
    ) async -> Bool {
        guard showGreenLightWhenInhibiting, appMode == .charging else { return false }
        // The backend gate, and it is ahead of the round trip rather than inside the
        // helper on purpose: the round trip is the cost. Only asked while the backend is
        // still unknown, which is at most once.
        if let cachedChargeBackend, cachedChargeBackend != .systemChargeLimit { return false }
        // A helper that is unreachable or has nothing to say leaves the existing inhibit
        // flag as the only signal, which is the safe answer.
        let diagnostics = try? await chargingClient.chargingDiagnostics()
        if let backend = diagnostics.flatMap({ ChargeBackend(rawValue: $0.backend) }) {
            cachedChargeBackend = backend
        }
        return diagnostics?.systemChargeLimitIsHoldingCharge == true
    }

    private func resetMagSafeColor() async {
        do {
            logger.debug("Should reset the color of MagSafe...")
            _ = try await magSafeLEDColor.changeMagSafeLEDColor(.reset)
            logger.debug("Color reset was succesful! 🎉")
        } catch {
            logger.error("Error when resetting the color of MagSafe: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private extension Optional where Wrapped == MagSafeLEDOption {
    func isDifferentThan(_ option: MagSafeLEDOption) -> Bool {
        switch self {
        case .none:
            return true
        case .some(let wrapped):
            return wrapped != option
        }
    }
}
