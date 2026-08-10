// AlDente's "Golden Gate" macOS 27 charge-limit backend, reproduced exactly.
//
// Recovered from AlDente 1.39b3 by disassembling the app's Golden Gate function
// (app 0x100225b90) and the helper's SMC write path (helper 0x100002b88):
//
//   UPPER = clamp(target, 1, 100)
//   LOWER = min(UPPER - 1, requestedLower)
//
//   1. bfF0 <- 0x00                    dataSize 1   (disarm)
//   2. bfD0 <- UInt32(UPPER) << 24     dataSize 4   (upper threshold)
//   3. bfE0 <- UInt32(LOWER) << 24     dataSize 4   (lower threshold / hysteresis)
//   4. bfF0 <- 0x02                    dataSize 2? -> 1                (arm)
//   5. read bfD0 / bfE0 back and verify
//
// Two details the earlier investigation got wrong, and which are why its write
// test reported NotPrivileged / did nothing:
//
//   * The helper serialises the UInt32 LITTLE-ENDIAN into SMCParamStruct.bytes,
//     so `value << 24` puts the percentage in bytes[3], NOT bytes[0].
//     The earlier tool wrote [70,0,0,0]; the correct payload is [0,0,0,70].
//   * kSMCGetKeyInfo is privilege-gated for these keys, so the size must be
//     HARDCODED (4 and 1) and getKeyInfo must never be called. Probing first and
//     bailing on failure makes these keys permanently unreachable.
//
// SMCParamStruct layout verified empirically (size 80, result@0x28, data8@0x2a,
// bytes@0x30) against the helper's own IOConnectCallStructMethod call.
//
//   swiftc -O goldengate.swift -o goldengate
//   sudo ./goldengate 75          # engage an upper/lower band at 75/74
//   sudo ./goldengate --off       # disarm

import Foundation
import IOKit

typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

struct SMCParamStruct {
    struct SMCVersion {
        var major: CUnsignedChar = 0, minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0, reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }
    struct SMCPLimitData {
        var version: UInt16 = 0, length: UInt16 = 0
        var cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0
    }
    struct SMCKeyInfoData {
        var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0
    }
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    /// Restores the C layout: Swift packs `keyInfo` by size (9), not stride (12).
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

let kRead: UInt8 = 5
let kWrite: UInt8 = 6

func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }

var conn: io_connect_t = 0
let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
guard service != 0, IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else {
    print("FATAL: cannot open AppleSMC"); exit(1)
}
IOObjectRelease(service)

func call(_ input: inout SMCParamStruct) -> (Int32, SMCParamStruct) {
    var output = SMCParamStruct()
    var outSize = MemoryLayout<SMCParamStruct>.stride
    let rc = IOConnectCallStructMethod(conn, 2, &input,
                                       MemoryLayout<SMCParamStruct>.stride,
                                       &output, &outSize)
    return (rc, output)
}

func describe(_ rc: Int32, _ out: SMCParamStruct) -> String {
    if rc == kIOReturnSuccess && out.result == 0 { return "OK" }
    if rc == kIOReturnNotPrivileged { return "NOTPRIVILEGED" }
    if rc == kIOReturnSuccess && out.result == 132 { return "KEY-NOT-FOUND" }
    if rc == kIOReturnSuccess { return "smcResult=\(out.result)" }
    return String(format: "ioReturn=0x%08x", UInt32(bitPattern: rc))
}

/// Reads `size` bytes without ever calling kSMCGetKeyInfo (gated for these keys).
func readKey(_ code: String, size: UInt32) -> (String, [UInt8]) {
    var input = SMCParamStruct()
    input.key = fourCC(code)
    input.keyInfo.dataSize = size
    input.data8 = kRead
    let (rc, out) = call(&input)
    var raw = [UInt8]()
    withUnsafeBytes(of: out.bytes) { buf in
        for i in 0 ..< Int(size) { raw.append(buf[i]) }
    }
    return (describe(rc, out), raw)
}

func writeKey(_ code: String, _ payload: [UInt8]) -> String {
    var input = SMCParamStruct()
    input.key = fourCC(code)
    input.keyInfo.dataSize = UInt32(payload.count)
    input.data8 = kWrite
    withUnsafeMutableBytes(of: &input.bytes) { buf in
        for (i, b) in payload.enumerated() where i < 32 { buf[i] = b }
    }
    let (rc, out) = call(&input)
    return describe(rc, out)
}

/// Little-endian, matching the helper's byte-by-byte serialisation.
func le32(_ v: UInt32) -> [UInt8] {
    [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
}

guard geteuid() == 0 else { print("FATAL: must run as root (sudo)."); exit(1) }

print("euid = \(geteuid())")
print("")
print("--- reads with HARDCODED sizes (no getKeyInfo) ---")
for (code, size) in [("bfF0", UInt32(1)), ("bfD0", 4), ("bfE0", 4)] {
    let (status, raw) = readKey(code, size: size)
    let hex = raw.map { String(format: "%02x", $0) }.joined(separator: " ")
    print(String(format: "  %@  size=%d  %-14@  bytes=[%@]",
                 code, size, status as NSString, hex))
}
print("")

if CommandLine.arguments.contains("--off") {
    print("--- disarming ---")
    print("  bfF0 <- 0x00 : \(writeKey("bfF0", [0x00]))")
    exit(0)
}

let target = Int(CommandLine.arguments.dropFirst().first(where: { Int($0) != nil }) ?? "") ?? 75
let upper = min(max(target, 1), 100)
let lower = min(upper - 1, upper - 1)
print("--- engaging Golden Gate band: UPPER=\(upper) LOWER=\(lower) ---")
print("  bfF0 <- 0x00                 : \(writeKey("bfF0", [0x00]))")
print("  bfD0 <- \(upper)<<24  \(le32(UInt32(upper) << 24)) : \(writeKey("bfD0", le32(UInt32(upper) << 24)))")
print("  bfE0 <- \(lower)<<24  \(le32(UInt32(lower) << 24)) : \(writeKey("bfE0", le32(UInt32(lower) << 24)))")
print("  bfF0 <- 0x02                 : \(writeKey("bfF0", [0x02]))")
print("")

print("--- readback verification ---")
for (code, size) in [("bfF0", UInt32(1)), ("bfD0", 4), ("bfE0", 4)] {
    let (status, raw) = readKey(code, size: size)
    let hex = raw.map { String(format: "%02x", $0) }.joined(separator: " ")
    let decoded = raw.count == 4 ? "  => \(Int(raw[3])) (bytes[3])" : ""
    print(String(format: "  %@  %-14@  bytes=[%@]%@",
                 code, status as NSString, hex, decoded as NSString))
}
print("")

print("--- charge current (B0AC) over 20s ---")
for i in 0 ..< 10 {
    let (status, raw) = readKey("B0AC", size: 2)
    if raw.count == 2 {
        let v = Int16(bitPattern: UInt16(raw[0]) << 8 | UInt16(raw[1]))
        print("  t+\(i * 2)s  B0AC = \(v) mA   (\(status))")
    } else {
        print("  t+\(i * 2)s  B0AC read failed: \(status)")
    }
    usleep(2_000_000)
}
