// Minimal sub-80 charge limit on macOS 27, via the channel AlDente actually uses.
//
// CONFIRMED MECHANISM (measured 2026-08-10 on Mac15,8 / 26A5388g):
//
//   As root, in preference domain `com.apple.smartcharging.topoffprotection`,
//   scope (kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) -- "current user"
//   is root, because PowerUIAgent runs as root and reads root's domain:
//
//       mclLimitValue   = <target>      (Int)
//       MCLFeatureState = 1             (Int)
//
//   then post the Darwin notification `com.apple.smartcharging.defaultschanged`.
//
//   PowerUIAgent (/usr/libexec/PowerUIAgent) re-reads the domain and registers a
//   ChargeCtrlPolicy { soclimit: <target>, reason: "manualChargeLimit", owner: 510 }
//   which powerd serialises into /Library/Preferences/com.apple.powerd.charging.plist.
//
// PowerUI's `setMCLLimit:` is NOT part of this and is refused for every sub-80
// value (PowerUISmartChargingErrorDomain code=4) -- including while a sub-80 limit
// is already in force. It floors at 80 and always will; it is a red herring.
//
// The two key names are Swift small-string literals in AlDente's binary, built with
// movz/movk, so they never appear in `strings` output:
//   0x74696d694c6c636d + "Value"   (count 13) -> "mclLimitValue"
//   0x75746165464c434d + "reState" (count 15) -> "MCLFeatureState"
//
//   swiftc -O mclset.swift -o mclset
//   sudo ./mclset 72          # apply
//   sudo ./mclset --off       # clear (restores unlimited charging)
//   sudo ./mclset --status    # report only

import Foundation
import ObjectiveC

let domain = "com.apple.smartcharging.topoffprotection" as CFString
let limitKey = "mclLimitValue" as CFString
let stateKey = "MCLFeatureState" as CFString
let notification = "com.apple.smartcharging.defaultschanged"
let user = kCFPreferencesCurrentUser
let host = kCFPreferencesCurrentHost

func post() {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(notification as CFString), nil, nil, true)
}

/// The soclimit powerd currently has in force, if any. This is the real proof that
/// a limit is applied -- reading back the preference only proves we wrote it.
func activeSocLimit() -> Int? {
    guard let data = FileManager.default.contents(
            atPath: "/Library/Preferences/com.apple.powerd.charging.plist"),
          let top = try? PropertyListSerialization.propertyList(
            from: data, format: nil) as? [String: Any],
          let blob = top["policies"] as? Data,
          let arch = try? PropertyListSerialization.propertyList(
            from: blob, format: nil) as? [String: Any],
          let objects = arch["$objects"] as? [Any] else { return nil }
    for o in objects {
        if let d = o as? [String: Any], let soc = d["soclimit"] as? Int { return soc }
    }
    return nil
}

func report(_ label: String) {
    let limit = CFPreferencesCopyValue(limitKey, domain, user, host)
    let state = CFPreferencesCopyValue(stateKey, domain, user, host)
    print("\(label):")
    print("  prefs   mclLimitValue=\(limit.map { "\($0)" } ?? "unset") "
          + "MCLFeatureState=\(state.map { "\($0)" } ?? "unset")")
    print("  powerd  soclimit=\(activeSocLimit().map { "\($0)" } ?? "none")")
}

// MARK: - PowerUI, used ONLY to toggle the feature on/off for the --strict experiment

func mclClient() -> AnyObject? {
    guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI",
                 RTLD_NOW | RTLD_GLOBAL) != nil,
          let cls = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type else { return nil }
    return cls.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
        .perform(NSSelectorFromString("initWithClientName:"),
                 with: "AlDente" as NSString)?.takeUnretainedValue()
}

func mclBool(_ name: String) -> Bool {
    guard let client = mclClient(),
          let m = class_getInstanceMethod(type(of: client), NSSelectorFromString(name))
    else { return false }
    typealias F = @convention(c) (AnyObject, Selector,
                                  AutoreleasingUnsafeMutablePointer<NSError?>?) -> ObjCBool
    var e: NSError?
    return unsafeBitCast(method_getImplementation(m), to: F.self)(
        client, NSSelectorFromString(name), &e).boolValue
}

