//
//  SMC+Keys.swift
//  Helper
//
//  Created by Adam on 23/04/2023.
//

import Foundation

extension SMCKey {
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
}
