//
//  SystemFirmware.swift
//
//
//  The Mac's firmware identity, e.g. "mBoot-18000.161.9".
//
//  This is an OPAQUE token. Log it, cache on it, compare it for equality — never
//  parse it for meaning and never branch on its contents. Firmware versions do not
//  map cleanly onto macOS releases (26.6, 15.7.8 and 14.8.8 all ship the same
//  firmware), and the prefix changed from "iBoot-" to "mBoot-" in macOS 26.4.
//

import Foundation
import IOKit

public enum SystemFirmware {
    /// Reads the firmware token from the device tree. No root or entitlement needed.
    public static func version() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/chosen")
        guard entry != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(entry) }

        for key in ["system-firmware-version", "firmware-version"] {
            guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() else { continue }
            if let string = value as? String, !string.isEmpty { return string }
            if let data = value as? Data, let parsed = parse(data) { return parsed }
        }
        return nil
    }

    /// `firmware-version` is a fixed-size NUL-padded buffer; truncate at the first NUL.
    public static func parse(_ data: Data) -> String? {
        let bytes = data.prefix(while: { $0 != 0 })
        guard !bytes.isEmpty, let string = String(data: bytes, encoding: .utf8), !string.isEmpty else {
            return nil
        }
        return string
    }
}
