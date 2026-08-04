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

    public func setUpObserving() {
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

    private func updateMagsafeLEDIndicator(
        showGreenLightWhenInhibiting: Bool,
        blinkWhenDischarging: Bool,
        powerState: PowerState,
        chargingMode: AppChargingMode,
        limit: Int
    ) async {
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
        // `try?` over a throwing call that already returns an optional nests two levels;
        // flattened here so the property below is read off the diagnostics, not off an
        // optional wrapping them. A helper that is unreachable or has nothing to say
        // leaves the existing inhibit flag as the only signal, which is the safe answer.
        let diagnostics = (try? await chargingClient.chargingDiagnostics()) ?? nil
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
