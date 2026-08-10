// READ-ONLY. Tests whether kSMCReadKey (5) works on keys whose kSMCGetKeyInfo (9)
// is privilege-gated. Assumes the known shapes instead of probing for them.
// Issues ONLY selectors 9 and 5. Never 6 (kSMCWriteKey).
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

var conn: io_connect_t = 0
let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
guard service != 0, IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else {
    print("FATAL: cannot open AppleSMC"); exit(1)
}
IOObjectRelease(service)

func describe(_ r: Int32, _ out: SMCParamStruct) -> String? {
    if r == kIOReturnSuccess && out.result == 0 { return nil }
    if r == kIOReturnNotPrivileged { return "NOTPRIV" }
    if r == kIOReturnSuccess && out.result == 132 { return "ABSENT" }
    if r == kIOReturnSuccess { return "smcResult=\(out.result)" }
    return String(format: "io=0x%08x", UInt32(bitPattern: r))
}

print("euid = \(geteuid())")
print("")
print("key    kSMCGetKeyInfo(9)   kSMCReadKey(5)")
print("----   -----------------   --------------")

// Shapes taken from BatFi's FirmwareRangeKeyShape, so no probe is needed.
let candidates: [(String, UInt32)] = [
    ("bfD0", 4), ("bfE0", 4), ("bfF0", 1),
    ("CH0J", 1), ("CHLS", 1), ("BDFU", 1),
    ("CHIE", 1),          // control: known-good
]

for (code, size) in candidates {
    // selector 9
    var i1 = SMCParamStruct(); i1.key = sfc(code); i1.data8 = 9
    var o1 = SMCParamStruct()
    var s1 = MemoryLayout<SMCParamStruct>.stride
    let r1 = IOConnectCallStructMethod(conn, 2, &i1, MemoryLayout<SMCParamStruct>.stride, &o1, &s1)
    let info = describe(r1, o1) ?? "OK"

    // selector 5, using the assumed size rather than the probed one
    var i2 = SMCParamStruct(); i2.key = sfc(code); i2.keyInfo.dataSize = size; i2.data8 = 5
    var o2 = SMCParamStruct()
    var s2 = MemoryLayout<SMCParamStruct>.stride
    let r2 = IOConnectCallStructMethod(conn, 2, &i2, MemoryLayout<SMCParamStruct>.stride, &o2, &s2)
    var read = describe(r2, o2) ?? "OK"
    if read == "OK" {
        var arr = [UInt8]()
        withUnsafeBytes(of: o2.bytes) { raw in for n in 0..<Int(size) { arr.append(raw[n]) } }
        read = "OK = " + arr.map { String(format: "%02x", $0) }.joined(separator: " ")
        if size == 4 {
            let le = UInt32(arr[0]) | UInt32(arr[1]) << 8 | UInt32(arr[2]) << 16 | UInt32(arr[3]) << 24
            read += "  (LE=\(le))"
        }
    }
    print(String(format: "%-6@ %-19@ %@", code as NSString, info as NSString, read as NSString))
}

IOServiceClose(conn)
