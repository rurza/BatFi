//
// SMCKit
//
// The MIT License
//
// Copyright (C) 2014-2017  beltex <https://beltex.github.io>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import IOKit
import Foundation

//------------------------------------------------------------------------------
// MARK: Type Aliases
//------------------------------------------------------------------------------

// http://stackoverflow.com/a/22383661

/// Floating point, unsigned, 14 bits exponent, 2 bits fraction
public typealias FPE2 = (UInt8, UInt8)

/// Floating point, signed, 7 bits exponent, 8 bits fraction
public typealias SP78 = (UInt8, UInt8)

public typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                             UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                             UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                             UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                             UInt8, UInt8, UInt8, UInt8)

//------------------------------------------------------------------------------
// MARK: Standard Library Extensions
//------------------------------------------------------------------------------

extension UInt32 {

    init(fromBytes bytes: (UInt8, UInt8, UInt8, UInt8)) {
        // TODO: Broken up due to "Expression was too complex" error as of
        //       Swift 4.

        let byte0 = UInt32(bytes.0) << 24
        let byte1 = UInt32(bytes.1) << 16
        let byte2 = UInt32(bytes.2) << 8
        let byte3 = UInt32(bytes.3)

        self = byte0 | byte1 | byte2 | byte3
    }
}

extension Bool {

    init(fromByte byte: UInt8) {
        self = byte == 1 ? true : false
    }
}

public extension Int {

    init(fromFPE2 bytes: FPE2) {
        self = (Int(bytes.0) << 6) + (Int(bytes.1) >> 2)
    }

    func toFPE2() -> FPE2 {
        return (UInt8(self >> 6), UInt8((self << 2) ^ ((self >> 6) << 8)))
    }
}

extension Double {

    init(fromSP78 bytes: SP78) {
        // FIXME: Handle second byte
        let sign = bytes.0 & 0x80 == 0 ? 1.0 : -1.0
        self = sign * Double(bytes.0 & 0x7F)    // AND to mask sign bit
    }
}

// Thanks to Airspeed Velocity for the great idea!
// http://airspeedvelocity.net/2015/05/22/my-talk-at-swift-summit/
public extension FourCharCode {

    init(fromString str: String) {
        precondition(str.count == 4)

        self = str.utf8.reduce(0) { sum, character in
            return sum << 8 | UInt32(character)
        }
    }

    init(fromStaticString str: StaticString) {
        precondition(str.utf8CodeUnitCount == 4)

        self = str.withUTF8Buffer { buffer in
            // TODO: Broken up due to "Expression was too complex" error as of
            //       Swift 4.

            let byte0 = UInt32(buffer[0]) << 24
            let byte1 = UInt32(buffer[1]) << 16
            let byte2 = UInt32(buffer[2]) << 8
            let byte3 = UInt32(buffer[3])

            return byte0 | byte1 | byte2 | byte3
        }
    }

    func toString() -> String {
        return String(describing: UnicodeScalar(self >> 24 & 0xff)!) +
        String(describing: UnicodeScalar(self >> 16 & 0xff)!) +
        String(describing: UnicodeScalar(self >> 8  & 0xff)!) +
        String(describing: UnicodeScalar(self       & 0xff)!)
    }
}

//------------------------------------------------------------------------------
// MARK: Defined by AppleSMC.kext
//------------------------------------------------------------------------------

/// Defined by AppleSMC.kext
///
/// This is the predefined struct that must be passed to communicate with the
/// AppleSMC driver. While the driver is closed source, the definition of this
/// struct happened to appear in the Apple PowerManagement project at around
/// version 211, and soon after disappeared. It can be seen in the PrivateLib.c
/// file under pmconfigd. Given that it is C code, this is the closest
/// translation to Swift from a type perspective.
///
/// ### Issues
///
/// * Padding for struct alignment when passed over to C side
/// * Size of struct must be 80 bytes
/// * C array's are bridged as tuples
///
/// http://www.opensource.apple.com/source/PowerManagement/PowerManagement-211/
public struct SMCParamStruct {

