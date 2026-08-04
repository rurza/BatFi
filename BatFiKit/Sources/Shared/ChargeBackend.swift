//
//  ChargeBackend.swift
//
//
//  Which SMC mechanism this machine's firmware actually supports.
//
//  Deliberately free of IOKit and of any macOS version check. SMC behaviour tracks
//  firmware, which moves independently of the OS: installing a new macOS on any
//  volume reflashes firmware for the whole Mac, and downgrading macOS does not roll
//  it back. Selection is therefore driven only by what the key table reports.
//

import Foundation

public enum ChargeBackend: String, Sendable, CaseIterable {
    /// `bfD0`/`bfE0`/`bfF0` — macOS 27-era firmware, which removed `CHTE`. The
    /// firmware enforces a hysteresis band rather than BatFi toggling an inhibit,
    /// so the limit holds while the Mac is asleep — and the battery percentage may
    /// fall below the limit, because the firmware can run the Mac off the battery.
    case firmwareRange
    /// `CHTE` (ui32) — Tahoe-era firmware, first shipped in macOS 15.7.
    case chte
    /// `CH0B` + `CH0C` (ui8 pair) — pre-Tahoe firmware.
    case legacyCH0BC
    /// Apple's Manual Charge Limit (macOS 26.4+). Fallback when no SMC mechanism
    /// works — notably macOS 27 firmware, which removed `CHTE`. Restricted to
    /// 80–100% in 5% steps, so it cannot honour BatFi's sub-80% limits.
    case systemChargeLimit
    /// No usable mechanism. Report honestly rather than appearing to work.
    case unsupported

    public var isUsable: Bool { self != .unsupported }

    /// Whether this backend can express a limit below 80%. Apple's own limit cannot,
    /// which is the single most important thing to tell the user when it is active.
    public var honoursLimitsBelow80: Bool {
        switch self {
        case .firmwareRange, .chte, .legacyCH0BC: return true
        case .systemChargeLimit, .unsupported: return false
        }
    }

    /// Whether BatFi ever writes a temporary Manual Charge Limit override while this
    /// backend is the one in force.
    ///
    /// Only the *inhibit* backends do, and only to push Apple's limit to 100% so their own
    /// inhibit is the single thing holding charge back. Under `.systemChargeLimit` BatFi
    /// *sets* the limit instead and must not also hold an override; under `.unsupported`
    /// it writes nothing at all. `.firmwareRange` is an SMC backend that is nonetheless
    /// **false**: it does not inhibit charging, it hands the firmware a band and the
    /// firmware enforces it, so there is no inhibit for Apple's limit to interfere with
    /// and nothing to push out of the way. Writing an override there would be a change to
    /// a setting the user can see, made for no mechanism at all — and, through
    /// `SystemLimitSnapshot.readIsTrustworthy`, it would poison BatFi's own read of that
    /// setting on exactly the firmware where the read is clean.
    ///
    /// **This is the decision, not a description of one.** `SMCService.reconcileMCLOwnership`
    /// branches on this property directly — writing an override where it is true, clearing
    /// one where it is false — and `SystemLimitSnapshot.readIsTrustworthy` reads the same
    /// property to decide whether a limit read could be BatFi's own write. Deliberately not
    /// a second copy of the reconcile's arms: the two facts disagreeing is how BatFi records
    /// its own number as the user's saved limit, and a copy is something an edit to one side
    /// can put out of step. To change which backends BatFi holds an override under, change
    /// this switch; both readers follow.
    ///
    /// It is a property of the *backend*, and a backend is a property of the firmware,
    /// which is stable across processes on a given Mac: installing macOS 27 on any volume
    /// reflashes firmware for the whole machine and downgrading macOS does not roll it
    /// back. So "false" here says something stronger than "this process wrote no
    /// override" — it says no BatFi process on this Mac ever had reason to.
    public var writesMCLOverride: Bool {
        switch self {
        case .chte, .legacyCH0BC: return true
        case .firmwareRange, .systemChargeLimit, .unsupported: return false
        }
    }
}

/// One key as the firmware describes it. `type` is the raw four-character type
/// code (`ui32`, `ui8 `, `hex_`, …) exactly as reported, including trailing spaces.
public struct SMCKeyCapability: Sendable, Equatable {
    public let code: String
    public let type: String
    public let size: UInt32
    public let isReadable: Bool
    public let isWritable: Bool

