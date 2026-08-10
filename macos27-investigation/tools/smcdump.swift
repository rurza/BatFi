// Read-only SMC key enumerator. Dumps every key with type/size/attributes,
// and reads values for a watchlist of charge-control keys.
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

let kSMCReadKey: UInt8 = 5
let kSMCGetKeyFromIndex: UInt8 = 8
let kSMCGetKeyInfo: UInt8 = 9

var connection: io_connect_t = 0

func fourCharToString(_ v: UInt32) -> String {
    let b = [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    return String(bytes: b.map { $0 >= 32 && $0 < 127 ? $0 : 0x3F }, encoding: .ascii) ?? "????"
}
func stringToFourChar(_ s: String) -> UInt32 {
    s.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
}

enum CallError: Error { case io(Int32), smc(UInt8) }

func call(_ input: inout SMCParamStruct) throws -> SMCParamStruct {
    var output = SMCParamStruct()
    let inSize = MemoryLayout<SMCParamStruct>.stride
    var outSize = MemoryLayout<SMCParamStruct>.stride
    let r = IOConnectCallStructMethod(connection, 2, &input, inSize, &output, &outSize)
    if r != kIOReturnSuccess { throw CallError.io(r) }
    if output.result != 0 { throw CallError.smc(output.result) }
    return output
}

let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
guard service != 0, IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
    print("FATAL: cannot open AppleSMC"); exit(1)
}
IOObjectRelease(service)

func keyInfo(_ code: UInt32) throws -> SMCParamStruct.SMCKeyInfoData {
    var i = SMCParamStruct(); i.key = code; i.data8 = kSMCGetKeyInfo
    return try call(&i).keyInfo
}
func readKey(_ code: UInt32, size: UInt32) throws -> [UInt8] {
    var i = SMCParamStruct(); i.key = code; i.keyInfo.dataSize = size; i.data8 = kSMCReadKey
    let o = try call(&i)
    var arr = [UInt8]()
    withUnsafeBytes(of: o.bytes) { raw in
        for n in 0..<Int(min(size, 32)) { arr.append(raw[n]) }
    }
    return arr
}

// key count
let countBytes = try readKey(stringToFourChar("#KEY"), size: 4)
let count = Int(UInt32(countBytes[0]) << 24 | UInt32(countBytes[1]) << 16 | UInt32(countBytes[2]) << 8 | UInt32(countBytes[3]))
print("#KEY count = \(count)")
print("")

var all: [(String, String, UInt32, UInt8)] = []
for idx in 0..<count {
    var i = SMCParamStruct(); i.data8 = kSMCGetKeyFromIndex; i.data32 = UInt32(idx)
    guard let o = try? call(&i) else { continue }
    guard let info = try? keyInfo(o.key) else { continue }
    all.append((fourCharToString(o.key), fourCharToString(info.dataType), info.dataSize, info.dataAttributes))
}

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "charge"

func attrString(_ a: UInt8) -> String {
    var s = ""
    s += (a & 0x80) != 0 ? "r" : "-"
    s += (a & 0x40) != 0 ? "w" : "-"
    return s + String(format: " (0x%02x)", a)
}

func dump(_ rows: [(String, String, UInt32, UInt8)]) {
    for (code, type, size, attr) in rows {
        var valueStr = ""
        if size > 0, size <= 32, (attr & 0x80) != 0 {
            if let v = try? readKey(stringToFourChar(code), size: size) {
                valueStr = "  = " + v.map { String(format: "%02x", $0) }.joined(separator: " ")
            } else {
                valueStr = "  = <read denied>"
            }
        }
        print(String(format: "%-6@ %-5@ size=%-2d attr=%@%@", code as NSString, type as NSString, Int(size), attrString(attr) as NSString, valueStr as NSString))
    }
}

if mode == "all" {
    dump(all.sorted { $0.0 < $1.0 })
} else {
    let prefixes = ["CH", "bf", "BC", "BF", "BM", "AC", "B0", "BS"]
    let watch = ["CHTE","CHIE","CHSC","CHLS","CHNC","CHBI","CHBV","CH0B","CH0C","CH0I","CH0J",
                 "bfD0","bfE0","bfF0","bfA0","bfB0","bfC0","bfG0","bfH0","BCF0","BFCL","BRSC"]
    let rows = all.filter { row in prefixes.contains { row.0.hasPrefix($0) } || watch.contains(row.0) }
    dump(rows.sorted { $0.0 < $1.0 })
    print("\n--- watchlist keys NOT present ---")
    let present = Set(all.map { $0.0 })
    print(watch.filter { !present.contains($0) }.joined(separator: ", "))
}
