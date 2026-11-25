//
//  AutoLowPowerModePolicyTests.swift
//  BatFi
//
//  Unit tests for the pure policy that turns Low Power Mode on for the battery profile
//  below a charge threshold, and gives back exactly what it took.
//

import Foundation
import Testing

@testable import Shared

@Suite struct AutoLowPowerModePolicyTests {
    private typealias Policy = AutoLowPowerModePolicy
    private typealias Decision = AutoLowPowerModePolicy.Decision

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func live(battery: UInt8?, ac: UInt8? = 0, usesPowermodeKey: Bool = true) -> PowerModeBySource {
        PowerModeBySource(battery: battery, ac: ac, usesPowermodeKey: usesPowermodeKey)
    }

    private func record(
        previous: UInt8 = 0,
        acAtWrite: UInt8? = 0,
        usesPowermodeKey: Bool = true
    ) -> AutoLowPowerModeRecord {
        AutoLowPowerModeRecord(
            usesPowermodeKey: usesPowermodeKey,
            previousBatteryValue: previous,
            acValueAtWrite: acAtWrite,
            engagedAt: now
        )
    }

    private func input(
        enabled: Bool = true,
        license: LicenseStatus = .valid,
        threshold: Int = 20,
        onBattery: Bool = true,
        level: Int,
        live: PowerModeBySource?,
        record: AutoLowPowerModeRecord? = nil,
        yieldedUntilCharge: Bool = false
    ) -> Policy.Input {
        Policy.Input(
            enabled: enabled,
            license: license,
            threshold: threshold,
            onBattery: onBattery,
            batteryLevel: level,
            live: live,
            record: record,
            yieldedUntilCharge: yieldedUntilCharge,
            now: now
        )
    }

    private func nothing(_ reason: Policy.Reason, yieldedUntilCharge: Bool = false) -> Decision {
        Decision(write: nil, record: .keep, yieldedUntilCharge: yieldedUntilCharge, reason: reason)
    }

    // MARK: Engaging

