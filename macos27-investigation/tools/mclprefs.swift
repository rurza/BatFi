// Sets a sub-80 charge limit through the preference channel AlDente actually uses.
//
// Recovered by disassembling AlDente 1.39b3's `setChargeLimit264` (app 0x1001fb53c..)
// and decoding the Swift small-string literals built with movz/movk -- which never
// appear in `strings`, which is why earlier candidate-key lists missed them:
//
//   x8 = 0x74696d694c6c636d + x1 "Value", count 13  ->  "mclLimitValue"
//   x8 = 0x75746165464c434d + x1 "reState", count 15 -> "MCLFeatureState"
//
// Sequence AlDente performs:
//   1. write  mclLimitValue   = <target>   in com.apple.smartcharging.topoffprotection
//   2. write  MCLFeatureState = 1          in the same domain
//   3. post   com.apple.smartcharging.defaultschanged
//   4. call   PowerUI setMCLLimit / enableMCL
//
// PowerUIAgent (the process that owns the ChargeCtrlPolicy carrying `soclimit`)
// re-reads the domain on that notification. The preference scope PowerUIAgent
// reads with is unknown, so all four (user, host) combinations are tried.
//
//   swiftc -O mclprefs.swift -o mclprefs
//   sudo ./mclprefs 72
//   sudo ./mclprefs --off

import Foundation
import ObjectiveC

let domain = "com.apple.smartcharging.topoffprotection" as CFString
let limitKey = "mclLimitValue" as CFString
let stateKey = "MCLFeatureState" as CFString
let notification = "com.apple.smartcharging.defaultschanged"

let scopes: [(String, CFString, CFString)] = [
    ("anyUser/anyHost", kCFPreferencesAnyUser, kCFPreferencesAnyHost),
    ("anyUser/currentHost", kCFPreferencesAnyUser, kCFPreferencesCurrentHost),
    ("currentUser/anyHost", kCFPreferencesCurrentUser, kCFPreferencesAnyHost),
    ("currentUser/currentHost", kCFPreferencesCurrentUser, kCFPreferencesCurrentHost),
]

guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI",
             RTLD_NOW | RTLD_GLOBAL) != nil else {
    print("FATAL: cannot dlopen PowerUI"); exit(1)
}
guard let cls = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type,
      let client = cls.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
        .perform(NSSelectorFromString("initWithClientName:"),
                 with: "AlDente" as NSString)?.takeUnretainedValue() else {
    print("FATAL: cannot create PowerUISmartChargeClient"); exit(1)
}

func getLimit() -> Int {
    let sel = NSSelectorFromString("getMCLLimitWithError:")
    guard let m = class_getInstanceMethod(cls, sel) else { return -1 }
    typealias F = @convention(c) (AnyObject, Selector,
                                  AutoreleasingUnsafeMutablePointer<NSError?>?) -> UInt8
    var e: NSError?
    return Int(unsafeBitCast(method_getImplementation(m), to: F.self)(client, sel, &e))
}

func setLimit(_ v: Int) -> String {
    let sel = NSSelectorFromString("setMCLLimit:error:")
    guard let m = class_getInstanceMethod(cls, sel) else { return "<absent>" }
    typealias F = @convention(c) (AnyObject, Selector, UInt8,
                                  AutoreleasingUnsafeMutablePointer<NSError?>?) -> ObjCBool
    var e: NSError?
    let ok = unsafeBitCast(method_getImplementation(m), to: F.self)(client, sel, UInt8(v), &e)
    return ok.boolValue ? "ACCEPTED" : "REFUSED \(e?.domain ?? "?") code=\(e?.code ?? -1)"
}

func enableMCL() -> String {
    let sel = NSSelectorFromString("enableMCL:")
    guard let m = class_getInstanceMethod(cls, sel) else { return "<absent>" }
    typealias F = @convention(c) (AnyObject, Selector,
                                  AutoreleasingUnsafeMutablePointer<NSError?>?) -> ObjCBool
    var e: NSError?
    let ok = unsafeBitCast(method_getImplementation(m), to: F.self)(client, sel, &e).boolValue
    return ok ? "ok" : "failed(\(e?.localizedDescription ?? "-"))"
}

func poke() {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(notification as CFString), nil, nil, true)
    usleep(600_000)
}

func write(_ key: CFString, _ value: CFPropertyList?, _ user: CFString, _ host: CFString) {
    CFPreferencesSetValue(key, value, domain, user, host)
    CFPreferencesSynchronize(domain, user, host)
}

guard geteuid() == 0 else { print("FATAL: must run as root (sudo)."); exit(1) }

if CommandLine.arguments.contains("--off") {
    for (name, user, host) in scopes {
        write(limitKey, nil, user, host)
        write(stateKey, nil, user, host)
        print("cleared \(name)")
    }
    poke()
    print("setMCLLimit(100) -> \(setLimit(100))")
    poke()
    print("getMCLLimit = \(getLimit())")
    exit(0)
}

let target = Int(CommandLine.arguments.dropFirst().first(where: { Int($0) != nil }) ?? "") ?? 72
guard (20 ... 100).contains(target) else { print("target out of range"); exit(1) }

print("getMCLLimit = \(getLimit())  (before)")
print("target      = \(target)")
print("")

for (name, user, host) in scopes {
    print("--- scope \(name) ---")
    write(limitKey, target as CFNumber, user, host)
    write(stateKey, 1 as CFNumber, user, host)
    let rl = CFPreferencesCopyValue(limitKey, domain, user, host)
    let rs = CFPreferencesCopyValue(stateKey, domain, user, host)
    print("  mclLimitValue=\(rl.map { "\($0)" } ?? "nil")  MCLFeatureState=\(rs.map { "\($0)" } ?? "nil")")
    poke()
    print("  getMCLLimit after notification = \(getLimit())")
    print("  enableMCL: \(enableMCL())")
    print("  setMCLLimit(\(target)): \(setLimit(target))")
    poke()
    let now = getLimit()
    print("  getMCLLimit = \(now)")
    if now == target {
        print("")
        print("*** SUCCESS: sub-80 limit \(target) in force via \(name) ***")
        print("Verify with: pmset -g batt   (expect 'AC attached; not charging')")
        exit(0)
    }
    write(limitKey, nil, user, host)
    write(stateKey, nil, user, host)
    poke()
    print("")
}

print("No scope worked. final getMCLLimit = \(getLimit())")
