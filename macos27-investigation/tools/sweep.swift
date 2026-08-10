// Probes which values setMCLLimit: actually accepts, then restores the original.
// Writes the user-visible charge limit transiently; restores to the value found at start.
import Foundation
import ObjectiveC

guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW | RTLD_GLOBAL) != nil,
      let cls = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type,
      let alloc = cls.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
      let client = alloc.perform(NSSelectorFromString("initWithClientName:"),
                                 with: (CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AlDente") as NSString)?.takeUnretainedValue()
else { print("FATAL: PowerUI unavailable"); exit(1) }

print("clientName = \(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AlDente")")

func getLimit() -> Int {
    let sel = NSSelectorFromString("getMCLLimitWithError:")
    guard let m = class_getInstanceMethod(cls, sel) else { return -1 }
    typealias F = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> UInt8
    let f = unsafeBitCast(method_getImplementation(m), to: F.self)
    var e: NSError?
    return Int(f(client, sel, &e))
}
func setLimit(_ v: Int) -> String {
    let sel = NSSelectorFromString("setMCLLimit:error:")
    guard let m = class_getInstanceMethod(cls, sel) else { return "selector absent" }
    typealias F = @convention(c) (AnyObject, Selector, UInt8, AutoreleasingUnsafeMutablePointer<NSError?>?) -> ObjCBool
    let f = unsafeBitCast(method_getImplementation(m), to: F.self)
    var e: NSError?
    let ok = f(client, sel, UInt8(v), &e).boolValue
    if let e { return "REFUSED (code \(e.code))" }
    return ok ? "accepted" : "returned false"
}

let original = getLimit()
print("original limit = \(original)")
print("")
for v in [78, 75, 70, 65, 60, 55, 50, 40, 30, 20] {
    let r = setLimit(v)
    let readBack = getLimit()
    print(String(format: "setMCLLimit(%3d) -> %-20@  getMCLLimit=%d", v, r as NSString, readBack))
}
print("")
print("restoring \(original): \(setLimit(original)); now \(getLimit())")
