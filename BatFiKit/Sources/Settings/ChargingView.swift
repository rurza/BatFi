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
import License
import SettingsKit
import Shared
import SharedUI
import SwiftUI

struct ChargingView: View {
    /// Handed to the override banner, which is the only part of the pane that reads it, so a
    /// licence change redraws the banner rather than the whole pane.
    let unlockModel: UnlockModel

    @Default(.chargeLimit) private var chargeLimit
    @Default(.manageCharging) private var manageCharging
    @Default(.sailingEnabled) private var sailingEnabled
    @Default(.sailingResumeLevel) private var sailingResumeLevel
    @Default(.allowDischargingFullBattery) private var dischargeBatteryWhenFull
    @Default(.turnOnInhibitingChargingWhenGoingToSleep) private var inhibitChargingOnSleep
    @Default(.disableSleepDuringDischarging) private var disableSleepDuringDischarging
    // Also read by `facts`: under the firmware range it is one of the two settings that
    // silently do nothing, and this is the pane that explains what this Mac's charge control
    // can and cannot do.
    @Default(.temperatureSwitch) private var turnOffChargingWhenBatteryIsHot
    @Default(.disableSleep) private var disableAutomaticSleep
    // What the helper last said this Mac's mechanism can do. Read synchronously so the
    // hidden controls are absent from the first render rather than vanishing after it.
    @Default(.lastKnownCanPauseCharging) private var canPauseChargingCache
    @Default(.lastKnownForceDischargeAvailable) private var forceDischargeAvailableCache
    // The hot-battery toggle asks a narrower question than the two above, and no cache of
    // its own is needed for it: the backend itself is cached, by the client, on every fetch.
    @Default(.lastKnownChargeBackend) private var lastKnownChargeBackend

    @Dependency(\.systemVersionClient) var systemVersion
    @Dependency(\.chargingClient) private var chargingClient
    @Dependency(\.otherChargeTools) private var otherChargeTools