guard geteuid() == 0 else { print("FATAL: must run as root (sudo)."); exit(1) }

let args = CommandLine.arguments.dropFirst()

// Determines whether the two preference keys plus the notification are sufficient on their
// own, or whether Apple's charge-limit feature must additionally be switched on via PowerUI.
// Starts from a deliberately hostile state: feature OFF and no preferences at all.
if args.contains("--strict") {
    guard let target = args.compactMap({ Int($0) }).first else {
        print("usage: mclset --strict <20-100>"); exit(1)
    }
    print("clearing prefs and disabling MCL first...")
    CFPreferencesSetValue(limitKey, nil, domain, user, host)
    CFPreferencesSetValue(stateKey, nil, domain, user, host)
    CFPreferencesSynchronize(domain, user, host)
    print("  disableMCL: \(mclBool("disableMCL:"))")
    post()
    usleep(1_500_000)
    print("  isMCLCurrentlyEnabled=\(mclBool("isMCLCurrentlyEnabled:")) "
          + "soclimit=\(activeSocLimit().map { "\($0)" } ?? "none")")

    // Without this the test can pass by doing nothing: if powerd is already holding the
    // target, the poll below exits on its first read and reports success for a value the
    // preferences never had to set. A confirming read is not a result.
    if activeSocLimit() == target {
        print("""

        ABORT: powerd is already holding \(target), so this test could only confirm itself.
        Re-run with a different target, e.g. `--strict \(target > 60 ? target - 7 : target + 7)`.
        """)
        exit(1)
    }

    print("\nstep 1 — preferences + notification ONLY (no enableMCL, no setMCLLimit):")
    CFPreferencesSetValue(limitKey, target as CFNumber, domain, user, host)
    CFPreferencesSetValue(stateKey, 1 as CFNumber, domain, user, host)
    CFPreferencesSynchronize(domain, user, host)
    post()
    for _ in 0 ..< 12 where activeSocLimit() != target { usleep(500_000) }
    let afterPrefs = activeSocLimit()
    print("  soclimit=\(afterPrefs.map { "\($0)" } ?? "none")  "
          + "isMCLCurrentlyEnabled=\(mclBool("isMCLCurrentlyEnabled:"))")

    if afterPrefs == target {
        print("\nRESULT: preferences + notification are SUFFICIENT. enableMCL not required.")
        exit(0)
    }

    print("\nstep 2 — now also enableMCL:")
    print("  enableMCL: \(mclBool("enableMCL:"))")
    post()
    for _ in 0 ..< 12 where activeSocLimit() != target { usleep(500_000) }
    print("  soclimit=\(activeSocLimit().map { "\($0)" } ?? "none")")
    print(activeSocLimit() == target
          ? "\nRESULT: enableMCL IS required in addition to the preferences."
          : "\nRESULT: neither worked from a disabled start — something else is involved.")
    exit(0)
}

if args.contains("--status") {
    report("status")
    exit(0)
}

if args.contains("--off") {
    report("before")
    CFPreferencesSetValue(limitKey, nil, domain, user, host)
    CFPreferencesSetValue(stateKey, nil, domain, user, host)
    CFPreferencesSynchronize(domain, user, host)
    post()
    usleep(1_500_000)
    report("after clearing")
    exit(0)
}

guard let target = args.compactMap({ Int($0) }).first, (20 ... 100).contains(target) else {
    print("usage: mclset <20-100> | --off | --status"); exit(1)
}

report("before")
CFPreferencesSetValue(limitKey, target as CFNumber, domain, user, host)
CFPreferencesSetValue(stateKey, 1 as CFNumber, domain, user, host)
CFPreferencesSynchronize(domain, user, host)
post()

// PowerUIAgent needs a moment to re-read and register the policy.
for _ in 0 ..< 10 {
    usleep(500_000)
    if activeSocLimit() == target { break }
}
report("after applying \(target)")

if activeSocLimit() == target {
    print("\nOK: powerd is enforcing soclimit=\(target).")
} else {
    print("\nNOT APPLIED: powerd has no matching policy.")
}
