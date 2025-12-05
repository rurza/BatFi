//
//  SMCError.swift
//  Helper
//
//  Created by Adam on 23/04/2023.
//

import Foundation

public enum SMCError: Error, Codable {
    /// AppleSMC driver not found
    case driverNotFound

    /// Failed to open a connection to the AppleSMC driver
    case failedToOpen

    /// This SMC key is not valid on this machine
    case keyNotFound(code: String)

    /// Requires root privileges
    case notPrivileged

    /// Fan speed must be > 0 && <= fanMaxSpeed
    case unsafeFanSpeed

    /// https://developer.apple.com/library/mac/qa/qa1075/_index.html
    ///
    /// - parameter kIOReturn: I/O Kit error code
    /// - parameter SMCResult: SMC specific return code
    case unknown(kIOReturn: kern_return_t, SMCResult: UInt8)

    case canNotCreateMagSafeLEDOption

    // MARK: - macOS 26+ Errors

    /// SMC key access blocked by entitlement requirement (macOS 26+)
    case entitlementRequired

    /// No accessible SMC keys found - using fallback mode
    case usingFallbackMode

    /// Feature not supported in current mode
    case featureNotSupported(feature: String)
}
