//
//  PowerUICharging.swift
//
//
//  Created by Adam Różyński on 12/05/2026.
//

import Foundation
import os
import Shared

actor PowerUICharging {
    static let shared = PowerUICharging()

    private let logger = Logger(subsystem: Constant.helperBundleIdentifier, category: "PowerUI Charging")
    private let client: AnyObject?
    private let clientClass: AnyClass?

    private var renewalTask: Task<Void, Never>?
    private var lastOverrideValue: UInt8 = 0

    /// The user's System Settings value, captured before BatFi first changed it.
    private var userSystemLimitSnapshot: Int?

    private static let renewalInterval: Duration = .seconds(60)

    private init() {
        let frameworkPath = "/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI"
        guard dlopen(frameworkPath, RTLD_NOW | RTLD_GLOBAL) != nil else {
            self.client = nil
            self.clientClass = nil
            return
        }

        guard let cls = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type,
              let allocated = cls.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let initialized = allocated.perform(
                NSSelectorFromString("initWithClientName:"),
                with: "BatFi" as NSString
              )?.takeUnretainedValue() else {
            self.client = nil
            self.clientClass = nil
            return
        }

        self.client = initialized
        self.clientClass = cls
    }

    var isAvailable: Bool { client != nil && clientClass != nil }

    /// Whether this machine's PowerUI reports Manual Charge Limit support. Asking the
    /// framework is strictly better than inferring it from the macOS version.
    var isMCLSupported: Bool {
        guard let client, let clientClass else { return false }
        let selector = NSSelectorFromString("isMCLSupported")
        guard let method = class_getInstanceMethod(clientClass, selector) else { return false }
        typealias Query = @convention(c) (AnyObject, Selector) -> ObjCBool
        let query = unsafeBitCast(method_getImplementation(method), to: Query.self)
        return query(client, selector).boolValue
    }

    /// Values Apple accepts, measured as (80, 85, 90, 95, 100). Queried rather than
    /// hardcoded so a future macOS that widens the range works without a code change.
    func availableLimits() -> [Int] {
        guard let client, let clientClass else { return [] }
        let selector = NSSelectorFromString("availableChargeLimitsWithError:")
        guard let method = class_getInstanceMethod(clientClass, selector) else { return [] }
        typealias Query = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> NSArray?
        let query = unsafeBitCast(method_getImplementation(method), to: Query.self)
        var error: NSError?
        guard let values = query(client, selector, &error) as? [NSNumber], error == nil else { return [] }
        return values.map(\.intValue).sorted()
    }

    /// The user's own System Settings value. Note the selector returns an unsigned
    /// char, not an object.
    func currentSystemLimit() -> Int? {
        guard let client, let clientClass else { return nil }
        let selector = NSSelectorFromString("getMCLLimitWithError:")
        guard let method = class_getInstanceMethod(clientClass, selector) else { return nil }
        typealias Query = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> UInt8
        let query = unsafeBitCast(method_getImplementation(method), to: Query.self)
        var error: NSError?
        let value = query(client, selector, &error)
        guard error == nil else { return nil }
        return Int(value)
    }

    var hasActiveOverride: Bool { lastOverrideValue != 0 }

    /// Temporarily overrides the system Manual Charge Limit (System Settings → Battery → Charging).
    /// Apple stores the user's MCL in `MCLSavedTargetSoC` and restores it once the override expires.
    /// Use 100 to fully release the system limit so BatFi's SMC inhibit can act unimpeded.
    func overrideMCLTarget(_ targetSoC: UInt8) throws {
        try invokeOverride(targetSoC)
        lastOverrideValue = targetSoC
        startRenewalTask()
    }

    /// Cancels the renewal task and attempts to clear the active override so the system snaps
    /// back to the user's saved MCL value. Client-side selector may not exist on every build —
    /// if it doesn't, the override still self-expires via `MCLOverridenUntilDate`.
    func clearMCLOverride() {
        cancelRenewalTask()
        lastOverrideValue = 0

        guard let client, let clientClass else { return }

        let selector = NSSelectorFromString("clearMCLOverride")
        guard class_getInstanceMethod(clientClass, selector) != nil else {
            logger.notice("clearMCLOverride selector not exposed on client; relying on natural expiry")
            return
        }

        typealias Clearer = @convention(c) (AnyObject, Selector) -> Void
        let method = class_getInstanceMethod(clientClass, selector)!
        let clearer = unsafeBitCast(method_getImplementation(method), to: Clearer.self)
        clearer(client, selector)
        logger.notice("PowerUI MCL override cleared")
    }

    func mclStatus() -> MCLStatus {
        MCLStatus(
            supported: isAvailable,
            batFiHasActiveOverride: hasActiveOverride,
            lastOverrideValue: hasActiveOverride ? Int(lastOverrideValue) : nil
        )
    }

    /// Drives Apple's Manual Charge Limit. Only for the `.systemChargeLimit` backend —
    /// every other backend releases the system limit instead of setting it, and the two
    /// must never run together or the renewal task will fight this setter.
    func adoptSystemLimit(_ percentage: Int) throws {
        guard isAvailable else { throw PowerUIChargingError.frameworkUnavailable }

        let available = availableLimits()
        guard available.contains(percentage) else {
            throw PowerUIChargingError.limitOutOfRange(requested: percentage, available: available)
        }

        if userSystemLimitSnapshot == nil {
            userSystemLimitSnapshot = currentSystemLimit()
            logger.notice("Captured user's system charge limit: \(self.userSystemLimitSnapshot?.description ?? "unknown", privacy: .public)")
        }

        try adoptSystemLimitWithoutSnapshotting(percentage)
    }

    /// Puts the user's own value back. Safe to call when nothing was ever adopted.
    func releaseSystemLimit() {
        guard let snapshot = userSystemLimitSnapshot else { return }
        userSystemLimitSnapshot = nil
        do {
            try adoptSystemLimitWithoutSnapshotting(snapshot)
            logger.notice("Restored user's system charge limit to \(snapshot, privacy: .public)%")
        } catch {
            logger.error("Could not restore the user's system charge limit: \(error, privacy: .public)")
        }
    }

    // MARK: - Private

    /// Raw `setMCLLimit:error:` call with no snapshotting. `adoptSystemLimit` and
    /// `releaseSystemLimit` both funnel through here so restoring the user's value can
    /// never re-capture it as a new snapshot.
    private func adoptSystemLimitWithoutSnapshotting(_ percentage: Int) throws {
        guard let client, let clientClass else {
            throw PowerUIChargingError.frameworkUnavailable
        }

        let selector = NSSelectorFromString("setMCLLimit:error:")
        guard let method = class_getInstanceMethod(clientClass, selector) else {
            throw PowerUIChargingError.selectorUnavailable("setMCLLimit:error:")
        }

        typealias Setter = @convention(c) (AnyObject, Selector, UInt8, AutoreleasingUnsafeMutablePointer<NSError?>?) -> ObjCBool
        let setter = unsafeBitCast(method_getImplementation(method), to: Setter.self)

        var error: NSError?
        let success = setter(client, selector, UInt8(percentage), &error).boolValue

        if let error {
            logger.error("setMCLLimit returned error: \(error, privacy: .public)")
            throw PowerUIChargingError.apiCallFailed(error)
        }

        if !success {
            logger.error("setMCLLimit returned false without error")
            throw PowerUIChargingError.apiCallReturnedFalse
        }

        logger.notice("System charge limit set to \(percentage, privacy: .public)%")
    }

    private func invokeOverride(_ targetSoC: UInt8) throws {
        guard let client, let clientClass else {
            throw PowerUIChargingError.frameworkUnavailable
        }

        let selector = NSSelectorFromString("temporarilyOverrideMCLTargetSoC:error:")
        guard let method = class_getInstanceMethod(clientClass, selector) else {
            throw PowerUIChargingError.selectorUnavailable("temporarilyOverrideMCLTargetSoC:error:")
        }

        typealias Setter = @convention(c) (AnyObject, Selector, UInt8, AutoreleasingUnsafeMutablePointer<NSError?>?) -> ObjCBool
        let setter = unsafeBitCast(method_getImplementation(method), to: Setter.self)

        var error: NSError?
        let success = setter(client, selector, targetSoC, &error).boolValue

        if let error {
            logger.error("temporarilyOverrideMCLTargetSoC returned error: \(error, privacy: .public)")
            throw PowerUIChargingError.apiCallFailed(error)
        }

        if !success {
            logger.error("temporarilyOverrideMCLTargetSoC returned false without error")
            throw PowerUIChargingError.apiCallReturnedFalse
        }

        logger.notice("PowerUI MCL target overridden to \(targetSoC, privacy: .public)%")
    }

    private func startRenewalTask() {
        renewalTask?.cancel()
        renewalTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.renewalInterval)
                guard !Task.isCancelled, let self else { return }
                await self.renewOverrideIfNeeded()
            }
        }
    }

    private func cancelRenewalTask() {
        renewalTask?.cancel()
        renewalTask = nil
    }

    private func renewOverrideIfNeeded() {
        let value = lastOverrideValue
        guard value != 0 else { return }
        do {
            try invokeOverride(value)
        } catch {
            logger.warning("MCL override renewal failed: \(error, privacy: .public)")
        }
    }
}

enum PowerUIChargingError: Error, CustomStringConvertible {
    case frameworkUnavailable
    case selectorUnavailable(String)
    case apiCallFailed(Error)
    case apiCallReturnedFalse
    case limitOutOfRange(requested: Int, available: [Int])

    var description: String {
        switch self {
        case .frameworkUnavailable: return "PowerUI framework unavailable"
        case .selectorUnavailable(let name): return "PowerUI selector unavailable: \(name)"
        case .apiCallFailed(let err): return "PowerUI API failed: \(err)"
        case .apiCallReturnedFalse: return "PowerUI API returned false"
        case .limitOutOfRange(let requested, let available):
            return "Requested system charge limit \(requested)% is not one of the available limits \(available)"
        }
    }
}
