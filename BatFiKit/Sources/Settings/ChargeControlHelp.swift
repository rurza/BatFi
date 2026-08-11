//
//  ChargeControlHelp.swift
//  BatFi
//
//  Renders what `ChargeControlFacts` decided has to be said about charge control on this
//  Mac. Which statements are true is decided in `Shared`, where it is tested; this file
//  only turns those values into words.
//
//  These used to be a permanent banner stacked above the slider. It was three paragraphs
//  tall, it dominated the pane, and — more to the point — it described BatFi's internals
//  ("charging can't be paused", "BatFi's own charge control") when the only thing a user
//  wants to know is whether their battery is going to stop at the limit they picked. On
//  the backends that trigger these disclosures it does. So the explanation moved behind a
//  standard macOS help button, and the copy behind it now leads with the outcome.
//
//  The button still signals when something the user switched on is not taking effect:
//  `ChargeControlFacts` marks those disclosures as warnings and the glyph turns orange,
//  so the one case that genuinely costs the user something is not silent.
//

import AppShared
import L10n
import Shared
import SwiftUI

/// Formats a whole-percent charge limit for display.
///
/// Shared with `ChargingView` so the number in the help text and the number on the slider
/// are formatted the same way, and written without a force-unwrap: a formatter that
/// declines the conversion falls back to the plain number rather than crashing a pane.
func chargeLimitPercentageLabel(_ percentage: Int) -> String {
    percentageFormatter.string(from: NSNumber(value: Double(percentage) / 100)) ?? "\(percentage)%"
}

/// The help affordance itself. Renders nothing at all when this Mac has nothing to
/// disclose, which is the common case — most Macs charge exactly the way the pane implies
/// and deserve no extra chrome.
struct ChargeControlHelpButton: View {
    let disclosures: [ChargeControlDisclosure]
    @State private var showHelp = false

