//
//  SMC+Keys.swift
//  Helper
//
//  Created by Adam on 23/04/2023.
//

import Foundation

extension SMCKey {
    // Old firmware
    static let disableCharging1 = Self(
        code: .init(fromStaticString: "CH0I"),
        info: DataTypes.UInt8
    )

    // Old firmware
    static let disableCharging2 = Self(
        code: .init(fromStaticString: "CH0J"),
        info: DataTypes.UInt8
    )

    // New firmware
    static let disableCharging3 = Self(
        code: .init(fromStaticString: "CHIE"),
        info: DataTypes.UInt8
    )

    // Old firmware
    static let inhibitCharging1 = Self(
        code: .init(fromStaticString: "CH0B"),
        info: DataTypes.UInt8
    )

    // Old firmware
    static let inhibitCharging2 = Self(
        code: .init(fromStaticString: "CH0C"),
        info: DataTypes.UInt8
    )

    // New firmware
    static let inhibitCharging3 = Self(
        code: .init(fromStaticString: "CHTE"),
        info: DataTypes.UInt32
    )

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

    /// Byte that engages adapter isolation for this key.
    ///
    /// CHIE is asymmetric: it takes 0x08, while the legacy CH0I/CH0J take 0x01.
    /// Verified against charlie0129/batt (`pkg/smc/adapter.go` writes 0x1 for
    /// AdapterKey1/2 and 0x8 for AdapterKey3), mhaeuser/Battery-Toolkit and
    /// actuallymentor/battery. Writing 0x01 to CHIE is accepted but inert.
    var forceDischargeEngagedValue: UInt8 {
        code == SMCKey.disableCharging3.code ? 0x08 : 0x01
    }
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
    
    static func writeData(_ key: SMCKey, byte0: UInt8, byte1: UInt8, byte2: UInt8, byte3: UInt8) throws {
        try writeData(key, data: (
            byte0, byte1, byte2, byte3, UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0)
        ))
    }
}
