// Minimal read-only SMC sampler: B0AC (charge current), CHIE, ACLC. One line, fast.
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
    print("smc-open-failed"); exit(1)
}
IOObjectRelease(svc)
func read(_ code: String, _ size: UInt32) -> [UInt8]? {
    var i = P(); i.key = sfc(code); i.keyInfo.dataSize = size; i.data8 = 5
    var o = P(); var n = MemoryLayout<P>.stride
    guard IOConnectCallStructMethod(conn, 2, &i, MemoryLayout<P>.stride, &o, &n) == kIOReturnSuccess,
          o.result == 0 else { return nil }
    var a = [UInt8]()
    withUnsafeBytes(of: o.bytes) { r in for k in 0..<Int(size) { a.append(r[k]) } }
    return a
}
var out: [String] = []
if let b = read("B0AC", 2) {
    out.append("B0AC=\(Int16(bitPattern: UInt16(b[0]) | UInt16(b[1]) << 8))mA")
} else { out.append("B0AC=?") }
for k in ["CHIE", "ACLC"] {
    if let b = read(k, 1) { out.append("\(k)=\(String(format: "%02x", b[0]))") } else { out.append("\(k)=?") }
}
print(out.joined(separator: " "))
