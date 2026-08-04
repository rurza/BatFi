# Phase 2 — Firmware Capability Probing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop choosing the SMC charge-control mechanism by exception-on-write, and start choosing it by probing key metadata — so a firmware change picks the right path (or reports honestly) instead of silently doing nothing.

**Architecture:** The helper probes `kSMCGetKeyInfo` for type, size **and attributes**, and feeds a dictionary of capabilities to a pure resolver in `Shared` that returns a `ChargeBackend`. The result is cached against the machine's firmware token and invalidated when that token changes — which is what handles "upgrade macOS, get new firmware, downgrade macOS". Behaviour on today's firmware is unchanged.

**Tech Stack:** Swift 6, SwiftPM (`BatFiKit`), swift-testing, IOKit `AppleSMC` user client, NSXPC.

## Global Constraints

- **Swift 6 language mode** for all targets.
- **Never gate SMC behaviour on the macOS version.** No `#available`, `@available`, or `operatingSystemVersion` may select an SMC path. Firmware moves independently of macOS: installing macOS 27 on any volume reflashes firmware for the whole Mac, downgrading macOS does not roll it back, and macOS 26.6 / 15.7.8 / 14.8.8 ship identical firmware. This is the entire point of the phase.
- **The firmware token is opaque.** Log it, cache on it, compare it for equality. Never parse it, never order it, never branch on its contents. The prefix changed from `iBoot-` to `mBoot-` in macOS 26.4.
- **Probing must run in the helper (root).** `CH0J`, `CHLS` and `BDFU` return `kIOReturnNotPrivileged` from `kSMCGetKeyInfo` for an unprivileged caller, so an app-side probe would wrongly conclude they are absent.
- **Never `print()`** — `os.Logger` only. **No force-unwraps.**
- **Do not change behaviour on existing firmware.** A machine that works today must take the same code path and write the same bytes afterwards.
- **Commit messages must never mention Claude** and must not carry `Co-Authored-By` or `Generated with` trailers.

## File Structure

| File | Responsibility |
|---|---|
| `BatFiKit/Sources/Shared/ChargeBackend.swift` | **new** — `ChargeBackend`, `SMCKeyCapability`, pure `ChargeBackendResolver`. No IOKit. |
| `BatFiKit/Sources/Shared/SystemFirmware.swift` | **new** — firmware token read + pure `parse(_:)`. Shared by app and helper. |
| `BatFiKit/Sources/Shared/ChargingDiagnostics.swift` | **new** — XPC-transportable diagnostics snapshot |
| `BatFiKit/Sources/Server/SMC+Probe.swift` | **new** — `SMCKeyProbeInfo`, `SMCKeyProbeResult`, `SMCKit.probe(_:)`, `supports(...)` |
| `BatFiKit/Sources/Server/SMCService.swift` | backend cache + dispatch, `CHNC` decode, diagnostics |
| `BatFiKit/Sources/Server/PowerUICharging.swift` | `isMCLSupported` capability gate |
| `BatFiKit/Sources/Server/Listener.swift`, `Shared/XPCService.swift` | new `getChargingDiagnostics` method |
| `BatFiKit/Sources/ClientsLive/PowerSourceClient+Live.swift` | use `Shared.SystemFirmware` instead of its private copy |
| `BatFiKit/Tests/AppSharedTests/…` | resolver + firmware-parse + CHNC-decode tests |
| `BatFiKit/Package.swift` | add `.shared` to `AppSharedTests` deps |