    var body: some View {
        if !disclosures.isEmpty {
            Button {
                showHelp.toggle()
            } label: {
                Image(systemName: hasWarning ? "exclamationmark.circle.fill" : "questionmark.circle")
                    .font(.title3)
                    .foregroundStyle(hasWarning ? Color.orange : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .help(L10n.Settings.Label.chargeControlHelpButtonAccessibility)
            .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                ChargeControlHelpView(disclosures: disclosures)
            }
        }
    }

    private var hasWarning: Bool {
        disclosures.contains(where: ChargeControlDisclosureText.isWarning)
    }
}

/// The popover body, styled to match `AutomationHelpView` so the two help sheets in the
/// app read as the same thing.
struct ChargeControlHelpView: View {
    let disclosures: [ChargeControlDisclosure]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Settings.Label.chargeControlHelpHeading)
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                // Indexed rather than by value: the list is short, ordered, and fixed by
                // `ChargeControlFacts.disclosures`, and nothing here needs identity.
                ForEach(Array(disclosures.enumerated()), id: \.offset) { _, disclosure in
                    row(for: disclosure)
                }
            }
            .font(.callout)
        }
        .padding(16)
        .frame(width: 340)
    }

    @ViewBuilder
    private func row(for disclosure: ChargeControlDisclosure) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ChargeControlDisclosureText.symbolName(for: disclosure))
                .foregroundStyle(ChargeControlDisclosureText.isWarning(disclosure) ? Color.orange : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(ChargeControlDisclosureText.text(for: disclosure))
                // Force discharge is probed from its own key and outlives charge limiting,
                // so where it still works the user is told that in the same breath rather
                // than left to assume everything went down together.
                if ChargeControlDisclosureText.showsForceDischargeStillWorks(disclosure) {
                    Text(L10n.Settings.Label.forceDischargeStillWorks)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The disclosure-to-words mapping, kept free of any view so the button and the popover
/// can both consult it without one owning the other.
enum ChargeControlDisclosureText {
    /// Exhaustive over `ChargeControlDisclosure` with no `default:` arm, so a new case has
    /// to be given words here rather than silently rendering as another one.
    static func text(for disclosure: ChargeControlDisclosure) -> String {
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
        case .mayChargeToFullForCalibration:
            return l10n.systemChargeLimitMayChargeToFull
        case .limitNotAppliedWithoutSnapshot:
            return l10n.systemChargeLimitNoSnapshot
        case .firmwareEnforcedLimit:
            return l10n.firmwareRangeEnforcedByFirmware
        case .batteryMayDipBelowLimit(let hysteresis):
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

    /// Whether the secondary "Run on Battery still works" line belongs under this row.
    static func showsForceDischargeStillWorks(_ disclosure: ChargeControlDisclosure) -> Bool {
        switch disclosure {
        case .pausingChargingUnavailable(_, let stillAvailable),
             .chargingControlUnavailable(let stillAvailable):
            return stillAvailable
        case .usingSystemChargeLimit, .limitRaisedToSystemMinimum, .limitRoundedUp,
             .managingSystemSettingsLimit, .limitNotAppliedWithoutSnapshot,
             .firmwareEnforcedLimit, .batteryMayDipBelowLimit, .chargingStatusIsInferred,
             .mayChargeToFullForCalibration:
            return false
        }
    }

    /// Whether the user's battery is not going to end up where they asked it to, as
    /// opposed to a description of how this Mac gets it there. Only the first kind turns
    /// the help button orange.
    ///
    /// The bar is deliberately that outcome, not "some mechanism is missing". A Mac whose
    /// limit is enforced by macOS or by its own firmware is doing exactly what the user
    /// asked — arguably better than BatFi could, since the limit survives sleep — and
    /// badging its settings pane with a warning glyph says the opposite.
    static func isWarning(_ disclosure: ChargeControlDisclosure) -> Bool {
        switch disclosure {
        // Each of these means the limit in force is not the one the user chose, or that
        // no limit is in force at all. Nothing else in the pane says so.
        case .chargingControlUnavailable,
             .limitRaisedToSystemMinimum,
             .limitRoundedUp,
             .limitNotAppliedWithoutSnapshot:
            return true
        // Not a warning, though it reads like one. Nothing the user wanted has stopped
        // happening: the limit still holds while the Mac sleeps, which is the whole reason
        // pausing existed. The settings it *does* cost — pause-on-sleep and the
        // hot-battery cutout — are disabled in the panes that own them, with tooltips
        // saying why, so the state is already visible where the user would look for it.
        case .pausingChargingUnavailable:
            return false
        // These describe how this Mac works, and the first of them is good news.
        //
        // `mayChargeToFullForCalibration` belongs here despite being the one row that says
        // the limit will be exceeded. The bar is whether the user's battery ends up
        // somewhere they did not ask for *because something is wrong*, and a calibration
        // charge is macOS working as Apple documents it. Badging it orange would turn a
        // designed behaviour into a permanent fault light on every Mac using this backend.
        case .usingSystemChargeLimit,
             .managingSystemSettingsLimit,
             .firmwareEnforcedLimit,
             .batteryMayDipBelowLimit,
             .chargingStatusIsInferred,
             .mayChargeToFullForCalibration:
            return false
        }
    }

    static func symbolName(for disclosure: ChargeControlDisclosure) -> String {
        switch disclosure {
        case .chargingControlUnavailable,
             .limitRaisedToSystemMinimum,
             .limitRoundedUp,
             .limitNotAppliedWithoutSnapshot:
            return "exclamationmark.triangle.fill"
        // Kept in step with `isWarning`: a triangle beside this row inside the popover
        // would reintroduce, one level down, exactly the alarm the button no longer raises.
        case .usingSystemChargeLimit, .batteryMayDipBelowLimit, .chargingStatusIsInferred,
             .pausingChargingUnavailable, .mayChargeToFullForCalibration:
            return "info.circle"
        case .firmwareEnforcedLimit:
            return "checkmark.seal"
        case .managingSystemSettingsLimit:
            return "gearshape"
        }
    }
}
