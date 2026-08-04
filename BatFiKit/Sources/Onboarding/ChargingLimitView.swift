//
//  ChargingLimitView.swift
//
//
//  Created by Adam on 01/06/2023.
//

import AppShared
import Clients
import Defaults
import DefaultsKeys
import Dependencies
import L10n
import Shared
import SharedUI
import SwiftUI

struct ChargingLimitView: View {
    @Default(.chargeLimit) private var chargeLimit
    @Default(.launchAtLogin) private var launchAtLogin
    @ObservedObject var model: Onboarding.Model

    @Dependency(\.chargingClient) private var chargingClient

    /// The resolved backend, or nil while unknown — which is the normal state here, since
    /// this pane can be reached before the helper is installed. Nil gives the same 50%
    /// floor the pane always had, so nothing regresses on a Mac that cannot answer yet.
    ///
    /// Asked at all because the range was hardcoded `50 ... 90` with hardcoded end labels,
    /// while `ChargingView` stops the slider at the floor this Mac's mechanism can express.
    /// A new user on `.systemChargeLimit` was walked through choosing 55% in the one pane
    /// every new user sees, and then told in Settings that 55% cannot be applied.
    @State private var backend: ChargeBackend?

    var body: some View {
        VStack(spacing: 0) {
            let l10n = L10n.Onboarding.Label.self
            AVPlayerViewRepresented(player: model.player)
                .edgesIgnoringSafeArea(.all)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.4, contentMode: .fill)
            VStack(alignment: .leading, spacing: 20) {
                Text(l10n.setLimit)
                    .font(.system(size: 24, weight: .bold))
                    .padding(.bottom, -10) // so the space between header and the text is -10
                Text(l10n.setLimitDescription)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                GroupBackground {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            let lowestLimit = ChargeLimitRange.lowestSelectable(for: backend)
                            let displayedLimit = ChargeLimitRange.displayedLimit(
                                configured: chargeLimit,
                                for: backend
                            )
                            // No force-unwrap. A formatter that declines the conversion
                            // falls back to the plain number rather than crashing the one
                            // pane every new user sees.
                            Text(L10n.Onboarding.Slider.Label.setLimit(percentageLabel(displayedLimit)))
                            Slider(
                                value: .convert(from: $chargeLimit),
                                in: Double(lowestLimit) ... Double(ChargeLimitRange.highest),
                                step: 5
                            ) {
                                EmptyView()
                            } minimumValueLabel: {
                                Text(percentageLabel(lowestLimit))
                            } maximumValueLabel: {
                                Text(percentageLabel(ChargeLimitRange.highest))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        Spacer()
                        Text(l10n.setLimitSetUpLater)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
            .padding(20)
        }
        .task {
            // A failed fetch — the usual case here, since the helper may not be installed
            // yet — leaves the backend nil and the slider at its widest, which is the
            // permissive direction.
            if let diagnostics = try? await chargingClient.chargingDiagnostics() {
                backend = ChargeBackend(rawValue: diagnostics.backend)
            }
        }
    }

    private func percentageLabel(_ percentage: Int) -> String {
        percentageFormatter.string(from: NSNumber(value: Double(percentage) / 100)) ?? "\(percentage)%"
    }
}
