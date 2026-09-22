//
//  AppChargingModeDescriptionTests.swift
//  BatFi
//
//  Unit tests for the charging-state description, focused on automation attribution:
//  the body must reflect the effective limit and name the active rule, while a manual
//  temp override always suppresses automation attribution (the override wins).
//

import Foundation
import L10n
import Testing

@testable import AppShared

@Suite struct AppChargingModeDescriptionTests {
    private func mode(
        _ mode: ChargingMode,
        override: Int? = nil,
        chargerConnected: Bool = true,
        systemIsDischargingToLimit: Bool = false,
        systemIsHoldingBelowLimit: Bool = false,
        systemIsChargingPastLimit: Bool = false,
        isHoldingFullChargeUntilUnplugged: Bool = false
    ) -> AppChargingMode {
        AppChargingMode(
            mode: mode,
            userTempOverride: override.map(UserTempChargingMode.init(limit:)),
            chargerConnected: chargerConnected,
            systemIsDischargingToLimit: systemIsDischargingToLimit,
            systemIsHoldingBelowLimit: systemIsHoldingBelowLimit,
            systemIsChargingPastLimit: systemIsChargingPastLimit,
            isHoldingFullChargeUntilUnplugged: isHoldingFullChargeUntilUnplugged
        )
    }

    private func percent(_ fraction: Double) -> String {
        percentageFormatter.string(from: fraction as NSNumber)!
    }

    // MARK: - No automation (regression guard)

    @Test func chargingWithoutAutomationDoesNotMentionARule() {
        let description = mode(.charging).stateDescription(chargeLimitFraction: 0.8)
        #expect(description?.contains(percent(0.8)) == true)
        #expect(description?.contains("Work") == false)
    }

    @Test func inhibitWithoutAutomationDoesNotMentionARule() {
        let description = mode(.inhibit).stateDescription(chargeLimitFraction: 0.8)
        #expect(description?.contains(percent(0.8)) == true)
        #expect(description?.contains("Work") == false)
    }

    // MARK: - Automation attribution

    @Test func chargingWithAutomationShowsLimitAndRuleName() {
        let plain = mode(.charging).stateDescription(chargeLimitFraction: 0.85)
        let attributed = mode(.charging).stateDescription(chargeLimitFraction: 0.85, automationRuleName: "Work")
        #expect(attributed?.contains(percent(0.85)) == true)
        #expect(attributed?.contains("Work") == true)
        #expect(attributed != plain)
    }

    @Test func inhibitWithAutomationShowsLimitAndRuleName() {
        let attributed = mode(.inhibit).stateDescription(chargeLimitFraction: 0.85, automationRuleName: "Work")
        #expect(attributed?.contains(percent(0.85)) == true)
        #expect(attributed?.contains("Work") == true)
    }

    @Test func forceDischargeWithAutomationNamesTheRule() {
        let attributed = mode(.forceDischarge, chargerConnected: false)
            .stateDescription(chargeLimitFraction: 0.85, automationRuleName: "Work")
        #expect(attributed?.contains("Work") == true)
    }

    // MARK: - Helper health outranks the mode

    // The mode is only ever as trustworthy as the helper that reported it. A record left
    // behind by a copy of BatFi that has since been deleted or moved reports `.enabled`
    // forever while every spawn fails, so the app can hold a mode it has no way to verify —
    // or, at launch, never get one at all and sit on `.initial`.

    @Test func degradedHelperIsReportedInsteadOfInitializing() {
        let description = mode(.initial).stateDescription(helperHealth: .degraded(.registeredButUnreachable))
        #expect(description != L10n.AppChargingMode.State.Title.initial)
        #expect(description == L10n.AppChargingMode.State.Title.helperNotRunning)
    }

    @Test func degradedHelperOutranksAStaleMode() {
        // Reporting "Inhibiting charging" while the helper is unreachable claims a pause
        // that nothing is holding.
        for staleMode in [ChargingMode.charging, .inhibit, .forceDischarge] {
            let description = mode(staleMode).stateDescription(helperHealth: .degraded(.notRegistered))
            #expect(description == L10n.AppChargingMode.State.Title.helperNotRunning)
        }
    }

    @Test func unknownHelperHealthStillReportsInitializing() {
        // The launch window, before the first probe lands, really is initializing.
        let description = mode(.initial).stateDescription(helperHealth: .unknown)
        #expect(description == L10n.AppChargingMode.State.Title.initial)
    }

    @Test func healthyHelperReportsTheModeUnchanged() {
        for anyMode in [ChargingMode.initial, .charging, .inhibit, .forceDischarge] {
            let withHealth = mode(anyMode).stateDescription(helperHealth: .healthy)
            #expect(withHealth == mode(anyMode).stateDescription)
        }
    }

