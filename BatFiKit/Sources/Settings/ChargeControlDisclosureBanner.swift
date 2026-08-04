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
                    // Orange only when something the user asked for is not happening. A
                    // box that is always orange says "problem" about a Mac whose firmware
                    // is enforcing the limit better than BatFi could — which is the
                    // opposite of what these rows say — and it costs the colour its meaning
                    // on the panes that do have something wrong.
                    .fill(hasWarning ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.10))
            }
            .padding(.bottom, 14)
        }
    }

    private var hasWarning: Bool {
        disclosures.contains(where: isWarning)
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
                if case .pausingChargingUnavailable(_, forceDischargeStillAvailable: true) = disclosure {
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
        case .limitRoundedUp(let requested, let applied):
            return l10n.systemChargeLimitRoundedUp(
                chargeLimitPercentageLabel(applied),
                chargeLimitPercentageLabel(requested)
            )
        case .managingSystemSettingsLimit:
            return l10n.systemChargeLimitManagesSystemSettings
        case .limitNotAppliedWithoutSnapshot:
            return l10n.systemChargeLimitNoSnapshot
        case .firmwareEnforcedLimit:
            return l10n.firmwareRangeEnforcedByFirmware
        case .batteryMayDipBelowLimit(let hysteresis):
            // Formatted with the same helper the slider label uses, so "5%" here and the
            // limit above it are written the same way.
            return l10n.firmwareRangeBatteryMayDipBelowLimit(chargeLimitPercentageLabel(hysteresis))
        case .chargingStatusIsInferred:
            return l10n.firmwareRangeChargingStatusIsInferred
        case .pausingChargingUnavailable(let heldBy, _):
            // The consequence is one statement; the mechanism holding charge is not, and
            // naming the wrong one would point a macOS 27 user at a System Settings value
            // BatFi never touches.
            switch heldBy {
            case .macOSChargeLimit:
                return l10n.systemChargeLimitCannotPauseCharging
            case .macFirmware:
                return l10n.firmwareRangeCannotPauseCharging
            }
        }
    }

    /// Whether something the user asked for is not happening, as opposed to a description
    /// of how this Mac works. Only the first kind gets the warning treatment.
    private func isWarning(_ disclosure: ChargeControlDisclosure) -> Bool {
        switch disclosure {
        case .chargingControlUnavailable,
             .limitRaisedToSystemMinimum,
             .limitRoundedUp,
             .limitNotAppliedWithoutSnapshot,
             .pausingChargingUnavailable:
            return true
        // Both firmware-range rows describe how this Mac works, and the first of them is
        // good news. Warning-styling either would tell a user whose limit is being
        // enforced through sleep that something is wrong.
        case .usingSystemChargeLimit,
             .managingSystemSettingsLimit,
             .firmwareEnforcedLimit,
             .batteryMayDipBelowLimit,
             // Not a warning either, and that is a judgement worth recording: nothing the
             // user asked for has stopped happening. The limit is enforced exactly and the
             // battery reading is real — only BatFi's label for what the firmware is doing
             // is inferred. Styling it orange would say the limit is unreliable, which is
             // precisely the wrong thing to leave a user believing.
             .chargingStatusIsInferred:
            return false
        }
    }

    private func symbolName(for disclosure: ChargeControlDisclosure) -> String {
        switch disclosure {
        case .chargingControlUnavailable,
             .limitRaisedToSystemMinimum,
             .limitRoundedUp,
             .limitNotAppliedWithoutSnapshot,
             .pausingChargingUnavailable:
            return "exclamationmark.triangle.fill"
        case .usingSystemChargeLimit, .batteryMayDipBelowLimit, .chargingStatusIsInferred:
            return "info.circle"
        case .firmwareEnforcedLimit:
            return "checkmark.seal"
        case .managingSystemSettingsLimit:
            return "gearshape"
        }
    }
}
