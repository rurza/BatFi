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

    @Dependency(\.systemVersionClient) var systemVersion
    @Dependency(\.chargingClient) private var chargingClient

    // Fetched once from the helper and shown read-only for bug reports.
    @State private var diagnostics: ChargingDiagnostics?

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
                                VStack(alignment: .leading, spacing: 14) {
                                    let label = l10n.Slider.Label.turnOffChargingAt(
                                        percentageFormatter.string(from: NSNumber(value: Double(chargeLimit) / 100))!
                                    )
                                    Text(label)
                                        .foregroundColor(manageCharging ? .primary : .secondary)
                                    HStack {
                                        Slider(value: .convert(from: $chargeLimit), in: 50 ... 90, step: 5) {
                                            EmptyView()
                                        } minimumValueLabel: {
                                            Text(L10n.Settings.Label.lowestLimit)
                                        } maximumValueLabel: {
                                            Text(L10n.Settings.Label.highestLimit)
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
            if chargeBackend == .unsupported {
                Text(l10n.diagnosticsChargingControlUnsupportedExplanation)
                    .fixedSize(horizontal: false, vertical: true)
                    .settingDescription()
            }

            HStack(alignment: .firstTextBaseline) {
                Text(l10n.diagnosticsFirmware)
                Spacer(minLength: 20)
                Text(diagnostics?.firmwareVersion ?? l10n.diagnosticsFirmwareUnknown)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            if systemChargeLimitMayConflict {
                Label(l10n.diagnosticsSystemChargeLimitWarning, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }

    /// The resolved backend, reconstituted from `ChargingDiagnostics.backend`'s raw value.
    /// `nil` both before the initial fetch completes and if the helper ever reports a raw
    /// value this build doesn't recognize.
    private var chargeBackend: ChargeBackend? {
        diagnostics.flatMap { ChargeBackend(rawValue: $0.backend) }
    }

    // BatFi neutralizes the system's own Charge Limit by overriding it to 100% whenever
    // it's actively managing charging. No active override means whatever the user set
    // natively in System Settings is the one in effect — which can silently cap charging
    // below the limit configured above. That only matters while BatFi is actually
    // managing charging: with automatic management off, BatFi holds no override by
    // design, and the system's own limit is exactly what should be in effect.
    private var systemChargeLimitMayConflict: Bool {
        guard let mcl = diagnostics?.mcl else { return false }
        return manageCharging && mcl.supported && !mcl.batFiHasActiveOverride
    }

    /// User-facing summary of the resolved backend. `.chte` and `.legacyCH0BC` both read
    /// as "Active" — the mechanism only matters for a bug report, and the firmware token
    /// below already disambiguates that unambiguously. Exhaustive over `ChargeBackend` so
    /// a future case (`.systemChargeLimit`, `.firmwareRange`) fails to compile here rather
    /// than silently falling into the wrong branch.
    private var chargingControlDescription: String {
        guard let chargeBackend else {
            return L10n.Settings.Label.diagnosticsChargingControlUnknown
        }
        switch chargeBackend {
        case .unsupported:
            return L10n.Settings.Label.diagnosticsChargingControlUnavailable
        case .chte, .legacyCH0BC:
            return L10n.Settings.Label.diagnosticsChargingControlActive
        }
    }

    private func loadDiagnostics() async {
        diagnostics = try? await chargingClient.chargingDiagnostics()
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