    @Test func engagesExactlyAtTheThreshold() {
        #expect(
            Policy.decide(input(level: 20, live: live(battery: 0, ac: 0)))
                == Decision(
                    write: 1,
                    record: .set(record(previous: 0, acAtWrite: 0)),
                    yieldedUntilCharge: false,
                    reason: .engaged
                )
        )
    }

    @Test func doesNotEngageOnePercentAboveTheThreshold() {
        #expect(Policy.decide(input(level: 21, live: live(battery: 0))) == nothing(.aboveThreshold))
    }

    /// Zero is what an unread level looks like. Acting on it would engage on every launch
    /// before the first power-source reading arrives.
    @Test func ignoresALevelOfZero() {
        #expect(Policy.decide(input(level: 0, live: live(battery: 0))) == nothing(.levelUnknown))
    }

    @Test func recordsWhatItFoundOnBothProfilesAndWhichKey() {
        let decision = Policy.decide(input(level: 12, live: live(battery: 0, ac: 1, usesPowermodeKey: false)))
        #expect(decision.write == 1)
        #expect(decision.record == .set(record(previous: 0, acAtWrite: 1, usesPowermodeKey: false)))
    }

    /// A Mac with no AC section published: the record says so, and ownership does not
    /// depend on an AC value that was never seen.
    @Test func recordsAMissingACValueAsMissing() {
        let decision = Policy.decide(input(level: 12, live: live(battery: 0, ac: nil)))
        #expect(decision.record == .set(record(previous: 0, acAtWrite: nil)))
    }

    /// The user chose Always or Only on Battery, or turned it on with BatFi's own toggle.
    /// That Low Power Mode is theirs: taking it over would mean switching it off for them
    /// the moment the charger goes in.
    @Test func neverTakesOwnershipOfLowPowerModeThatIsAlreadyOn() {
        #expect(Policy.decide(input(level: 10, live: live(battery: 1, ac: 0))) == nothing(.alreadyLowPower))
        #expect(Policy.decide(input(level: 10, live: live(battery: 1, ac: 1))) == nothing(.alreadyLowPower))
    }

    /// A value BatFi could not write back is a value it must not take: Low Power Mode would
    /// stay on for good. `powermode` restores 0 or 2; `lowpowermode` only 0.
    @Test func neverTakesOwnershipOfAValueItCannotRestore() {
        #expect(
            Policy.decide(input(level: 10, live: live(battery: 3, ac: 0, usesPowermodeKey: true)))
                == nothing(.previousValueNotRestorable)
        )
        #expect(
            Policy.decide(input(level: 10, live: live(battery: 2, ac: 0, usesPowermodeKey: false)))
                == nothing(.previousValueNotRestorable)
        )
    }

    @Test func takesOwnershipOfEveryValueItCanRestore() {
        #expect(Policy.decide(input(level: 10, live: live(battery: 0, usesPowermodeKey: true))).reason == .engaged)
        #expect(Policy.decide(input(level: 10, live: live(battery: 2, usesPowermodeKey: true))).reason == .engaged)
        #expect(Policy.decide(input(level: 10, live: live(battery: 0, usesPowermodeKey: false))).reason == .engaged)
    }

    @Test func doesNothingWhileDisabled() {
        #expect(Policy.decide(input(enabled: false, level: 10, live: live(battery: 0))) == nothing(.disabled))
    }

    @Test func doesNothingOnTheCharger() {
        #expect(Policy.decide(input(onBattery: false, level: 10, live: live(battery: 0))) == nothing(.notOnBattery))
    }

    // MARK: Never acting blind

    @Test func doesNothingWithoutLiveStateAndNoRecord() {
        #expect(Policy.decide(input(level: 10, live: nil)) == nothing(.liveStateUnknown))
        #expect(Policy.decide(input(level: 10, live: live(battery: nil, ac: 0))) == nothing(.liveStateUnknown))
    }

    /// With a record held, not knowing the live value is exactly when a write could
    /// overwrite something the user just chose. The record is kept for the next reading.
    @Test func doesNothingWithoutLiveStateAndARecord() {
        #expect(
            Policy.decide(input(onBattery: false, level: 30, live: nil, record: record()))
                == nothing(.liveStateUnknown)
        )
        #expect(
            Policy.decide(input(onBattery: false, level: 30, live: live(battery: nil, ac: 0), record: record()))
                == nothing(.liveStateUnknown)
        )
    }

    // MARK: Giving it back

    @Test func restoresThePreviousValueWhenTheChargerIsConnected() {
        #expect(
            Policy.decide(input(
                onBattery: false,
                level: 15,
                live: live(battery: 1, ac: 0),
                record: record(previous: 0),
                yieldedUntilCharge: true
            ))
                == Decision(write: 0, record: .clear, yieldedUntilCharge: false, reason: .restoredOnCharger)
        )
    }

    /// High Power Mode is 2. Restoring "off" would be restoring 0 — automatic — and quietly
    /// lose the user's choice.
    @Test func restoresHighPowerModeAsHighPowerMode() {
        let engaged = Policy.decide(input(level: 10, live: live(battery: 2, ac: 0)))
        #expect(engaged.record == .set(record(previous: 2)))

        #expect(
            Policy.decide(input(onBattery: false, level: 10, live: live(battery: 1), record: record(previous: 2)))
                == Decision(write: 2, record: .clear, yieldedUntilCharge: false, reason: .restoredOnCharger)
        )
    }

    @Test func restoresWhenDisabledWhileHolding() {
        #expect(
            Policy.decide(input(enabled: false, level: 10, live: live(battery: 1, ac: 0), record: record(previous: 0)))
                == Decision(write: 0, record: .clear, yieldedUntilCharge: false, reason: .restoredBecauseDisabled)
        )
    }

    /// Lowered from 20 to 10 at 18%: 18 is at least 10 + 5, so the battery is comfortably
    /// above the new threshold and Low Power Mode goes.
    @Test func restoresWhenTheThresholdIsLoweredPastTheHysteresis() {
        #expect(
            Policy.decide(input(threshold: 10, level: 18, live: live(battery: 1, ac: 0), record: record(previous: 0)))
                == Decision(write: 0, record: .clear, yieldedUntilCharge: false, reason: .restoredAboveThreshold)
        )
        #expect(
            Policy.decide(input(threshold: 10, level: 15, live: live(battery: 1, ac: 0), record: record(previous: 0)))
                == Decision(write: 0, record: .clear, yieldedUntilCharge: false, reason: .restoredAboveThreshold)
        )
    }

    /// Lowered from 20 to 15 at 18%: 18 is above the new threshold but within 5 of it.
    /// Giving Low Power Mode back here would only have it re-engage a few percent later.
    @Test func keepsWhenTheThresholdIsLoweredWithinTheHysteresis() {
        #expect(
            Policy.decide(input(threshold: 15, level: 18, live: live(battery: 1, ac: 0), record: record()))
                == nothing(.holding)
        )
        #expect(
            Policy.decide(input(threshold: 10, level: 14, live: live(battery: 1, ac: 0), record: record()))
                == nothing(.holding)
        )
    }

    @Test func keepsWhileOnBatteryBelowTheThreshold() {
        #expect(Policy.decide(input(level: 8, live: live(battery: 1, ac: 0), record: record())) == nothing(.holding))
    }

    // MARK: Handing back to the user

    /// The user turned Low Power Mode off themselves while BatFi held it. It is theirs now:
    /// the record goes, nothing is written, and BatFi stays out until the next charge.
    @Test func handsBackWhenTheUserTurnsItOff() {
        #expect(
            Policy.decide(input(level: 10, live: live(battery: 0, ac: 0), record: record(previous: 0)))
                == Decision(write: nil, record: .clear, yieldedUntilCharge: true, reason: .handedBackToUser)
        )
    }

    @Test func handsBackWhenTheUserChangesOnlyTheACValue() {
        #expect(
            Policy.decide(input(level: 10, live: live(battery: 1, ac: 1), record: record(acAtWrite: 0)))
                == Decision(write: nil, record: .clear, yieldedUntilCharge: true, reason: .handedBackToUser)
        )
    }

    @Test func handsBackWhenTheKeyChanged() {
        #expect(
            Policy.decide(input(
                level: 10,
                live: live(battery: 1, ac: 0, usesPowermodeKey: false),
                record: record(usesPowermodeKey: true)
            ))
                == Decision(write: nil, record: .clear, yieldedUntilCharge: true, reason: .handedBackToUser)
        )
    }

    /// Handed back on the charger there is nothing to wait for: the charge that ends the
    /// latch is already happening.
    @Test func handingBackOnTheChargerDoesNotLatch() {
        #expect(
            Policy.decide(input(onBattery: false, level: 10, live: live(battery: 0, ac: 0), record: record()))
                == Decision(write: nil, record: .clear, yieldedUntilCharge: false, reason: .handedBackToUser)
        )
    }

    /// The whole cycle: BatFi engages, the user turns it off, BatFi stays out for the rest
    /// of that discharge however low it goes, and engages again only after a spell on AC.
    @Test func staysOutUntilTheNextChargeAfterHandingBack() {
        var record: AutoLowPowerModeRecord?
        var yielded = false
        var batteryValue: UInt8 = 0

        func step(onBattery: Bool, level: Int) -> Decision {
            let decision = Policy.decide(
                input(
                    onBattery: onBattery,
                    level: level,
                    live: live(battery: batteryValue, ac: 0),
                    record: record,
                    yieldedUntilCharge: yielded
                )
            )
            switch decision.record {
            case .keep: break
            case let .set(new): record = new
            case .clear: record = nil
            }
            yielded = decision.yieldedUntilCharge
            if let write = decision.write { batteryValue = write }
            return decision
        }

        #expect(step(onBattery: true, level: 20).reason == .engaged)
        #expect(batteryValue == 1)

        batteryValue = 0 // The user turns it off in System Settings.
        #expect(step(onBattery: true, level: 19).reason == .handedBackToUser)
        #expect(record == nil)
        #expect(yielded)

        #expect(step(onBattery: true, level: 10) == nothing(.yieldedUntilCharge, yieldedUntilCharge: true))
        #expect(step(onBattery: true, level: 5) == nothing(.yieldedUntilCharge, yieldedUntilCharge: true))
        #expect(batteryValue == 0)

        #expect(step(onBattery: false, level: 6) == nothing(.notOnBattery, yieldedUntilCharge: false))

        #expect(step(onBattery: true, level: 6).reason == .engaged)
        #expect(batteryValue == 1)
    }

    /// The latch ends on AC even when nothing else can be decided.
    @Test func theLatchEndsOnTheChargerEvenWithoutLiveState() {
        #expect(
            Policy.decide(input(onBattery: false, level: 10, live: nil, yieldedUntilCharge: true))
                == nothing(.liveStateUnknown, yieldedUntilCharge: false)
        )
    }

    @Test func theLatchSurvivesOnBattery() {
        #expect(
            Policy.decide(input(level: 30, live: nil, yieldedUntilCharge: true))
                == nothing(.liveStateUnknown, yieldedUntilCharge: true)
        )
        #expect(
            Policy.decide(input(level: 10, live: live(battery: 0), yieldedUntilCharge: true))
                == nothing(.yieldedUntilCharge, yieldedUntilCharge: true)
        )
    }

    // MARK: The licence

    /// Without a valid licence the feature is off, whatever the switch says: at the
    /// threshold, on battery, with a value it could give back, nothing is turned on.
    @Test func neverEngagesWithoutAValidLicence() {
        #expect(Policy.decide(input(license: .invalid, level: 10, live: live(battery: 0))) == nothing(.disabled))
    }

    /// Nor before the licence has been read at launch.
    @Test func neverEngagesBeforeTheLicenceIsRead() {
        #expect(Policy.decide(input(license: .unknown, level: 10, live: live(battery: 0))) == nothing(.disabled))
    }

    /// Losing the licence gives Low Power Mode back exactly as switching the feature off
    /// does — and, like that, without the hand-back latch: the user took nothing over.
    @Test func losingTheLicenceGivesBackWhatBatFiHolds() {
        #expect(
            Policy.decide(input(license: .invalid, level: 10, live: live(battery: 1, ac: 0), record: record(previous: 0)))
                == Decision(write: 0, record: .clear, yieldedUntilCharge: false, reason: .restoredBecauseDisabled)
        )
        #expect(
            Policy.decide(input(license: .invalid, level: 10, live: live(battery: 1, ac: 0), record: record(previous: 2)))
                == Decision(write: 2, record: .clear, yieldedUntilCharge: false, reason: .restoredBecauseDisabled)
        )
    }

    /// A licence not read yet is no reason to give anything back: once it reads valid, a
    /// launch would only take Low Power Mode again a moment later.
    @Test func aLicenceNotReadYetKeepsWhatBatFiHolds() {
        #expect(
            Policy.decide(input(license: .unknown, level: 10, live: live(battery: 1, ac: 0), record: record(previous: 0)))
                == nothing(.holding)
        )
    }

    /// Every other reason to give back still holds while the licence is being read.
    @Test func aLicenceNotReadYetStillGivesBackForEveryOtherReason() {
        #expect(
            Policy.decide(input(license: .unknown, onBattery: false, level: 10, live: live(battery: 1), record: record(previous: 0)))
                == Decision(write: 0, record: .clear, yieldedUntilCharge: false, reason: .restoredOnCharger)
        )
        #expect(
            Policy.decide(input(enabled: false, license: .unknown, level: 10, live: live(battery: 1), record: record(previous: 0)))
                == Decision(write: 0, record: .clear, yieldedUntilCharge: false, reason: .restoredBecauseDisabled)
        )
        #expect(
            Policy.decide(input(license: .unknown, level: 60, live: live(battery: 1), record: record(previous: 0)))
                == Decision(write: 0, record: .clear, yieldedUntilCharge: false, reason: .restoredAboveThreshold)
        )
    }

    /// Activating a licence while running turns Low Power Mode on where the feature would
    /// have, with no relaunch.
    @Test func gainingTheLicenceEngagesAgain() {
        let unlicensed = input(license: .invalid, level: 10, live: live(battery: 0))
        #expect(Policy.decide(unlicensed).write == nil)

        var licensed = unlicensed
        licensed.license = .valid
        #expect(
            Policy.decide(licensed)
                == Decision(write: 1, record: .set(record(previous: 0)), yieldedUntilCharge: false, reason: .engaged)
        )
    }

    // MARK: Launch

    /// BatFi crashed while holding Low Power Mode; the helper noticed it exit and put the
    /// previous value back. The record is stale, not a sign the user took over — so no latch.
    @Test func launchClearsARecordTheHelperAlreadyRestored() {
        #expect(
            Policy.reconcileAtLaunch(input(level: 10, live: live(battery: 0, ac: 0), record: record(previous: 0)))
                == Decision(write: nil, record: .clear, yieldedUntilCharge: false, reason: .alreadyRestoredByHelper)
        )
        #expect(
            Policy.reconcileAtLaunch(input(level: 10, live: live(battery: 2, ac: 0), record: record(previous: 2)))
                == Decision(write: nil, record: .clear, yieldedUntilCharge: false, reason: .alreadyRestoredByHelper)
        )
    }

    @Test func launchRestoresARecordStillOwnedOnTheCharger() {
        #expect(
            Policy.reconcileAtLaunch(input(onBattery: false, level: 40, live: live(battery: 1), record: record(previous: 0)))
                == Decision(write: 0, record: .clear, yieldedUntilCharge: false, reason: .restoredOnCharger)
        )
    }

    @Test func launchKeepsARecordStillOwnedOnBatteryBelowTheThreshold() {
        #expect(
            Policy.reconcileAtLaunch(input(level: 10, live: live(battery: 1, ac: 0), record: record(previous: 0)))
                == nothing(.holding)
        )
    }

    /// The battery value matches but the AC value moved: the user changed Low Power Mode in
    /// System Settings after the helper restored it. That is a hand-back, latch and all.
    @Test func launchHandsBackWhenOnlyTheBatteryValueMatches() {
        #expect(
            Policy.reconcileAtLaunch(input(
                level: 10,
                live: live(battery: 0, ac: 1),
                record: record(previous: 0, acAtWrite: 0)
            ))
                == Decision(write: nil, record: .clear, yieldedUntilCharge: true, reason: .handedBackToUser)
        )
    }

    @Test func launchWithoutARecordDecidesAsUsual() {
        #expect(
            Policy.reconcileAtLaunch(input(level: 10, live: live(battery: 0, ac: 0)))
                == Decision(write: 1, record: .set(record(previous: 0)), yieldedUntilCharge: false, reason: .engaged)
        )
        #expect(Policy.reconcileAtLaunch(input(level: 10, live: nil, record: record())) == nothing(.liveStateUnknown))
    }

    // MARK: Ownership

    struct OwnershipCase: Sendable, CustomTestStringConvertible {
        var recordUsesPowermodeKey = true
        let acAtWrite: UInt8?
        let liveBattery: UInt8?
        let liveAC: UInt8?
        let liveUsesPowermodeKey: Bool
        let owned: Bool

        var testDescription: String {
            "record (\(recordUsesPowermodeKey ? "powermode" : "lowpowermode"), "
                + "ac \(acAtWrite.map(String.init) ?? "nil")) vs live "
                + "(\(liveBattery.map(String.init) ?? "nil"), \(liveAC.map(String.init) ?? "nil"), "
                + "\(liveUsesPowermodeKey ? "powermode" : "lowpowermode")) → \(owned)"
        }
    }

    /// The record was written as battery 1, with the `powermode` key unless a case says
    /// otherwise.
    @Test(arguments: [
        OwnershipCase(acAtWrite: 0, liveBattery: 1, liveAC: 0, liveUsesPowermodeKey: true, owned: true),
        OwnershipCase(acAtWrite: 0, liveBattery: 0, liveAC: 0, liveUsesPowermodeKey: true, owned: false),
        OwnershipCase(acAtWrite: 0, liveBattery: 2, liveAC: 0, liveUsesPowermodeKey: true, owned: false),
        OwnershipCase(acAtWrite: 0, liveBattery: nil, liveAC: 0, liveUsesPowermodeKey: true, owned: false),
        OwnershipCase(acAtWrite: 0, liveBattery: 1, liveAC: 1, liveUsesPowermodeKey: true, owned: false),
        OwnershipCase(acAtWrite: 0, liveBattery: 1, liveAC: nil, liveUsesPowermodeKey: true, owned: false),
        OwnershipCase(acAtWrite: 0, liveBattery: 1, liveAC: 0, liveUsesPowermodeKey: false, owned: false),
        OwnershipCase(acAtWrite: 1, liveBattery: 1, liveAC: 1, liveUsesPowermodeKey: true, owned: true),
        OwnershipCase(acAtWrite: nil, liveBattery: 1, liveAC: 0, liveUsesPowermodeKey: true, owned: true),
        OwnershipCase(acAtWrite: nil, liveBattery: 1, liveAC: 2, liveUsesPowermodeKey: true, owned: true),
        OwnershipCase(acAtWrite: nil, liveBattery: 1, liveAC: nil, liveUsesPowermodeKey: true, owned: true),
        OwnershipCase(acAtWrite: nil, liveBattery: 0, liveAC: nil, liveUsesPowermodeKey: true, owned: false),
        OwnershipCase(
            recordUsesPowermodeKey: false,
            acAtWrite: 0,
            liveBattery: 1,
            liveAC: 0,
            liveUsesPowermodeKey: true,
            owned: false
        ),
        OwnershipCase(
            recordUsesPowermodeKey: false,
            acAtWrite: 0,
            liveBattery: 1,
            liveAC: 0,
            liveUsesPowermodeKey: false,
            owned: true
        ),
    ])
    func isStillOwned(_ testCase: OwnershipCase) {
        #expect(
            Policy.isStillOwned(
                record(previous: 0, acAtWrite: testCase.acAtWrite, usesPowermodeKey: testCase.recordUsesPowermodeKey),
                live: live(
                    battery: testCase.liveBattery,
                    ac: testCase.liveAC,
                    usesPowermodeKey: testCase.liveUsesPowermodeKey
                )
            ) == testCase.owned
        )
    }

    // MARK: Persistence

    /// The record is stored in defaults through its Codable form and must come back whole:
    /// a record that loses its previous value cannot be given back.
    @Test func theRecordRoundTripsThroughItsCodableForm() throws {
        let original = AutoLowPowerModeRecord(
            usesPowermodeKey: false,
            previousBatteryValue: 2,
            acValueAtWrite: nil,
            engagedAt: now
        )
        let decoded = try JSONDecoder().decode(
            AutoLowPowerModeRecord.self,
            from: JSONEncoder().encode(original)
        )
        #expect(decoded == original)
        #expect(decoded.writtenBatteryValue == Policy.lowPowerValue)
    }
}