    public init(code: String, type: String, size: UInt32, isReadable: Bool, isWritable: Bool) {
        self.code = code
        self.type = type
        self.size = size
        self.isReadable = isReadable
        self.isWritable = isWritable
    }

    /// Matching on name alone is unsafe: `bfD0` exists on Tahoe firmware as a
    /// read-only `hex_`/2 key with unrelated meaning, and some firmware exposes
    /// zero-size placeholders that can be neither read nor written.
    public func matches(type expectedType: String, size expectedSize: UInt32, writable: Bool) -> Bool {
        self.type == expectedType && matchesAnyType(size: expectedSize, writable: writable)
    }

    /// The same rule minus the type check, for keys whose type has never been
    /// measured on real firmware and whose expected type would therefore be a guess.
    ///
    /// Everything else still applies. A zero-size key is a placeholder that can be
    /// neither read nor written, and a key that cannot be read cannot be verified
    /// after a write — both are real firmware behaviours, not type pedantry, so
    /// dropping the type expectation must not drop them too.
    public func matchesAnyType(size expectedSize: UInt32, writable: Bool) -> Bool {
        guard size > 0, size == expectedSize else { return false }
        guard isReadable else { return false }
        return !writable || isWritable
    }
}

public enum ChargeBackendResolver {
    public static func resolve(
        _ capabilities: [String: SMCKeyCapability],
        systemChargeLimitSupported: Bool = false
    ) -> ChargeBackend {
        // Checked first: an older macOS can be carrying newer firmware, so the
        // presence of this key set outranks anything older regardless of the OS.
        // Installing macOS 27 on any volume reflashes firmware for the whole Mac and
        // downgrading macOS does not roll it back, so `bf**` keys on a Mac running
        // macOS 26 is a normal machine, not a contradiction.
        if FirmwareRangeKeyShape.isSupported(by: capabilities) {
            return .firmwareRange
        }
        if capabilities["CHTE"]?.matches(type: "ui32", size: 4, writable: true) == true {
            return .chte
        }
        if capabilities["CH0B"]?.matches(type: "ui8 ", size: 1, writable: true) == true,
           capabilities["CH0C"]?.matches(type: "ui8 ", size: 1, writable: true) == true {
            return .legacyCH0BC
        }
        // Ranked last on purpose: only the SMC backends honour limits below 80%.
        if systemChargeLimitSupported { return .systemChargeLimit }
        return .unsupported
    }

    /// Keys the helper must probe to resolve a backend.
    ///
    /// The `bf**` codes are taken from `FirmwareRangeKeyShape` rather than written out
    /// again: a key the helper never probes is absent from the table `resolve` is handed,
    /// so it can never match, and the mechanism would silently never be selected.
    public static let probedKeys: [String] =
        ["CHTE", "CH0B", "CH0C", "CHIE", "CH0I", "CH0J"] + FirmwareRangeKeyShape.all.map(\.code)
}

/// The shapes the macOS 27-era firmware-managed charge range keys must have, stated
/// once.
///
/// Here for the same reason as `ForceDischargeKeyShape`: this is the value that decides
/// whether charge control works at all on macOS 27 firmware, and only `Shared` is
/// reachable from the test target. It is also the only statement of these shapes —
/// `ChargeBackendResolver.resolve` reads it to select the backend and
/// `ChargeBackendResolver.probedKeys` reads it to decide what gets probed, so the two
/// cannot drift apart.
///
/// Every one of the three is required, at its exact type and size, writable. Name-only
/// probing is unsafe here in a way it is not for `CHTE`: `bfD0` exists on Tahoe-era
/// firmware as a **read-only `hex_`/2 key with an unrelated meaning** — measured on a
/// Mac15,8 / M3 Max, firmware mBoot-18000.161.9 — and matching it would select a
/// mechanism that machine does not have. Requiring all three at these shapes is what
/// makes that impossible, so neither the shapes nor the all-three rule may be relaxed
/// to "be more tolerant of firmware variation". A firmware that moved the key set is a
/// firmware this mechanism does not run on, and falling through to `CHTE` or to Apple's
/// limit is the correct outcome.
public enum FirmwareRangeKeyShape {
    /// One key as the firmware must report it.
    public struct Key: Sendable, Equatable {
        public let code: String
        public let type: String
        public let size: UInt32

