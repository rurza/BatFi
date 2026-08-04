//
//  ChargeControlDisclosureTests.swift
//  BatFi
//
//  What the Charging pane tells the user about this Mac. The honest message under
//  `.systemChargeLimit` is not "reduced functionality" — it is that limits below 80%
//  cannot be applied on this firmware, and a user set to 55% has to learn their setting
//  is not in effect and what is in force instead.
//
//  Pinned here rather than in a SwiftUI `body` because every case that matters lives on
//  hardware nobody testing this has: the machine whose firmware dropped CHTE, the build
//  of PowerUI that exposes an override selector but no clear, the Mac that kept CHIE
//  after losing charge limiting. The rules are the only part that can be checked.
//

import Foundation
import Testing

@testable import Shared

@Suite struct ChargeControlDisclosureTests {
    private func facts(
        backend: ChargeBackend?,
        manageCharging: Bool = true,
        appliedChargeLimit: Int? = nil,
        chargeLimitWasRaised: Bool = false,
        requestedChargeLimit: Int? = nil,
        systemLimitSnapshotRefused: Bool = false,
        systemLimitIsSupported: Bool = true,
        systemLimit: Int? = 100,
        batFiHoldsSystemLimitOverride: Bool = false,
        forceDischargeAvailable: Bool = false,
        hotBatteryProtectionEnabled: Bool = false,
        pauseChargingOnSleepEnabled: Bool = false
    ) -> ChargeControlFacts {
        ChargeControlFacts(
            backend: backend,
            manageCharging: manageCharging,
            appliedChargeLimit: appliedChargeLimit,
            chargeLimitWasRaised: chargeLimitWasRaised,
            requestedChargeLimit: requestedChargeLimit,
            systemLimitSnapshotRefused: systemLimitSnapshotRefused,
            systemLimitIsSupported: systemLimitIsSupported,
            systemLimit: systemLimit,
            batFiHoldsSystemLimitOverride: batFiHoldsSystemLimitOverride,
            forceDischargeAvailable: forceDischargeAvailable,
            hotBatteryProtectionEnabled: hotBatteryProtectionEnabled,
            pauseChargingOnSleepEnabled: pauseChargingOnSleepEnabled
        )
    }

    // MARK: - Nothing is claimed about a machine we have not resolved

    /// Before the first diagnostics fetch lands there is no mechanism to describe. Saying
    /// anything here would flash a warning on every working Mac each time the pane opens.
    @Test func anUnresolvedBackendDisclosesNothing() {
        #expect(facts(backend: nil).disclosures.isEmpty)
        #expect(facts(backend: nil).conflictingSystemLimit == nil)
    }

    /// The SMC backends apply the user's value exactly. There is nothing to explain, and
    /// this is every Mac that works today.
    @Test func theSMCBackendsDiscloseNothing() {
        for backend in [ChargeBackend.chte, .legacyCH0BC] {
            #expect(facts(backend: backend).disclosures.isEmpty, "\(backend.rawValue)")
        }
    }

    /// Even with the settings that cannot engage under Apple's limit switched on: on an
    /// SMC backend they work, and warning about them would be a lie.
    @Test func theSMCBackendsStaySilentAboutPausingCharging() {
        let value = facts(
            backend: .chte,
            hotBatteryProtectionEnabled: true,
            pauseChargingOnSleepEnabled: true
        )
        #expect(value.disclosures.isEmpty)
    }

    // MARK: - .firmwareRange