    /// I/O Kit function selector
    public enum Selector: UInt8 {
        case kSMCHandleYPCEvent  = 2
        case kSMCReadKey         = 5
        case kSMCWriteKey        = 6
        case kSMCGetKeyFromIndex = 8
        case kSMCGetKeyInfo      = 9
    }

    /// Return codes for SMCParamStruct.result property
    public enum Result: UInt8 {
        case kSMCSuccess     = 0
        case kSMCError       = 1
        case kSMCKeyNotFound = 132
    }

    public struct SMCVersion {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }

    public struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    public struct SMCKeyInfoData {
        /// How many bytes written to SMCParamStruct.bytes
        var dataSize: UInt32 = 0

        /// Type of data written to SMCParamStruct.bytes. This lets us know how
        /// to interpret it (translate it to human readable)
        var dataType: UInt32 = 0

        var dataAttributes: UInt8 = 0
    }

    /// FourCharCode telling the SMC what we want
    var key: UInt32 = 0

    var vers = SMCVersion()

    var pLimitData = SMCPLimitData()

    var keyInfo = SMCKeyInfoData()

    /// Padding for struct alignment when passed over to C side
    var padding: UInt16 = 0

    /// Result of an operation
    var result: UInt8 = 0

    var status: UInt8 = 0

    /// Method selector
    var data8: UInt8 = 0

    var data32: UInt32 = 0

    /// Data returned from the SMC
    var bytes: SMCBytes = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                           UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                           UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                           UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                           UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                           UInt8(0), UInt8(0))
}

//------------------------------------------------------------------------------
// MARK: SMC Client
//------------------------------------------------------------------------------

/// SMC data type information
public struct DataTypes {
    /// Fan information struct
    public static let FDS =
    DataType(type: FourCharCode(fromStaticString: "{fds"), size: 16)
    public static let Flag =
    DataType(type: FourCharCode(fromStaticString: "flag"), size: 1)
    /// See type aliases
    public static let FPE2 =
    DataType(type: FourCharCode(fromStaticString: "fpe2"), size: 2)
    /// See type aliases
    public static let SP78 =
    DataType(type: FourCharCode(fromStaticString: "sp78"), size: 2)
    public static let UInt8 =
    DataType(type: FourCharCode(fromStaticString: "ui8 "), size: 1)
    public static let UInt32 =
    DataType(type: FourCharCode(fromStaticString: "ui32"), size: 4)
}

public struct SMCKey {
    let code: FourCharCode
    let info: DataType
}

public struct DataType: Equatable {
    let type: FourCharCode
    let size: UInt32
}

public func ==(lhs: DataType, rhs: DataType) -> Bool {
    return lhs.type == rhs.type && lhs.size == rhs.size
}

/// Apple System Management Controller (SMC) user-space client for Intel-based
/// Macs. Works by talking to the AppleSMC.kext (kernel extension), the closed
/// source driver for the SMC.
public struct SMCKit {

    /// Connection to the SMC driver
    fileprivate static var connection: io_connect_t = 0

    /// Open connection to the SMC driver. This must be done first before any
    /// other calls
    public static func open() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSMC"))

        if service == 0 { throw SMCError.driverNotFound }

        let result = IOServiceOpen(service, mach_task_self_, 0,
                                   &SMCKit.connection)
        IOObjectRelease(service)

