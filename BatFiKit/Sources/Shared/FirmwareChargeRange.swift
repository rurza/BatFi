//
//  FirmwareChargeRange.swift
//
//
//  How a percentage is written to the macOS 27-era firmware-managed charge range.
//
//  Pure, and in `Shared`, for the same reason `ChargeBackendResolver` is: only `Shared`
//  is reachable from the test target, and a byte order is precisely the kind of decision
//  that fails silently. The keys themselves — `bfD0`/`bfE0`/`bfF0`, and the shapes they
//  must have — are stated once in `FirmwareRangeKeyShape` and are deliberately not
//  restated here.
//

import Foundation

/// One write in a firmware-range sequence: the key it targets and the exact bytes for it.
///
/// The key is a `FirmwareRangeKeyShape.Key` rather than a code of its own, so a sequence
/// can only ever name a key the resolver already probed and matched, and the four-character
/// codes stay stated exactly once.
public struct FirmwareRangeWrite: Sendable, Equatable {
    public let key: FirmwareRangeKeyShape.Key
    /// `key.size` bytes, already in the byte order the firmware expects — little-endian
    /// for the two bounds. Shorter than `key.size` is never produced by the sequences
    /// below; a writer that pads is padding into bytes the driver ignores, because the
    /// write length comes from the key's own size.
    public let bytes: [UInt8]

    public init(key: FirmwareRangeKeyShape.Key, bytes: [UInt8]) {
        self.key = key
        self.bytes = bytes
    }
}

/// Encoding for the macOS 27 firmware-managed charge range.
public enum FirmwareChargeRange {
    /// Hysteresis in percentage points between the upper and lower bounds. Matches
    /// the 5 points Apple's own charge limit uses before it resumes charging.
    public static let hysteresis = 5
    /// Floor for the lower bound, so a small limit cannot produce a nonsensical band.
    public static let minimumLowerBound = 10

    /// These keys are little-endian, unlike every other `ui32` key here.
    ///
    /// Every other `ui32` SMC key in this codebase is big-endian, so this is a reversal
    /// of the house convention and not a detail to "tidy up" into the shared path. The
    /// failure mode if it is: 50% written big-endian reads back as 838,860,800, which the
    /// firmware neither rejects nor reports — it simply enforces a limit that is nothing
    /// like the one the user asked for. `decodeIsNotBigEndian` is the test that pins it.
    ///
    /// Returned as four bytes rather than a `UInt32` because that is what `SMCKit.writeData`
    /// takes, so no caller is left to re-derive the byte order at the call site.
    public static func encodePercentage(_ value: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let clamped = UInt32(max(0, min(100, value)))
        return (
            UInt8(clamped & 0xFF),
            UInt8((clamped >> 8) & 0xFF),
            UInt8((clamped >> 16) & 0xFF),
            UInt8((clamped >> 24) & 0xFF)
        )
    }

    /// The inverse of `encodePercentage`, for reading a bound back off the firmware.
    public static func decodePercentage(_ bytes: (UInt8, UInt8, UInt8, UInt8)) -> Int {
        let value = UInt32(bytes.0)
            | (UInt32(bytes.1) << 8)
            | (UInt32(bytes.2) << 16)
            | (UInt32(bytes.3) << 24)
        return Int(value)
    }

    /// BatFi exposes one limit; the firmware enforces a band.
    ///
    /// The upper bound is always the user's limit exactly — that is the number they set
    /// and the number they will watch the battery stop at. Only the lower bound is
    /// derived, and it is floored so that a small limit cannot ask the firmware to let
    /// the battery run down to something absurd before charging resumes.
    public static func band(forLimit limit: Int) -> (upper: Int, lower: Int) {
        let upper = max(0, min(100, limit))
        let lower = max(minimumLowerBound, upper - hysteresis)
        // A limit at or below the floor would otherwise produce a lower bound above the
        // upper one, i.e. an inverted band, which is not something to hand to firmware.
        return (upper, min(lower, upper))
    }

    /// `bfF0` at this value: the range is not in force and the firmware charges freely.
    public static let activationOff: UInt8 = 0x00
    /// `bfF0` at this value: the range is in force and the firmware enforces the band,
    /// including while the Mac is asleep.
    public static let activationOn: UInt8 = 0x02

