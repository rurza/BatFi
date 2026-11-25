//
//  EnergyView.swift
//  BatFi
//
//  The Energy settings pane: what BatFi does to save power on battery. One titled section
//  per feature, each built by its own property so the next one slots into the container
//  beside the others.
//

import AppShared
import Clients
import Defaults
import DefaultsKeys
import Dependencies
import L10n
import SettingsKit
import Shared
import SwiftUI

struct EnergyView: View {
    @Default(.autoLowPowerModeEnabled) private var autoLowPowerModeEnabled
    @Default(.autoLowPowerModeThreshold) private var autoLowPowerModeThreshold

    @Dependency(\.powerModeClient) private var powerModeClient

    /// Whether the helper can report Low Power Mode for the battery, which the automatic
    /// switch cannot work without. Assumed until the helper has answered otherwise: a
    /// current helper answers at once, while one too old to know the call only answers
    /// when the client's watchdog gives up on it, fifteen seconds later — too long to leave
    /// the section greyed out on every Mac that can use it.
    @State private var lowPowerModeAvailable = true

    /// Whether the helper may still be asked. The same rule the automatic Low Power Mode
    /// keeps: a *slow* "unknown" is an older helper that drops the call, and every ask costs
    /// a watchdog teardown of the shared connection fifteen seconds later, failing whatever
    /// else was in flight — so after one, the pane stops asking and stays unavailable. A
    /// quick "unknown" stops nothing, and the next appearance asks again.
    ///
    /// Never told a helper became healthy, so a stall holds for as long as the pane's state
    /// does: the settings window keeps its panes for the life of the app.
    @State private var helperSession = AutoLowPowerModeHelperSession()

    var body: some View {
        Container(contentWidth: settingsContentWidth) {
            lowPowerModeSection
            slowDownSection
        }
        .task {
            await checkLowPowerModeAvailability()
        }
    }

    private func checkLowPowerModeAvailability() async {
        guard helperSession.mayAsk else { return }
        let asked = helperSession.mark
        let started = ContinuousClock.now
        // The same test the automatic Low Power Mode applies before it acts: no battery
        // value is as good as no answer, since the battery value is the one it writes.
        let available = await powerModeClient.powerModeBySource()?.battery != nil
        if !available {
            helperSession.helperAnsweredUnknown(at: asked, after: ContinuousClock.now - started)
        }
        lowPowerModeAvailable = available
    }

    // MARK: - Low Power Mode

    // Spelled out because SwiftUI has a `Section` of its own; the container only takes these.
    private var lowPowerModeSection: SettingsKit.Section {
        let l10n = L10n.EnergySaving.self
        return SettingsKit.Section(title: l10n.lowPowerModeSectionTitle, bottomDivider: true) {
            VStack(alignment: .leading, spacing: 4) {
                let threshold = chargeLimitPercentageLabel(autoLowPowerModeThreshold)
                Toggle(isOn: $autoLowPowerModeEnabled) {
                    Text(l10n.lowPowerModeToggle(threshold))
                        .monospacedDigit()
                }
                // Locked only while off: a switch left on must always be switchable off,
                // helper or no helper.
                .disabled(!autoLowPowerModeEnabled && !lowPowerModeAvailable)
                SettingsSliderContainer(
                    minLabel: chargeLimitPercentageLabel(5),
                    maxLabel: chargeLimitPercentageLabel(50),
                    min: 5,
                    max: 50,
                    step: 5,
                    value: .convert(from: $autoLowPowerModeThreshold),
                    accessibility: (l10n.lowPowerModeThresholdAccessibilityLabel, threshold)
                )
                .disabled(!autoLowPowerModeEnabled || !lowPowerModeAvailable)
                .frame(width: 360)
            }

            lowPowerModeFootnote
                .padding(.top, 6)
        }
    }

    /// The footnote, or in its place the reason the feature can't be turned on.
    ///
    /// Both are always laid out and only one is visible, so the section is as tall as the
    /// longer of the two whatever the helper answers. `SettingsWindowController` sizes the
    /// window from `fittingSize` once, before the helper can have answered, so a note that
    /// arrived as an extra line would be cut off at the bottom of the window.
    private var lowPowerModeFootnote: some View {
        let l10n = L10n.EnergySaving.self
        return ZStack(alignment: .topLeading) {
            Text(l10n.lowPowerModeFootnote)
                .opacity(lowPowerModeAvailable ? 1 : 0)
                .accessibilityHidden(!lowPowerModeAvailable)
            Text(l10n.lowPowerModeUnavailable)
                .opacity(lowPowerModeAvailable ? 0 : 1)
                .accessibilityHidden(lowPowerModeAvailable)
        }
        .fixedSize(horizontal: false, vertical: true)
        .settingDescription()
    }

    // MARK: - Apps on battery

    private var slowDownSection: SettingsKit.Section {
        SettingsKit.Section(title: L10n.EnergySaving.slowDownSectionTitle) {
            SlowedAppsSettings()
        }
    }

    // MARK: - Pane

    static let pane: Pane<Self> = Pane(
        identifier: identifier,
        title: L10n.EnergySaving.paneTitle,
        toolbarIcon: NSImage(
            systemSymbolName: "leaf",
            accessibilityDescription: L10n.EnergySaving.paneAccessibilityTitle
        )!
    ) {
        Self()
    }

    static var identifier: NSToolbarItem.Identifier { .init("Energy") }
}

#Preview("Helper can report Low Power Mode") {
    withDependencies {
        $0.powerModeClient = .preview(powerModeBySource: PowerModeBySource(battery: 0, ac: 0, usesPowermodeKey: true))
    } operation: {
        EnergyView()
    }
}

#Preview("Helper can't report Low Power Mode") {
    withDependencies {
        $0.powerModeClient = .preview(powerModeBySource: nil)
    } operation: {
        EnergyView()
    }
}

private extension PowerModeClient {
    static func preview(powerModeBySource: PowerModeBySource?) -> Self {
        PowerModeClient(
            getCurrentPowerMode: { (.normal, false) },
            setPowerMode: { _, _ in },
            observePowerMode: { AsyncStream { $0.finish() } },
            powerModeBySource: { powerModeBySource }
        )
    }
}
