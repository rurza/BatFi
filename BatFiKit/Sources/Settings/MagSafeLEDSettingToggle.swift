//
//  MagSafeLEDSettingToggle.swift
//  BatFi
//
//  The two MagSafe LED settings live in two different panes — the green light in
//  Advanced, the discharge blink in Notifications — and share one availability rule. It is
//  written here once so the two cannot drift: a Mac where BatFi cannot drive the LED must
//  not offer one of them and refuse the other.
//
//  The rule itself is not decided here. `ChargingDiagnostics.magSafeLEDAvailable` carries
//  the answer, which is the `ACLC` probe narrowed by
//  `ChargeBackend.canMirrorChargingStateOnMagSafeLED`; this view only renders it.
//

import Clients
import Dependencies
import L10n
import Shared
import SwiftUI

/// A MagSafe LED setting, switched off and disabled with an explanation on a Mac whose
/// charging state BatFi cannot mirror.
///
/// Disabled rather than hidden. A user who knows their Mac has a MagSafe LED and finds the
/// setting simply gone learns nothing; leaving it visible with the reason underneath is the
/// same treatment the rest of the Charging pane gives a capability this firmware lost.
///
/// The toggle is *also* turned off in `Defaults` by `MagSafeColorManager`, independently of
/// anything shown here. Disabling a control the user cannot see the state of would be no
/// protection at all: the settings sync between Macs, so the stored value has to be cleared
/// where it is stored, not merely greyed out where it is drawn.
struct MagSafeLEDSettingToggle: View {
    let title: String
    @Binding var isOn: Bool

    @Dependency(\.chargingClient) private var chargingClient

    /// Optimistic until the helper answers. Every Mac shipping today can drive its LED, and
    /// greying the setting out for the moment before the first fetch lands would flicker on
    /// all of them to be accurate about none.
    @State private var isAvailable = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: $isOn) {
                Text(title)
            }
            .disabled(!isAvailable)
            if !isAvailable {
                Text(L10n.Settings.Label.magSafeLEDUnavailable)
                    .offset(x: 19)
                    .fixedSize(horizontal: false, vertical: true)
                    .settingDescription()
            }
        }
        .task {
            // A failed fetch leaves the setting enabled rather than disabling it: the same
            // fail-open rule the pane's other diagnostics reads follow, since a dropped
            // connection is not evidence about the firmware.
            if let diagnostics = try? await chargingClient.chargingDiagnostics() {
                isAvailable = diagnostics.magSafeLEDAvailable
            }
        }
    }
}
