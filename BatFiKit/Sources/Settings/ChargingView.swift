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
    // What the helper last said this Mac's mechanism can do. Read synchronously so the
    // hidden controls are absent from the first render rather than vanishing after it.
    @Default(.lastKnownCanPauseCharging) private var canPauseChargingCache
    @Default(.lastKnownForceDischargeAvailable) private var forceDischargeAvailableCache

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
                                conflictingSystemLimitWarning
                                VStack(alignment: .leading, spacing: 14) {
                                    // The value the slider shows, which on firmware that
                                    // cannot express limits below 80% is the floor rather
                                    // than the stored number. Label and knob read the same
                                    // value so they cannot contradict each other, and the
                                    // help button beside them names what is really in
                                    // force for the Macs where the two differ.
                                    let lowestLimit = ChargeLimitRange.lowestSelectable(for: facts.backend)
                                    let displayedLimit = ChargeLimitRange.displayedLimit(
                                        configured: chargeLimit,
                                        for: facts.backend
                                    )
                                    let label = l10n.Slider.Label.turnOffChargingAt(
                                        chargeLimitPercentageLabel(displayedLimit)
                                    )
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(label)
                                            .foregroundColor(manageCharging ? .primary : .secondary)
                                        Spacer(minLength: 8)
                                        ChargeControlHelpButton(disclosures: facts.disclosures)
                                    }
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

                                // Absent, not greyed out, where this Mac's firmware cannot
                                // honour them: a setting that cannot do anything is not a
                                // setting. The stored preference is left untouched, so it
                                // comes back exactly as it was if the Mac ever regains a
                                // mechanism that can act on it. The help button beside the
                                // slider is what explains the absence.
                                if !pausingChargingUnavailable {
                                    Toggle(isOn: $inhibitChargingOnSleep) {
                                        Text(l10n.Button.Label.pauseChargingOnSleep)
                                    }
                                    .disabled(!manageCharging)
                                    .padding(.bottom, 4)
                                }

                                if !forceDischargeUnavailable {
                                    VStack(alignment: .leading, spacing: 2) {
                                        // Forced on and greyed out where macOS performs the
                                        // discharge, the same treatment the MagSafe green
                                        // light gets and for the same reason: the behaviour is
                                        // real and better than BatFi's, it simply is not
                                        // BatFi's to switch off. Shown rather than hidden
                                        // because it *does* happen — the pane hides settings
                                        // this Mac has lost, and this is the opposite case.
                                        // Not written through to `Defaults`, so the user's own
                                        // choice survives a change of backend.
                                        Toggle(isOn: dischargeIsSystemDriven ? .constant(true) : $dischargeBatteryWhenFull) {
                                            Text(l10n.Button.Label.dischargeBatterWhenOvercharged)
                                        }
                                        .disabled(!manageCharging || dischargeIsSystemDriven)
                                        .onChange(of: dischargeBatteryWhenFull) { _, newValue in
                                            if newValue {
                                                disableSleepDuringDischarging = true
                                            }
                                        }
                                        Text(
                                            dischargeIsSystemDriven
                                                ? l10n.Button.Description.dischargeIsSystemDriven
                                                : l10n.Button.Description.lidMustBeOpened
                                        )
                                        .offset(x: 19)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .settingDescription()
                                        .opacity(manageCharging ? 1 : 0.4)
                                    }
                                    // Only meaningful while discharging, so it shares the
                                    // gate. Its lack of a `manageCharging` check is
                                    // pre-existing and left alone.
                                    //
                                    // Absent entirely where macOS drives the discharge: that
                                    // drain continues while asleep and lid-closed, so there is
                                    // nothing for holding sleep off to protect. This is the
                                    // pane's usual rule for a setting that cannot do anything
                                    // — and here it would do worse than nothing, since BatFi
                                    // no longer takes the assertion at all under this backend.
                                    if !dischargeIsSystemDriven {
                                        Toggle(isOn: $disableSleepDuringDischarging) {
                                            Text(l10n.Button.Label.disableSleepWhileDischarging)
                                        }
                                    }
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
                // The Diagnostics rows moved to the General pane. Keeping them here meant
                // this pane mixed a titled section with untitled ones, and `Container`
                // sizes an untitled section as if the label column did not exist before
                // shifting it into one anyway — which ran this pane's full-width content
                // off the right edge of the window. Every section here is untitled now.
            }
        }
        .task {
            await loadDiagnosticsAndRefreshCache()
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

    /// The one thing on this pane that is both a problem and the user's to fix: their own
    /// System Settings charge limit can stop charging before BatFi's does. It stays inline
    /// rather than moving behind the help button, because unlike the disclosures it is not
    /// a description of how this Mac works — it is an instruction to go change something.
    ///
    /// Keyed on the system's own percentage now that it crosses the XPC boundary, and
    /// silent under `.systemChargeLimit`, where the limit it would warn about is the one
    /// BatFi itself set. `ChargeControlFacts.conflictingSystemLimit` holds the rule and the
    /// tests that pin it.
    @ViewBuilder
    private var conflictingSystemLimitWarning: some View {
        if let conflictingLimit = facts.conflictingSystemLimit {
            Label(
                L10n.Settings.Label.diagnosticsSystemChargeLimitConflict(
                    chargeLimitPercentageLabel(conflictingLimit)
                ),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.callout)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 10)
        }
    }

    /// Whether this Mac can stop charging on demand — read from the cache, not from the
    /// live fetch, because the controls it gates are *hidden* rather than greyed out and
    /// visibility has to be right on the very first render. See
    /// `Defaults.Keys.lastKnownCanPauseCharging` for why the window cannot cope otherwise.
    ///
    /// Under `.systemChargeLimit` and `.firmwareRange` the limit is held by macOS or the
    /// firmware, neither of which offers a "stop now", so pausing on sleep writes nothing.
    private var pausingChargingUnavailable: Bool { !canPauseChargingCache }

    /// Whether this Mac can run off its battery with the charger attached, which is what
    /// both discharge settings depend on. Probed from its own SMC key, so it is answered
    /// separately from charge limiting and can outlive it.
    private var forceDischargeUnavailable: Bool { !forceDischargeAvailableCache }

    /// Whether macOS performs the over-limit discharge itself on this Mac.
    ///
    /// Read from the cached backend rather than from `facts`, for the same reason the two
    /// capability caches above it exist: the row then renders in its final state on the first
    /// pass, instead of showing an editable toggle that greys itself out a moment later.
    ///
    /// Defaults to false on an unknown or unrecognised backend, so a Mac whose backend has not
    /// been resolved yet keeps the ordinary editable control rather than being told macOS owns
    /// a discharge it may well not be doing.
    private var dischargeIsSystemDriven: Bool {
        guard let raw = Defaults[.lastKnownChargeBackend], let backend = ChargeBackend(rawValue: raw)
        else { return false }
        return backend.dischargesToLimitItself
    }

    /// Writes what the helper just said into the cache the panes render from. Called on
    /// every successful fetch, so a firmware change costs one stale render and settles.
    private func refreshCapabilityCache() {
        guard diagnostics != nil else { return }
        canPauseChargingCache = facts.backend?.canPauseChargingOnDemand ?? true
        forceDischargeAvailableCache = facts.forceDischargeAvailable
    }

    /// Everything the pane knows about charge control, in one value. The decisions that
    /// hang off it — which disclosures show, whether the slider is constrained, whether
    /// the conflict warning fires — all live in `Shared` and are tested there.
    private var facts: ChargeControlFacts {
        ChargeControlFacts(
            diagnostics: diagnostics,
            manageCharging: manageCharging,
            configuredChargeLimit: chargeLimit,
            hotBatteryProtectionEnabled: turnOffChargingWhenBatteryIsHot,
            pauseChargingOnSleepEnabled: inhibitChargingOnSleep
        )
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

    private func loadDiagnosticsAndRefreshCache() async {
        await loadDiagnostics()
        refreshCapabilityCache()
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
            await loadDiagnosticsAndRefreshCache()
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