    // MARK: - The system draining to the limit is not BatFi pausing

    // On firmware whose mechanism owns the charging decision, macOS drains the battery down
    // to the limit by itself. BatFi writes no inhibit there and takes `.inhibit` as the
    // honest mode for "charge is being held, just not by me" — but the title said
    // "Inhibiting charging" while the battery visibly fell, which is the one reading a user
    // watching 61% drop toward a 55% limit can prove wrong.

    @Test func systemDischargingToTheLimitIsNotReportedAsInhibiting() {
        let title = mode(.inhibit, systemIsDischargingToLimit: true).stateDescription
        #expect(title != L10n.AppChargingMode.State.Title.inhibit)
        #expect(title == L10n.AppChargingMode.State.Title.systemDischargingToLimit)
    }

    @Test func inhibitingWithoutASystemDrainIsUnchanged() {
        let title = mode(.inhibit).stateDescription
        #expect(title == L10n.AppChargingMode.State.Title.inhibit)
    }

    /// The flag describes why charge is being held; it says nothing about any other mode and
    /// must not leak into one.
    @Test func aSystemDrainDoesNotRelabelTheOtherModes() {
        for otherMode in [ChargingMode.charging, .forceDischarge] {
            let drained = mode(otherMode, systemIsDischargingToLimit: true).stateDescription
            #expect(drained == mode(otherMode).stateDescription)
        }
    }

    // MARK: - Charge held below the limit

    // Measured on 26A5416b, 2026-08-19: 56% against a 60% limit, 0 mA, `CHNC` bit 24 set, for
    // two hours. The mode decision reads `batteryLevel < limitInForce` and so chose
    // `.charging` — the menu said "Charging to the limit" while no current flowed at all.
    // `.inhibit` is the honest mode, and "Inhibiting charging" is still the wrong sentence
    // for it: BatFi wrote nothing, and the number the user set is not the one being held at.

    @Test func systemHoldingChargeBelowTheLimitIsNotReportedAsInhibiting() {
        let title = mode(.inhibit, systemIsHoldingBelowLimit: true).stateDescription
        #expect(title != L10n.AppChargingMode.State.Title.inhibit)
        #expect(title == L10n.AppChargingMode.State.Title.systemHoldingBelowLimit)
    }

    @Test func inhibitingWithoutASystemHoldIsUnchanged() {
        let title = mode(.inhibit).stateDescription
        #expect(title == L10n.AppChargingMode.State.Title.inhibit)
    }

    /// Same containment the drain flag gets: it explains why charge is being held and must
    /// not leak into a mode where nothing is.
    @Test func aSystemHoldDoesNotRelabelTheOtherModes() {
        for otherMode in [ChargingMode.charging, .forceDischarge] {
            let held = mode(otherMode, systemIsHoldingBelowLimit: true).stateDescription
            #expect(held == mode(otherMode).stateDescription)
        }
    }

    @Test func aTempOverrideOutranksASystemHold() {
        let title = mode(.inhibit, override: 100, systemIsHoldingBelowLimit: true).stateDescription
        #expect(title == L10n.AppChargingMode.State.Title.chargeOverride)
    }

    /// The two cannot both be true of one reading — a drain needs the battery above the limit
    /// and a hold needs it below — but the struct cannot express that, so the precedence is
    /// pinned here. The drain wins: it is the one the user can watch happening.
    @Test func aDrainOutranksAHoldIfBothAreSomehowSet() {
        let title = mode(
            .inhibit,
            systemIsDischargingToLimit: true,
            systemIsHoldingBelowLimit: true
        ).stateDescription
        #expect(title == L10n.AppChargingMode.State.Title.systemDischargingToLimit)
    }

    /// A temp override is BatFi acting on the user's own instruction, and the override text
    /// already says so. It outranks the system's drain for the same reason it outranks
    /// automation attribution below.
    @Test func aTempOverrideOutranksASystemDrain() {
        let title = mode(.inhibit, override: 100, systemIsDischargingToLimit: true).stateDescription
        #expect(title == L10n.AppChargingMode.State.Title.chargeOverride)
    }

    // MARK: - macOS charging past the limit

    // Measured 2026-08-26: 100% against a 75% limit in force, `IsCharging` true, 477 mA and
    // 7.0 W going into the battery — and the menu read "Discharging to the limit" over it,
    // because the drain was keyed on the level alone. Apple documents this charge; BatFi has
    // no representation for it and so reported its opposite.

