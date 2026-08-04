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

    public init(backend: String, firmwareVersion: String?, notChargingReasons: [String], mcl: MCLStatus?) {
        self.backend = backend
        self.firmwareVersion = firmwareVersion
        self.notChargingReasons = notChargingReasons
        self.mcl = mcl
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(backend, forKey: "backend")
        coder.encode(firmwareVersion, forKey: "firmwareVersion")
        coder.encode(notChargingReasons, forKey: "notChargingReasons")
        coder.encode(mcl, forKey: "mcl")
    }

    public required init?(coder: NSCoder) {
        backend = coder.decodeObject(of: NSString.self, forKey: "backend") as String? ?? "unknown"
        firmwareVersion = coder.decodeObject(of: NSString.self, forKey: "firmwareVersion") as String?
        let reasons = coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "notChargingReasons")
        notChargingReasons = (reasons as? [String]) ?? []
        mcl = coder.decodeObject(of: MCLStatus.self, forKey: "mcl")
        super.init()
    }

    public override var description: String {
        "ChargingDiagnostics(backend: \(backend), firmware: \(firmwareVersion ?? "unknown"), reasons: \(notChargingReasons))"
    }
}
