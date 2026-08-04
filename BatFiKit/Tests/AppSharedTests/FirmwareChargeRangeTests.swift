//
//  FirmwareChargeRangeTests.swift
//  BatFi
//
//  The macOS 27 firmware keys encode ui32 percentages LITTLE-endian, against the
//  normal SMC convention every other ui32 key in this codebase follows.
//

import Foundation
import Testing

@testable import Shared

@Suite struct FirmwareChargeRangeTests {
    /// 50% is 32 00 00 00, not 00 00 00 32.
    @Test func encodesPercentageLittleEndian() {
        let bytes = FirmwareChargeRange.encodePercentage(50)
        #expect(bytes == (0x32, 0x00, 0x00, 0x00))
    }

    @Test func encodesFullChargeLittleEndian() {
        #expect(FirmwareChargeRange.encodePercentage(100) == (0x64, 0x00, 0x00, 0x00))
    }

    @Test func roundTripsEveryValidPercentage() {
        for value in 0 ... 100 {
            #expect(FirmwareChargeRange.decodePercentage(FirmwareChargeRange.encodePercentage(value)) == value)
        }
    }

    /// A big-endian reading of 50% would be 838860800 — the check that catches a
    /// byte-order regression outright.
    @Test func decodeIsNotBigEndian() {
        #expect(FirmwareChargeRange.decodePercentage((0x32, 0x00, 0x00, 0x00)) == 50)
        #expect(FirmwareChargeRange.decodePercentage((0x00, 0x00, 0x00, 0x32)) != 50)
    }

    /// BatFi has a single limit; the firmware wants a band. Five points of
    /// hysteresis matches what Apple's own limit uses.
    @Test func derivesBandFromSingleLimit() {
        let band = FirmwareChargeRange.band(forLimit: 80)
        #expect(band.upper == 80)
        #expect(band.lower == 75)
    }

    /// The lower bound must not go absurdly low for small limits.
    @Test func clampsLowerBound() {
        #expect(FirmwareChargeRange.band(forLimit: 12).lower >= 10)
        #expect(FirmwareChargeRange.band(forLimit: 10).lower >= 10)
    }

    @Test func upperNeverExceedsLimit() {
        for limit in 10 ... 100 {
            #expect(FirmwareChargeRange.band(forLimit: limit).upper == limit)
        }
    }

