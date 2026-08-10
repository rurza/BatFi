// READ-ONLY privileged SMC probe. Performs kSMCGetKeyInfo + kSMCReadKey only.
// It never issues kSMCWriteKey, so it cannot change charging behaviour.
// Mirrors BatFi's FirmwareRangeKeyShape / ForceDischargeKeyShape matching rules.
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
func fcs(_ v: UInt32) -> String {
    let b = [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    return String(bytes: b.map { $0 >= 32 && $0 < 127 ? $0 : 0x3F }, encoding: .ascii) ?? "????"
}
func sfc(_ s: String) -> UInt32 { s.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }

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
guard service != 0, IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
    print("FATAL: cannot open AppleSMC"); exit(1)
}
IOObjectRelease(service)

print("euid = \(geteuid())  (0 = root)")
print("")

struct Shape { let type: String; let size: UInt32 }
let expected: [String: Shape] = [
    "bfF0": Shape(type: "ui8 ", size: 1),
    "bfD0": Shape(type: "ui32", size: 4),
    "bfE0": Shape(type: "ui32", size: 4),
]

var resolvedShapes: [String: (String, UInt32, UInt8)] = [:]

let interesting = ["bfD0", "bfE0", "bfF0", "CHTE", "CHIE", "CH0B", "CH0C", "CH0I", "CH0J",
                   "CHLS", "BDFU", "BCF0", "CHNC", "CHSC", "bfB0", "bfC0", "bfG0", "bfv0"]

for code in interesting {
    var i = SMCParamStruct(); i.key = sfc(code); i.data8 = 9
    do {
        let o = try call(&i)
        let type = fcs(o.keyInfo.dataType)
        let size = o.keyInfo.dataSize
        let attr = o.keyInfo.dataAttributes
        resolvedShapes[code] = (type, size, attr)
        var line = String(format: "%-5@ type=%-5@ size=%-3d attr=0x%02x [%@%@]",
                          code as NSString, type as NSString, Int(size), attr,
                          ((attr & 0x80) != 0 ? "r" : "-") as NSString,
                          ((attr & 0x40) != 0 ? "w" : "-") as NSString)
        if size > 0 && size <= 32 {
            var i2 = SMCParamStruct(); i2.key = sfc(code); i2.keyInfo.dataSize = size; i2.data8 = 5
            if let o2 = try? call(&i2) {
                var arr = [UInt8]()
                withUnsafeBytes(of: o2.bytes) { raw in for n in 0..<Int(size) { arr.append(raw[n]) } }
                line += "  = " + arr.map { String(format: "%02x", $0) }.joined(separator: " ")
                if size == 4 {
                    let le = UInt32(arr[0]) | UInt32(arr[1]) << 8 | UInt32(arr[2]) << 16 | UInt32(arr[3]) << 24
                    let be = UInt32(arr[3]) | UInt32(arr[2]) << 8 | UInt32(arr[1]) << 16 | UInt32(arr[0]) << 24
                    line += "  (LE=\(le) BE=\(be))"
                }
            } else { line += "  = <read failed>" }
        }
        print(line)
    } catch E.smc(let c) {
        print(String(format: "%-5@ %@", code as NSString,
                     (c == 132 ? "ABSENT (kSMCKeyNotFound)" : "SMC error \(c)") as NSString))
    } catch E.io(let r) {
        print(String(format: "%-5@ %@", code as NSString,
                     (r == kIOReturnNotPrivileged ? "PRIVILEGE-GATED (still!)"
                      : String(format: "IOKit 0x%08x", UInt32(bitPattern: r))) as NSString))
    }
}

print("\n=== BatFi FirmwareRangeKeyShape verdict ===")
var allMatch = true
for (code, want) in expected.sorted(by: { $0.key < $1.key }) {
    guard let got = resolvedShapes[code] else {
        print("\(code): MISSING -> no match"); allMatch = false; continue
    }
    let (type, size, attr) = got
    let readable = (attr & 0x80) != 0
    let writable = (attr & 0x40) != 0
    let ok = type == want.type && size == want.size && size > 0 && readable && writable
    print("\(code): expected \(want.type)/\(want.size) writable — got \(type)/\(size) r=\(readable) w=\(writable) -> \(ok ? "MATCH" : "NO MATCH")")
    if !ok { allMatch = false }
}
print("\nresolve() would select: \(allMatch ? ".firmwareRange" : "NOT .firmwareRange (falls through)")")
