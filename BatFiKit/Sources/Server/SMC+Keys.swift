//
//  SMC+Keys.swift
//  Helper
//
//  Created by Adam on 23/04/2023.
//

import Foundation

extension SMCKey {
    // MARK: - Legacy Keys (pre-macOS 26)

    static let disableCharging = Self(
        code: .init(fromStaticString: "CH0I"),
        info: DataTypes.UInt8
    )

    static let inhibitChargingC = Self(
        code: .init(fromStaticString: "CH0C"),
        info: DataTypes.UInt8
    )

    static let inhibitChargingB = Self(
        code: .init(fromStaticString: "CH0B"),
        info: DataTypes.UInt8
    )

    static let enableSystemChargeLimit = Self(
        code: .init(fromStaticString: "CHWA"),
        info: DataTypes.Flag
    )

    // MARK: - macOS 26+ Keys

    /// macOS 26+ Charge Limit Setting key
    /// Format: 2 bytes - first byte is percentage in hex, second byte is enable flag (01)
    /// Example: 0x50, 0x01 = 80% limit enabled
    static let chargeLimitSetting = Self(
        code: .init(fromStaticString: "CHLS"),
        info: DataType(type: FourCharCode(fromStaticString: "ui16"), size: 2)
    )

    /// Alternative charge inhibit key for macOS 26+
    static let chargeInhibit = Self(
        code: .init(fromStaticString: "CHIn"),
        info: DataTypes.UInt8
    )

    // MARK: - Common Keys

    static let lidClosed = Self(
        code: .init(fromStaticString: "MSLD"),
        info: DataTypes.UInt8
    )

    static let magSafeLED = Self(
        code: .init(fromStaticString: "ACLC"),
        info: DataTypes.UInt8
    )

    static let batteryPower = Self(
        code: .init(fromStaticString: "SBAP"),
        info: DataTypes.Float
    )

    static let externalPower = Self(
        code: .init(fromStaticString: "PDTR"),
        info: DataTypes.Float
    )

    static let systemPower = Self(
        code: .init(fromStaticString: "PSTR"),
        info: DataTypes.Float
    )
}

extension SMCKit {
    static func writeData(_ key: SMCKey, uint8: UInt8) throws {
        var inputStruct = SMCParamStruct()

        inputStruct.key = key.code
        inputStruct.bytes = (
            uint8, UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0)
        )
        inputStruct.keyInfo.dataSize = UInt32(key.info.size)
        inputStruct.data8 = SMCParamStruct.Selector.kSMCWriteKey.rawValue

        _ = try callDriver(&inputStruct)
    }

    /// Write 2-byte value for CHLS key (macOS 26+)
    /// Format: first byte is percentage, second byte is enable flag
    static func writeData(_ key: SMCKey, percentage: UInt8, enabled: Bool) throws {
        var inputStruct = SMCParamStruct()

        inputStruct.key = key.code
        inputStruct.bytes = (
            percentage, enabled ? UInt8(1) : UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0)
        )
        inputStruct.keyInfo.dataSize = UInt32(key.info.size)
        inputStruct.data8 = SMCParamStruct.Selector.kSMCWriteKey.rawValue

        _ = try callDriver(&inputStruct)
    }

    /// Check if a key exists and is accessible
    static func isKeyAccessible(_ key: SMCKey) -> Bool {
        do {
            _ = try keyInformation(key.code)
            return true
        } catch {
            return false
        }
    }
}