    /// Lead with what works. The first thing this Mac's user reads is that the firmware is
    /// enforcing their limit and keeps enforcing it through sleep — which is *better* than
    /// what BatFi can do for itself — and only then what that costs. Ordering is the whole
    /// difference between "your Mac is well looked after" and "limited support".
    @Test func theFirmwareRangeLeadsWithWhatWorks() {
        let value = facts(backend: .firmwareRange)
        #expect(value.disclosures == [
            .firmwareEnforcedLimit,
            .batteryMayDipBelowLimit(hysteresis: FirmwareChargeRange.hysteresis),
            .chargingStatusIsInferred,
        ])
    }

    /// The label disclosure has to sit *immediately* after the dip it explains. They are two
    /// halves of one fact — the battery sits below the limit, and for that same stretch
    /// BatFi's own label says "charging" — and a row between them would leave the second
    /// reading as a separate complaint rather than the completion of the first.
    @Test func theInferredStatusFollowsTheDipItExplains() {
        let disclosures = facts(backend: .firmwareRange).disclosures
        let dip = disclosures.firstIndex(of: .batteryMayDipBelowLimit(
            hysteresis: FirmwareChargeRange.hysteresis
        ))
        let label = disclosures.firstIndex(of: .chargingStatusIsInferred)
        #expect(dip != nil)
        #expect(label != nil)
        if let dip, let label { #expect(label == dip + 1) }
    }

    /// Not conditional on either pause setting, unlike the row below it. The label is wrong
    /// on this firmware whatever the user has switched on, because it is inferred from the
    /// battery level and the band moves independently of it.
    @Test func theInferredStatusIsDisclosedWhateverTheUserHasSwitchedOn() {
        #expect(facts(backend: .firmwareRange).disclosures.contains(.chargingStatusIsInferred))
        #expect(
            facts(
                backend: .firmwareRange,
                hotBatteryProtectionEnabled: true,
                pauseChargingOnSleepEnabled: true
            ).disclosures.contains(.chargingStatusIsInferred)
        )
    }

    /// Asked directly rather than scoped by reflex: `.systemChargeLimit` looks like it has
    /// the same problem and does not have the same cause. There the firmware *does* report
    /// the hold, in `CHNC` bit 24, and BatFi already reads it through
    /// `systemChargeLimitIsHoldingCharge`. Its mode can still be wrong — a limit raised from
    /// 55% to 80% reports `.inhibit` from 55% up while the hardware charges — but that is a
    /// bug with a signal available to fix it, not a limitation to disclose, and saying
    /// "BatFi can't tell whether it's charging" there would be false.
    ///
    /// Every other backend too: no mechanism, no inference to warn about.
    @Test func onlyTheFirmwareRangeDisclosesAnInferredStatus() {
        for backend in ChargeBackend.allCases where backend != .firmwareRange {
            let value = facts(
                backend: backend,
                appliedChargeLimit: 80,
                chargeLimitWasRaised: true,
                requestedChargeLimit: 55,
                hotBatteryProtectionEnabled: true,
                pauseChargingOnSleepEnabled: true
            )
            #expect(
                value.disclosures.contains(.chargingStatusIsInferred) == false,
                "\(backend.rawValue)"
            )
        }
    }

    /// The dip is the mechanism, and a user watching 75% with an 80% limit needs to be
    /// able to find that out. The figure comes from the constant the engage sequence
    /// actually encodes into `bfE0`, so the sentence cannot name a band the firmware is
    /// not given — assert against the band itself rather than against a literal 5.
    @Test func theDipDisclosureNamesTheBandTheFirmwareIsActuallyGiven() {
        let value = facts(backend: .firmwareRange)
        let band = FirmwareChargeRange.band(forLimit: 80)
        #expect(value.disclosures.contains(.batteryMayDipBelowLimit(hysteresis: band.upper - band.lower)))
    }

    /// The gap the previous task handed forward, disclosed rather than fixed: a band has no
    /// "stop now" in it, so hot-battery protection and pause-on-sleep do nothing here. Same
    /// gate `.systemChargeLimit` uses — only a user who switched one on is told.
    @Test func eitherPauseSettingIsDisclosedUnderTheFirmwareRange() {
        let hot = facts(backend: .firmwareRange, hotBatteryProtectionEnabled: true)
        #expect(hot.disclosures.last == .pausingChargingUnavailable(
            heldBy: .macFirmware,
            forceDischargeStillAvailable: false
        ))

        let sleep = facts(backend: .firmwareRange, pauseChargingOnSleepEnabled: true)
        #expect(sleep.disclosures.last == .pausingChargingUnavailable(
            heldBy: .macFirmware,
            forceDischargeStillAvailable: false
        ))
    }

    /// The mechanism is named, not assumed. Both backends lose the same feature and the
    /// sentence explaining it differs: pointing a macOS 27 user at "the macOS charge limit"
    /// would send them to a System Settings value BatFi never touches on their Mac.
    @Test func theTwoBackendsThatCannotPauseNameDifferentMechanisms() {
        let firmware = facts(backend: .firmwareRange, hotBatteryProtectionEnabled: true)
        let system = facts(backend: .systemChargeLimit, hotBatteryProtectionEnabled: true)
        #expect(firmware.disclosures.contains(.pausingChargingUnavailable(
            heldBy: .macFirmware, forceDischargeStillAvailable: false
        )))
        #expect(system.disclosures.contains(.pausingChargingUnavailable(
            heldBy: .macOSChargeLimit, forceDischargeStillAvailable: false
        )))
        #expect(firmware.disclosures.contains(.pausingChargingUnavailable(
            heldBy: .macOSChargeLimit, forceDischargeStillAvailable: false
        )) == false)
    }

    /// Run on Battery runs off `CHIE`, which survives on this firmware. A user whose Run on
    /// Battery still works must never read that it is gone, so the flag is carried here
    /// exactly as it is under `.systemChargeLimit`.
    @Test func forceDischargeIsCarriedUnderTheFirmwareRangeToo() {
        let value = facts(
            backend: .firmwareRange,
            forceDischargeAvailable: true,
            pauseChargingOnSleepEnabled: true
        )
        #expect(value.disclosures.contains(.pausingChargingUnavailable(
            heldBy: .macFirmware, forceDischargeStillAvailable: true
        )))
    }

    /// With management off BatFi releases the band, so every one of these sentences would
    /// describe a limit that is not in force — including the reassuring one, which would be
    /// the worst of them to get wrong.
    @Test func theFirmwareRangeSaysNothingWithManagementOff() {
        let value = facts(
            backend: .firmwareRange,
            manageCharging: false,
            hotBatteryProtectionEnabled: true,
            pauseChargingOnSleepEnabled: true
        )
        #expect(value.disclosures.isEmpty)
    }

    /// None of the system-limit statements may leak in: BatFi applies its limit through the
    /// firmware here and leaves System Settings › Battery alone, so telling the user it
    /// changed a value there — or that limits below 80% cannot be applied — would be false
    /// on both counts. The applied/raised fields are set to what a *system-limit* Mac
    /// carries, to prove the arm does not read them.
    @Test func theFirmwareRangeNeverClaimsToTouchSystemSettings() {
        let value = facts(
            backend: .firmwareRange,
            appliedChargeLimit: 80,
            chargeLimitWasRaised: true,
            requestedChargeLimit: 55,
            systemLimitSnapshotRefused: true
        )
        #expect(value.disclosures.contains(.managingSystemSettingsLimit) == false)
        #expect(value.disclosures.contains(.usingSystemChargeLimit) == false)
        #expect(value.disclosures.contains(.limitRaisedToSystemMinimum(applied: 80)) == false)
        #expect(value.disclosures.contains(.limitNotAppliedWithoutSnapshot) == false)
    }

    // MARK: - .unsupported

    @Test func unsupportedFirmwareSaysSoAndNothingElse() {
        let value = facts(backend: .unsupported, hotBatteryProtectionEnabled: true)
        #expect(value.disclosures == [.chargingControlUnavailable(forceDischargeStillAvailable: false)])
    }

    /// The same precision `.pausingChargingUnavailable` already carried, applied to the
    /// case that needed it more. `CHIE` is probed independently of the backend precisely so
    /// "Run on Battery" survives where charge limiting is gone, and `.unsupported` is
    /// reachable with it working — so the flat "BatFi can't control charging" told a user
    /// whose Run on Battery works perfectly that the app does nothing on their Mac.
    @Test func unsupportedFirmwareStillNamesForceDischargeWhereItWorks() {
        let value = facts(
            backend: .unsupported,
            forceDischargeAvailable: true,
            hotBatteryProtectionEnabled: true
        )
        #expect(value.disclosures == [.chargingControlUnavailable(forceDischargeStillAvailable: true)])
    }

    /// Said with management off too, unlike every other arm: this is a statement about what
    /// the Mac can do, not about what BatFi is doing, and turning management off does not
    /// give the firmware a charge-limit key back.
    @Test func unsupportedFirmwareSaysSoWithManagementOff() {
        let value = facts(backend: .unsupported, manageCharging: false)
        #expect(value.disclosures == [.chargingControlUnavailable(forceDischargeStillAvailable: false)])
    }

    // MARK: - .systemChargeLimit

    /// The banner is unconditional under this backend: the mechanism only accepts
    /// 80–100%, which is true whether or not a limit happens to be in force right now.
    @Test func theSystemChargeLimitBannerAlwaysShows() {
        let value = facts(backend: .systemChargeLimit)
        #expect(value.disclosures.first == .usingSystemChargeLimit)
    }

    /// The single thing the user most needs told, and it names the number in force. The
    /// floor-clamp wording — "limits below 80% can't be applied, 80% is the lowest
    /// accepted" — is true only here, for a request that really was below the floor.
    @Test func aLimitBelowTheFloorIsDisclosedAsAFloorClampWithTheValueActuallyApplied() {
        let value = facts(
            backend: .systemChargeLimit,
            appliedChargeLimit: 80,
            chargeLimitWasRaised: true,
            requestedChargeLimit: 55
        )
        #expect(value.disclosures.contains(.limitRaisedToSystemMinimum(applied: 80)))
    }

    /// A request *at or above* the floor that could not be expressed exactly is a
    /// round-up, not a clamp, and gets its own words. Reached by clicking stop-charging at
    /// 87%: `inhibitCharging()` requests the current battery level, which is an arbitrary
    /// integer. Told as a floor clamp it would claim 87 is below 80 and that 90 is the
    /// lowest value the mechanism accepts — two false statements in an everyday flow.
    @Test func aLimitAboveTheFloorIsDisclosedAsARoundUpNamingBothNumbers() {
        let value = facts(
            backend: .systemChargeLimit,
            appliedChargeLimit: 90,
            chargeLimitWasRaised: true,
            requestedChargeLimit: 87
        )
        #expect(value.disclosures.contains(.limitRoundedUp(requested: 87, applied: 90)))
        #expect(value.disclosures.contains(.limitRaisedToSystemMinimum(applied: 90)) == false)
    }

    /// The top of the range, where the floor-clamp string claimed 100% was "the lowest the
    /// macOS charge limit accepts".
    @Test func aRoundUpToTheCeilingIsStillARoundUp() {
        let value = facts(
            backend: .systemChargeLimit,
            appliedChargeLimit: 100,
            chargeLimitWasRaised: true,
            requestedChargeLimit: 97
        )
        #expect(value.disclosures.contains(.limitRoundedUp(requested: 97, applied: 100)))
        #expect(value.disclosures.contains(.limitRaisedToSystemMinimum(applied: 100)) == false)
    }

    /// The boundary itself belongs to the round-up side: 80 is expressible, so a request of
    /// exactly 80 is never clamped, and anything from 80 up that moves was rounded.
    @Test func theFloorItselfIsNotTreatedAsBelowTheFloor() {
        let value = facts(
            backend: .systemChargeLimit,
            appliedChargeLimit: 85,
            chargeLimitWasRaised: true,
            requestedChargeLimit: ChargeLimitRange.systemChargeLimitLowest
        )
        #expect(value.disclosures.contains(.limitRoundedUp(requested: 80, applied: 85)))
        #expect(value.disclosures.contains(.limitRaisedToSystemMinimum(applied: 85)) == false)
    }

    /// Fail closed, as an applied-less raise already does. Without the requested value
    /// there is no way to tell a clamp from a round-up, and both sentences assert a reason;
    /// guessing would be how the pane starts naming the wrong one. A matched install cannot
    /// reach this — both numbers come from the same `AppliedChargeLimit`.
    @Test func aRaiseWithNoRequestedValueNamesNoReason() {
        let value = facts(
            backend: .systemChargeLimit,
            appliedChargeLimit: 90,
            chargeLimitWasRaised: true,
            requestedChargeLimit: nil
        )
        #expect(value.disclosures == [.usingSystemChargeLimit, .managingSystemSettingsLimit])
    }

    /// A limit the mechanism could express exactly is not a raise, and must not be
    /// reported as one — that would put a permanent warning on a Mac doing what was asked.
    @Test func anExactlyAppliedLimitIsNotReportedAsRaised() {
        let value = facts(
            backend: .systemChargeLimit,
            appliedChargeLimit: 85,
            chargeLimitWasRaised: false,
            requestedChargeLimit: 85
        )
        #expect(value.disclosures.contains(.limitRaisedToSystemMinimum(applied: 85)) == false)
        #expect(value.disclosures.contains(.limitRoundedUp(requested: 85, applied: 85)) == false)
        #expect(value.disclosures.contains(.managingSystemSettingsLimit))
    }

    /// The raise flag comes from the helper, which compared against what was really
    /// requested — an automation limit or a temporary override, not necessarily the
    /// slider. A flag set with no applied value to name says nothing rather than guessing.
    @Test func aRaiseWithNoAppliedValueNamesNothing() {
        let value = facts(
            backend: .systemChargeLimit,
            appliedChargeLimit: nil,
            chargeLimitWasRaised: true,
            requestedChargeLimit: 55
        )
        #expect(value.disclosures == [.usingSystemChargeLimit])
    }

    /// `setMCLLimit:` mutates a control the user can see in System Settings. The
    /// disclosure the whole snapshot/restore machinery exists to justify.
    @Test func managingTheSystemSettingsValueIsDisclosedOnceALimitIsHeld() {
        #expect(facts(backend: .systemChargeLimit, appliedChargeLimit: 80)
            .disclosures.contains(.managingSystemSettingsLimit))
    }

    /// `appliedChargeLimit` is cleared by every route that ends BatFi's ownership of the
    /// system limit, so with none held the pane must not claim BatFi is managing one.
    @Test func noLimitHeldMeansNoClaimOfManagingSystemSettings() {
        let value = facts(backend: .systemChargeLimit, appliedChargeLimit: nil)
        #expect(value.disclosures.contains(.managingSystemSettingsLimit) == false)
    }

    // MARK: - The snapshot refusal

    /// Previously invisible: the refusal reached the helper log and one breadcrumb, while
    /// the user just saw a limit that never took effect.
    @Test func aRefusedSnapshotIsSurfaced() {
        let value = facts(backend: .systemChargeLimit, systemLimitSnapshotRefused: true)
        #expect(value.disclosures.contains(.limitNotAppliedWithoutSnapshot))
    }

    /// It replaces the other two rather than joining them: when nothing was applied,
    /// "your limit was raised to 80%" and "BatFi is managing your System Settings value"
    /// are both false. A stale applied value must not resurrect either.
    @Test func aRefusedSnapshotSuppressesTheClaimsThatWouldBeFalse() {
        let value = facts(
            backend: .systemChargeLimit,
            appliedChargeLimit: 80,
            chargeLimitWasRaised: true,
            requestedChargeLimit: 55,
            systemLimitSnapshotRefused: true
        )
        #expect(value.disclosures.contains(.limitNotAppliedWithoutSnapshot))
        #expect(value.disclosures.contains(.limitRaisedToSystemMinimum(applied: 80)) == false)
        #expect(value.disclosures.contains(.managingSystemSettingsLimit) == false)
    }

    // MARK: - Pausing charging: disclosed precisely, not sweepingly

    /// Apple's limit holds charge at a percentage and bottoms out at 80%; it cannot stop
    /// charging outright, and `inhibitCharging()` writes nothing under this backend. A
    /// user who switched either setting on is entitled to know it will not engage.
    @Test func eitherPauseSettingTriggersTheDisclosure() {
        let hot = facts(backend: .systemChargeLimit, hotBatteryProtectionEnabled: true)
        #expect(hot.disclosures.contains(.pausingChargingUnavailable(heldBy: .macOSChargeLimit, forceDischargeStillAvailable: false)))

        let sleep = facts(backend: .systemChargeLimit, pauseChargingOnSleepEnabled: true)
        #expect(sleep.disclosures.contains(.pausingChargingUnavailable(heldBy: .macOSChargeLimit, forceDischargeStillAvailable: false)))
    }

    /// Neither switched on, nothing to warn about. Silence here is what keeps the pane
    /// from lecturing a user about features they are not using.
    @Test func neitherPauseSettingMeansNoPauseDisclosure() {
        let value = facts(backend: .systemChargeLimit)
        #expect(value.disclosures.contains(.pausingChargingUnavailable(heldBy: .macOSChargeLimit, forceDischargeStillAvailable: false)) == false)
        #expect(value.disclosures.contains(.pausingChargingUnavailable(heldBy: .macOSChargeLimit, forceDischargeStillAvailable: true)) == false)
    }

    /// The precision the finding asked for. CHIE outlives CHTE, so a Mac on
    /// `.systemChargeLimit` can still run on battery — and the copy has to say so rather
    /// than sweep force discharge in with the things that genuinely stopped working.
    @Test func forceDischargeAvailabilityIsCarriedRatherThanImplied() {
        let withDischarge = facts(
            backend: .systemChargeLimit,
            forceDischargeAvailable: true,
            hotBatteryProtectionEnabled: true
        )
        #expect(withDischarge.disclosures.contains(.pausingChargingUnavailable(heldBy: .macOSChargeLimit, forceDischargeStillAvailable: true)))

        let without = facts(
            backend: .systemChargeLimit,
            forceDischargeAvailable: false,
            hotBatteryProtectionEnabled: true
        )
        #expect(without.disclosures.contains(.pausingChargingUnavailable(heldBy: .macOSChargeLimit, forceDischargeStillAvailable: false)))
    }

    /// With management off BatFi holds nothing at all, so it discloses nothing — the same
    /// guard `.firmwareRange` carries. It used to seed `.usingSystemChargeLimit`
    /// unconditionally, so the pane read "BatFi is using the macOS charge limit" on a Mac
    /// where `restoreSystemDefaults()` had already released the adopted limit.
    @Test func managementOffMeansNoSystemChargeLimitDisclosureAtAll() {
        let value = facts(
            backend: .systemChargeLimit,
            manageCharging: false,
            hotBatteryProtectionEnabled: true,
            pauseChargingOnSleepEnabled: true
        )
        #expect(value.pausingChargingIsExpected == false)
        #expect(value.disclosures.isEmpty)
    }

    /// And in particular it does not claim BatFi is managing a System Settings value it
    /// has handed back.
    @Test func managementOffNeverClaimsToBeManagingSystemSettings() {
        let value = facts(
            backend: .systemChargeLimit,
            manageCharging: false,
            appliedChargeLimit: 80
        )
        #expect(value.disclosures.isEmpty)
    }

    // MARK: - Ordering

    /// Read top to bottom: what is in use, what that means for the limit, what BatFi is
    /// touching to do it, then what stopped working.
    @Test func disclosuresAreOrderedForReading() {
        let value = facts(
            backend: .systemChargeLimit,
            appliedChargeLimit: 80,
            chargeLimitWasRaised: true,
            requestedChargeLimit: 55,
            forceDischargeAvailable: true,
            hotBatteryProtectionEnabled: true
        )
        #expect(value.disclosures == [
            .usingSystemChargeLimit,
            .limitRaisedToSystemMinimum(applied: 80),
            .managingSystemSettingsLimit,
            .pausingChargingUnavailable(heldBy: .macOSChargeLimit, forceDischargeStillAvailable: true),
        ])
    }

    /// The round-up takes the same slot in the same order — it replaces the clamp rather
    /// than adding a row.
    @Test func aRoundUpTakesTheClampsPlaceInTheOrder() {
        let value = facts(
            backend: .systemChargeLimit,
            appliedChargeLimit: 90,
            chargeLimitWasRaised: true,
            requestedChargeLimit: 87,
            forceDischargeAvailable: true,
            hotBatteryProtectionEnabled: true
        )
        #expect(value.disclosures == [
            .usingSystemChargeLimit,
            .limitRoundedUp(requested: 87, applied: 90),
            .managingSystemSettingsLimit,
            .pausingChargingUnavailable(heldBy: .macOSChargeLimit, forceDischargeStillAvailable: true),
        ])
    }

    // MARK: - conflictingSystemLimit

    /// The condition the warning was always trying to express, now that the percentage
    /// crosses the boundary instead of being proxied.
    @Test func aSystemLimitBelow100ConflictsUnderTheSMCBackends() {
        for backend in [ChargeBackend.chte, .legacyCH0BC] {
            #expect(facts(backend: backend, systemLimit: 80).conflictingSystemLimit == 80, "\(backend.rawValue)")
        }
    }

    /// The old proxy — "BatFi holds no override" — fired here, on a Mac whose system
    /// limit is 100 and caps nothing at all. That was most of the fleet.
    @Test func aSystemLimitOf100DoesNotConflict() {
        #expect(facts(backend: .chte, systemLimit: 100).conflictingSystemLimit == nil)
    }

    /// The finding. Under `.systemChargeLimit` the limit being warned about is the one
    /// BatFi itself set, so the warning was unconditionally true and told the user to
    /// raise the very value applying their limit.
    @Test func theSystemChargeLimitBackendNeverWarnsAgainstItsOwnLimit() {
        let value = facts(backend: .systemChargeLimit, appliedChargeLimit: 80, systemLimit: 80)
        #expect(value.conflictingSystemLimit == nil)
        #expect(value.disclosures.contains(.managingSystemSettingsLimit))
    }

    /// BatFi applies no limit under `.unsupported`, so the system's own limit is not in
    /// conflict with anything — it is the only thing in control, and the pane says so.
    @Test func unsupportedFirmwareNeverWarnsOfAConflict() {
        #expect(facts(backend: .unsupported, systemLimit: 80).conflictingSystemLimit == nil)
    }

    /// Survives the rewiring on its own merits: while BatFi holds its 100% override the
    /// system's saved limit is not in force whatever it reads back as.
    @Test func anActiveOverrideMeansTheSystemLimitIsNotInForce() {
        let value = facts(backend: .chte, systemLimit: 80, batFiHoldsSystemLimitOverride: true)
        #expect(value.conflictingSystemLimit == nil)
    }

    /// With management off BatFi holds no override by design, and the system's own limit
    /// is exactly what should be in effect.
    @Test func managementOffMeansNoConflict() {
        #expect(facts(backend: .chte, manageCharging: false, systemLimit: 80).conflictingSystemLimit == nil)
    }

    @Test func noMCLSupportMeansNoConflict() {
        #expect(facts(backend: .chte, systemLimitIsSupported: false, systemLimit: 80).conflictingSystemLimit == nil)
    }

    /// An unreadable limit is not evidence of a conflict. Warning on `nil` would pin a
    /// permanent orange label to every Mac whose PowerUI declines the read.
    @Test func anUnreadableSystemLimitDoesNotConflict() {
        #expect(facts(backend: .chte, systemLimit: nil).conflictingSystemLimit == nil)
    }

    // MARK: - Slider bounds

    /// The constraint: rather than letting the user pick a value that gets silently
    /// raised, the mechanism's real floor is what the slider offers.
    @Test func theSystemChargeLimitRaisesTheSliderFloor() {
        #expect(ChargeLimitRange.lowestSelectable(for: .systemChargeLimit) == 80)
    }

    @Test func theSMCBackendsKeepTheFullRange() {
        #expect(ChargeLimitRange.lowestSelectable(for: .chte) == 50)
        #expect(ChargeLimitRange.lowestSelectable(for: .legacyCH0BC) == 50)
    }

    /// Deliberately not constrained despite `honoursLimitsBelow80` being false. Nothing is
    /// applied here at all, so raising the floor to 80% would imply 80% is in force when
    /// nothing is — and that Mac is already told the truth by `.chargingControlUnavailable`.
    @Test func unsupportedFirmwareIsNotConstrainedToEighty() {
        #expect(ChargeLimitRange.lowestSelectable(for: .unsupported) == 50)
    }

    /// Before diagnostics land, so the slider does not jump on every working Mac each
    /// time the pane opens.
    @Test func anUnresolvedBackendKeepsTheFullRange() {
        #expect(ChargeLimitRange.lowestSelectable(for: nil) == 50)
    }

    /// The slider floor is now *derived* from `ChargeBackend.honoursLimitsBelow80` rather
    /// than restating it in a second switch over the same enum. This is the assertion that
    /// keeps them one fact: a backend that does not honour limits below 80 gets the raised
    /// floor, and one that does keeps the full range — for every case, so a sixth backend
    /// cannot answer the property correctly while the slider quietly offers 50%.
    ///
    /// `.unsupported` is the deliberate exception and is asserted as such rather than
    /// skipped: nothing is applied there at all, so a raised floor would imply 80% is in
    /// force when nothing is.
    @Test func theSliderFloorFollowsTheBackendProperty() {
        for backend in ChargeBackend.allCases {
            let floor = ChargeLimitRange.lowestSelectable(for: backend)
            if backend == .unsupported {
                #expect(!backend.honoursLimitsBelow80)
                #expect(floor == ChargeLimitRange.lowest, "\(backend.rawValue)")
                continue
            }
            let expected = backend.honoursLimitsBelow80
                ? ChargeLimitRange.lowest
                : ChargeLimitRange.systemChargeLimitLowest
            #expect(floor == expected, "\(backend.rawValue)")
        }
    }

    /// The user's 55% is *shown* at the floor, never written back to it. Keeping the
    /// stored value is what lets it return untouched if this Mac ever regains a mechanism
    /// that can honour it — and clamping it would erase the very setting the disclosure
    /// exists to talk about.
    @Test func aStoredLimitBelowTheFloorIsDisplayedAtTheFloor() {
        #expect(ChargeLimitRange.displayedLimit(configured: 55, for: .systemChargeLimit) == 80)
        #expect(ChargeLimitRange.displayedLimit(configured: 55, for: .chte) == 55)
    }

    @Test func aStoredLimitWithinRangeIsUntouched() {
        for limit in [80, 85, 90] {
            #expect(ChargeLimitRange.displayedLimit(configured: limit, for: .systemChargeLimit) == limit)
        }
    }

    /// Both ends are clamped. The slider is the only writer of this default today, but a
    /// value from anywhere else must not push the knob off the track.
    @Test func aStoredLimitAboveTheCeilingIsClamped() {
        #expect(ChargeLimitRange.displayedLimit(configured: 100, for: .systemChargeLimit) == 90)
        #expect(ChargeLimitRange.displayedLimit(configured: 100, for: .chte) == 90)
    }

    // MARK: - Reading the helper's snapshot

    /// The convenience init is what the pane actually uses, so the field-by-field mapping
    /// is worth pinning: a field read from the wrong place would silently disclose the
    /// wrong thing.
    @Test func factsAreReadFromTheDiagnosticsSnapshot() {
        let diagnostics = ChargingDiagnostics(
            backend: ChargeBackend.systemChargeLimit.rawValue,
            firmwareVersion: "mBoot-18000.161.9",
            notChargingReasons: [],
            mcl: MCLStatus(
                supported: true,
                batFiHasActiveOverride: false,
                lastOverrideValue: nil,
                systemLimit: 80,
                snapshotRefused: false
            ),
            forceDischargeAvailable: true,
            magSafeLEDAvailable: false,
            appliedChargeLimit: 80,
            chargeLimitWasRaised: true,
            requestedChargeLimit: 55
        )
        let value = ChargeControlFacts(
            diagnostics: diagnostics,
            manageCharging: true,
            hotBatteryProtectionEnabled: true,
            pauseChargingOnSleepEnabled: false
        )
        #expect(value.backend == .systemChargeLimit)
        #expect(value.appliedChargeLimit == 80)
        #expect(value.chargeLimitWasRaised)
        #expect(value.requestedChargeLimit == 55)
        #expect(value.systemLimit == 80)
        #expect(value.systemLimitIsSupported)
        #expect(value.forceDischargeAvailable)
        #expect(value.systemLimitSnapshotRefused == false)
        #expect(value.disclosures == [
            .usingSystemChargeLimit,
            .limitRaisedToSystemMinimum(applied: 80),
            .managingSystemSettingsLimit,
            .pausingChargingUnavailable(heldBy: .macOSChargeLimit, forceDischargeStillAvailable: true),
        ])
    }

    /// No snapshot at all — the pane before the helper answers, or a helper that failed.
    @Test func noDiagnosticsDisclosesNothing() {
        let value = ChargeControlFacts(
            diagnostics: nil,
            manageCharging: true,
            hotBatteryProtectionEnabled: true,
            pauseChargingOnSleepEnabled: true
        )
        #expect(value.backend == nil)
        #expect(value.disclosures.isEmpty)
        #expect(value.conflictingSystemLimit == nil)
    }

    /// A raw backend string this build does not recognize fails closed, the same rule
    /// `systemChargeLimitIsHoldingCharge` follows.
    ///
    /// The placeholder used to be `"firmwareRange"`, which stopped being unrecognized the
    /// day that case shipped — the scenario is a *newer helper* talking to an older app,
    /// so it needs a string no build has ever meant. Assert that directly rather than
    /// trusting the literal, so the next case added cannot quietly empty this test out.
    @Test func anUnrecognizedBackendStringDisclosesNothing() {
        let unknownBackend = "aBackendNoBuildHasEverShipped"
        #expect(ChargeBackend(rawValue: unknownBackend) == nil)
        let diagnostics = ChargingDiagnostics(
            backend: unknownBackend,
            firmwareVersion: nil,
            notChargingReasons: [],
            mcl: MCLStatus(supported: true, batFiHasActiveOverride: false, lastOverrideValue: nil, systemLimit: 80),
            forceDischargeAvailable: false,
            magSafeLEDAvailable: false
        )
        let value = ChargeControlFacts(
            diagnostics: diagnostics,
            manageCharging: true,
            hotBatteryProtectionEnabled: true,
            pauseChargingOnSleepEnabled: true
        )
        #expect(value.backend == nil)
        #expect(value.disclosures.isEmpty)
        #expect(value.conflictingSystemLimit == nil)
    }

    // MARK: - MCLStatus carries the new fields across XPC

    /// Both new fields ride the XPC boundary, and a field added to the class but forgotten
    /// in either half of the coder decodes as a silent nil/false — which here would mean
    /// "no conflict" and "no refusal" on the machines where both are true.
    @Test func theNewMCLFieldsSurviveTheXPCRoundTrip() throws {
        let status = MCLStatus(
            supported: true,
            batFiHasActiveOverride: true,
            lastOverrideValue: 100,
            systemLimit: 80,
            snapshotRefused: true
        )
        let data = try NSKeyedArchiver.archivedData(withRootObject: status, requiringSecureCoding: true)
        let decoded = try #require(try NSKeyedUnarchiver.unarchivedObject(ofClass: MCLStatus.self, from: data))
        #expect(decoded.systemLimit == 80)
        #expect(decoded.snapshotRefused)
        #expect(decoded.lastOverrideValue == 100)
        #expect(decoded.batFiHasActiveOverride)
        #expect(decoded.supported)
    }

    /// An absent limit has to decode as absent, not as a stored zero — which is why the
    /// flag-plus-value shape is used rather than a bare `decodeInteger`.
    @Test func anAbsentSystemLimitRoundTripsAsAbsent() throws {
        let status = MCLStatus(supported: false, batFiHasActiveOverride: false, lastOverrideValue: nil)
        let data = try NSKeyedArchiver.archivedData(withRootObject: status, requiringSecureCoding: true)
        let decoded = try #require(try NSKeyedUnarchiver.unarchivedObject(ofClass: MCLStatus.self, from: data))
        #expect(decoded.systemLimit == nil)
        #expect(decoded.snapshotRefused == false)
    }
}
