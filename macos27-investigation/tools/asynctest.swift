// Tests the *handler* variants of the PowerUI charge-limit selectors, which are
// separate entry points from the error: ones and may validate differently.
import Foundation
import ObjectiveC

guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW | RTLD_GLOBAL) != nil,
      let cls = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type,
      let alloc = cls.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
      let client = alloc.perform(NSSelectorFromString("initWithClientName:"),
                                 with: "AlDente" as NSString)?.takeUnretainedValue()
else { print("FATAL"); exit(1) }

func getLimit() -> Int {
    let sel = NSSelectorFromString("getMCLLimitWithError:")
    guard let m = class_getInstanceMethod(cls, sel) else { return -1 }
    typealias F = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> UInt8
    let f = unsafeBitCast(method_getImplementation(m), to: F.self)
    var e: NSError?
    return Int(f(client, sel, &e))
}

let target: UInt8 = UInt8(CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 70 : 70)
print("start limit = \(getLimit()), target = \(target)")

let sem = DispatchSemaphore(value: 0)

// setMCLLimit:withHandler:
if let m = class_getInstanceMethod(cls, NSSelectorFromString("setMCLLimit:withHandler:")) {
    typealias F = @convention(c) (AnyObject, Selector, UInt8, @convention(block) (ObjCBool, NSError?) -> Void) -> Void
    let f = unsafeBitCast(method_getImplementation(m), to: F.self)
    f(client, NSSelectorFromString("setMCLLimit:withHandler:"), target, { ok, err in
        print("setMCLLimit:withHandler: ok=\(ok.boolValue) err=\(err.map { "\($0.domain) code=\($0.code)" } ?? "none")")
        sem.signal()
    })
    _ = sem.wait(timeout: .now() + 5)
} else { print("setMCLLimit:withHandler: selector absent") }
print("  limit now = \(getLimit())")

// temporarilyOverrideMCLTargetSoC:withHandler:
if let m = class_getInstanceMethod(cls, NSSelectorFromString("temporarilyOverrideMCLTargetSoC:withHandler:")) {
    typealias F = @convention(c) (AnyObject, Selector, UInt8, @convention(block) (ObjCBool, NSError?) -> Void) -> Void
    let f = unsafeBitCast(method_getImplementation(m), to: F.self)
    f(client, NSSelectorFromString("temporarilyOverrideMCLTargetSoC:withHandler:"), target, { ok, err in
        print("temporarilyOverrideMCLTargetSoC:withHandler: ok=\(ok.boolValue) err=\(err.map { "\($0.domain) code=\($0.code)" } ?? "none")")
        sem.signal()
    })
    _ = sem.wait(timeout: .now() + 5)
} else { print("override:withHandler: selector absent") }
print("  limit now = \(getLimit())")

// enableMCL: — does enabling take a value or just a bool?
for name in ["enableMCL:", "enableMCLWithHandler:"] {
    if let m = class_getInstanceMethod(cls, NSSelectorFromString(name)) {
        let enc = method_getTypeEncoding(m).map { String(cString: $0) } ?? "?"
        print("\(name) exists, type encoding = \(enc)")
    }
}
