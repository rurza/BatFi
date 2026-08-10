// Tests whether kSMCWriteKey succeeds on keys whose kSMCGetKeyInfo/kSMCReadKey return
// NotPrivileged. Read-only by default; pass --arm to actually engage a 70% band.
//
// Without --arm it writes NOTHING: it only re-confirms that info/read are gated.
// With --arm it performs the documented engage sequence for the macOS 27 firmware band:
//   bfF0=0x00, bfD0=upper, bfE0=lower, bfF0=0x02
import Foundation
import IOKit

typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
struct P {
    struct V { var a: CUnsignedChar = 0; var b: CUnsignedChar = 0; var c: CUnsignedChar = 0
        var d: CUnsignedChar = 0; var e: CUnsignedShort = 0 }
    struct L { var v: UInt16 = 0; var l: UInt16 = 0; var c: UInt32 = 0; var g: UInt32 = 0; var m: UInt32 = 0 }
    struct K { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
    var key: UInt32 = 0
    var vers = V(); var pl = L(); var keyInfo = K()
    var padding: UInt16 = 0; var result: UInt8 = 0; var status: UInt8 = 0
    var data8: UInt8 = 0; var data32: UInt32 = 0
    var bytes: SMCBytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}
func sfc(_ s: String) -> UInt32 { s.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }
var conn: io_connect_t = 0
let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
guard svc != 0, IOServiceOpen(svc, mach_task_self_, 0, &conn) == kIOReturnSuccess else {
    print("FATAL: cannot open AppleSMC"); exit(1)
}
IOObjectRelease(svc)

func describe(_ r: Int32, _ o: P) -> String {
    if r == kIOReturnSuccess && o.result == 0 { return "OK" }
    if r == kIOReturnNotPrivileged { return "NOTPRIV" }
    if r == kIOReturnSuccess && o.result == 132 { return "ABSENT" }
    if r == kIOReturnSuccess { return "smcResult=\(o.result)" }
    return String(format: "io=0x%08x", UInt32(bitPattern: r))
}
func call(_ i: inout P) -> (Int32, P) {
    var o = P(); var n = MemoryLayout<P>.stride
    let r = IOConnectCallStructMethod(conn, 2, &i, MemoryLayout<P>.stride, &o, &n)
    return (r, o)
}
func info(_ code: String) -> String {
    var i = P(); i.key = sfc(code); i.data8 = 9
    let (r, o) = call(&i); return describe(r, o)
}
func read(_ code: String, _ size: UInt32) -> String {
    var i = P(); i.key = sfc(code); i.keyInfo.dataSize = size; i.data8 = 5
    let (r, o) = call(&i); return describe(r, o)
}
func write(_ code: String, _ bytes: [UInt8]) -> String {
    var i = P(); i.key = sfc(code); i.keyInfo.dataSize = UInt32(bytes.count); i.data8 = 6
    withUnsafeMutableBytes(of: &i.bytes) { raw in
        for (n, b) in bytes.enumerated() where n < 32 { raw[n] = b }
    }
    let (r, o) = call(&i); return describe(r, o)
}

print("euid = \(geteuid())")
let arm = CommandLine.arguments.contains("--arm")
print(arm ? "MODE: ARM (will write the band at 70%)" : "MODE: probe only (no writes)")
print("")
print("key    getKeyInfo(9)  readKey(5)   writeKey(6)")
print("----   -------------  ----------   -----------")
for (code, size) in [("bfF0", UInt32(1)), ("bfD0", 4), ("bfE0", 4)] {
    let w = arm ? "(see sequence)" : "not attempted"
    print(String(format: "%-6@ %-14@ %-12@ %@", code as NSString, info(code) as NSString,
                 read(code, size) as NSString, w as NSString))
}

if arm {
    print("")
    print("=== engage sequence: bfF0=00, bfD0=70, bfE0=65, bfF0=02 (little-endian ui32) ===")
    print("bfF0 = 0x00 -> \(write("bfF0", [0x00]))")
    print("bfD0 = 70   -> \(write("bfD0", [70, 0, 0, 0]))")
    print("bfE0 = 65   -> \(write("bfE0", [65, 0, 0, 0]))")
    print("bfF0 = 0x02 -> \(write("bfF0", [0x02]))")
}
