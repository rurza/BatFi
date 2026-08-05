//
//  GeneralView.swift
//
//
//  Created by Adam on 05/05/2023.
//

import Clients
import Defaults
import Dependencies
import L10n
import ServiceManagement
import SettingsKit
import Shared
import SharedUI
import SwiftUI

struct GeneralView: View {
    @State private var automaticallyDownloadsUpdates: Bool = false

    /// What the helper reports about charge control on this Mac. Read-only here — the
    /// Charging pane keeps its own copy because it drives live decisions there (the
    /// slider's floor, which disclosures the help button carries). This one only prints
    /// two lines for a bug report, so it is fetched once and never refreshed.
    @State private var diagnostics: ChargingDiagnostics?

    @Default(.sendAnalytics) private var sendAnalytics
    @Default(.launchAtLogin) private var launchAtLogin
    @Default(.downloadBetaVersion) private var checkForBetaUpdates

    // Read only to build `ChargeControlFacts` below, which is what keeps the "Charging
    // control" row honest about whether BatFi is actually doing anything.
    @Default(.manageCharging) private var manageCharging
    @Default(.chargeLimit) private var chargeLimit
    @Default(.temperatureSwitch) private var turnOffChargingWhenBatteryIsHot
    @Default(.turnOnInhibitingChargingWhenGoingToSleep) private var inhibitChargingOnSleep

    @Dependency(\.featureFlags) private var featureFlags
    @Dependency(\.updater) private var updater
    @Dependency(\.chargingClient) private var chargingClient

    @Environment(\.openURL) private var openURL

    var body: some View {
        let l10n = L10n.Settings.self
        Container(contentWidth: settingsContentWidth) {
            Section(title: l10n.Section.general) {
                Toggle(l10n.Button.Label.launchAtLogin, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if newValue {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
            }
            Section(title: l10n.Section.updates, bottomDivider: true) {
                Toggle(l10n.Button.Label.automaticallyDownloadUpdates, isOn: $automaticallyDownloadsUpdates)
                    .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
                        updater.setAutomaticallyDownloadsUpdates(newValue)
                    }
                Toggle(l10n.Button.Label.checkForBetaUpdates, isOn: $checkForBetaUpdates)
                    .onChange(of: checkForBetaUpdates) { _, checkForBetaUpdates in
                        if checkForBetaUpdates {
                            updater.checkForUpdates()
                        }
                    }
            }
            Section(title: l10n.Section.other, bottomDivider: true) {
                VStack(alignment: .leading) {
                    if featureFlags.isUsingBetaVersion() {
                        Toggle(l10n.Button.Label.sendAnalytics, isOn: .constant(true))
                            .disabled(true)
                        Text(l10n.Label.analyticsAreAlwaysOnDuringBeta).settingDescription()
                    } else {
                        Toggle(l10n.Button.Label.sendAnalytics, isOn: $sendAnalytics)
                    }
                }
            }
            // Lives here rather than in the Charging pane, where it started. It is
            // reference material for a bug report, not something to read while setting a
            // limit, and every section in this pane is titled — which is what gives these
            // rows a correctly-sized column instead of one that overruns the window.
            Section(title: l10n.Section.diagnostics) {
                diagnosticsContent
            }
        }
        .onAppear {
            automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates()
        }
        .task {
            // A failed fetch leaves `nil` in place, which renders as "Unknown" rather than
            // asserting something false about this Mac.
            if let fresh = try? await chargingClient.chargingDiagnostics() {
                diagnostics = fresh
            }
        }
    }

    @ViewBuilder
    private var diagnosticsContent: some View {
        let l10n = L10n.Settings.Label.self
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(l10n.diagnosticsChargingControl)
                Spacer(minLength: 20)
                Text(chargingControlDescription)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(l10n.diagnosticsFirmware)
                Spacer(minLength: 20)
                Text(diagnostics?.firmwareVersion ?? l10n.diagnosticsFirmwareUnknown)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    /// Everything known about charge control, in one value — the same construction the
    /// Charging pane makes, from the same defaults, so the two panes cannot disagree about
    /// what this Mac is doing.
    private var facts: ChargeControlFacts {
        ChargeControlFacts(
            diagnostics: diagnostics,
            manageCharging: manageCharging,
            configuredChargeLimit: chargeLimit,
            hotBatteryProtectionEnabled: turnOffChargingWhenBatteryIsHot,
            pauseChargingOnSleepEnabled: inhibitChargingOnSleep
        )
    }

    /// User-facing summary of the resolved backend. `.chte`, `.legacyCH0BC` and
    /// `.firmwareRange` all read as "Active" — the mechanism only matters for a bug
    /// report, and the firmware row below disambiguates it unambiguously. What the user
    /// needs from this line is whether their own limit is being honoured, and all three
    /// honour it exactly, below 80% included; `.systemChargeLimit` is called out
    /// separately because it is the one that cannot. Exhaustive over `ChargeBackend` so a
    /// future case fails to compile here rather than silently falling into another branch.
    private var chargingControlDescription: String {
        let l10n = L10n.Settings.Label.self
        // Read off `facts`, not off the backend alone. The backend says what this Mac's
        // firmware *can* do, and that is not the same question: with charge management
        // switched off, or when the helper refused to snapshot the user's System Settings
        // limit and is therefore applying nothing, the hardware is still perfectly capable
        // while BatFi is doing nothing with it. Both of those used to read "Active".
        guard let backend = facts.backend else {
            return l10n.diagnosticsChargingControlUnknown
        }
        guard facts.manageCharging else {
            // Resolved, and not in use. `.unsupported` still reports itself, since there is
            // nothing to be idle about.
            return backend == .unsupported
                ? l10n.diagnosticsChargingControlUnavailable
                : l10n.diagnosticsChargingControlIdle
        }
        if facts.systemLimitSnapshotRefused, backend == .systemChargeLimit {
            return l10n.diagnosticsChargingControlUnavailable
        }
        switch backend {
        case .unsupported:
            return l10n.diagnosticsChargingControlUnavailable
        case .firmwareRange, .chte, .legacyCH0BC:
            return l10n.diagnosticsChargingControlActive
        case .systemChargeLimit:
            return l10n.diagnosticsChargingControlSystemChargeLimit
        }
    }

    static let pane: Pane<Self> = Pane(
        identifier: NSToolbarItem.Identifier("General"),
        title: L10n.Settings.Tab.Title.general,
        toolbarIcon: NSImage(
            systemSymbolName: "gear",
            accessibilityDescription: L10n.Settings.Accessibility.Title.general
        )!
    ) {
        Self()
    }
}

struct GeneralView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralView()
    }
}
