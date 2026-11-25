//
//  MagSafeGreenLightSetting.swift
//
//
//  What BatFi may do to the user's "green light on the MagSafe when charging is paused"
//  setting, given what the helper was able to find out about this Mac.
//
//  Here, beside `AppliedChargeLimit` and `ChargeControlDisclosure`, and for the same
//  reason: it is a decision with edge cases worth pinning, and `Shared` is the only module
//  the test target can reach. The decision is small and the cost of getting it wrong is
//  not — the "off" arm writes a persisted default that used to leave the settings toggle
//  stuck off, so a user whose Mac was fine could not put it back without `defaults write`.
//

import Foundation

/// What to do with `showGreenLightMagSafeWhenInhibiting`.
public enum MagSafeGreenLightSetting {
    public enum Action: Equatable, Sendable {
        /// The light works here, or nothing was learned. Leave the setting alone and ask
        /// again — a probe that could not run is not evidence about the firmware.
        case leaveAlone

        /// The light cannot be driven right now, but the reason is not durable enough to
        /// act on: the `ACLC` probe answered "absent", and a probe run over a degrading
        /// connection answers that for keys that are really there. Stop driving the LED
        /// for this session and ask again next launch. The user's setting is not touched.
        case suppressForThisSession

        /// The light cannot be driven here and never will be on this firmware, because the
        /// resolved backend cannot tell when charge is being held back at all
        /// (`ChargeBackend.canMirrorChargingStateOnMagSafeLED`). No backend answers that
        /// today; the arm stays so that withdrawing the light from one is a single edit. That is a
        /// property of the machine rather than of a probe, so the stored setting is turned
        /// off — a stored `true` re-arms the feature for every reader that does not
        /// independently ask the same question, and the settings pane is a reader too.
        case disablePermanently
    }

    /// - Parameters:
    ///   - magSafeLEDAvailable: `ChargingDiagnostics.magSafeLEDAvailable` — nil where the
    ///     helper could not ask.
    ///   - backend: the resolved backend, or nil for "not resolved / not recognized by
    ///     this build".
    ///
    /// The backend is consulted **first**, and deliberately: it is answered from a
    /// resolution the helper refuses to cache over a closed connection, so it is the one
    /// input here that a transient driver hiccup cannot fabricate. The LED probe has no
    /// such protection.
    public static func action(magSafeLEDAvailable: Bool?, backend: ChargeBackend?) -> Action {
        if let backend, !backend.canMirrorChargingStateOnMagSafeLED {
            return .disablePermanently
        }
        guard let magSafeLEDAvailable else { return .leaveAlone }
        return magSafeLEDAvailable ? .leaveAlone : .suppressForThisSession
    }

    /// The macOS version this process runs on, for the production callers of the two
    /// decisions below. A parameter there rather than a read inside, so the tests can pin
    /// both sides of the line without running on both systems.
    public static var currentOSMajorVersion: Int {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }

    /// Whether macOS, rather than BatFi, turns the light green while charge is held.
    ///
    /// Apple's own charge limit on macOS 27 and later, and nothing else. On 27 powerd sets
    /// `ACLC` itself while its limit holds — measured on 27.0.1, green at limits of 80 and
    /// 75, with nothing in BatFi writing the key — so a setting there cannot switch it off.
    ///
    /// **The backend alone is not enough, and that is the whole reason the version is an
    /// input.** Installing macOS 27 reflashes the SMC firmware for the whole Mac, and an
    /// older macOS booted afterwards does not roll it back. That firmware has no `CHTE`, so
    /// macOS 26 on it resolves to `.systemChargeLimit` exactly as 27 does — measured on
    /// 26.7.1 — but macOS 26 does not drive the LED for its limit: it stays amber while
    /// BatFi reports "Inhibiting charging". Reading the backend as "the system lights it"
    /// hid the toggle there, left the setting at its default of off, and so nobody lit it.
    /// Below 27 the light is BatFi's, and `MagSafeColorManager` lights it off the app's own
    /// `.inhibit` mode, which `ChargingManager` reports while macOS holds charge at the limit.
    public static func isSystemDriven(backend: ChargeBackend, osMajorVersion: Int) -> Bool {
        backend == .systemChargeLimit && osMajorVersion >= 27
    }

    /// Whether the settings pane shows the toggle at all, decided from the backend and the
    /// OS version alone.
    ///
    /// Hidden wherever the user can never change it: under `.systemChargeLimit` on macOS 27
    /// and later macOS turns the light green itself while its limit holds — see
    /// `isSystemDriven` for why the same backend on macOS 26 keeps the toggle — and under any
    /// backend that cannot mirror the charging state, of which there is none today. That is
    /// the treatment the Charging pane gives the capabilities a firmware loses —
    /// pause-on-sleep and the hot-battery cutout.
    ///
    /// No live fetch, because the pane needs the answer synchronously from the cached
    /// backend at first layout — the OS version is just as synchronous and cannot go stale: `SettingsWindowController` sizes the window once from
    /// `fittingSize`, so a control that disappears after a fetch leaves a gap. An unknown
    /// backend shows the toggle, since every Mac shipping today can drive its light.
    public static func isShownInSettings(
        backend: ChargeBackend?,
        osMajorVersion: Int = currentOSMajorVersion
    ) -> Bool {
        guard let backend else { return true }
        return backend.canMirrorChargingStateOnMagSafeLED
            && !isSystemDriven(backend: backend, osMajorVersion: osMajorVersion)
    }
}
