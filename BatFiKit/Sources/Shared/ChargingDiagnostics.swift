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
    /// Whether this firmware exposes a force-discharge mechanism BatFi can engage, or
    /// **nil where the helper could not ask** — the driver connection never opened, so
    /// every key looks absent.
    ///
    /// Optional for the same reason `currentBackend()` refuses to cache a resolution over
    /// a closed connection: a probe that could not run is not evidence that a key is
    /// missing, and a `false` here is acted on. Nil means "unknown", which every reader
    /// must render as "leave it alone" rather than as "gone".
    ///
    /// Deliberately independent of `backend`: `CHIE` outlives `CHTE` on newer firmware,
    /// so "Run on Battery" can still work on a machine whose charge limiting has fallen
    /// back to `.systemChargeLimit`. Answered by probing the keys, never inferred from
    /// the resolved backend.
    public let forceDischargeAvailable: Bool?
    /// Whether `ACLC`, the MagSafe LED key, is present — that is, whether the LED can be
    /// driven at all — or nil where the helper could not ask, exactly as above.
    /// Independent of `backend`, and it must stay that way: the key survives
    /// on macOS 27 firmware, and the discharge blink runs off BatFi's own `.forceDischarge`
    /// mode, which BatFi writes itself and therefore knows on every firmware.
    ///
    /// Whether the *green light* can be driven is a narrower question with a different
    /// answer on one backend — see `magSafeGreenLightAvailable`. Answering both with this
    /// one flag took a working feature down with a broken one.
    public let magSafeLEDAvailable: Bool?

    /// Whether the macOS 27 firmware charge range is armed right now, or nil where the
    /// question does not apply — every other backend — or where `bfF0` could not be read.
    ///
    /// Reported, never branched on. It was briefly the answer `isChargingEnabled` returned
    /// under `.firmwareRange`, which was a category error: "a limit is in force" is not
    /// "charging is being held back this second", and since the band is now armed
    /// permanently the two do not even correlate. As a diagnostic it is the only window
    /// onto whether the band BatFi asked for actually took, which is worth having in a bug
    /// report from firmware nobody can test against.
    public let firmwareRangeIsArmed: Bool?
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
        forceDischargeAvailable: Bool?,
        magSafeLEDAvailable: Bool?,
        firmwareRangeIsArmed: Bool? = nil,
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
        self.firmwareRangeIsArmed = firmwareRangeIsArmed
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

    /// Whether the "green light on the MagSafe when charging is paused" setting can work on
    /// this Mac: the LED can be driven **and** BatFi knows when charge is being held back.
    /// Nil when the helper could not ask — see `magSafeLEDAvailable`.
    ///
    /// The narrower of the two MagSafe questions, and the only one any backend takes away.
    /// The discharge blink deliberately does not consult it: that runs off BatFi's own
    /// `.forceDischarge` mode, which BatFi writes through `CHIE` and knows exactly, on
    /// firmware where charge limiting is long gone. A user whose "Run on Battery" still
    /// works — and whose LED still blinks for it — must not be told either is gone.
    ///
    /// Fails *open* on a backend string this build does not recognize, unlike
    /// `systemChargeLimitIsHoldingCharge` above, and the difference is which way the damage
    /// runs. There, guessing wrong invents a claim about the hardware; here, guessing wrong
    /// switches off a feature that works. An older app talking to a newer helper should
    /// keep its LED.
    /// A backend that cannot mirror the charging state answers `false` even where the LED
    /// probe could not run: that answer is a property of the firmware, not of the probe,
    /// and it is the one cause of unavailability that is durable enough to act on.
    public var magSafeGreenLightAvailable: Bool? {
        if let resolved = ChargeBackend(rawValue: backend), !resolved.canMirrorChargingStateOnMagSafeLED {
            return false
        }
        guard let magSafeLEDAvailable else { return nil }
        guard magSafeLEDAvailable else { return false }
        // An unrecognized backend string leaves this open, unlike
        // `systemChargeLimitIsHoldingCharge` above, and the difference is which way the
        // damage runs. There, guessing wrong invents a claim about the hardware; here,
        // guessing wrong switches off a feature that works.
        return true
    }

    /// Whether the green light belongs to macOS rather than to BatFi.
    ///
    /// True under `.systemChargeLimit`. There the hold is the system's, and macOS drives
    /// `ACLC` itself while the limit is in force — observed going green the moment a sub-80
    /// limit was applied, with nothing in BatFi writing the key. The setting cannot turn
    /// that off, so rendering it as a live choice offers the user a switch that does
    /// nothing.
    ///
    /// Distinct from `magSafeGreenLightAvailable`, which stays **true** here: the light does
    /// work under this backend, which is exactly the point. This is not a capability BatFi
    /// lost, it is one the system is already exercising, so the setting is shown on rather
    /// than off — and, unlike the durable unavailability in `MagSafeGreenLightSetting`, the
    /// stored preference is deliberately left untouched so it survives a backend change.
    ///
    /// Nil when the backend string is unrecognized: an older app talking to a newer helper
    /// should render the ordinary control rather than assert something it cannot support.
    public var magSafeGreenLightIsSystemDriven: Bool? {
        guard let resolved = ChargeBackend(rawValue: backend) else { return nil }
        return resolved == .systemChargeLimit
    }

    public func encode(with coder: NSCoder) {
        coder.encode(backend, forKey: "backend")
        coder.encode(firmwareVersion, forKey: "firmwareVersion")
        coder.encode(notChargingReasons, forKey: "notChargingReasons")
        coder.encode(mcl, forKey: "mcl")
        // Flag-plus-value, like everything else optional here: `decodeBool` cannot tell an
        // absent key from a stored `false`, and here those are different answers — "the
        // helper could not ask" versus "the key is not there". A newer app talking to an
        // older daemon, which wrote a bare `Bool` under the same key, decodes the absent
        // flag as nil and treats it as unknown, which is the fail-open direction.
        if let forceDischargeAvailable {
            coder.encode(true, forKey: "hasForceDischargeAvailable")
            coder.encode(forceDischargeAvailable, forKey: "forceDischargeAvailable")
        } else {
            coder.encode(false, forKey: "hasForceDischargeAvailable")
        }
        if let magSafeLEDAvailable {
            coder.encode(true, forKey: "hasMagSafeLEDAvailable")
            coder.encode(magSafeLEDAvailable, forKey: "magSafeLEDAvailable")
        } else {
            coder.encode(false, forKey: "hasMagSafeLEDAvailable")
        }
        // Same flag-plus-value shape the optional Ints below use, and needed for the same
        // reason: `decodeBool` cannot tell an absent key from a stored `false`, and here
        // those are different answers — "this Mac has no band" versus "the band is off".
        if let firmwareRangeIsArmed {
            coder.encode(true, forKey: "hasFirmwareRangeIsArmed")
            coder.encode(firmwareRangeIsArmed, forKey: "firmwareRangeIsArmed")
        } else {
            coder.encode(false, forKey: "hasFirmwareRangeIsArmed")
        }
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
        if coder.decodeBool(forKey: "hasForceDischargeAvailable") {
            forceDischargeAvailable = coder.decodeBool(forKey: "forceDischargeAvailable")
        } else {
            forceDischargeAvailable = nil
        }
        if coder.decodeBool(forKey: "hasMagSafeLEDAvailable") {
            magSafeLEDAvailable = coder.decodeBool(forKey: "magSafeLEDAvailable")
        } else {
            magSafeLEDAvailable = nil
        }
        if coder.decodeBool(forKey: "hasFirmwareRangeIsArmed") {
            firmwareRangeIsArmed = coder.decodeBool(forKey: "firmwareRangeIsArmed")
        } else {
            firmwareRangeIsArmed = nil
        }
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
        // "—" for nil rather than "false": on firmware with no band the question does not
        // apply, and a bug report that says the band is off would send the reader hunting
        // for a write that was never owed.
        let band = firmwareRangeIsArmed.map { $0 ? "armed" : "released" } ?? "—"
        // "—" rather than "false" for the same reason: a probe that could not run is not
        // the same report as a key that is not there, and a bug report must not conflate
        // them.
        func flag(_ value: Bool?) -> String { value.map(String.init(describing:)) ?? "—" }
        return """
        ChargingDiagnostics(backend: \(backend), firmware: \(firmwareVersion ?? "unknown"), \
        reasons: \(notChargingReasons), appliedLimit: \(applied), firmwareRange: \(band), \
        forceDischarge: \(flag(forceDischargeAvailable)), magSafeLED: \(flag(magSafeLEDAvailable)))
        """
    }
}
