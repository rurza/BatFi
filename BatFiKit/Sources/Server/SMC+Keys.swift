//
//  SMC+Keys.swift
//  Helper
//
//  Created by Adam on 23/04/2023.
//

import Foundation
import Shared

extension SMCKey {
    /// Turns one probed-key shape into the key to read or write.
    ///
    /// **Derived, never restated.** `bfD0`/`bfE0`/`bfF0` and their types and sizes are
    /// stated once, in `FirmwareRangeKeyShape` — where `ChargeBackendResolver.resolve`
    /// matches them and `ChargeBackendResolver.probedKeys` decides what gets probed.
    /// Writing the codes out again here would be a second copy with nothing forcing
    /// agreement: repoint the shape and this would go on writing the old key, which the
    /// firmware accepts and ignores, so the resolver would select a mechanism the writes
    /// never touch. Same reason `SMCKit.probeCapability(for:)` takes an `SMCKey` rather
    /// than a bare literal beside one.
    ///
    /// The type is carried across too, not just the code. `SMCKit` takes the write length
    /// from `info.size`, and the size the resolver *verified against the firmware* is the
    /// only one known to be right.
    init(_ shape: FirmwareRangeKeyShape.Key) {
        self.init(
            code: FourCharCode(fromString: shape.code),
            info: DataType(type: FourCharCode(fromString: shape.type), size: shape.size)
        )
    }

    /// macOS 27-era firmware: activation and status. `0x00` charging unrestricted,
    /// `0x02` band in force.
    ///
    /// The only one of the three with a name here, because it is the only one anything
    /// names directly — the status read. The two bounds are written solely as steps of
    /// `FirmwareChargeRange.engageSequence`, which carries its own shape key, so naming
    /// them would add a second way to reach the same key with nothing keeping the two in
    /// step. Even this one is derived, not written out.
    static let firmwareRangeActivation = Self(FirmwareRangeKeyShape.activation)

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

    /// The firmware's own reason for not charging — an 8-byte little-endian
    /// bitfield. See `NotChargingReason` for the bit layout.
    static let notChargingReason = Self(
        code: .init(fromStaticString: "CHNC"),
        info: DataTypes.Hex8
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