    /// The order is mandated by the firmware: deactivate, upper, lower, activate.
    /// Nobody has macOS 27 hardware, so this test is the only thing that can catch a
    /// reordering — and a reordering produces a Mac that charges past the user's limit
    /// while reporting success.
    @Test func engageSequenceFollowsTheMandatoryOrder() {
        let steps = FirmwareChargeRange.engageSequence(forLimit: 80)
        #expect(steps.map(\.key.code) == ["bfF0", "bfD0", "bfE0", "bfF0"])
        #expect(steps.map(\.bytes) == [
            [0x00],
            [0x50, 0x00, 0x00, 0x00],
            [0x4B, 0x00, 0x00, 0x00],
            [0x02],
        ])
    }

    /// The order holds for every limit, not just the one spelled out above.
    @Test func engageSequenceOrderHoldsForEveryLimit() {
        for limit in 0 ... 100 {
            let steps = FirmwareChargeRange.engageSequence(forLimit: limit)
            #expect(steps.map(\.key) == [
                FirmwareRangeKeyShape.activation,
                FirmwareRangeKeyShape.upperBound,
                FirmwareRangeKeyShape.lowerBound,
                FirmwareRangeKeyShape.activation,
            ])
            #expect(steps.first?.bytes == [FirmwareChargeRange.activationOff])
            #expect(steps.last?.bytes == [FirmwareChargeRange.activationOn])
        }
    }

    /// Arming is the last thing the sequence does, which is what makes clearing the one
    /// activation key a complete undo.
    @Test func nothingIsArmedBeforeTheFinalWrite() {
        let steps = FirmwareChargeRange.engageSequence(forLimit: 65)
        let armingWrites = steps.filter {
            $0.key == FirmwareRangeKeyShape.activation && $0.bytes != [FirmwareChargeRange.activationOff]
        }
        #expect(armingWrites.count == 1)
        #expect(steps.last.map { $0.key == FirmwareRangeKeyShape.activation } == true)
    }

    /// The bounds carry the little-endian percentages the encoder produces — no second
    /// encoding crept into the sequence builder.
    @Test func engageSequenceUsesTheLittleEndianEncoder() {
        for limit in 0 ... 100 {
            let bounds = FirmwareChargeRange.band(forLimit: limit)
            let upper = FirmwareChargeRange.encodePercentage(bounds.upper)
            let lower = FirmwareChargeRange.encodePercentage(bounds.lower)
            let steps = FirmwareChargeRange.engageSequence(forLimit: limit)
            #expect(steps[1].bytes == [upper.0, upper.1, upper.2, upper.3])
            #expect(steps[2].bytes == [lower.0, lower.1, lower.2, lower.3])
        }
    }

    /// Every write is exactly as long as the key the resolver verified, so the driver
    /// never sends a truncated or over-long value.
    @Test func everyWriteMatchesItsKeySize() {
        let sequences = [FirmwareChargeRange.engageSequence(forLimit: 80), FirmwareChargeRange.releaseSequence]
        for steps in sequences {
            for step in steps {
                #expect(UInt32(step.bytes.count) == step.key.size)
            }
        }
    }

    /// **Release only on restore.** Of the three points at which BatFi touches these keys,
    /// only the release path may clear the activation key.
    ///
    /// A charging-mode change must not. `ChargingManager.updateStatus` applies the limit and
    /// *then* takes a mode decision, so a release on the "charging allowed" arm would disarm
    /// the band in the very pass that armed it, on every pass where the battery sits below
    /// the limit — and the Mac would sleep with nothing in force. That turns a
    /// firmware-managed limit into no limit at all while displacing Apple's own, which is
    /// worse than the fallback it outranks.
    @Test func onlyTheReleasePathClearsActivation() {
        func clearsActivation(_ steps: [FirmwareRangeWrite]) -> Bool {
            steps.contains {
                $0.key == FirmwareRangeKeyShape.activation && $0.bytes == [FirmwareChargeRange.activationOff]
            }
        }
        #expect(clearsActivation(FirmwareChargeRange.releaseSequence))
        #expect(clearsActivation(FirmwareChargeRange.chargingModeChangeSequence) == false)
    }

    /// A charging-mode change writes nothing at all under this mechanism — the firmware owns
    /// the decision. Empty is the rule, not an oversight, so it is asserted rather than left
    /// as a `break` in an actor where nothing could look at it.
    @Test func chargingModeChangesWriteNothing() {
        #expect(FirmwareChargeRange.chargingModeChangeSequence.isEmpty)
    }

    /// The engage sequence's leading deactivate is not a release: it re-arms immediately, and
    /// the firmware requires `bfF0 <- 0x00` before the bounds move. So changing the user's
    /// limit runs the whole sequence over a live band with no separate release first — and
    /// leaves it armed.
    @Test func changingTheLimitRearmsOverALiveBand() {
        for limit in [50, 65, 80, 100] {
            let steps = FirmwareChargeRange.engageSequence(forLimit: limit)
            #expect(steps.count == 4)
            // Deactivate first, because the bounds may not move while the band is in force.
            #expect(steps.first?.key == FirmwareRangeKeyShape.activation)
            #expect(steps.first?.bytes == [FirmwareChargeRange.activationOff])
            // ...and armed again by the end, so re-arming never leaves the band off.
            #expect(steps.last?.key == FirmwareRangeKeyShape.activation)
            #expect(steps.last?.bytes == [FirmwareChargeRange.activationOn])
        }
        // Self-sufficient: the sequence does not depend on what ran before it, so applying a
        // new limit twice in a row is the same sequence twice.
        #expect(FirmwareChargeRange.engageSequence(forLimit: 70) == FirmwareChargeRange.engageSequence(forLimit: 70))
    }

    /// Releasing is one write of the activation key, and it is `off`.
    @Test func releaseSequenceClearsActivation() {
        #expect(FirmwareChargeRange.releaseSequence == [
            FirmwareRangeWrite(key: FirmwareRangeKeyShape.activation, bytes: [FirmwareChargeRange.activationOff])
        ])
    }

    /// **The reset invariant, as a value.** Every key the engage path writes must be
    /// cleared by the release path — either directly, or because it is inert once the
    /// activation key is off. The bounds are in the second category, so the check is that
    /// the release path covers the activation key and that nothing else the engage path
    /// touches survives it.
    @Test func releaseCoversEveryKeyEngageArms() {
        let engaged = Set(FirmwareChargeRange.engageSequence(forLimit: 80).map(\.key.code))
        let released = Set(FirmwareChargeRange.releaseSequence.map(\.key.code))
        #expect(released.contains(FirmwareRangeKeyShape.activation.code))
        // Anything engage writes that release does not must be a bound, which the firmware
        // ignores while the activation key is off. A new key here is a new thing to clear.
        let uncleared = engaged.subtracting(released)
        #expect(uncleared == [FirmwareRangeKeyShape.upperBound.code, FirmwareRangeKeyShape.lowerBound.code])
    }

    /// Every key either sequence names is one the helper actually probes, so a write can
    /// never target a key the resolver never verified.
    @Test func everySequenceKeyIsProbed() {
        let sequences = [FirmwareChargeRange.engageSequence(forLimit: 80), FirmwareChargeRange.releaseSequence]
        for steps in sequences {
            for step in steps {
                #expect(FirmwareRangeKeyShape.all.contains(step.key))
                #expect(ChargeBackendResolver.probedKeys.contains(step.key.code))
            }
        }
    }

    /// `off` is the only value read as "not armed". A firmware using some other non-zero
    /// byte for an armed state must not read back as released.
    @Test func activationStatusTreatsAnyNonZeroAsEngaged() {
        #expect(FirmwareChargeRange.rangeIsEngaged(activation: FirmwareChargeRange.activationOff) == false)
        #expect(FirmwareChargeRange.rangeIsEngaged(activation: FirmwareChargeRange.activationOn))
        for value in UInt8(1) ... UInt8(255) {
            #expect(FirmwareChargeRange.rangeIsEngaged(activation: value))
        }
    }

    // MARK: - The release obligation

    /// The C1 case, as a value. A band armed under `.firmwareRange` must still be handed
    /// back after a transient SMC failure drops the backend cache and the re-probe answers
    /// something else. Gating the release on the backend alone left the Mac permanently
    /// capped by a firmware limit that nothing in System Settings shows.
    @Test func aBandThisProcessArmedIsReleasedWhateverTheBackendNowSays() {
        for backend in ChargeBackend.allCases {
            #expect(
                FirmwareChargeRange.releaseIsOwed(armedByThisProcess: true, resolvedBackend: backend),
                "\(backend.rawValue)"
            )
        }
        // Including where the backend was deliberately not asked, which is what the quit
        // path does so an armed band never pays for a nine-key re-probe against a watchdog.
        #expect(FirmwareChargeRange.releaseIsOwed(armedByThisProcess: true, resolvedBackend: nil))
    }

    /// The other half, and it is not redundant: the flag is process-local, so a helper that
    /// was restarted — jetsam, a crash, a launchd relaunch — has no memory of a band the
    /// firmware is still enforcing. The resolved backend is the only thing left that knows.
    @Test func aBandThisProcessDoesNotRememberIsStillReleasedUnderTheFirmwareRange() {
        #expect(
            FirmwareChargeRange.releaseIsOwed(armedByThisProcess: false, resolvedBackend: .firmwareRange)
        )
    }

    /// And nothing is owed where neither input says so — writing `bfF0` on firmware that has
    /// no such key throws, and `restoreSystemDefaults()` would report a failed restore to
    /// the entire existing fleet.
    @Test func nothingIsOwedOnFirmwareThatNeverHadABand() {
        for backend in ChargeBackend.allCases where backend != .firmwareRange {
            #expect(
                !FirmwareChargeRange.releaseIsOwed(armedByThisProcess: false, resolvedBackend: backend),
                "\(backend.rawValue)"
            )
        }
        #expect(!FirmwareChargeRange.releaseIsOwed(armedByThisProcess: false, resolvedBackend: nil))
    }
}
