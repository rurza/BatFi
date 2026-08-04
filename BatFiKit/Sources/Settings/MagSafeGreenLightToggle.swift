//
//  MagSafeGreenLightToggle.swift
//  BatFi
//
//  The one MagSafe setting that depends on BatFi knowing when charge is being held back,
//  and therefore the one a backend can take away.
//
//  Its neighbour in the Notifications pane — blink the LED when BatFi discharges — is
//  deliberately *not* built on this and stays a plain `Toggle`. That one fires on BatFi's
//  own `.forceDischarge` mode, written through `CHIE`, which works on macOS 27 firmware and
//  is known exactly. Gating both on one answer switched off a working indicator for a
//  feature that still works.
//
//  The rule is not decided here. `ChargingDiagnostics.magSafeGreenLightAvailable` carries
//  it — the `ACLC` probe narrowed by `ChargeBackend.canMirrorChargingStateOnMagSafeLED` —
//  and this view only renders it.
//

import Clients
import Defaults
import DefaultsKeys
import Dependencies
import L10n
import Shared
import SwiftUI

/// "Use the green light on the MagSafe when charging is paused", disabled with the reason
/// on a Mac where BatFi cannot tell that charging is paused.
///
/// Disabled rather than hidden. A user who knows their Mac has a MagSafe LED and finds the
/// setting simply gone learns nothing; leaving it visible with the reason underneath is the
/// same treatment the Charging pane gives every other capability this firmware lost.
///
/// The setting is *also* turned off in `Defaults` by `MagSafeColorManager`, independently of
/// anything shown here — but only where the reason is durable, see
/// `MagSafeGreenLightSetting`. Greying out a control is no protection on its own: the stored
/// value outlives this view and every other reader looks at it directly, so where the answer
/// is permanent it has to be cleared where it is stored.
struct MagSafeGreenLightToggle: View {
    @Default(.showGreenLightMagSafeWhenInhibiting) private var greenLight

    @Dependency(\.chargingClient) private var chargingClient

    /// Optimistic until the helper answers. Every Mac shipping today can drive its green
    /// light, and greying the setting out for the moment before the first fetch lands would
    /// flicker on all of them to be accurate about none.
    @State private var isAvailable = true

    /// Which of the two reasons to give. `true` — the Mac has a MagSafe LED — means the
    /// unavailability is the firmware's charge reporting; `false` means there is no
    /// indicator light to drive at all, and the firmware sentence would describe a machine
    /// this user does not have. Optimistic before the fetch, like `isAvailable`, so the
    /// pair never renders "no light" on a Mac that has one.
    @State private var hasMagSafeLED = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: $greenLight) {
                Text(L10n.Settings.Button.Label.magsafeUseGreenLight)
            }
            .disabled(!isAvailable)
            if !isAvailable {
                Text(
                    hasMagSafeLED
                        ? L10n.Settings.Label.magSafeGreenLightUnavailable
                        : L10n.Settings.Label.magSafeGreenLightNoLED
                )
                .offset(x: 19)
                .fixedSize(horizontal: false, vertical: true)
                .settingDescription()
            }
        }
        .task {
            // A failed fetch leaves the setting enabled rather than disabling it: the same
            // fail-open rule the pane's other diagnostics reads follow, since a dropped
            // connection is not evidence about the firmware.
            // `?? true` for the same reason, one level down: the helper answers nil when
            // it could not probe at all, and "could not ask" is not "not there".
            if let diagnostics = try? await chargingClient.chargingDiagnostics() {
                isAvailable = diagnostics.magSafeGreenLightAvailable ?? true
                hasMagSafeLED = diagnostics.magSafeLEDAvailable ?? true
            }
        }
    }
}
