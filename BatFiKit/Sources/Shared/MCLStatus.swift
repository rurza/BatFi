//
//  MCLStatus.swift
//
//
//  Created by Adam Różyński on 13/05/2026.
//

import Foundation

/// Snapshot of the macOS 26.4+ Manual Charge Limit (MCL) state as managed by BatFi.
public final class MCLStatus: NSObject, NSSecureCoding, @unchecked Sendable {
    public static let supportsSecureCoding: Bool = true

    /// True if the helper successfully loaded the PowerUI private framework.
    public let supported: Bool

    /// True if BatFi currently holds an active `temporarilyOverrideMCLTargetSoC` override.
    public let batFiHasActiveOverride: Bool

    /// Last override value BatFi sent (1-100). Nil when no override is held.
    public let lastOverrideValue: Int?

    public init(supported: Bool, batFiHasActiveOverride: Bool, lastOverrideValue: Int?) {
        self.supported = supported
        self.batFiHasActiveOverride = batFiHasActiveOverride
        self.lastOverrideValue = lastOverrideValue
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(supported, forKey: "supported")
        coder.encode(batFiHasActiveOverride, forKey: "batFiHasActiveOverride")
        if let lastOverrideValue {
            coder.encode(true, forKey: "hasLastOverrideValue")
            coder.encode(lastOverrideValue, forKey: "lastOverrideValue")
        } else {
            coder.encode(false, forKey: "hasLastOverrideValue")
        }
    }

    public required init?(coder: NSCoder) {
        supported = coder.decodeBool(forKey: "supported")
        batFiHasActiveOverride = coder.decodeBool(forKey: "batFiHasActiveOverride")
        if coder.decodeBool(forKey: "hasLastOverrideValue") {
            lastOverrideValue = coder.decodeInteger(forKey: "lastOverrideValue")
        } else {
            lastOverrideValue = nil
        }
        super.init()
    }

    public override var description: String {
        let limit = lastOverrideValue.map(String.init) ?? "—"
        return "MCLStatus(supported: \(supported), override: \(batFiHasActiveOverride), lastValue: \(limit))"
    }
}
