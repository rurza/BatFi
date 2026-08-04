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
    /// Whether BatFi can drive the MagSafe LED on this Mac: `ACLC` is present **and** the
    /// resolved backend leaves BatFi knowing what the LED would show.
    ///
    /// Not a pure key probe, and the one exception is deliberate. The key survives on
    /// macOS 27 firmware and is still unusable there, because under `.firmwareRange` the
    /// firmware owns the charging decision and BatFi cannot tell when charge is being held
    /// back — so the light would be on permanently, including while the Mac charges. The
    /// reasoning is stated once, in `ChargeBackend.canMirrorChargingStateOnMagSafeLED`.
    public let magSafeLEDAvailable: Bool
    /// The limit BatFi last applied through Apple's Manual Charge Limit. Nil under the
    /// SMC backends, which apply the user's value exactly and so have nothing to report.
    public let appliedChargeLimit: Int?
    /// True when `appliedChargeLimit` is higher than the user asked for, because the
    /// mechanism in use cannot express the requested value. The single thing the user
    /// most needs told: their limit is not the one in effect.
    public let chargeLimitWasRaised: Bool

    /// What was actually asked for, beside what was applied. Nil under the SMC backends
    /// for the same reason `appliedChargeLimit` is: they apply the request exactly.
    ///
    /// Carried because `chargeLimitWasRaised` alone cannot tell the two kinds of raise
    /// apart, and they need different words. A request *below* the mechanism's floor was
    /// clamped up to it — "limits below 80% can't be applied here". A request above the
    /// floor was merely rounded up to the next accepted step — 87 becomes 90 — where
    /// saying "below 80%" and calling 90 the lowest accepted value are both false. That is
    /// not a corner: `ChargingManager.inhibitCharging()` sets a temporary limit at the
    /// current battery level, an arbitrary integer, so any stop-charging click at a
    /// non-multiple of 5 lands in it.
    public let requestedChargeLimit: Int?

    public init(
        backend: String,
        firmwareVersion: String?,
        notChargingReasons: [String],
        mcl: MCLStatus?,
        forceDischargeAvailable: Bool,
        magSafeLEDAvailable: Bool,
        appliedChargeLimit: Int? = nil,
        chargeLimitWasRaised: Bool = false,
        requestedChargeLimit: Int? = nil
    ) {
        self.backend = backend
        self.firmwareVersion = firmwareVersion
        self.notChargingReasons = notChargingReasons
        self.mcl = mcl
        self.forceDischargeAvailable = forceDischargeAvailable
        self.magSafeLEDAvailable = magSafeLEDAvailable
        self.appliedChargeLimit = appliedChargeLimit
        self.chargeLimitWasRaised = chargeLimitWasRaised
        self.requestedChargeLimit = requestedChargeLimit
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
        if let requestedChargeLimit {
            coder.encode(true, forKey: "hasRequestedChargeLimit")
            coder.encode(requestedChargeLimit, forKey: "requestedChargeLimit")
        } else {
            coder.encode(false, forKey: "hasRequestedChargeLimit")
        }
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
        if coder.decodeBool(forKey: "hasRequestedChargeLimit") {
            requestedChargeLimit = coder.decodeInteger(forKey: "requestedChargeLimit")
        } else {
            requestedChargeLimit = nil
        }
        super.init()
    }

    public override var description: String {
        let requested = requestedChargeLimit.map { "\($0)% → " } ?? ""
        let applied = appliedChargeLimit.map { "\(requested)\($0)%\(chargeLimitWasRaised ? " (raised)" : "")" } ?? "—"
        return """
        ChargingDiagnostics(backend: \(backend), firmware: \(firmwareVersion ?? "unknown"), \
        reasons: \(notChargingReasons), appliedLimit: \(applied), \
        forceDischarge: \(forceDischargeAvailable), magSafeLED: \(magSafeLEDAvailable))
        """
    }
}
