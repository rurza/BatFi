//
//  ChargeControlDisclosureBanner.swift
//  BatFi
//
//  Renders what `ChargeControlFacts` decided has to be said about charge control on this
//  Mac. Which statements are true is decided in `Shared`, where it is tested; this file
//  only turns those values into words and puts them beside the slider they are about.
//
//  Shown next to the limit slider rather than down in Diagnostics on purpose: a user whose
//  55% is not being applied needs to read that where they set it, not in a section they
//  open when filing a bug report.
//

import AppShared
import L10n
import Shared
import SwiftUI

/// Formats a whole-percent charge limit for display.
///
/// Shared with `ChargingView` so the number in the banner and the number on the slider are
/// formatted the same way, and written without the force-unwrap the pane used to carry: a
/// formatter that declines the conversion falls back to the plain number rather than
/// crashing a settings pane.
func chargeLimitPercentageLabel(_ percentage: Int) -> String {
    percentageFormatter.string(from: NSNumber(value: Double(percentage) / 100)) ?? "\(percentage)%"
}

struct ChargeControlDisclosureBanner: View {
    let disclosures: [ChargeControlDisclosure]

    var body: some View {
        if !disclosures.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                // Indexed rather than by value: the list is short, ordered, and fixed by
                // `ChargeControlFacts.disclosures`, and nothing here needs identity.
                ForEach(Array(disclosures.enumerated()), id: \.offset) { _, disclosure in
                    row(for: disclosure)
                }
            }
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
            }
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private func row(for disclosure: ChargeControlDisclosure) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbolName(for: disclosure))
                .foregroundStyle(isWarning(disclosure) ? Color.orange : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(text(for: disclosure))
                // The precision the "hot battery and sleep do nothing" finding asked for.
                // Force discharge is probed from its own key and outlives charge limiting,
                // so where it still works the user is told that in the same breath rather
                // than left to assume everything went down together.
                if case .pausingChargingUnavailable(forceDischargeStillAvailable: true) = disclosure {
                    Text(L10n.Settings.Label.systemChargeLimitForceDischargeStillWorks)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Exhaustive over `ChargeControlDisclosure` with no `default:` arm, so a new case has
    /// to be given words here rather than silently rendering as another one.
    private func text(for disclosure: ChargeControlDisclosure) -> String {
        let l10n = L10n.Settings.Label.self
        switch disclosure {
        case .chargingControlUnavailable:
            return l10n.diagnosticsChargingControlUnsupportedExplanation
        case .usingSystemChargeLimit:
            return l10n.systemChargeLimitBanner
        case .limitRaisedToSystemMinimum(let applied):
            return l10n.systemChargeLimitRaised(chargeLimitPercentageLabel(applied))
        case .managingSystemSettingsLimit:
            return l10n.systemChargeLimitManagesSystemSettings
        case .limitNotAppliedWithoutSnapshot:
            return l10n.systemChargeLimitNoSnapshot
        case .pausingChargingUnavailable:
            return l10n.systemChargeLimitCannotPauseCharging
        }
    }

    /// Whether something the user asked for is not happening, as opposed to a description
    /// of how this Mac works. Only the first kind gets the warning treatment.
    private func isWarning(_ disclosure: ChargeControlDisclosure) -> Bool {
        switch disclosure {
        case .chargingControlUnavailable,
             .limitRaisedToSystemMinimum,
             .limitNotAppliedWithoutSnapshot,
             .pausingChargingUnavailable:
            return true
        case .usingSystemChargeLimit, .managingSystemSettingsLimit:
            return false
        }
    }

    private func symbolName(for disclosure: ChargeControlDisclosure) -> String {
        switch disclosure {
        case .chargingControlUnavailable,
             .limitRaisedToSystemMinimum,
             .limitNotAppliedWithoutSnapshot,
             .pausingChargingUnavailable:
            return "exclamationmark.triangle.fill"
        case .usingSystemChargeLimit:
            return "info.circle"
        case .managingSystemSettingsLimit:
            return "gearshape"
        }
    }
}
