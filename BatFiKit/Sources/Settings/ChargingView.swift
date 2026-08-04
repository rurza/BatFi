//
//  ChargingView.swift
//
//
//  Created by Adam on 05/05/2023.
//

import AppShared
import Clients
import Defaults
import DefaultsKeys
import Dependencies
import L10n
import SettingsKit
import Shared
import SharedUI
import SwiftUI

struct ChargingView: View {
    @Default(.chargeLimit) private var chargeLimit
    @Default(.manageCharging) private var manageCharging
    @Default(.allowDischargingFullBattery) private var dischargeBatteryWhenFull
    @Default(.turnOnInhibitingChargingWhenGoingToSleep) private var inhibitChargingOnSleep
    @Default(.disableSleepDuringDischarging) private var disableSleepDuringDischarging
    // Lives in the Advanced pane, read here because it is one of the two settings that
    // silently do nothing under Apple's Manual Charge Limit — and this is the pane that
    // explains what this Mac's charge control can and cannot do.
    @Default(.temperatureSwitch) private var turnOffChargingWhenBatteryIsHot

    @Dependency(\.systemVersionClient) var systemVersion
    @Dependency(\.chargingClient) private var chargingClient

    // What the helper says about charge control on this Mac. Re-fetched whenever the user
    // touches something that can change it: this no longer only feeds the read-only
    // Diagnostics section, it drives the warning sitting directly above the slider, and a
    // banner that still says "80% is in force" after the user has dragged to 85% is worse
    // than no banner.
    @State private var diagnostics: ChargingDiagnostics?

