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

    /// This firmware exposes no charge-control mechanism BatFi can drive — no `bf**` band,
    /// no `CHTE`, no `CH0B`/`CH0C`, and no Manual Charge Limit.
    ///
    /// Distinct from `keyNotFound(code: "CHTE")`, which the `.unsupported` arms used to
    /// throw. On macOS 27 firmware `CHTE` is not the mechanism that is missing — it is
    /// simply one of several that were looked for — and that string lands in user-visible
    /// error text and in Sentry, where it would send the reader hunting for one key.
    case noChargeControlMechanism
}
