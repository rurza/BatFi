//
//  ChargingLimitView.swift
//
//
//  Created by Adam on 01/06/2023.
//

import AppShared
import Defaults
import DefaultsKeys
import L10n
import Shared
import SharedUI
import SwiftUI

struct ChargingLimitView: View {
    @Default(.chargeLimit) private var chargeLimit
    @Default(.launchAtLogin) private var launchAtLogin
    @ObservedObject var model: Onboarding.Model

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
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            // Resolved by the model at helper-install time, so this is the
                            // real floor from the first frame rather than a permissive guess
                            // that corrects itself. That is the entire point of this pane
                            // coming after the helper.
                            let lowestLimit = ChargeLimitRange.lowestSelectable(for: model.backend)
                            let displayedLimit = ChargeLimitRange.displayedLimit(
                                configured: chargeLimit,
                                for: model.backend
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
                        Divider()
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle(L10n.Onboarding.Button.Label.launchAtLogin, isOn: $launchAtLogin)
                            Text(l10n.launchAtLoginRecommendation)
                                .foregroundStyle(.secondary)
                                // Wraps rather than truncating. Without this the label is
                                // handed a single line and clipped mid-word — it only just
                                // overruns the group's width in English, and every longer
                                // translation loses more of the sentence. Every other
                                // multi-line `Text` in this pane carries the same modifier.
                                .fixedSize(horizontal: false, vertical: true)
                                // Required, otherwise it will render in center, SwiftUI bug
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                }
                Text(l10n.appIsReady)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
    }

    private func percentageLabel(_ percentage: Int) -> String {
        percentageFormatter.string(from: NSNumber(value: Double(percentage) / 100)) ?? "\(percentage)%"
    }
}
