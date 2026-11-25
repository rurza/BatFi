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
//  Shown only where it is a real, editable control, and absent everywhere else — the
//  treatment the Charging pane gives every other capability this firmware loses
//  (pause-on-sleep and the hot-battery cutout are hidden the same way). Two states are
//  hidden:
//
//  - *Unavailable*: the Mac has no MagSafe LED at all, or the backend cannot tell when
//    charge is held back (none today). `ChargingDiagnostics.magSafeGreenLightAvailable`
//    carries that rule — the `ACLC` probe narrowed by
//    `ChargeBackend.canMirrorChargingStateOnMagSafeLED`.
//  - *System-driven*: under `.systemChargeLimit` on macOS 27 and later, macOS sets `ACLC`
//    itself while its own limit holds, so the light is already green and the setting cannot
//    switch it off. `ChargingDiagnostics.magSafeGreenLightIsSystemDriven` carries that one.
//    Not on macOS 26: a Mac that has had 27 installed keeps 27's firmware when it boots 26,
//    resolves to the same backend there, and 26 leaves the LED amber at its limit — so the
//    toggle is shown and BatFi lights it, see `MagSafeGreenLightSetting.isSystemDriven`.
//
//  These used to be shown disabled, with a sentence underneath saying why. Hiding is more
//  consistent with the rest of the pane: a switch the user can never move is not a setting.
//  The user's stored preference is never written here, so it comes back as it was if the
//  Mac ever changes backend.
//

import Clients
import Defaults
import DefaultsKeys
import Dependencies
import L10n
import Shared
import SwiftUI

/// "Use the green light on the MagSafe when charging is paused", present only on a Mac
/// where BatFi drives the light and the user can actually change it.
///
/// **Visibility is decided at first layout from the cached backend**
/// (`MagSafeGreenLightSetting.isShownInSettings`), not from the live fetch:
/// `SettingsWindowController` sizes the window once from `fittingSize` before any fetch
/// answers, so a control that disappeared afterwards would leave a gap the window cannot
/// close. That cache, read with the OS version, covers the durable case — Apple's charge
/// limit on macOS 27 and later. The live fetch can still hide the toggle afterwards, which only happens on a Mac
/// with no MagSafe LED (a probe answer, not a backend property) or one whose cache is
/// stale; both are rare, and a missing switch beats one that does nothing.
///
/// The setting is *also* turned off in `Defaults` by `MagSafeColorManager`, independently of
/// anything shown here — but only where the reason is durable, see
/// `MagSafeGreenLightSetting`. Hiding a control is no protection on its own: the stored
/// value outlives this view and every other reader looks at it directly, so where the answer
/// is permanent it has to be cleared where it is stored.
struct MagSafeGreenLightToggle: View {
    @Default(.showGreenLightMagSafeWhenInhibiting) private var greenLight

    @Dependency(\.chargingClient) private var chargingClient

    /// Optimistic until the helper answers. Every Mac shipping today can drive its green
    /// light, and hiding the setting for the moment before the first fetch lands would
    /// flicker on all of them to be accurate about none.
    @State private var isAvailable = true

    /// The system, not BatFi, is driving the light. Pessimistic before the fetch — the
    /// opposite default to `isAvailable`, and for the same reason it is optimistic: the
    /// honest pre-answer state is the ordinary editable control, not a claim.
    @State private var isSystemDriven = false

    /// Read synchronously so the decision is already right on the first render. Unknown
    /// shows the toggle; see `MagSafeGreenLightSetting.isShownInSettings`.
    private var shownForCachedBackend: Bool {
        let backend = Defaults[.lastKnownChargeBackend].flatMap(ChargeBackend.init(rawValue:))
        return MagSafeGreenLightSetting.isShownInSettings(backend: backend)
    }

    var body: some View {
        if shownForCachedBackend, isAvailable, !isSystemDriven {
            Toggle(isOn: $greenLight) {
                Text(L10n.Settings.Button.Label.magsafeUseGreenLight)
            }
            // Here rather than at the call site, so a hidden toggle leaves no spacing behind.
            .padding(.bottom, 4)
            .task {
                // A failed fetch keeps the toggle rather than hiding it: the same fail-open
                // rule the pane's other diagnostics reads follow, since a dropped connection
                // is not evidence about the firmware. `?? true` for the same reason, one
                // level down: the helper answers nil when it could not probe at all, and
                // "could not ask" is not "not there".
                if let diagnostics = try? await chargingClient.chargingDiagnostics() {
                    isAvailable = diagnostics.magSafeGreenLightAvailable ?? true
                    // `?? false` rather than `?? true`: an unrecognized backend keeps the
                    // ordinary editable control instead of hiding it on a guess.
                    isSystemDriven = diagnostics.magSafeGreenLightIsSystemDriven() ?? false
                }
            }
        }
    }
}