        if result != kIOReturnSuccess { throw SMCError.failedToOpen }
    }

    /// Close connection to the SMC driver
    @discardableResult
    public static func close() -> Bool {
        let result = IOServiceClose(SMCKit.connection)
        return result == kIOReturnSuccess ? true : false
    }

    /// Get information about a key
    public static func keyInformation(_ key: FourCharCode) throws -> DataType {
        var inputStruct = SMCParamStruct()

        inputStruct.key = key
        inputStruct.data8 = SMCParamStruct.Selector.kSMCGetKeyInfo.rawValue

        let outputStruct = try callDriver(&inputStruct)

        return DataType(type: outputStruct.keyInfo.dataType,
                        size: outputStruct.keyInfo.dataSize)
    }

    /// Get information about the key at index
    public static func keyInformationAtIndex(_ index: Int) throws ->
    FourCharCode {
        var inputStruct = SMCParamStruct()

        inputStruct.data8 = SMCParamStruct.Selector.kSMCGetKeyFromIndex.rawValue
        inputStruct.data32 = UInt32(index)

        let outputStruct = try callDriver(&inputStruct)

        return outputStruct.key
    }

    /// Read data of a key
    public static func readData(_ key: SMCKey) throws -> SMCBytes {
        var inputStruct = SMCParamStruct()

        inputStruct.key = key.code
        inputStruct.keyInfo.dataSize = UInt32(key.info.size)
        inputStruct.data8 = SMCParamStruct.Selector.kSMCReadKey.rawValue

        let outputStruct = try callDriver(&inputStruct)

        return outputStruct.bytes
    }

    /// Write data for a key
    public static func writeData(_ key: SMCKey, data: SMCBytes) throws {
        var inputStruct = SMCParamStruct()

        inputStruct.key = key.code
        inputStruct.bytes = data
        inputStruct.keyInfo.dataSize = UInt32(key.info.size)
        inputStruct.data8 = SMCParamStruct.Selector.kSMCWriteKey.rawValue

        _ = try callDriver(&inputStruct)
    }

    /// Make an actual call to the SMC driver
    public static func callDriver(_ inputStruct: inout SMCParamStruct,
                                  selector: SMCParamStruct.Selector = .kSMCHandleYPCEvent)
    throws -> SMCParamStruct {
        assert(MemoryLayout<SMCParamStruct>.stride == 80, "SMCParamStruct size is != 80")

        var outputStruct = SMCParamStruct()
        let inputStructSize = MemoryLayout<SMCParamStruct>.stride
        var outputStructSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(SMCKit.connection,
                                               UInt32(selector.rawValue),
                                               &inputStruct,
                                               inputStructSize,
                                               &outputStruct,
                                               &outputStructSize)

        switch (result, outputStruct.result) {
        case (kIOReturnSuccess, SMCParamStruct.Result.kSMCSuccess.rawValue):
            return outputStruct
        case (kIOReturnSuccess, SMCParamStruct.Result.kSMCKeyNotFound.rawValue):
            throw SMCError.keyNotFound(code: inputStruct.key.toString())
        case (kIOReturnNotPrivileged, _):
            throw SMCError.notPrivileged
        default:
            throw SMCError.unknown(kIOReturn: result,
                                   SMCResult: outputStruct.result)
        }
    }
}

//------------------------------------------------------------------------------
// MARK: General
//------------------------------------------------------------------------------

extension SMCKit {

    /// Get all valid SMC keys for this machine
    public static func allKeys() throws -> [SMCKey] {
        let count = try keyCount()
        var keys = [SMCKey]()

        for i in 0 ..< count {
            let key = try keyInformationAtIndex(i)
            let info = try keyInformation(key)
            keys.append(SMCKey(code: key, info: info))
        }

        return keys
    }

    /// Get the number of valid SMC keys for this machine
    public static func keyCount() throws -> Int {
        let key = SMCKey(code: FourCharCode(fromStaticString: "#KEY"),
                         info: DataTypes.UInt32)

        let data = try readData(key)
        return Int(UInt32(fromBytes: (data.0, data.1, data.2, data.3)))
    }

    /// Is this key valid on this machine?
    public static func isKeyFound(_ code: FourCharCode) throws -> Bool {
        do {
            _ = try keyInformation(code)
        } catch SMCError.keyNotFound { return false }

        return true
    }
}
