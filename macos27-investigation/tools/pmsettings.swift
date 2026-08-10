// READ-ONLY. Dumps powerd's system power settings and IOPMrootDomain properties,
// looking for whatever currently encodes the sub-80 charge limit.
import Foundation
import IOKit
import IOKit.pwr_mgt

print("")
print("=== IOPMrootDomain properties mentioning charge/limit/soc/battery ===")
let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
if root != 0 {
    var props: Unmanaged<CFMutableDictionary>?
    if IORegistryEntryCreateCFProperties(root, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
       let d = props?.takeRetainedValue() as? [String: Any] {
        let interesting = d.filter { k, _ in
            let l = k.lowercased()
            return l.contains("charg") || l.contains("limit") || l.contains("soc")
                || l.contains("batt") || l.contains("mcl")
        }
        if interesting.isEmpty {
            print("  (none matched). All \(d.count) property names:")
            print("  " + d.keys.sorted().joined(separator: ", "))
        } else {
            for (k, v) in interesting.sorted(by: { $0.key < $1.key }) { print("  \(k) = \(v)") }
        }
    }
    IOObjectRelease(root)
} else { print("  IOPMrootDomain not found") }

print("")
print("=== AppleSmartBattery properties mentioning charge/limit ===")
let batt = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
if batt != 0 {
    var props: Unmanaged<CFMutableDictionary>?
    if IORegistryEntryCreateCFProperties(batt, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
       let d = props?.takeRetainedValue() as? [String: Any] {
        for (k, v) in d.sorted(by: { $0.key < $1.key })
        where k.lowercased().contains("charg") || k.lowercased().contains("limit") {
            print("  \(k) = \(v)")
        }
    }
    IOObjectRelease(batt)
} else { print("  AppleSmartBattery not found") }