        /// Whether the probed table reports this key at exactly this shape, writable.
        /// Zero-size placeholders and unreadable keys are rejected by `matches`.
        public func isPresent(in capabilities: [String: SMCKeyCapability]) -> Bool {
            capabilities[code]?.matches(type: type, size: size, writable: true) == true
        }
    }

    /// `bfF0` — activation. Whether the firmware range is in force.
    public static let activation = Key(code: "bfF0", type: "ui8 ", size: 1)
    /// `bfD0` — the upper bound of the band, a little-endian `ui32` percentage.
    public static let upperBound = Key(code: "bfD0", type: "ui32", size: 4)
    /// `bfE0` — the lower bound of the band, same encoding.
    public static let lowerBound = Key(code: "bfE0", type: "ui32", size: 4)

    public static let all: [Key] = [activation, upperBound, lowerBound]

    /// Whether this firmware exposes the whole mechanism. A partial set is not a usable
    /// mechanism: without the bounds there is no band to write, and without the
    /// activation key nothing puts it in force.
    public static func isSupported(by capabilities: [String: SMCKeyCapability]) -> Bool {
        all.allSatisfy { $0.isPresent(in: capabilities) }
    }
}

/// The shapes a force-discharge key must have before BatFi will write it.
///
/// Force discharge is probed independently of the charge backend — `CHIE` outlives
/// `CHTE` on newer firmware — so these expectations do not belong to
/// `ChargeBackendResolver`, but they are the same kind of decision and they live
/// here for the same reason: this is the value that decides whether "Run on Battery"
/// works, and only `Shared` is reachable from the test target. Buried in `Server` the
/// accepted encodings could be "tidied up" to match a declaration and take the whole
/// feature down with a green suite.
///
/// The rule is strict where the shape was measured and permissive where it was not.
public enum ForceDischargeKeyShape {
    /// `CHIE` (`SMCKey.disableCharging3`), the current mechanism.
    ///
    /// Measured on a Mac15,8 / M3 Max / firmware mBoot-18000.161.9 as `hex_`/1 with
    /// attributes 0xd4 — **not** the `ui8 ` its `SMCKey` declaration implies. `hex_`
    /// is therefore load-bearing on every current Mac and must not be dropped.
    /// `ui8 ` is accepted alongside it: one machine is not enough evidence to reject
    /// a second plausible encoding, and at size 1 the write is byte-identical either
    /// way.
    public static let chieAcceptedTypes: [String] = ["hex_", "ui8 "]

    /// Size, in bytes, of every force-discharge key. Measured for `CHIE`, and the
    /// one thing the legacy pair's declaration and every other implementation agree
    /// on.
    public static let expectedSize: UInt32 = 1

    /// Whether a probed key is a force-discharge mechanism BatFi can use.
    ///
    /// Pass the capability the helper probed for the `SMCKey` it is about to touch;
    /// the key is identified by the code the firmware answered for. `writable: false`
    /// asks only whether the key can back a status read, `writable: true` whether it
    /// can be written — the two are deliberately different tests.
    ///
    /// `CH0I`/`CH0J` are checked on size and attributes only, with no type
    /// expectation. They are the Intel-era pair: absent on the machine available to
    /// measure, so their declared `ui8 ` is a guess — and `CHIE`, whose declaration
    /// says `ui8 ` while the firmware says `hex_`, is direct proof that those
    /// declarations do not track firmware. Guessing wrong there would silently
    /// disable force discharge across the entire Intel fleet.
    public static func isUsable(_ capability: SMCKeyCapability, writable: Bool) -> Bool {
        switch capability.code {
        case "CHIE":
            return chieAcceptedTypes.contains {
                capability.matches(type: $0, size: expectedSize, writable: writable)
            }
        case "CH0I", "CH0J":
            return capability.matchesAnyType(size: expectedSize, writable: writable)
        default:
            // Not a key this mechanism is ever driven by. Answering "usable" for an
            // unrelated code is how a same-shaped key of another meaning gets written.
            return false
        }
    }
}