    @Test func systemChargingPastTheLimitIsNotReportedAsADrain() {
        let title = mode(.inhibit, systemIsChargingPastLimit: true).stateDescription
        #expect(title != L10n.AppChargingMode.State.Title.systemDischargingToLimit)
        #expect(title != L10n.AppChargingMode.State.Title.inhibit)
        #expect(title == L10n.AppChargingMode.State.Title.systemChargingPastLimit)
    }

    /// The description is the one place the `.inhibit` body does not simply restate the limit:
    /// "The charging limit is set to 75%" is true at 100% and is exactly what makes the state
    /// read as BatFi having failed.
    @Test func theTopUpDescriptionSaysTheLimitStillApplies() {
        let body = mode(.inhibit, systemIsChargingPastLimit: true)
            .stateDescription(chargeLimitFraction: 0.75)
        #expect(body == L10n.AppChargingMode.State.Description.systemChargingPastLimit(percent(0.75)))
        #expect(body != L10n.AppChargingMode.State.Description.inhibit(percent(0.75)))
        // Asserted on the content rather than only against the same call, which would hold
        // however badly the string resolved. The limit has to reach the sentence: an
        // unsubstituted `%@` here is the whole reassurance lost, and the catalog entry is
        // new — `systemChargeLimitRaised` has already been shipped once reading "set below
        // 100%" because a percentage never crossed a boundary.
        #expect(body?.contains(percent(0.75)) == true)
        #expect(body?.contains("%@") == false)
    }

    /// Automation attribution names the rule that set the limit. During a top-up the limit is
    /// not what is in doubt, so the reassurance outranks it.
    @Test func theTopUpDescriptionOutranksAutomationAttribution() {
        let body = mode(.inhibit, systemIsChargingPastLimit: true)
            .stateDescription(chargeLimitFraction: 0.75, automationRuleName: "Work")
        #expect(body == L10n.AppChargingMode.State.Description.systemChargingPastLimit(percent(0.75)))
    }

    /// Same containment the other two system flags get.
    @Test func aTopUpDoesNotRelabelTheOtherModes() {
        for otherMode in [ChargingMode.charging, .forceDischarge] {
            let toppedUp = mode(otherMode, systemIsChargingPastLimit: true).stateDescription
            #expect(toppedUp == mode(otherMode).stateDescription)
        }
    }

    @Test func aTempOverrideOutranksATopUp() {
        let title = mode(.inhibit, override: 100, systemIsChargingPastLimit: true).stateDescription
        #expect(title == L10n.AppChargingMode.State.Title.chargeOverride)
    }

    /// The three cannot co-occur on any real reading — the top-up and the drain read one
    /// direction rule and negate it, and the hold needs the battery below a limit both of the
    /// others need it above — but the flags are independent, so the order is pinned here. The
    /// top-up leads: it is the only one of the three whose absence produced a contradiction
    /// rather than a merely vague sentence.
    @Test func aTopUpOutranksBothOtherSystemStatesIfAllAreSomehowSet() {
        let title = mode(
            .inhibit,
            systemIsDischargingToLimit: true,
            systemIsHoldingBelowLimit: true,
            systemIsChargingPastLimit: true
        ).stateDescription
        #expect(title == L10n.AppChargingMode.State.Title.systemChargingPastLimit)
    }

    // MARK: - Holding 100% until unplugged

    // Customer log 2026-09-22: "Charge to 100%" completed against a 70% limit with
    // "Discharge battery when overcharged" on, and the next pass force-discharged the 30%
    // the user had just asked for. BatFi now keeps requesting 100 until the charger comes
    // out — which means the mode under this state alternates between `.charging` (topping
    // 99 back to 100) and `.inhibit` (resting at 100), and the label must be the same
    // sentence for both rather than flickering between "Charging to the limit" and
    // "Inhibiting charging".

    @Test func holdingFullChargeIsLabelledForBothModesItCanSitUnder() {
        for heldMode in [ChargingMode.charging, .inhibit] {
            let title = mode(heldMode, isHoldingFullChargeUntilUnplugged: true).stateDescription
            #expect(title == L10n.AppChargingMode.State.Title.holdingFullChargeUntilUnplugged)
        }
    }

    @Test func holdingFullChargeDescribesTheLimitThatTakesOverOnUnplug() {
        for heldMode in [ChargingMode.charging, .inhibit] {
            let body = mode(heldMode, isHoldingFullChargeUntilUnplugged: true)
                .stateDescription(chargeLimitFraction: 0.7)
            #expect(body == L10n.AppChargingMode.State.Description.holdingFullChargeUntilUnplugged(percent(0.7)))
            // The limit has to reach the sentence — an unsubstituted `%@` is the whole
            // explanation of what happens next, lost.
            #expect(body?.contains(percent(0.7)) == true)
            #expect(body?.contains("%@") == false)
            // The literal percent is escaped as `100%%` in the format string, because
            // unescaped `% a` parses as a conversion and swallows the limit argument. That
            // escape must not survive into the rendered sentence.
            #expect(body?.contains("100%") == true)
            #expect(body?.contains("100%%") == false)
        }
    }

