// Enumerate every SMC index and report keys whose keyInfo call FAILED,
// so "absent" can be distinguished from "present but unreadable metadata".
import Foundation
import IOKit

typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

struct SMCParamStruct {
    struct SMCVersion { var major: CUnsignedChar = 0; var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0; var reserved: CUnsignedChar = 0; var release: CUnsignedShort = 0 }
    struct SMCPLimitData { var version: UInt16 = 0; var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0 }
    struct SMCKeyInfoData { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

var connection: io_connect_t = 0
func fourCharToString(_ v: UInt32) -> String {
    let b = [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    return String(bytes: b.map { $0 >= 32 && $0 < 127 ? $0 : 0x3F }, encoding: .ascii) ?? "????"
}
func stringToFourChar(_ s: String) -> UInt32 { s.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }

enum E: Error { case io(Int32), smc(UInt8) }
func call(_ input: inout SMCParamStruct) throws -> SMCParamStruct {
    var output = SMCParamStruct()
    let inSize = MemoryLayout<SMCParamStruct>.stride
    var outSize = MemoryLayout<SMCParamStruct>.stride
    let r = IOConnectCallStructMethod(connection, 2, &input, inSize, &output, &outSize)
    if r != kIOReturnSuccess { throw E.io(r) }
    if output.result != 0 { throw E.smc(output.result) }
    return output
}

let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
guard service != 0, IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { exit(1) }
IOObjectRelease(service)

var i0 = SMCParamStruct(); i0.key = stringToFourChar("#KEY"); i0.keyInfo.dataSize = 4; i0.data8 = 5
let o0 = try call(&i0)
var cb = [UInt8]()
withUnsafeBytes(of: o0.bytes) { raw in for n in 0..<4 { cb.append(raw[n]) } }
let count = Int(UInt32(cb[0]) << 24 | UInt32(cb[1]) << 16 | UInt32(cb[2]) << 8 | UInt32(cb[3]))

var indexFailed = 0
var infoFailed: [String] = []
var names = Set<String>()
for idx in 0..<count {
    var i = SMCParamStruct(); i.data8 = 8; i.data32 = UInt32(idx)
    guard let o = try? call(&i) else { indexFailed += 1; continue }
    let name = fourCharToString(o.key)
    names.insert(name)
    var i2 = SMCParamStruct(); i2.key = o.key; i2.data8 = 9
    if (try? call(&i2)) == nil { infoFailed.append(name) }
}

print("#KEY = \(count)")
print("names recovered by index = \(names.count)")
print("index lookups that failed = \(indexFailed)")
print("keyInfo failures = \(infoFailed.count): \(infoFailed.sorted().joined(separator: " "))")
print("")
for probe in ["bfD0", "bfE0", "bfF0", "CHTE", "CH0B", "CH0C", "CH0I", "CH0J", "CHIE", "BCF0"] {
    var i = SMCParamStruct(); i.key = stringToFourChar(probe); i.data8 = 9
    var verdict: String
    do {
        let o = try call(&i)
        verdict = "PRESENT type=\(fourCharToString(o.keyInfo.dataType)) size=\(o.keyInfo.dataSize) attr=0x\(String(format: "%02x", o.keyInfo.dataAttributes))"
    } catch E.smc(let c) {
        verdict = c == 132 ? "ABSENT (kSMCKeyNotFound)" : "SMC error \(c)"
    } catch E.io(let r) {
        verdict = r == kIOReturnNotPrivileged ? "PRIVILEGE-GATED" : String(format: "IOKit 0x%08x", UInt32(bitPattern: r))
    }
    print(String(format: "%-5@ in-index=%@  direct: %@", probe as NSString,
                 (names.contains(probe) ? "yes" : "no ") as NSString, verdict as NSString))
}
