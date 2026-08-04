//
//  SMC+Probe.swift
//  Helper
//
//  Capability probing via kSMCGetKeyInfo.
//
//  Must run in the privileged helper: CH0J, CHLS and BDFU return
//  kIOReturnNotPrivileged for an unprivileged caller, so an app-side probe would
//  wrongly conclude they are absent.
//

import Foundation
import Shared

extension SMCKit {
    /// Attribute bits, established by probing all 2802 keys on a Mac15,8:
    /// every key that reads has 0x80, every writable control key has 0x40.
    private enum Attribute {
        static let readable: UInt8 = 0x80
        static let writable: UInt8 = 0x40
    }

    /// Probes one key. Returns nil when the key is absent, privilege-gated, or a
    /// zero-size placeholder — none of which can drive charging.
    static func probeCapability(_ code: String) -> SMCKeyCapability? {
        var inputStruct = SMCParamStruct()
        inputStruct.key = FourCharCode(fromString: code)
        inputStruct.data8 = SMCParamStruct.Selector.kSMCGetKeyInfo.rawValue

        guard let outputStruct = try? callDriver(&inputStruct) else { return nil }
        let info = outputStruct.keyInfo
        guard info.dataSize > 0 else { return nil }

        return SMCKeyCapability(
            code: code,
            type: info.dataType.toString(),
            size: info.dataSize,
            isReadable: info.dataAttributes & Attribute.readable != 0,
            isWritable: info.dataAttributes & Attribute.writable != 0
        )
    }

    /// Probes every code, dropping the ones that come back nil.
    static func probeCapabilities(_ codes: [String]) -> [String: SMCKeyCapability] {
        var table: [String: SMCKeyCapability] = [:]
        for code in codes {
            if let capability = probeCapability(code) { table[code] = capability }
        }
        return table
    }
}
