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
        guard size > 0, size == expectedSize, self.type == expectedType else { return false }
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
