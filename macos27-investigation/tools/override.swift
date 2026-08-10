// Verifies whether temporarilyOverrideMCLTargetSoC: can hold a sub-80 charge target.
// Writes a TEMPORARY override (self-expiring by construction) and renews it, printing
// battery level and charge current each cycle. Usage: override <targetSoC> <cycles>
import Foundation
import IOKit
import IOKit.ps
import ObjectiveC

// ---- SMC read (B0AC charge current) ----
typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
struct SMCParamStruct {
    struct V { var major: CUnsignedChar = 0; var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0; var reserved: CUnsignedChar = 0; var release: CUnsignedShort = 0 }
    struct P { var version: UInt16 = 0; var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0 }
    struct K { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
    var key: UInt32 = 0
    var vers = V(); var pLimitData = P(); var keyInfo = K()
    var padding: UInt16 = 0; var result: UInt8 = 0; var status: UInt8 = 0
    var data8: UInt8 = 0; var data32: UInt32 = 0
    var bytes: SMCBytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}
var conn: io_connect_t = 0
func sfc(_ s: String) -> UInt32 { s.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }
func smcInt16(_ code: String) -> Int? {
    var i = SMCParamStruct(); i.key = sfc(code); i.keyInfo.dataSize = 2; i.data8 = 5
    var o = SMCParamStruct(); var sz = MemoryLayout<SMCParamStruct>.stride
    guard IOConnectCallStructMethod(conn, 2, &i, MemoryLayout<SMCParamStruct>.stride, &o, &sz) == kIOReturnSuccess,
          o.result == 0 else { return nil }
    var b = [UInt8]()
    withUnsafeBytes(of: o.bytes) { raw in for n in 0..<2 { b.append(raw[n]) } }
    return Int(Int16(bitPattern: UInt16(b[0]) | UInt16(b[1]) << 8))
}
let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
if svc != 0 { IOServiceOpen(svc, mach_task_self_, 0, &conn); IOObjectRelease(svc) }

// ---- PowerUI ----
guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW | RTLD_GLOBAL) != nil,
      let cls = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type,
      let alloc = cls.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
      let client = alloc.perform(NSSelectorFromString("initWithClientName:"),
                                 with: "BatFiOverrideProbe" as NSString)?.takeUnretainedValue() else {
    print("FATAL: PowerUI unavailable"); exit(1)
}

let target = UInt8(CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 20 : 20)
let cycles = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 12 : 12

func writeOverride(_ soc: UInt8) -> String {
    let sel = NSSelectorFromString("temporarilyOverrideMCLTargetSoC:error:")
    guard let m = class_getInstanceMethod(cls, sel) else { return "selector absent" }
    typealias F = @convention(c) (AnyObject, Selector, UInt8, AutoreleasingUnsafeMutablePointer<NSError?>?) -> ObjCBool
    let f = unsafeBitCast(method_getImplementation(m), to: F.self)
    var e: NSError?
    let ok = f(client, sel, soc, &e).boolValue
    if let e { return "ERROR \(e.domain) code=\(e.code)" }
    return ok ? "ok" : "returned false"
}
func readLimit() -> Int {
    let sel = NSSelectorFromString("getMCLLimitWithError:")
    guard let m = class_getInstanceMethod(cls, sel) else { return -1 }
    typealias F = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> UInt8
    let f = unsafeBitCast(method_getImplementation(m), to: F.self)
    var e: NSError?
    return Int(f(client, sel, &e))
}

print("target SoC = \(target), cycles = \(cycles) (30s apart)")
print("first write: \(writeOverride(target))")
print("")
print("time      level  current(mA)  getMCLLimit")

let fmt = DateFormatter(); fmt.dateFormat = "HH:mm:ss"
for n in 0..<cycles {
    if n > 0 { _ = writeOverride(target) }          // renew
    let cur = smcInt16("B0AC") ?? -9999
    // battery level via IOKit power sources
    var level = -1
    if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
       let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
       let first = list.first,
       let d = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any],
       let cap = d[kIOPSCurrentCapacityKey] as? Int { level = cap }
    print(String(format: "%@  %3d%%  %8d     %d",
                 fmt.string(from: Date()) as NSString, level, cur, readLimit()))
    if n < cycles - 1 { Thread.sleep(forTimeInterval: 30) }
}
print("\ndone — override left to expire naturally")
