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
        case .chte, .legacyCH0BC: return true
        case .systemChargeLimit, .unsupported: return false
        }
    }

    /// Whether BatFi ever writes a temporary Manual Charge Limit override while this
    /// backend is the one in force.
    ///
    /// Only the SMC backends do, and only to push Apple's limit to 100% so their own
    /// inhibit is the single thing holding charge back. Under `.systemChargeLimit` BatFi
    /// *sets* the limit instead and must not also hold an override; under `.unsupported`
    /// it writes nothing at all.
    ///
    /// **This mirrors the arms of `SMCService.reconcileMCLOwnership`, which is the one
    /// switch that decides MCL ownership. If an arm there ever starts or stops writing an
    /// override, this must move with it** — the snapshot rule below reads this to decide
    /// whether a limit read could be BatFi's own write, and a stale answer here is how
    /// BatFi would record its own number as the user's.
    ///
    /// It is a property of the *backend*, and a backend is a property of the firmware,
    /// which is stable across processes on a given Mac: installing macOS 27 on any volume
    /// reflashes firmware for the whole machine and downgrading macOS does not roll it
    /// back. So "false" here says something stronger than "this process wrote no
    /// override" — it says no BatFi process on this Mac ever had reason to.
    public var writesMCLOverride: Bool {
        switch self {
        case .chte, .legacyCH0BC: return true
        case .systemChargeLimit, .unsupported: return false
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
    public static let probedKeys: [String] = ["CHTE", "CH0B", "CH0C", "CHIE", "CH0I", "CH0J"]
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