    // Held so a drag across the slider does not queue one fetch per step. Each change
    // cancels the previous wait; only the last one lands.
    @State private var diagnosticsReload: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Container(contentWidth: settingsContentWidth) {
                Section(bottomDivider: true) {
                    EmptyView()
                } content: {
                    let l10n = L10n.Settings.self
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Toggle(isOn: $manageCharging) {
                                EmptyView()
                            }
                            .controlSize(.regular)
                            Text(l10n.Button.Label.automaticallyManageCharging)
                        }
                        .toggleStyle(.switch)
                        .padding(.bottom, 20)
                        .padding(.top, 10)

                        GroupBackground {
                            VStack(alignment: .leading, spacing: 6) {
                                AutomationOverrideBanner()
                                ChargeControlDisclosureBanner(disclosures: facts.disclosures)
                                VStack(alignment: .leading, spacing: 14) {
                                    // The value the slider shows, which on firmware that
                                    // cannot express limits below 80% is the floor rather
                                    // than the stored number. Label and knob read the same
                                    // value so they cannot contradict each other, and the
                                    // banner above names what is really in force.
                                    let lowestLimit = ChargeLimitRange.lowestSelectable(for: facts.backend)
                                    let displayedLimit = ChargeLimitRange.displayedLimit(
                                        configured: chargeLimit,
                                        for: facts.backend
                                    )
                                    let label = l10n.Slider.Label.turnOffChargingAt(
                                        chargeLimitPercentageLabel(displayedLimit)
                                    )
                                    Text(label)
                                        .foregroundColor(manageCharging ? .primary : .secondary)
                                    HStack {
                                        Slider(
                                            value: limitSliderBinding(for: facts.backend),
                                            in: Double(lowestLimit) ... Double(ChargeLimitRange.highest),
                                            step: 5
                                        ) {
                                            EmptyView()
                                        } minimumValueLabel: {
                                            Text(chargeLimitPercentageLabel(lowestLimit))
                                        } maximumValueLabel: {
                                            Text(chargeLimitPercentageLabel(ChargeLimitRange.highest))
                                        }
                                        .disabled(!manageCharging)
                                        .frame(width: 360)
                                        Spacer()
                                    }.frame(maxWidth: .infinity)
                                }
                                .padding(.bottom, 14)

                                Toggle(isOn: $inhibitChargingOnSleep) {
                                    Text(l10n.Button.Label.pauseChargingOnSleep)
                                }
                                .disabled(!manageCharging)
                                .padding(.bottom, 4)

                                VStack(alignment: .leading, spacing: 2) {
                                    Toggle(isOn: $dischargeBatteryWhenFull) {
                                        Text(l10n.Button.Label.dischargeBatterWhenOvercharged)
                                    }
                                    .disabled(!manageCharging)
                                    .onChange(of: dischargeBatteryWhenFull) { _, newValue in
                                        if newValue {
                                            disableSleepDuringDischarging = true
                                        }
                                    }
                                    Text(l10n.Button.Description.lidMustBeOpened)
                                        .offset(x: 19)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .settingDescription()
                                        .opacity(manageCharging ? 1 : 0.4)
                                }
                                Toggle(isOn: $disableSleepDuringDischarging) {
                                    Text(l10n.Button.Label.disableSleepWhileDischarging)
                                }
                            }
                            .padding()
                        }
                    }
                }
                Section {
                    EmptyView()
                } content: {
                    VStack(alignment: .leading, spacing: 0) {
                        let l10n = L10n.Settings.Label.self
                        Group {
                            Text(l10n.chargingRecommendationPart1)
                            Text(l10n.chargingRecommendationPart2)
                        }
                        .settingDescription()
                    }
                }
                Section(title: L10n.Settings.Section.diagnostics) {
                    diagnosticsContent
                }
            }
        }
        .task {
            await loadDiagnostics()
        }
        // Both inputs that can change what the helper reports. The limit decides
        // `appliedChargeLimit`, `requestedChargeLimit` and `chargeLimitWasRaised`;
        // switching management off releases the limit entirely, which clears all three and
        // can clear a snapshot refusal with them.
        .onChange(of: chargeLimit) { _, _ in
            // The wait is for `ChargingManager` to observe the same default, ask the helper
            // to apply it and have the helper record the outcome. Fetching immediately
            // would read the state from before the change and pin the stale banner in
            // place rather than refreshing it.
            scheduleDiagnosticsReload(after: .milliseconds(750))
        }
        .onChange(of: manageCharging) { _, _ in
            scheduleDiagnosticsReload(after: .milliseconds(750))
        }
        .onDisappear {
            diagnosticsReload?.cancel()
            diagnosticsReload = nil
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
            // The "BatFi can't control charging on this Mac" line used to live here. It is
            // now one of the disclosures shown beside the slider, where the user actually
            // is — this section still reports the mechanism as "Not available".

            HStack(alignment: .firstTextBaseline) {
                Text(l10n.diagnosticsFirmware)
                Spacer(minLength: 20)
                Text(diagnostics?.firmwareVersion ?? l10n.diagnosticsFirmwareUnknown)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            // Keyed on the system's own percentage now that it crosses the XPC boundary,
            // and silent under `.systemChargeLimit`, where the limit it would warn about
            // is the one BatFi itself set. `ChargeControlFacts.conflictingSystemLimit`
            // holds the rule and the tests that pin it.
            if let conflictingLimit = facts.conflictingSystemLimit {
                Label(
                    l10n.diagnosticsSystemChargeLimitConflict(chargeLimitPercentageLabel(conflictingLimit)),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            }
        }
    }

    /// Everything the pane knows about charge control, in one value. The decisions that
    /// hang off it — which disclosures show, whether the slider is constrained, whether
    /// the conflict warning fires — all live in `Shared` and are tested there.
    private var facts: ChargeControlFacts {
        ChargeControlFacts(
            diagnostics: diagnostics,
            manageCharging: manageCharging,
            hotBatteryProtectionEnabled: turnOffChargingWhenBatteryIsHot,
            pauseChargingOnSleepEnabled: inhibitChargingOnSleep
        )
    }

    /// The resolved backend, reconstituted from `ChargingDiagnostics.backend`'s raw value.
    /// `nil` both before the initial fetch completes and if the helper ever reports a raw
    /// value this build doesn't recognize.
    private var chargeBackend: ChargeBackend? {
        facts.backend
    }

    /// Reads the value the slider should *show* and writes what the user picks.
    ///
    /// Asymmetric on purpose. A stored limit below what this Mac's mechanism can express
    /// is displayed at the floor but never written back to it: clamping the default would
    /// quietly replace the 55% the user chose — the very setting the banner above exists
    /// to talk about — and would lose it for good if this Mac later regains a mechanism
    /// that can honour it.
    private func limitSliderBinding(for backend: ChargeBackend?) -> Binding<Double> {
        let stored = $chargeLimit
        return Binding(
            get: { Double(ChargeLimitRange.displayedLimit(configured: stored.wrappedValue, for: backend)) },
            set: { stored.wrappedValue = Int($0) }
        )
    }

    /// User-facing summary of the resolved backend. `.chte`, `.legacyCH0BC` and
    /// `.firmwareRange` all read as "Active" — the mechanism only matters for a bug
    /// report, and the firmware token below already disambiguates that unambiguously.
    /// What the user needs from this line is whether their own limit is being honoured,
    /// and all three honour it exactly, below 80% included; `.systemChargeLimit` is
    /// called out separately because it is the one that cannot. Exhaustive over
    /// `ChargeBackend` so a future case fails to compile here rather than silently
    /// falling into the wrong branch.
    private var chargingControlDescription: String {
        guard let chargeBackend else {
            return L10n.Settings.Label.diagnosticsChargingControlUnknown
        }
        switch chargeBackend {
        case .unsupported:
            return L10n.Settings.Label.diagnosticsChargingControlUnavailable
        case .firmwareRange, .chte, .legacyCH0BC:
            return L10n.Settings.Label.diagnosticsChargingControlActive
        case .systemChargeLimit:
            return L10n.Settings.Label.diagnosticsChargingControlSystemChargeLimit
        }
    }

    private func loadDiagnostics() async {
        // A failed fetch leaves the previous snapshot in place rather than blanking it:
        // `nil` discloses nothing, so overwriting on a dropped connection would silently
        // retract a warning that is still true.
        if let fresh = try? await chargingClient.chargingDiagnostics() {
            diagnostics = fresh
        }
    }

    /// Re-reads the helper's snapshot once the change the user just made has had time to
    /// reach it, coalescing a burst of changes into a single fetch.
    private func scheduleDiagnosticsReload(after delay: Duration) {
        diagnosticsReload?.cancel()
        diagnosticsReload = Task {
            // Cancellation lands as a thrown error here; the guard covers the case where it
            // arrives after the sleep has already completed.
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await loadDiagnostics()
        }
    }

    static let pane: Pane<Self> = Pane(
        identifier: identifier,
        title: L10n.Settings.Tab.Title.charging,
        toolbarIcon: NSImage(
            systemSymbolName: "bolt.badge.a",
            accessibilityDescription: L10n.Settings.Accessibility.Title.charging
        )!
    ) {
        Self()
    }

    static var identifier: NSToolbarItem.Identifier { .init("Charging") }
}

struct ChargingView_Previews: PreviewProvider {
    static var previews: some View {
        ChargingView()
    }
}