    // Other charge-control tools installed on this Mac, as the last scan found them.
    @State private var detectedChargeTools: [DetectedChargeTool] = []

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
                                AutomationOverrideBanner(unlockModel: unlockModel)
                                conflictingSystemLimitWarning
                                otherChargeToolsWarning
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
                                    // With sailing on the caption names both levels; off,
                                    // it is today's, word for word.
                                    let label = sailingEnabled
                                        ? L10n.Sailing.sliderCaption(
                                            chargeLimitPercentageLabel(displayedLimit),
                                            chargeLimitPercentageLabel(displayedResumeLevel)
                                        )
                                        : l10n.Slider.Label.turnOffChargingAt(
                                            chargeLimitPercentageLabel(displayedLimit)
                                        )
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(label)
                                            .foregroundColor(manageCharging ? .primary : .secondary)
                                        Spacer(minLength: 8)
                                        ChargeControlHelpButton(disclosures: facts.disclosures)
                                    }
                                    HStack {
                                        // Sailing off keeps the system slider exactly as it
                                        // was; on, the track widens to 20% so both handles
                                        // share one scale.
                                        if sailingEnabled {
                                            ChargeRangeSlider(
                                                limit: limitBinding(for: facts.backend),
                                                resumeLevel: resumeLevelBinding,
                                                limitRange: lowestLimit ... ChargeLimitRange.highest,
                                                track: SailingRange.trackLowerBound(
                                                    sailingEnabled: true,
                                                    lowestLimit: lowestLimit
                                                ) ... ChargeLimitRange.highest
                                            )
                                            .disabled(!manageCharging)
                                            .frame(width: 360)
                                        } else {
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
                                        }
                                        Spacer()
                                    }.frame(maxWidth: .infinity)

                                    // Under the slider in both states, so turning it on adds
                                    // the second handle without moving anything else.
                                    VStack(alignment: .leading, spacing: 2) {
                                        Toggle(isOn: sailingToggleBinding(for: facts.backend)) {
                                            Text(L10n.Sailing.toggleLabel)
                                        }
                                        .disabled(!manageCharging)
                                        Text(L10n.Sailing.toggleDescription)
                                            .offset(x: 19)
                                            .padding(.trailing, 19)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .settingDescription()
                                            .opacity(manageCharging ? 1 : 0.4)
                                    }
                                }
                                .padding(.bottom, 14)

                                // Absent, not greyed out, where this Mac's firmware cannot
                                // honour them: a setting that cannot do anything is not a
                                // setting. The stored preference is left untouched, so it
                                // comes back exactly as it was if the Mac ever regains a
                                // mechanism that can act on it. The help button beside the
                                // slider is what explains the absence.
                                //
                                // Pausing on sleep and delaying sleep share the gate for the
                                // same reason: there is no "stop now" to call. Delaying sleep
                                // protects nothing where the firmware or macOS holds the limit
                                // through sleep, and since the battery sits just below the
                                // limit there it kept the Mac awake on AC indefinitely;
                                // `ChargingManager` applies the same gate at runtime.
                                if !pausingChargingUnavailable {
                                    Toggle(isOn: $inhibitChargingOnSleep) {
                                        Text(l10n.Button.Label.pauseChargingOnSleep)
                                    }
                                    .disabled(!manageCharging)
                                    .padding(.bottom, 4)
                                }

                                // A gate of its own, because the cutout needs less: charging
                                // held where the battery is, which Apple's charge limit does
                                // by being set to the current level (`HotBatteryHold`). It
                                // defaults to **on**, so where even that is missing — the
                                // firmware range — it would be the one default-on setting
                                // that could quietly do nothing at 45 °C, and is hidden.
                                if hotBatteryCutoutAvailable {
                                    Toggle(isOn: $turnOffChargingWhenBatteryIsHot) {
                                        Text(l10n.Button.Label.turnOffChargingWhenBatteryIsHot)
                                            .help(l10n.Button.Tooltip.turnOffChargingWhenBatteryIsHot)
                                    }
                                    .padding(.bottom, 4)
                                }

                                if !pausingChargingUnavailable {
                                    Toggle(isOn: $disableAutomaticSleep) {
                                        Text(l10n.Button.Label.disableAutomaticSleep)
                                            .help(l10n.Button.Tooltip.disableAutomaticSleep)
                                    }
                                    .padding(.bottom, 4)
                                }

                                // Hides itself wherever the user can never change it —
                                // under `.firmwareRange` and Apple's charge limit — deciding
                                // from the cached backend so it is right at first layout.
                                MagSafeGreenLightToggle()

                                if !forceDischargeUnavailable {
                                    VStack(alignment: .leading, spacing: 2) {
                                        // Forced on and greyed out where macOS performs the
                                        // discharge: the behaviour is real and better than
                                        // BatFi's, it simply is not BatFi's to switch off.
                                        // Shown rather than hidden because it *does* happen
                                        // and is what the user asked for — the pane hides
                                        // settings this Mac has lost, and this is the
                                        // opposite case.
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
        // Follows every scan, starting with the last one's result. A tool the user removes
        // while this pane is open disappears on the next scan; the one below runs each time
        // the pane opens, so coming back to it after running the removal command is enough.
        .task {
            for await detected in otherChargeTools.observe() {
                detectedChargeTools = detected
            }
        }
        .task {
            _ = await otherChargeTools.detect()
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
        // Sailing changes the band handed to the firmware under `.firmwareRange`, and with it
        // what the helper reports, the same way the limit does.
        .onChange(of: sailingEnabled) { _, _ in
            scheduleDiagnosticsReload(after: .milliseconds(750))
        }
        .onChange(of: sailingResumeLevel) { _, _ in
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

    /// Other charge-control tools fight BatFi over the same SMC keys, and only the user can
    /// remove them, so like the conflict above this is an instruction rather than a
    /// disclosure, and sits beside it. One warning per tool: what it fights over on this
    /// Mac's backend, then how to remove it. `OtherChargeToolWarning` holds the wording
    /// choice and the tests that pin it.
    ///
    /// The backend comes from the live fetch when it has landed and from the cache before
    /// that, so the battery CLI on macOS 27-era firmware is not first described as fighting
    /// over the limit and then corrected.
    @ViewBuilder
    private var otherChargeToolsWarning: some View {
        let backend = facts.backend ?? Defaults[.lastKnownChargeBackend].flatMap(ChargeBackend.init(rawValue:))
        ForEach(detectedChargeTools.map { OtherChargeToolWarning(detected: $0, backend: backend) }) { warning in
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(warning.problem)
                    // Markdown so the Terminal commands show as code, and selectable so
                    // they can be copied rather than retyped.
                    Text((try? AttributedString(markdown: warning.removal)) ?? AttributedString(warning.removal))
                        .textSelection(.enabled)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
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

    /// Whether the hot-battery cutout can act on this Mac — `canHoldChargeAtCurrentLevel`,
    /// read off the cached backend for the same first-render reason as the caches above.
    ///
    /// An unresolved or unrecognised backend falls back to the pause cache, which is what
    /// gated this toggle before and defaults to showing it.
    private var hotBatteryCutoutAvailable: Bool {
        guard let raw = lastKnownChargeBackend, let backend = ChargeBackend(rawValue: raw) else {
            return !pausingChargingUnavailable
        }
        return backend.canHoldChargeAtCurrentLevel
    }

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
            pauseChargingOnSleepEnabled: inhibitChargingOnSleep,
            sailingResumeLevel: sailingEnabled ? displayedResumeLevel : nil
        )
    }

    /// The resume level the second handle shows: the stored one, or 10 below the limit before
    /// one is chosen, clamped against the limit the slider displays.
    ///
    /// The backend is read straight off the snapshot rather than from `facts`, which is built
    /// from this value.
    private var displayedResumeLevel: Int {
        let backend = diagnostics.flatMap { ChargeBackend(rawValue: $0.backend) }
        return SailingRange.resolvedResumeLevel(
            limit: ChargeLimitRange.displayedLimit(configured: chargeLimit, for: backend),
            stored: sailingResumeLevel
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

    /// The limit as the two-handle slider reads and writes it: the same rule as
    /// `limitSliderBinding`, in whole percentages.
    private func limitBinding(for backend: ChargeBackend?) -> Binding<Int> {
        let stored = $chargeLimit
        return Binding(
            get: { ChargeLimitRange.displayedLimit(configured: stored.wrappedValue, for: backend) },
            set: { stored.wrappedValue = $0 }
        )
    }

    /// The resume handle shows `displayedResumeLevel` and stores what the user picks;
    /// `ChargeRangeSlider` has already clamped it through `SailingRange`.
    private var resumeLevelBinding: Binding<Int> {
        Binding(
            get: { displayedResumeLevel },
            set: { sailingResumeLevel = $0 }
        )
    }

    /// Turning sailing on stores the resume level the handle will show — 10 below the limit
    /// the first time — before switching on, so the charging logic never reads sailing on
    /// with no valid level. A valid stored level is kept, so switching off and on again
    /// brings back the one the user chose.
    private func sailingToggleBinding(for backend: ChargeBackend?) -> Binding<Bool> {
        Binding(
            get: { sailingEnabled },
            set: { isOn in
                if isOn {
                    let limit = ChargeLimitRange.displayedLimit(configured: chargeLimit, for: backend)
                    let resolved = SailingRange.resolvedResumeLevel(limit: limit, stored: sailingResumeLevel)
                    if sailingResumeLevel != resolved {
                        sailingResumeLevel = resolved
                    }
                }
                sailingEnabled = isOn
            }
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

    static func pane(unlockModel: UnlockModel) -> Pane<Self> {
        Pane(
            identifier: identifier,
            title: L10n.Settings.Tab.Title.charging,
            toolbarIcon: NSImage(
                systemSymbolName: "bolt.badge.a",
                accessibilityDescription: L10n.Settings.Accessibility.Title.charging
            )!
        ) {
            Self(unlockModel: unlockModel)
        }
    }

    static var identifier: NSToolbarItem.Identifier { .init("Charging") }
}

struct ChargingView_Previews: PreviewProvider {
    static var previews: some View {
        let trialModel = TrialModel()
        ChargingView(
            unlockModel: UnlockModel(licenseModel: LicenseModel(trialModel: trialModel), trialModel: trialModel)
        )
    }
}
