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

    static let inhibitCharging = Self(
        code: .init(fromStaticString: "CH0C"),
        info: DataTypes.UInt8
    )

    static let lidClosed = Self(
        code: .init(fromStaticString: "MSLD"),
        info: DataTypes.UInt8
    )
}

extension SMCKit {
    public static func writeData(_ key: SMCKey, uint8: UInt8) throws {
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
