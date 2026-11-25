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

    /// Whether this machine has a Manual Charge Limit at all, as PowerUI itself reports it
    /// (`isMCLSupported`).
    ///
    /// Deliberately not "the helper loaded the framework", which is what this used to
    /// carry: PowerUI loads on every Mac, so that answer was true on machines with no MCL,
    /// and the readers of this field — the conflict warning, `ChargeControlFacts` — all
    /// mean the narrower question. Asking the framework also keeps the answer off the
    /// macOS version, which is not what charge control tracks.
    public let supported: Bool

    /// True if BatFi currently holds an active `temporarilyOverrideMCLTargetSoC` override.
    public let batFiHasActiveOverride: Bool

    /// Last override value BatFi sent (1-100). Nil when no override is held.
    public let lastOverrideValue: Int?

    /// The charge limit the system reports right now, as a percentage, or nil when it
    /// could not be read.
    ///
    /// Note what this is *not*: it is not guaranteed to be the user's own saved value.
    /// While BatFi holds a temporary override the limit reads back as BatFi's number, and
    /// an override outlives the process that set it — which is exactly why
    /// `SystemLimitSnapshot.readIsTrustworthy` guards the capture path. Callers that need
    /// the user's value must go through that; callers that need "what is in force" can
    /// read this directly.
    public let systemLimit: Int?

    /// Whether the helper refused to record the user's own System Settings limit, and is
    /// therefore applying no charge limit at all.
    ///
    /// Carried across the boundary because the refusal is otherwise invisible: it reaches
    /// the helper log and one Sentry breadcrumb, while the user simply sees a limit that
    /// never takes effect and nothing saying why.
    public let snapshotRefused: Bool

    public init(
        supported: Bool,
        batFiHasActiveOverride: Bool,
        lastOverrideValue: Int?,
        systemLimit: Int? = nil,
        snapshotRefused: Bool = false
    ) {
        self.supported = supported
        self.batFiHasActiveOverride = batFiHasActiveOverride
        self.lastOverrideValue = lastOverrideValue
        self.systemLimit = systemLimit
        self.snapshotRefused = snapshotRefused
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
        // Same flag-plus-value shape, for the same reason: decodeInteger cannot tell an
        // absent key from a stored zero, and zero is a value the limit could hold.
        if let systemLimit {
            coder.encode(true, forKey: "hasSystemLimit")
            coder.encode(systemLimit, forKey: "systemLimit")
        } else {
            coder.encode(false, forKey: "hasSystemLimit")
        }
        coder.encode(snapshotRefused, forKey: "snapshotRefused")
    }

    public required init?(coder: NSCoder) {
        supported = coder.decodeBool(forKey: "supported")
        batFiHasActiveOverride = coder.decodeBool(forKey: "batFiHasActiveOverride")
        if coder.decodeBool(forKey: "hasLastOverrideValue") {
            lastOverrideValue = coder.decodeInteger(forKey: "lastOverrideValue")
        } else {
            lastOverrideValue = nil
        }
        if coder.decodeBool(forKey: "hasSystemLimit") {
            systemLimit = coder.decodeInteger(forKey: "systemLimit")
        } else {
            systemLimit = nil
        }
        snapshotRefused = coder.decodeBool(forKey: "snapshotRefused")
        super.init()
    }

    public override var description: String {
        let limit = lastOverrideValue.map(String.init) ?? "—"
        let system = systemLimit.map { "\($0)%" } ?? "—"
        return """
        MCLStatus(supported: \(supported), override: \(batFiHasActiveOverride), \
        lastValue: \(limit), systemLimit: \(system), snapshotRefused: \(snapshotRefused))
        """
    }
}
