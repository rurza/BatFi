// READ-ONLY. Tests whether bfD0/bfE0/bfF0 become reachable via a different
// AppleSMC user-client type. Only kSMCGetKeyInfo (9) is ever issued.
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

func sfc(_ s: String) -> UInt32 { s.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }
func fcs(_ v: UInt32) -> String {
    let b = [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    return String(bytes: b.map { $0 >= 32 && $0 < 127 ? $0 : 0x3F }, encoding: .ascii) ?? "????"
}

print("euid = \(geteuid())")
print("")

let probes = ["bfD0", "bfE0", "bfF0", "CHIE", "CH0J"]

for type in UInt32(0)...UInt32(7) {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
    if service == 0 { print("type \(type): no AppleSMC service"); continue }
    var conn: io_connect_t = 0
    let openResult = IOServiceOpen(service, mach_task_self_, type, &conn)
    IOObjectRelease(service)
    guard openResult == kIOReturnSuccess else {
        print(String(format: "userClientType %d: IOServiceOpen failed 0x%08x", type, UInt32(bitPattern: openResult)))
        continue
    }
    var results: [String] = []
    for code in probes {
        var input = SMCParamStruct(); input.key = sfc(code); input.data8 = 9
        var output = SMCParamStruct()
        let inSize = MemoryLayout<SMCParamStruct>.stride
        var outSize = MemoryLayout<SMCParamStruct>.stride
        let r = IOConnectCallStructMethod(conn, 2, &input, inSize, &output, &outSize)
        if r == kIOReturnSuccess && output.result == 0 {
            results.append("\(code)=OK(\(fcs(output.keyInfo.dataType))/\(output.keyInfo.dataSize)/0x\(String(format: "%02x", output.keyInfo.dataAttributes)))")
        } else if r == kIOReturnNotPrivileged {
            results.append("\(code)=NOTPRIV")
        } else if r == kIOReturnSuccess && output.result == 132 {
            results.append("\(code)=ABSENT")
        } else if r == kIOReturnSuccess {
            results.append("\(code)=smcErr\(output.result)")
        } else {
            results.append("\(code)=io0x\(String(format: "%08x", UInt32(bitPattern: r)))")
        }
    }
    print("userClientType \(type): " + results.joined(separator: "  "))
    IOServiceClose(conn)
}