**Verification commands** (CLI `swift build`/`swift test` do NOT work in this repo — SwiftPM does not synthesise `Bundle.module` for the package's resources and a third-party dependency hits the same bug; do not attempt them and do not modify `Package.swift` to try to fix it):

```
xcodebuild test  -project BatFi.xcodeproj -scheme AppSharedTests -destination 'platform=macOS'
xcodebuild build -project BatFi.xcodeproj -scheme Server        -destination 'platform=macOS'
xcodebuild build -project BatFi.xcodeproj -scheme BatFi         -destination 'platform=macOS'
```

Baseline entering this phase: **35 tests / 7 suites**. A gitignored `BatFiKit/Sources/ClientsLive/AnalyticsDSN.swift` exists locally so the app compiles — leave it alone, never commit it.

---

### Task 1: Pure `ChargeBackend` resolver in `Shared`

Put the mechanism-selection policy in a dependency-free target so it is testable without IOKit or root.

**Files:**
- Create: `BatFiKit/Sources/Shared/ChargeBackend.swift`
- Test: `BatFiKit/Tests/AppSharedTests/ChargeBackendResolverTests.swift`
- Modify: `BatFiKit/Package.swift:292` — add `.shared` to `AppSharedTests` dependencies

**Interfaces:**
- Produces: `public enum ChargeBackend: String, Sendable, CaseIterable` — cases `chte`, `legacyCH0BC`, `unsupported`.
  `public struct SMCKeyCapability: Sendable, Equatable` — `code: String`, `type: String`, `size: UInt32`, `isReadable: Bool`, `isWritable: Bool`.
  `public enum ChargeBackendResolver` — `static func resolve(_ capabilities: [String: SMCKeyCapability]) -> ChargeBackend`.

- [ ] **Step 1: Add `.shared` to the test target**

`BatFiKit/Package.swift`, the `AppSharedTests` target:

```swift
            dependencies: [.appShared, .shared],
```

- [ ] **Step 2: Write the failing tests**

Create `BatFiKit/Tests/AppSharedTests/ChargeBackendResolverTests.swift`:

```swift
//
//  ChargeBackendResolverTests.swift
//  BatFi
//
//  Mechanism selection must follow the firmware's own key table, never the macOS
//  version. These cases encode the three firmware generations plus the traps that
//  a naive "does the key exist?" probe walks into.
//

import Foundation
import Testing

@testable import Shared

@Suite struct ChargeBackendResolverTests {
    private func cap(_ code: String, _ type: String, _ size: UInt32,
                     readable: Bool = true, writable: Bool = true) -> SMCKeyCapability {
        SMCKeyCapability(code: code, type: type, size: size, isReadable: readable, isWritable: writable)
    }

    private func table(_ caps: [SMCKeyCapability]) -> [String: SMCKeyCapability] {
        Dictionary(uniqueKeysWithValues: caps.map { ($0.code, $0) })
    }

    /// Tahoe-era firmware: CHTE present as a writable ui32.
    @Test func selectsCHTEWhenPresentAndWritable() {
        let caps = table([cap("CHTE", "ui32", 4)])
        #expect(ChargeBackendResolver.resolve(caps) == .chte)
    }

    /// Legacy firmware: the CH0B/CH0C pair.
    @Test func selectsLegacyWhenBothLegacyKeysPresent() {
        let caps = table([cap("CH0B", "ui8 ", 1), cap("CH0C", "ui8 ", 1)])
        #expect(ChargeBackendResolver.resolve(caps) == .legacyCH0BC)
    }

    /// CHTE outranks the legacy pair when a firmware exposes both.
    @Test func chteOutranksLegacy() {
        let caps = table([cap("CHTE", "ui32", 4), cap("CH0B", "ui8 ", 1), cap("CH0C", "ui8 ", 1)])
        #expect(ChargeBackendResolver.resolve(caps) == .chte)
    }

    /// Only one half of the legacy pair is not a usable mechanism.
    @Test func legacyRequiresBothKeys() {
        #expect(ChargeBackendResolver.resolve(table([cap("CH0B", "ui8 ", 1)])) == .unsupported)
        #expect(ChargeBackendResolver.resolve(table([cap("CH0C", "ui8 ", 1)])) == .unsupported)
    }

    /// Wrong size must not be accepted even when the name matches.
    @Test func rejectsCHTEWithWrongSize() {
        #expect(ChargeBackendResolver.resolve(table([cap("CHTE", "ui32", 2)])) == .unsupported)
    }

    /// Wrong type must not be accepted even when name and size match.
    @Test func rejectsCHTEWithWrongType() {
        #expect(ChargeBackendResolver.resolve(table([cap("CHTE", "hex_", 4)])) == .unsupported)
    }

    /// A read-only key cannot drive charging.
    @Test func rejectsNonWritableCHTE() {
        #expect(ChargeBackendResolver.resolve(table([cap("CHTE", "ui32", 4, writable: false)])) == .unsupported)
    }

    /// Zero-size placeholder keys are reported by some firmware and can be neither
    /// read nor written. They must not select a mechanism.
    @Test func rejectsZeroSizePlaceholder() {
        #expect(ChargeBackendResolver.resolve(table([cap("CHTE", "ui32", 0)])) == .unsupported)
    }

    @Test func emptyTableIsUnsupported() {
        #expect(ChargeBackendResolver.resolve([:]) == .unsupported)
    }

    /// Real capability table measured on a Mac15,8 / M3 Max, firmware mBoot-18000.161.9.
    /// Note bfD0 exists there as hex_/2 — an existence-only probe would false-positive
    /// on the macOS 27 mechanism. This must still resolve to .chte.
    @Test func realTahoeFirmwareTableResolvesToCHTE() {
        let caps = table([
            cap("CHTE", "ui32", 4),
            cap("CHIE", "hex_", 1),
            cap("ACLC", "ui8 ", 1),
            cap("bfD0", "hex_", 2, writable: false),
        ])
        #expect(ChargeBackendResolver.resolve(caps) == .chte)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `xcodebuild test -project BatFi.xcodeproj -scheme AppSharedTests -destination 'platform=macOS' -only-testing:AppSharedTests/ChargeBackendResolverTests`
Expected: FAIL — `cannot find 'SMCKeyCapability' in scope`.

- [ ] **Step 4: Write the implementation**

Create `BatFiKit/Sources/Shared/ChargeBackend.swift`:

```swift
//
//  ChargeBackend.swift
//
//
//  Which SMC mechanism this machine's firmware actually supports.
//
//  Deliberately free of IOKit and of any macOS version check. SMC behaviour tracks
//  firmware, which moves independently of the OS: installing a new macOS on any
//  volume reflashes firmware for the whole Mac, and downgrading macOS does not roll
//  it back. Selection is therefore driven only by what the key table reports.
//

import Foundation

public enum ChargeBackend: String, Sendable, CaseIterable {
    /// `CHTE` (ui32) — Tahoe-era firmware, first shipped in macOS 15.7.
    case chte
    /// `CH0B` + `CH0C` (ui8 pair) — pre-Tahoe firmware.
    case legacyCH0BC
    /// No usable mechanism. Report honestly rather than appearing to work.
    case unsupported

    public var isUsable: Bool { self != .unsupported }
}

/// One key as the firmware describes it. `type` is the raw four-character type
/// code (`ui32`, `ui8 `, `hex_`, …) exactly as reported, including trailing spaces.
public struct SMCKeyCapability: Sendable, Equatable {
    public let code: String
    public let type: String
    public let size: UInt32
    public let isReadable: Bool
    public let isWritable: Bool

    public init(code: String, type: String, size: UInt32, isReadable: Bool, isWritable: Bool) {
        self.code = code
        self.type = type
        self.size = size
        self.isReadable = isReadable
        self.isWritable = isWritable
    }

    /// Matching on name alone is unsafe: `bfD0` exists on Tahoe firmware as a
    /// read-only `hex_`/2 key with unrelated meaning, and some firmware exposes
    /// zero-size placeholders that can be neither read nor written.
    public func matches(type expectedType: String, size expectedSize: UInt32, writable: Bool) -> Bool {
        guard size > 0, size == expectedSize, self.type == expectedType else { return false }
        guard isReadable else { return false }
        return !writable || isWritable
    }
}

public enum ChargeBackendResolver {
    public static func resolve(_ capabilities: [String: SMCKeyCapability]) -> ChargeBackend {
        if capabilities["CHTE"]?.matches(type: "ui32", size: 4, writable: true) == true {
            return .chte
        }
        if capabilities["CH0B"]?.matches(type: "ui8 ", size: 1, writable: true) == true,
           capabilities["CH0C"]?.matches(type: "ui8 ", size: 1, writable: true) == true {
            return .legacyCH0BC
        }
        return .unsupported
    }

    /// Keys the helper must probe to resolve a backend.
    public static let probedKeys: [String] = ["CHTE", "CH0B", "CH0C", "CHIE", "CH0I", "CH0J"]
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -project BatFi.xcodeproj -scheme AppSharedTests -destination 'platform=macOS' -only-testing:AppSharedTests/ChargeBackendResolverTests`
Expected: PASS — 10 tests.

Then the full suite: `xcodebuild test -project BatFi.xcodeproj -scheme AppSharedTests -destination 'platform=macOS'` → 45 tests / 8 suites.

- [ ] **Step 6: Commit**

```bash
git add BatFiKit/Sources/Shared/ChargeBackend.swift BatFiKit/Tests/AppSharedTests/ChargeBackendResolverTests.swift BatFiKit/Package.swift
git commit -m "Add pure charge backend resolver driven by SMC key metadata

Mechanism selection now follows what the firmware's key table reports rather
than the macOS version. Matching requires type, size and writability, because
bfD0 exists on Tahoe firmware as an unrelated read-only hex_/2 key and some
firmware exposes zero-size placeholders that cannot be read or written."
```

---

### Task 2: Firmware token in `Shared`

Phase 1 put a firmware reader in `ClientsLive`. The helper needs the same value for its cache key, so move it to `Shared` and split the parsing out so it can be tested.

**Files:**
- Create: `BatFiKit/Sources/Shared/SystemFirmware.swift`
- Test: `BatFiKit/Tests/AppSharedTests/SystemFirmwareTests.swift`
- Modify: `BatFiKit/Sources/ClientsLive/PowerSourceClient+Live.swift` — delete its private `systemFirmwareVersion()` and call `SystemFirmware.version()`

**Interfaces:**
- Produces: `public enum SystemFirmware` — `static func version() -> String?` (IOKit) and `static func parse(_ data: Data) -> String?` (pure).

- [ ] **Step 1: Write the failing tests**

Create `BatFiKit/Tests/AppSharedTests/SystemFirmwareTests.swift`:

```swift
//
//  SystemFirmwareTests.swift
//  BatFi
//
//  The firmware token is an opaque cache key and diagnostic string. Only its
//  extraction from a fixed-size NUL-padded IORegistry buffer is testable.
//

import Foundation
import Testing

@testable import Shared

@Suite struct SystemFirmwareTests {
    @Test func parsesNULPaddedBuffer() {
        var bytes = Array("mBoot-18000.161.9".utf8)
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 239))
        #expect(SystemFirmware.parse(Data(bytes)) == "mBoot-18000.161.9")
    }

    @Test func parsesUnpaddedBuffer() {
        #expect(SystemFirmware.parse(Data("mBoot-18000.161.9".utf8)) == "mBoot-18000.161.9")
    }

    /// The prefix changed from iBoot- to mBoot- in macOS 26.4, which is exactly why
    /// the token is never parsed for meaning — both must come back verbatim.
    @Test func returnsPrefixVerbatim() {
        #expect(SystemFirmware.parse(Data("iBoot-11881.81.4".utf8)) == "iBoot-11881.81.4")
    }

    @Test func rejectsEmptyAndAllNUL() {
        #expect(SystemFirmware.parse(Data()) == nil)
        #expect(SystemFirmware.parse(Data([UInt8](repeating: 0, count: 256))) == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -project BatFi.xcodeproj -scheme AppSharedTests -destination 'platform=macOS' -only-testing:AppSharedTests/SystemFirmwareTests`
Expected: FAIL — `cannot find 'SystemFirmware' in scope`.

- [ ] **Step 3: Implement**

Create `BatFiKit/Sources/Shared/SystemFirmware.swift`:

```swift
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
```

- [ ] **Step 4: Replace the copy in `ClientsLive`**

In `BatFiKit/Sources/ClientsLive/PowerSourceClient+Live.swift`, delete the private `systemFirmwareVersion()` function and replace every call to it with `SystemFirmware.version()`. `ClientsLive` already depends on `Shared`; add `import Shared` only if it is not already present.

- [ ] **Step 5: Verify**

Run the filtered tests (4 pass), then the full suite (49 tests / 9 suites), then:
`xcodebuild build -project BatFi.xcodeproj -scheme BatFi -destination 'platform=macOS'`

- [ ] **Step 6: Commit**

```bash
git add BatFiKit/Sources/Shared/SystemFirmware.swift BatFiKit/Tests/AppSharedTests/SystemFirmwareTests.swift BatFiKit/Sources/ClientsLive/PowerSourceClient+Live.swift
git commit -m "Move the firmware token to Shared so the helper can use it

The helper needs the same identity string as its capability cache key. Splitting
the NUL-padded buffer parsing out makes that part testable."
```

---

### Task 3: `SMCKeyProbe` — surface the attributes byte

`SMCKit.keyInformation` already asks the SMC for `dataAttributes` and then discards it. That byte is what tells us whether a key is readable and writable.

**Files:**
- Create: `BatFiKit/Sources/Server/SMC+Probe.swift`

**Interfaces:**
- Consumes: `SMCKeyCapability`, `ChargeBackendResolver` (Task 1).
- Produces: `SMCKit.probeCapabilities(_ codes: [String]) -> [String: SMCKeyCapability]`.

- [ ] **Step 1: Implement**

Create `BatFiKit/Sources/Server/SMC+Probe.swift`:

```swift
//
//  SMC+Probe.swift
//  Helper
//
//  Capability probing via kSMCGetKeyInfo.
//
//  Must run in the privileged helper: CH0J, CHLS and BDFU return
//  kIOReturnNotPrivileged for an unprivileged caller, so an app-side probe would
//  wrongly conclude they are absent.
//

import Foundation
import Shared

extension SMCKit {
    /// Attribute bits, established by probing all 2802 keys on a Mac15,8:
    /// every key that reads has 0x80, every writable control key has 0x40.
    private enum Attribute {
        static let readable: UInt8 = 0x80
        static let writable: UInt8 = 0x40
    }

    /// Probes one key. Returns nil when the key is absent, privilege-gated, or a
    /// zero-size placeholder — none of which can drive charging.
    static func probeCapability(_ code: String) -> SMCKeyCapability? {
        var inputStruct = SMCParamStruct()
        inputStruct.key = FourCharCode(fromStaticString: code)
        inputStruct.data8 = SMCParamStruct.Selector.kSMCGetKeyInfo.rawValue

        guard let outputStruct = try? callDriver(&inputStruct) else { return nil }
        let info = outputStruct.keyInfo
        guard info.dataSize > 0 else { return nil }

        return SMCKeyCapability(
            code: code,
            type: info.dataType.toString(),
            size: info.dataSize,
            isReadable: info.dataAttributes & Attribute.readable != 0,
            isWritable: info.dataAttributes & Attribute.writable != 0
        )
    }

    static func probeCapabilities(_ codes: [String]) -> [String: SMCKeyCapability] {
        var table: [String: SMCKeyCapability] = [:]
        for code in codes {
            if let capability = probeCapability(code) { table[code] = capability }
        }
        return table
    }
}
```

If `FourCharCode(fromStaticString:)` does not accept a runtime `String`, add a runtime initialiser alongside it in the same file rather than changing the existing one, and say so in your report.

`info.dataType.toString()` must produce the raw four-character type including trailing spaces (`"ui8 "`, not `"ui8"`). `SMC.swift` already has a `FourCharCode.toString()`; verify it does not trim, and if it does, build the string explicitly from the four bytes here.

- [ ] **Step 2: Verify**

`xcodebuild build -project BatFi.xcodeproj -scheme Server -destination 'platform=macOS'` → BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add BatFiKit/Sources/Server/SMC+Probe.swift
git commit -m "Probe SMC key capabilities including the attributes byte

keyInformation already asked the SMC for dataAttributes and discarded it. That
byte is what says whether a key is readable and writable, which is the
difference between a key that exists and one that can drive charging."
```

---

### Task 4: Firmware-keyed backend cache in `SMCService`

**Files:**
- Modify: `BatFiKit/Sources/Server/SMCService.swift`

**Interfaces:**
- Consumes: `probeCapabilities`, `ChargeBackendResolver`, `SystemFirmware`.
- Produces: `SMCService.currentBackend() async -> ChargeBackend`.

- [ ] **Step 1: Add the cached resolution**

Add to `SMCService` (it is an actor, so these are actor-isolated):

```swift
    private var cachedBackend: ChargeBackend?
    private var cachedBackendFirmware: String?

    /// Resolves the charge-control mechanism from the firmware's key table.
    ///
    /// Cached against the firmware token, not the macOS version, and re-probed when
    /// that token changes. This is the case a user hits by updating macOS, taking the
    /// new firmware, then downgrading macOS again — the OS moves, the firmware does
    /// not, and the cache follows the firmware.
    func currentBackend() async -> ChargeBackend {
        let firmware = SystemFirmware.version()
        if let cachedBackend, cachedBackendFirmware == firmware {
            return cachedBackend
        }

        await openSMCIfNeeded()
        let capabilities = SMCKit.probeCapabilities(ChargeBackendResolver.probedKeys)
        let backend = ChargeBackendResolver.resolve(capabilities)

        let summary = capabilities.keys.sorted().joined(separator: ", ")
        logger.notice("""
        Charge backend resolved to \(backend.rawValue, privacy: .public) \
        on firmware \(firmware ?? "unknown", privacy: .public); usable keys: \(summary, privacy: .public)
        """)

        cachedBackend = backend
        cachedBackendFirmware = firmware
        return backend
    }
```

- [ ] **Step 2: Dispatch `enableCharging` on the backend**

Replace the try/catch ladder in `enableCharging(_:)`. Behaviour on existing firmware must be identical — the same keys, the same bytes.

```swift
    func enableCharging(_ enable: Bool) async throws {
        logger.notice(enable ? "Enabling charging" : "Inhibit charging")
        await openSMCIfNeeded()
        let enableByte: UInt8 = enable ? 0 : 1

        switch await currentBackend() {
        case .chte:
            try SMCKit.writeData(.inhibitCharging3, byte0: enableByte, byte1: 0, byte2: 0, byte3: 0)
            logger.notice("Inhibit charging changed using CHTE")
        case .legacyCH0BC:
            try SMCKit.writeData(.inhibitCharging1, uint8: enableByte)
            try SMCKit.writeData(.inhibitCharging2, uint8: enableByte)
            logger.notice("Inhibit charging changed using CH0B/CH0C")
        case .unsupported:
            logger.error("No usable charge control mechanism on this firmware")
            throw SMCError.keyNotFound(code: "CHTE")
        }
    }
```

- [ ] **Step 3: Dispatch `enableForceDischarge` on probed keys**

Force discharge uses a different key set than charge inhibit — `CHIE` survives on firmware where `CHTE` does not — so probe it independently rather than deriving it from the backend. Preserve the `0x08`/`0x01` asymmetry from Phase 1.

```swift
    func enableForceDischarge(_ enable: Bool) async throws {
        logger.notice(enable ? "Force discharge" : "Turn off force discharge")
        await openSMCIfNeeded()

        func engageByte(for key: SMCKey) -> UInt8 { enable ? key.forceDischargeEngagedValue : 0 }

        if SMCKit.probeCapability("CHIE") != nil {
            try SMCKit.writeData(.disableCharging3, uint8: engageByte(for: .disableCharging3))
            logger.notice("Force discharge changed using CHIE")
            return
        }
        if SMCKit.probeCapability("CH0J") != nil {
            try? SMCKit.writeData(.disableCharging1, uint8: engageByte(for: .disableCharging1))
            try SMCKit.writeData(.disableCharging2, uint8: engageByte(for: .disableCharging2))
            logger.notice("Force discharge changed using CH0I/CH0J")
            return
        }
        logger.error("No usable force discharge mechanism on this firmware")
        throw SMCError.keyNotFound(code: "CHIE")
    }
```

- [ ] **Step 4: Make `isChargingEnabled` and `smcChargingStatus` use the backend**

Replace their try/catch ladders with the same `switch await currentBackend()` shape, reading `CHTE` for `.chte` and `CH0B` for `.legacyCH0BC`, and returning the existing default for `.unsupported`. Keep the existing return semantics exactly.

- [ ] **Step 5: Verify**

Build `Server` and `BatFi`; run the full suite (unchanged count).

- [ ] **Step 6: Commit**

```bash
git add BatFiKit/Sources/Server/SMCService.swift
git commit -m "Select the charge mechanism by probe, cached on the firmware token

Replaces exception-on-write mechanism selection. The cache key is the firmware
identity rather than the macOS version, so a machine that took new firmware and
then downgraded macOS still resolves correctly."
```

---

### Task 5: Gate the MCL path on `isMCLSupported`, not the macOS version

Three `#available(macOS 26.4, *)` checks in `SMCService` currently decide whether the system Manual Charge Limit exists. That is a version gate on a capability BatFi can ask about directly.

**Files:**
- Modify: `BatFiKit/Sources/Server/PowerUICharging.swift`
- Modify: `BatFiKit/Sources/Server/SMCService.swift:56,75,94` (approx — locate by the `#available(macOS 26.4, *)` occurrences)

- [ ] **Step 1: Add the capability query**

In `PowerUICharging`, alongside `isAvailable`:

```swift
    /// Whether this machine's PowerUI reports Manual Charge Limit support. Asking the
    /// framework is strictly better than inferring it from the macOS version.
    var isMCLSupported: Bool {
        guard let client, let clientClass else { return false }
        let selector = NSSelectorFromString("isMCLSupported")
        guard let method = class_getInstanceMethod(clientClass, selector) else { return false }
        typealias Query = @convention(c) (AnyObject, Selector) -> ObjCBool
        let query = unsafeBitCast(method_getImplementation(method), to: Query.self)
        return query(client, selector).boolValue
    }
```

- [ ] **Step 2: Replace the three version gates**

At each of the three sites, replace `if #available(macOS 26.4, *)` with a check on `await PowerUICharging.shared.isMCLSupported`. The `mclStatus()` site should report `supported: isMCLSupported` rather than the hardcoded `false`.

Keep every other condition at those sites unchanged (for example `message == .auto`).

- [ ] **Step 3: Verify no `#available` remains in `SMCService`**

Run: `grep -n '#available\|@available' BatFiKit/Sources/Server/SMCService.swift`
Expected: no output.

- [ ] **Step 4: Build and commit**

```bash
git add BatFiKit/Sources/Server/PowerUICharging.swift BatFiKit/Sources/Server/SMCService.swift
git commit -m "Ask PowerUI whether the system charge limit exists

The macOS version gate was wrong for the population this work targets: machines
carrying newer firmware than their OS. PowerUI answers the capability question
directly."
```

---

### Task 6: Decode `CHNC` and report charging diagnostics over XPC

`CHNC` is an 8-byte little-endian bitfield giving the firmware's own reason for not charging. It is the only signal that distinguishes "our inhibit is working" from "a write was accepted and ignored" — read-back cannot, because Golden Gate firmware echoes `CHTE` while ignoring it.

**Deliberate limitation:** only the bits Asahi documents are decoded, and **no control flow branches on them**. Which bit a `CHTE` inhibit raises has not been confirmed on hardware, so this phase logs and reports the reason rather than acting on it.

**Files:**
- Create: `BatFiKit/Sources/Shared/ChargingDiagnostics.swift`
- Create: `BatFiKit/Tests/AppSharedTests/NotChargingReasonTests.swift`
- Modify: `BatFiKit/Sources/Shared/XPCService.swift`, `BatFiKit/Sources/Server/Listener.swift`, `BatFiKit/Sources/Server/SMCService.swift`

- [ ] **Step 1: Write the failing tests**

Create `BatFiKit/Tests/AppSharedTests/NotChargingReasonTests.swift`:

```swift
//
//  NotChargingReasonTests.swift
//  BatFi
//
//  CHNC is the firmware's own reason for not charging. Bit positions are Asahi's,
//  cross-checked against a live read on a Mac15,8: unplugged reported
//  80 00 00 00 00 00 00 00, which decodes little-endian to bit 7, NO_CHARGER.
//

import Foundation
import Testing

@testable import Shared

@Suite struct NotChargingReasonTests {
    @Test func decodesNoChargerFromLiveReading() {
        let bytes: [UInt8] = [0x80, 0, 0, 0, 0, 0, 0, 0]
        let reasons = NotChargingReason.decode(bytes)
        #expect(reasons.contains(.noCharger))
        #expect(!reasons.contains(.batteryFull))
    }

    @Test func decodesBatteryFull() {
        let bytes: [UInt8] = [0x01, 0, 0, 0, 0, 0, 0, 0]
        #expect(NotChargingReason.decode(bytes).contains(.batteryFull))
    }

    /// Bit 24 lives in the fourth byte little-endian.
    @Test func decodesSystemChargeLimit() {
        let bytes: [UInt8] = [0, 0, 0, 0x01, 0, 0, 0, 0]
        #expect(NotChargingReason.decode(bytes).contains(.systemChargeLimit))
    }

    /// Bit 54 lives in the seventh byte little-endian.
    @Test func decodesForceDischargeCH0I() {
        let bytes: [UInt8] = [0, 0, 0, 0, 0, 0, 0x40, 0]
        #expect(NotChargingReason.decode(bytes).contains(.adapterDisabledCH0I))
    }

    @Test func decodesNothingWhenClear() {
        #expect(NotChargingReason.decode([UInt8](repeating: 0, count: 8)).isEmpty)
    }

    @Test func ignoresShortBuffers() {
        #expect(NotChargingReason.decode([0x80]).isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL — `cannot find 'NotChargingReason' in scope`.

- [ ] **Step 3: Implement the diagnostics types**

Create `BatFiKit/Sources/Shared/ChargingDiagnostics.swift`:

```swift
//
//  ChargingDiagnostics.swift
//
//
//  What the helper knows about why charging is or is not happening.
//

import Foundation

/// Bits of the SMC `CHNC` key — the firmware's own reason for not charging.
/// Positions from the Asahi Linux macsmc driver; the value is little-endian.
public enum NotChargingReason: String, Sendable, CaseIterable {
    case batteryFull
    case noCharger
    case inhibitedCH0C
    case inhibitedCH0BOrCH0K
    case batteryManagementBusy
    case systemChargeLimit
    case adapterDisabledCH0J
    case adapterDisabledCH0I

    var bit: UInt64 {
        switch self {
        case .batteryFull:            return 0
        case .noCharger:              return 7
        case .inhibitedCH0C:          return 14
        case .inhibitedCH0BOrCH0K:    return 15
        case .batteryManagementBusy:  return 23
        case .systemChargeLimit:      return 24
        case .adapterDisabledCH0J:    return 53
        case .adapterDisabledCH0I:    return 54
        }
    }

    public static func decode(_ bytes: [UInt8]) -> [NotChargingReason] {
        guard bytes.count >= 8 else { return [] }
        var value: UInt64 = 0
        for index in 0 ..< 8 {
            value |= UInt64(bytes[index]) << (8 * UInt64(index))
        }
        return allCases.filter { value & (1 << $0.bit) != 0 }
    }
}

/// Snapshot the app can render and a user can paste into a bug report.
public final class ChargingDiagnostics: NSObject, NSSecureCoding, @unchecked Sendable {
    public static let supportsSecureCoding: Bool = true

    /// Resolved `ChargeBackend.rawValue`.
    public let backend: String
    /// Opaque firmware token, e.g. "mBoot-18000.161.9".
    public let firmwareVersion: String?
    /// Decoded `CHNC` reasons, as `NotChargingReason.rawValue`.
    public let notChargingReasons: [String]
    public let mcl: MCLStatus?

    public init(backend: String, firmwareVersion: String?, notChargingReasons: [String], mcl: MCLStatus?) {
        self.backend = backend
        self.firmwareVersion = firmwareVersion
        self.notChargingReasons = notChargingReasons
        self.mcl = mcl
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(backend, forKey: "backend")
        coder.encode(firmwareVersion, forKey: "firmwareVersion")
        coder.encode(notChargingReasons, forKey: "notChargingReasons")
        coder.encode(mcl, forKey: "mcl")
    }

    public required init?(coder: NSCoder) {
        backend = coder.decodeObject(of: NSString.self, forKey: "backend") as String? ?? "unknown"
        firmwareVersion = coder.decodeObject(of: NSString.self, forKey: "firmwareVersion") as String?
        let reasons = coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "notChargingReasons")
        notChargingReasons = (reasons as? [String]) ?? []
        mcl = coder.decodeObject(of: MCLStatus.self, forKey: "mcl")
        super.init()
    }

    public override var description: String {
        "ChargingDiagnostics(backend: \(backend), firmware: \(firmwareVersion ?? "unknown"), reasons: \(notChargingReasons))"
    }
}
```

- [ ] **Step 4: Add the XPC method**

In `BatFiKit/Sources/Shared/XPCService.swift`, add to the protocol:

```swift
    func getChargingDiagnostics(_ handler: @escaping (ChargingDiagnostics?, Error?) -> Void)
```

Implement it in `Server/Listener.swift` following the exact shape of the neighbouring `getMCLStatus` implementation, and add a matching method on the app side in `ClientsLive/XPCClient.swift` mirroring how `getMCLStatus` is wrapped there.

- [ ] **Step 5: Produce the diagnostics in `SMCService`**

Add a `chargingDiagnostics()` method that resolves the backend, reads `CHNC` (add an `SMCKey` for it: code `CHNC`, `DataTypes.UInt8`-style descriptor with size 8 — define a `DataTypes.Hex8` if one does not exist), decodes it via `NotChargingReason.decode`, and returns a `ChargingDiagnostics` including `PowerUICharging.shared.mclStatus()`.

Read `CHNC` defensively: if the key is absent, report an empty reason list rather than throwing.

- [ ] **Step 6: Verify and commit**

Filtered tests (6 pass), full suite (55 tests / 10 suites), build `Server` and `BatFi`.

```bash
git add BatFiKit/Sources/Shared/ChargingDiagnostics.swift BatFiKit/Tests/AppSharedTests/NotChargingReasonTests.swift BatFiKit/Sources/Shared/XPCService.swift BatFiKit/Sources/Server/Listener.swift BatFiKit/Sources/Server/SMCService.swift BatFiKit/Sources/ClientsLive/XPCClient.swift
git commit -m "Report the firmware's own reason for not charging

CHNC is the only signal that separates a working inhibit from a write that was
accepted and ignored, which read-back cannot detect. Decoded and reported only —
no control flow branches on it until the CHTE bit is confirmed on hardware."
```

---

### Task 7: Surface the diagnostics in the UI

`MCLStatus` has been plumbed across XPC since 3.1.0 and rendered nowhere, so a user whose system charge limit is fighting BatFi has no way to find out.

**Files:**
- Modify: `BatFiKit/Sources/Settings/` — the Charging pane (locate the view that renders charge-limit settings)
- Modify: `BatFiKit/Sources/Clients/ChargingClient.swift` and its live implementation — add a `chargingDiagnostics` endpoint mirroring the existing `mclStatus` one
- Modify: `BatFiKit/Sources/L10n/Strings.swift` — new strings

- [ ] **Step 1: Add the client endpoint**

Add `chargingDiagnostics` to `ChargingClient` following the exact shape of the existing `mclStatus` property, and implement it in the live client by calling the new XPC method.

- [ ] **Step 2: Render it in the Charging settings pane**

Add a diagnostics section showing:
- the active mechanism, from `backend` — for `unsupported`, say plainly that BatFi cannot control charging on this firmware;
- the firmware token, selectable so it can be pasted into a bug report;
- a warning when `mcl.supported` is true and the system limit is not 100%, telling the user the macOS charge limit will interact with BatFi's and that they should set it to 100%.

Follow the pane's existing layout and styling; use `L10n` for all user-facing strings, matching the existing key naming convention.

- [ ] **Step 3: Verify and commit**

Build `BatFi`; run the full suite.

```bash
git add BatFiKit/Sources/Settings BatFiKit/Sources/Clients/ChargingClient.swift BatFiKit/Sources/ClientsLive BatFiKit/Sources/L10n/Strings.swift
git commit -m "Show the active charge mechanism and firmware in settings

MCLStatus had been plumbed across XPC since 3.1.0 and rendered nowhere, so a
user whose system charge limit was fighting BatFi had no way to see it."
```

---

### Task 8: Phase 2 verification

- [ ] **Step 1: Full suite and builds**

```
xcodebuild test  -project BatFi.xcodeproj -scheme AppSharedTests -destination 'platform=macOS'
xcodebuild build -project BatFi.xcodeproj -scheme BatFi   -destination 'platform=macOS'
xcodebuild build -project BatFi.xcodeproj -scheme Server  -destination 'platform=macOS'
```

- [ ] **Step 2: No version gate selects an SMC path**

```
grep -rn '#available\|@available\|operatingSystemVersion' BatFiKit/Sources/Server/
```
Expected: no output.

- [ ] **Step 3: Behaviour unchanged on this machine**

The development Mac is `Mac15,8` on firmware `mBoot-18000.161.9`, which exposes `CHTE` as a writable `ui32`/4. Confirm the helper's log reports `Charge backend resolved to chte`, and that setting a charge limit still inhibits charging exactly as before this phase.

- [ ] **Step 4: Working tree clean**

`git status --short` → empty. `AnalyticsDSN.swift` must remain uncommitted.
