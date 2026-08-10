// Tests whether `allowMCLOverride` in the `com.apple.smartcharging.topoffprotection`
// preference domain unlocks sub-80 charge limits in PowerUI.
//
// Rationale: PowerUIAgent (pid = owner of the ChargeCtrlPolicy in
// com.apple.powerd.charging) is the ONLY binary on the system that references the
// string `allowMCLOverride`, and it sits directly beside the
// `com.apple.smartcharging.topoffprotection` domain string. AlDente writes defaults
// into that domain, posts `com.apple.smartcharging.defaultschanged`, then calls
// setMCLLimit: -- and removes the key afterwards, which is why setMCLLimit(78) is
// refused even while 78 is in force.
//
// The (user, host) scope PowerUIAgent reads with is unknown, so ALL FOUR
// combinations are tried; a wrong guess must not produce a false negative.
//
// Requires root. Run `--revert` to remove the key and restore a 100% limit.
//
//   swiftc -O mcloverride.swift -o mcloverride
//   sudo ./mcloverride 70
//   sudo ./mcloverride --revert

import Foundation
import ObjectiveC

let domain = "com.apple.smartcharging.topoffprotection" as CFString
let overrideKey = "allowMCLOverride" as CFString
let notification = "com.apple.smartcharging.defaultschanged"

let scopes: [(String, CFString, CFString)] = [
    ("anyUser/anyHost", kCFPreferencesAnyUser, kCFPreferencesAnyHost),
    ("anyUser/currentHost", kCFPreferencesAnyUser, kCFPreferencesCurrentHost),
    ("currentUser/anyHost", kCFPreferencesCurrentUser, kCFPreferencesAnyHost),
    ("currentUser/currentHost", kCFPreferencesCurrentUser, kCFPreferencesCurrentHost),
]

// MARK: - PowerUI client

guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI",
             RTLD_NOW | RTLD_GLOBAL) != nil else {
    print("FATAL: cannot dlopen PowerUI"); exit(1)
}
guard let cls = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type,
      let allocated = cls.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
      let client = allocated.perform(NSSelectorFromString("initWithClientName:"),
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

func isEnabled() -> Bool {
    let sel = NSSelectorFromString("isMCLCurrentlyEnabled:")
    guard let m = class_getInstanceMethod(cls, sel) else { return false }
    typealias F = @convention(c) (AnyObject, Selector,
                                  AutoreleasingUnsafeMutablePointer<NSError?>?) -> ObjCBool
    var e: NSError?
    return unsafeBitCast(method_getImplementation(m), to: F.self)(client, sel, &e).boolValue
}

func enableMCL(_ on: Bool) -> String {
    let sel = NSSelectorFromString("enableMCL:")
    guard let m = class_getInstanceMethod(cls, sel) else { return "<selector absent>" }
    typealias F = @convention(c) (AnyObject, Selector,
                                  AutoreleasingUnsafeMutablePointer<NSError?>?) -> ObjCBool
    var e: NSError?
    let ok = unsafeBitCast(method_getImplementation(m), to: F.self)(client, sel, &e).boolValue
    return ok ? "ok" : "FAILED (\(e?.localizedDescription ?? "no error"))"
}

/// Returns nil on success, or a short description of the refusal.
func setLimit(_ value: Int) -> String? {
    let sel = NSSelectorFromString("setMCLLimit:error:")
    guard let m = class_getInstanceMethod(cls, sel) else { return "<selector absent>" }
    typealias F = @convention(c) (AnyObject, Selector, UInt8,
                                  AutoreleasingUnsafeMutablePointer<NSError?>?) -> ObjCBool
    var e: NSError?
    let ok = unsafeBitCast(method_getImplementation(m), to: F.self)(
        client, sel, UInt8(value), &e)
    if ok.boolValue { return nil }
    if let e { return "\(e.domain) code=\(e.code)" }
    return "returned false, no NSError"
}

// MARK: - Preference plumbing

func writeOverride(_ on: Bool?, user: CFString, host: CFString) {
    let value: CFPropertyList? = on.map { $0 ? kCFBooleanTrue : kCFBooleanFalse }
    CFPreferencesSetValue(overrideKey, value, domain, user, host)
    CFPreferencesSynchronize(domain, user, host)
}

func poke() {
    // Equivalent to notify_post(3); notify.h is not exposed to Swift directly.
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(notification as CFString), nil, nil, true)
    usleep(400_000)
}

// MARK: - Main

guard geteuid() == 0 else {
    print("FATAL: must run as root (sudo)."); exit(1)
}

if CommandLine.arguments.contains("--revert") {
    for (name, user, host) in scopes {
        writeOverride(nil, user: user, host: host)
        print("cleared allowMCLOverride in \(name)")
    }
    poke()
    print("setMCLLimit(100) -> \(setLimit(100).map { "REFUSED: \($0)" } ?? "OK")")
    poke()
    print("getMCLLimit = \(getLimit())")
    exit(0)
}

let target = Int(CommandLine.arguments.dropFirst().first(where: { Int($0) != nil }) ?? "") ?? 70
guard (20...100).contains(target) else { print("target out of range"); exit(1) }

print("euid            = \(geteuid())")
print("MCL enabled     = \(isEnabled())")
print("getMCLLimit     = \(getLimit())   (before)")
print("target          = \(target)")
print("")

print("--- control: setMCLLimit(\(target)) with NO override flag ---")
print("  result: \(setLimit(target).map { "REFUSED: \($0)" } ?? "ACCEPTED")")
print("  getMCLLimit = \(getLimit())")
print("")

if !isEnabled() {
    print("MCL was disabled; enableMCL: -> \(enableMCL(true))")
    print("")
}

for (name, user, host) in scopes {
    print("--- scope \(name) ---")
    writeOverride(true, user: user, host: host)
    let readBack = CFPreferencesCopyValue(overrideKey, domain, user, host)
    print("  wrote allowMCLOverride=true, read back: \(readBack.map { "\($0)" } ?? "nil")")
    poke()
    let refusal = setLimit(target)
    print("  setMCLLimit(\(target)): \(refusal.map { "REFUSED: \($0)" } ?? "ACCEPTED")")
    poke()
    let now = getLimit()
    print("  getMCLLimit = \(now)")
    if refusal == nil, now == target {
        print("")
        print("*** SUCCESS: sub-80 limit \(target) accepted and in force via \(name) ***")
        exit(0)
    }
    // Leave a clean slate before trying the next scope.
    writeOverride(nil, user: user, host: host)
    poke()
    print("")
}

print("No scope unlocked a sub-80 limit. allowMCLOverride alone is not sufficient.")
print("final getMCLLimit = \(getLimit())")
