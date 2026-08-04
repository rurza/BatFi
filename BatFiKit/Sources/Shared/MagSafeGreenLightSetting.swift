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
//  not — the "off" arm writes a persisted default that the settings pane then renders as a
//  disabled control, so a user whose Mac is fine cannot put it back without `defaults
//  write`.
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
        /// resolved backend cannot tell when charge is being held back at all. That is a
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
}