    /// Whether a `bfF0` reading says the range is armed.
    ///
    /// Tested against "off" rather than for `activationOn` exactly, the same way
    /// `smcChargingStatus` tests the force-discharge keys for "not connected": only the
    /// released value has been pinned down, and a firmware that used some other non-zero
    /// byte for an armed state must not read back as released. Erring toward "armed" is
    /// the safe direction — it reports charge control as in force, which is what the
    /// engage path just asked for.
    public static func rangeIsEngaged(activation: UInt8) -> Bool {
        activation != activationOff
    }

    /// The writes that put a band in force, **in the order the firmware requires**:
    /// deactivate, upper bound, lower bound, activate.
    ///
    /// A value rather than four `writeData` calls in an actor method on purpose. The order
    /// is a firmware requirement and nobody has the hardware to observe it being violated,
    /// so it has to be something a test can read — and reordering it silently produces a
    /// Mac that charges past the user's limit, which is precisely the failure that goes
    /// unnoticed. The caller performs this list; it does not decide it.
    ///
    /// Note that the sequence both opens and closes on the activation key. That is what
    /// makes `releaseSequence` a complete undo: nothing is armed before the final write,
    /// so clearing that one key disarms everything this sequence did.
    public static func engageSequence(forLimit limit: Int) -> [FirmwareRangeWrite] {
        let bounds = band(forLimit: limit)
        let upper = encodePercentage(bounds.upper)
        let lower = encodePercentage(bounds.lower)
        return [
            FirmwareRangeWrite(key: FirmwareRangeKeyShape.activation, bytes: [activationOff]),
            FirmwareRangeWrite(
                key: FirmwareRangeKeyShape.upperBound,
                bytes: [upper.0, upper.1, upper.2, upper.3]
            ),
            FirmwareRangeWrite(
                key: FirmwareRangeKeyShape.lowerBound,
                bytes: [lower.0, lower.1, lower.2, lower.3]
            ),
            FirmwareRangeWrite(key: FirmwareRangeKeyShape.activation, bytes: [activationOn]),
        ]
    }

    /// The writes that take the band back out of force — a single one, because the bounds
    /// mean nothing while the activation key is off.
    ///
    /// The same list serves `releaseFirmwareRange` and the reset path, so the safety net
    /// cannot come to clear less than the engage path arms.
    ///
    /// **Release only on restore.** This runs when BatFi is handing the machine back — quit,
    /// or charge management turned off — and from the crash safety net. It must *not* run on
    /// a charging-mode change; see `chargingModeChangeSequence`.
    public static let releaseSequence: [FirmwareRangeWrite] = [
        FirmwareRangeWrite(key: FirmwareRangeKeyShape.activation, bytes: [activationOff])
    ]

    /// What a charging-mode change — charge, inhibit, discharge — writes under this
    /// mechanism: **nothing, in either direction.** Empty is the rule, not an oversight.
    ///
    /// Under an inhibit backend a mode change *is* the mechanism, so every one is a write.
    /// Here it is the opposite: BatFi hands the firmware a band once, in the engage
    /// sequence, and steps back. The firmware then decides moment to moment whether to
    /// charge — which is the entire reason this backend outranks the others, because it
    /// goes on deciding while the Mac is asleep and no BatFi process is running at all.
    ///
    /// Releasing the band here would destroy exactly that. `ChargingManager.updateStatus`
    /// applies the limit and *then* takes a mode decision, so a release on the "charging
    /// allowed" arm would disarm the band in the same pass that armed it, on every pass
    /// where the battery sits below the limit — leaving the machine to sleep with no limit
    /// in force. The result would be a backend that displaces Apple's own charge limit
    /// while enforcing strictly less than it. `onlyTheReleasePathClearsActivation` is the
    /// test that pins this.
    ///
    /// Same shape `.systemChargeLimit` already has, where the mechanism owns the decision
    /// and `enableCharging(_:)` succeeds without writing anything. Note this does **not**
    /// mean charging can be paused on demand: it cannot, under either backend, because a
    /// band is not an inhibit. That is a disclosure the user is owed, not a write to make.
    public static let chargingModeChangeSequence: [FirmwareRangeWrite] = []
}
