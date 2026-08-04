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
}