    /// The hold is BatFi's own state and explains a battery sitting at 100% over a lower
    /// limit; which rule set that limit is not what is in doubt.
    @Test func theHoldDescriptionOutranksAutomationAttribution() {
        let body = mode(.inhibit, isHoldingFullChargeUntilUnplugged: true)
            .stateDescription(chargeLimitFraction: 0.7, automationRuleName: "Work")
        #expect(body == L10n.AppChargingMode.State.Description.holdingFullChargeUntilUnplugged(percent(0.7)))
        #expect(body?.contains("Work") == false)
    }

    /// The three `systemIs…` flags describe what macOS is doing to a battery *above the
    /// limit*. While the hold is on, the limit in force is 100 and the battery is at it, so
    /// none of them can truthfully be set — but they are independent flags, and the hold is
    /// the state BatFi chose, so it leads.
    @Test func theHoldOutranksEverySystemState() {
        let title = mode(
            .inhibit,
            systemIsDischargingToLimit: true,
            systemIsHoldingBelowLimit: true,
            systemIsChargingPastLimit: true,
            isHoldingFullChargeUntilUnplugged: true
        ).stateDescription
        #expect(title == L10n.AppChargingMode.State.Title.holdingFullChargeUntilUnplugged)
    }

    /// A new override replaces the intent the hold came from, and `ChargingManager` clears
    /// the flag when one is armed — but the label's own order says the same thing, for the
    /// pass where both are briefly true.
    @Test func aTempOverrideOutranksTheHold() {
        let title = mode(.inhibit, override: 80, isHoldingFullChargeUntilUnplugged: true).stateDescription
        #expect(title == L10n.AppChargingMode.State.Title.chargeOverride)

        let body = mode(.charging, override: 80, isHoldingFullChargeUntilUnplugged: true)
            .stateDescription(chargeLimitFraction: 0.7)
        #expect(body == L10n.AppChargingMode.State.Description.tempChargingTo(percent(0.8)))
    }

    /// Nothing is force-discharged while the hold is on — that is the bug it fixes — so
    /// `.forceDischarge` never wears the hold's label.
    @Test func forceDischargeIgnoresTheHold() {
        let held = mode(.forceDischarge, isHoldingFullChargeUntilUnplugged: true)
        #expect(held.stateDescription == mode(.forceDischarge).stateDescription)
        #expect(
            held.stateDescription(chargeLimitFraction: 0.7)
                == mode(.forceDischarge).stateDescription(chargeLimitFraction: 0.7)
        )
    }

    /// The two guards at the top of `stateDescription` still come first: a mode BatFi has
    /// not established yet, and a charger that is not plugged in — which is exactly the
    /// event that ends the hold, so it must never be described as holding.
    @Test func theInitialAndUnpluggedGuardsStillWin() {
        #expect(
            mode(.initial, isHoldingFullChargeUntilUnplugged: true).stateDescription
                == L10n.AppChargingMode.State.Title.initial
        )
        let unplugged = mode(.inhibit, chargerConnected: false, isHoldingFullChargeUntilUnplugged: true)
        #expect(unplugged.stateDescription == L10n.AppChargingMode.State.Title.chargerNotConnected)
        #expect(unplugged.stateDescription(chargeLimitFraction: 0.7) == nil)
    }

    /// Same containment the system flags get: it explains a battery held at 100% and must
    /// not leak into a mode where nothing is being held.
    @Test func theHoldDoesNotRelabelAModeItCannotSitUnder() {
        let initialMode = mode(.initial, isHoldingFullChargeUntilUnplugged: true)
        #expect(initialMode.stateDescription == mode(.initial).stateDescription)
    }

    // MARK: - Temp override wins over automation

    @Test func tempOverrideSuppressesAutomationAttribution() {
        let withName = mode(.charging, override: 100)
            .stateDescription(chargeLimitFraction: 0.85, automationRuleName: "Work")
        let withoutName = mode(.charging, override: 100)
            .stateDescription(chargeLimitFraction: 0.85)
        // Override text is identical with or without an active automation rule, and never
        // attributes the charge to automation.
        #expect(withName == withoutName)
        #expect(withName?.contains("Work") == false)
    }
}
