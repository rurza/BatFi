// READ-ONLY PowerUI query. Mirrors BatFi's PowerUICharging setup exactly.
// Calls only isMCLSupported / availableChargeLimitsWithError: / getMCLLimitWithError:.
// It never calls setMCLLimit: or overrideMCLTarget:, so it cannot change any setting.
import Foundation
import ObjectiveC

let frameworkPath = "/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI"
guard dlopen(frameworkPath, RTLD_NOW | RTLD_GLOBAL) != nil else {
    print("FATAL: cannot dlopen PowerUI"); exit(1)
}
guard let cls = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type,
      let allocated = cls.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
      let client = allocated.perform(NSSelectorFromString("initWithClientName:"),
                                     with: "BatFiProbe" as NSString)?.takeUnretainedValue() else {
    print("FATAL: cannot create PowerUISmartChargeClient"); exit(1)
}

print("euid = \(geteuid())")
print("PowerUISmartChargeClient = OK")
print("")

// isMCLSupported
let supSel = NSSelectorFromString("isMCLSupported")
if let m = class_getInstanceMethod(cls, supSel) {
    typealias F = @convention(c) (AnyObject, Selector) -> ObjCBool
    let f = unsafeBitCast(method_getImplementation(m), to: F.self)
    print("isMCLSupported            = \(f(client, supSel).boolValue)")
} else { print("isMCLSupported            = <selector absent>") }

// isMCLCurrentlyEnabled
let enSel = NSSelectorFromString("isMCLCurrentlyEnabled:")
if let m = class_getInstanceMethod(cls, enSel) {
    typealias F = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> ObjCBool
    let f = unsafeBitCast(method_getImplementation(m), to: F.self)
    var e: NSError?
    let v = f(client, enSel, &e).boolValue
    print("isMCLCurrentlyEnabled     = \(v)\(e.map { "  error=\($0.localizedDescription)" } ?? "")")
} else { print("isMCLCurrentlyEnabled     = <selector absent>") }

// availableChargeLimitsWithError:
let availSel = NSSelectorFromString("availableChargeLimitsWithError:")
if let m = class_getInstanceMethod(cls, availSel) {
    typealias F = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> NSArray?
    let f = unsafeBitCast(method_getImplementation(m), to: F.self)
    var e: NSError?
    let arr = f(client, availSel, &e) as? [NSNumber]
    if let arr {
        print("availableChargeLimits     = \(arr.map(\.intValue).sorted())")
    } else {
        print("availableChargeLimits     = nil  error=\(e?.localizedDescription ?? "none")")
    }
} else { print("availableChargeLimits     = <selector absent>") }

// getMCLLimitWithError:  (returns unsigned char)
let getSel = NSSelectorFromString("getMCLLimitWithError:")
if let m = class_getInstanceMethod(cls, getSel) {
    typealias F = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> UInt8
    let f = unsafeBitCast(method_getImplementation(m), to: F.self)
    var e: NSError?
    let v = f(client, getSel, &e)
    print("getMCLLimit               = \(v)\(e.map { "  error=\($0.localizedDescription)" } ?? "")")
} else { print("getMCLLimit               = <selector absent>") }

// Enumerate every MCL-ish selector this build actually exposes.
print("")
print("=== MCL-related selectors on PowerUISmartChargeClient ===")
var count: UInt32 = 0
if let methods = class_copyMethodList(cls, &count) {
    var names: [String] = []
    for i in 0..<Int(count) {
        let n = NSStringFromSelector(method_getName(methods[i]))
        if n.lowercased().contains("mcl") || n.lowercased().contains("limit") { names.append(n) }
    }
    free(methods)
    for n in names.sorted() { print("  \(n)") }
}
