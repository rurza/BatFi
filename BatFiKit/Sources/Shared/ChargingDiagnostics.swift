//
//  ChargingDiagnostics.swift
//
//
//  What the helper knows about why charging is or is not happening.
//

import Foundation

/// Bits of the SMC `CHNC` key — the firmware's own reason for not charging.
/// Positions from the Asahi Linux macsmc driver; the value is little-endian.
public enum NotChargingReason: String, Sendable, CaseIterable {
    case batteryFull
    case noCharger
    case inhibitedCH0C
    case inhibitedCH0BOrCH0K
    case batteryManagementBusy
    case systemChargeLimit
    case adapterDisabledCH0J
    case adapterDisabledCH0I

    var bit: UInt64 {
        switch self {
        case .batteryFull:            return 0
        case .noCharger:              return 7
        case .inhibitedCH0C:          return 14
        case .inhibitedCH0BOrCH0K:    return 15
        case .batteryManagementBusy:  return 23
        case .systemChargeLimit:      return 24
        case .adapterDisabledCH0J:    return 53
        case .adapterDisabledCH0I:    return 54
        }
    }

    public static func decode(_ bytes: [UInt8]) -> [NotChargingReason] {
        guard bytes.count >= 8 else { return [] }
        var value: UInt64 = 0
        for index in 0 ..< 8 {
            value |= UInt64(bytes[index]) << (8 * UInt64(index))
        }
        return allCases.filter { value & (1 << $0.bit) != 0 }
    }
}

/// Snapshot the app can render and a user can paste into a bug report.
public final class ChargingDiagnostics: NSObject, NSSecureCoding, @unchecked Sendable {
    public static let supportsSecureCoding: Bool = true

    /// Resolved `ChargeBackend.rawValue`.
    public let backend: String
    /// Opaque firmware token, e.g. "mBoot-18000.161.9".
    public let firmwareVersion: String?
    /// Decoded `CHNC` reasons, as `NotChargingReason.rawValue`.
    public let notChargingReasons: [String]
    public let mcl: MCLStatus?
    /// Whether this firmware exposes a force-discharge mechanism BatFi can engage.
    ///
    /// Deliberately independent of `backend`: `CHIE` outlives `CHTE` on newer firmware,
    /// so "Run on Battery" can still work on a machine whose charge limiting has fallen
    /// back to `.systemChargeLimit`. Answered by probing the keys, never inferred from
    /// the resolved backend.
    public let forceDischargeAvailable: Bool
    /// Whether `ACLC`, the MagSafe LED key, is present. Independent of `backend` for the
    /// same reason: the key survives on macOS 27 firmware, and under
    /// `.systemChargeLimit` BatFi still knows when charge is being held back, so the LED
    /// can still mirror it.
    public let magSafeLEDAvailable: Bool
    /// The limit BatFi last applied through Apple's Manual Charge Limit. Nil under the
    /// SMC backends, which apply the user's value exactly and so have nothing to report.
    public let appliedChargeLimit: Int?
    /// True when `appliedChargeLimit` is higher than the user asked for, because the
    /// mechanism in use cannot express the requested value. The single thing the user
    /// most needs told: their limit is not the one in effect.
    public let chargeLimitWasRaised: Bool

    public init(
        backend: String,
        firmwareVersion: String?,
        notChargingReasons: [String],
        mcl: MCLStatus?,
        forceDischargeAvailable: Bool,
        magSafeLEDAvailable: Bool,
        appliedChargeLimit: Int? = nil,
        chargeLimitWasRaised: Bool = false
    ) {
        self.backend = backend
        self.firmwareVersion = firmwareVersion
        self.notChargingReasons = notChargingReasons
        self.mcl = mcl
        self.forceDischargeAvailable = forceDischargeAvailable
        self.magSafeLEDAvailable = magSafeLEDAvailable
        self.appliedChargeLimit = appliedChargeLimit
        self.chargeLimitWasRaised = chargeLimitWasRaised
        super.init()
    }

    /// Whether Apple's own Manual Charge Limit is what is holding charge back right now.
    ///
    /// Both halves are load-bearing. The backend check keeps this false on every SMC
    /// machine, where BatFi's own inhibit is the signal and nothing here may change that.
    /// The `CHNC` bit is the firmware's own attribution, and under `.systemChargeLimit`
    /// it is the only honest answer available: BatFi's charging *mode* can read
    /// `.inhibit` while the hardware is still charging, because a limit below 80% gets
    /// raised to one the system limit can express.
    public var systemChargeLimitIsHoldingCharge: Bool {
        ChargeBackend(rawValue: backend) == .systemChargeLimit
            && notChargingReasons.contains(NotChargingReason.systemChargeLimit.rawValue)
    }

    public func encode(with coder: NSCoder) {
        coder.encode(backend, forKey: "backend")
        coder.encode(firmwareVersion, forKey: "firmwareVersion")
        coder.encode(notChargingReasons, forKey: "notChargingReasons")
        coder.encode(mcl, forKey: "mcl")
        coder.encode(forceDischargeAvailable, forKey: "forceDischargeAvailable")
        coder.encode(magSafeLEDAvailable, forKey: "magSafeLEDAvailable")
        // Same flag-plus-value shape MCLStatus uses for its optional Int: decodeInteger
        // cannot tell an absent key from a stored zero.
        if let appliedChargeLimit {
            coder.encode(true, forKey: "hasAppliedChargeLimit")
            coder.encode(appliedChargeLimit, forKey: "appliedChargeLimit")
        } else {
            coder.encode(false, forKey: "hasAppliedChargeLimit")
        }
        coder.encode(chargeLimitWasRaised, forKey: "chargeLimitWasRaised")
    }

    public required init?(coder: NSCoder) {
        backend = coder.decodeObject(of: NSString.self, forKey: "backend") as String? ?? "unknown"
        firmwareVersion = coder.decodeObject(of: NSString.self, forKey: "firmwareVersion") as String?
        let reasons = coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "notChargingReasons")
        notChargingReasons = (reasons as? [String]) ?? []
        mcl = coder.decodeObject(of: MCLStatus.self, forKey: "mcl")
        forceDischargeAvailable = coder.decodeBool(forKey: "forceDischargeAvailable")
        magSafeLEDAvailable = coder.decodeBool(forKey: "magSafeLEDAvailable")
        if coder.decodeBool(forKey: "hasAppliedChargeLimit") {
            appliedChargeLimit = coder.decodeInteger(forKey: "appliedChargeLimit")
        } else {
            appliedChargeLimit = nil
        }
        chargeLimitWasRaised = coder.decodeBool(forKey: "chargeLimitWasRaised")
        super.init()
    }

    public override var description: String {
        let applied = appliedChargeLimit.map { "\($0)%\(chargeLimitWasRaised ? " (raised)" : "")" } ?? "—"
        return """
        ChargingDiagnostics(backend: \(backend), firmware: \(firmwareVersion ?? "unknown"), \
        reasons: \(notChargingReasons), appliedLimit: \(applied), \
        forceDischarge: \(forceDischargeAvailable), magSafeLED: \(magSafeLEDAvailable))
        """
    }
}
