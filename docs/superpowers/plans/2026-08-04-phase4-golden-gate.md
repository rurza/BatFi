# Phase 4 — Golden Gate `bf**` Support — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Support the firmware-managed charge limit that macOS 27 firmware uses in place of the removed `CHTE`, so limits below 80% work again on that hardware — and degrade honestly on firmware where the key set has moved again.

**Architecture:** A `.firmwareRange` backend, ranked **first** in Phase 2's resolver because old macOS releases routinely carry new firmware. Instead of an on/off inhibit, BatFi hands the firmware a hysteresis band — upper and lower percentages — and the firmware enforces it, including while the Mac is asleep.

**Tech Stack:** Swift 6, SwiftPM (`BatFiKit`), swift-testing, IOKit `AppleSMC`, NSXPC.

## The mechanism

| Key | Type | Meaning |
|---|---|---|
| `bfF0` | `ui8 ` / 1 | activation and status — `0x00` charging enabled, `0x02` limit active |
| `bfD0` | `ui32` / 4 | **upper** limit percentage |
| `bfE0` | `ui32` / 4 | **lower** limit percentage |

Two properties that are easy to get wrong and hard to notice:

1. **The write order is mandatory**, enforced by the firmware:
   `bfF0 ← 0x00` (deactivate) → `bfD0 ← upper` → `bfE0 ← lower` → `bfF0 ← 0x02` (activate).
   Re-enabling charging is just `bfF0 ← 0x00`.
2. **The `ui32` percentages are little-endian**, against normal SMC convention — 50% is `32 00 00 00`, not `00 00 00 32`. Every other `ui32` SMC key in this codebase is big-endian, so this needs its own encoder and its own test.

## Global Constraints

- **Swift 6 language mode.**
- **`.firmwareRange` is probed, never version-gated.** No `#available`, `@available`, or `operatingSystemVersion` may select it. Old macOS carries new firmware — that is the population this whole project exists for.
- **Match type AND size AND writability.** `bfD0` exists on Tahoe-era firmware as a **read-only `hex_`/2** key with unrelated meaning. Requiring all three of `bfF0`/`bfD0`/`bfE0` at their exact shapes is what stops a false positive there. Phase 2's `measuredTahoeBFD0DoesNotMatchTheMacOS27Shape` test pins this.
- **`resetIfPossible()` must clear `bfF0`.** A helper crash under this backend otherwise leaves the limit armed with nothing to clear it.
- **Never `print()`** — `os.Logger` only. **No force-unwraps.**
- **Commit messages must never mention Claude** and must not carry `Co-Authored-By` or `Generated with` trailers.

## Honest scope limit

The `bf**` mechanism is documented against macOS 27 developer betas 1–3 (firmware `20356.0.0.0.15` … `20457.0.77.0.2`). **Beta 4 (`20457.0.125.0.2`+) moved the key set again and no tool has a published fix.** This plan does not chase beta 4: on that firmware the probe simply will not match, and the resolver falls through to `.systemChargeLimit` or `.unsupported`. That is the correct behaviour and it needs no version check — which is precisely the argument for probing.

**No macOS 27 hardware is available**, so nothing here is runtime-verified. Every task is written so the untestable part is as small as possible and the testable part is pure.

**Verification commands** (CLI `swift build`/`swift test` do NOT work in this repo — do not attempt them, do not modify `Package.swift`):

```
xcodebuild test  -project BatFi.xcodeproj -scheme AppSharedTests -destination 'platform=macOS'
xcodebuild build -project BatFi.xcodeproj -scheme Server -destination 'platform=macOS'
xcodebuild build -project BatFi.xcodeproj -scheme BatFi  -destination 'platform=macOS'
```

A gitignored `BatFiKit/Sources/ClientsLive/AnalyticsDSN.swift` exists locally so the app compiles — leave it alone, never commit it.

---

### Task 1: `.firmwareRange` in the resolver, ranked first

**Files:**
- Modify: `BatFiKit/Sources/Shared/ChargeBackend.swift`
- Test: `BatFiKit/Tests/AppSharedTests/ChargeBackendResolverTests.swift`

- [ ] **Step 1: Write the failing tests**

Append:

```swift
    private var goldenGateTable: [String: SMCKeyCapability] {
        table([cap("bfF0", "ui8 ", 1), cap("bfD0", "ui32", 4), cap("bfE0", "ui32", 4)])
    }

    @Test func selectsFirmwareRangeWhenAllThreeKeysPresent() {
        #expect(ChargeBackendResolver.resolve(goldenGateTable) == .firmwareRange)
    }

    /// Ranked first on purpose: an old macOS can be running new firmware, so the
    /// presence of the newer mechanism must win over anything older.
    @Test func firmwareRangeOutranksCHTE() {
        var caps = goldenGateTable
        caps["CHTE"] = cap("CHTE", "ui32", 4)
        #expect(ChargeBackendResolver.resolve(caps) == .firmwareRange)
    }

    /// All three keys are required — a partial set is not a usable mechanism.
    @Test func firmwareRangeRequiresAllThreeKeys() {
        for missing in ["bfF0", "bfD0", "bfE0"] {
            var caps = goldenGateTable
            caps.removeValue(forKey: missing)
            #expect(ChargeBackendResolver.resolve(caps) == .unsupported,
                    "removing \(missing) should not leave a usable firmware range backend")
        }
    }

    /// The decoy in its natural habitat: Tahoe-era firmware has bfD0 as a read-only
    /// hex_/2 key and no bfE0 or bfF0 at all. It must resolve to CHTE, not to the
    /// macOS 27 mechanism.
    @Test func tahoeFirmwareWithDecoyBFD0StillSelectsCHTE() {
        let caps = table([
            cap("CHTE", "ui32", 4),
            cap("bfD0", "hex_", 2, writable: false),
        ])
        #expect(ChargeBackendResolver.resolve(caps) == .chte)
    }

    /// Beta 4 moved the key set again. A firmware exposing bfF0 at the wrong shape
    /// must not select this backend — it should fall through, with no version check.
    @Test func rejectsFirmwareRangeWhenBFF0HasWrongShape() {
        var caps = goldenGateTable
        caps["bfF0"] = cap("bfF0", "ui32", 4)
        #expect(ChargeBackendResolver.resolve(caps) == .unsupported)
    }

    @Test func firmwareRangeHonoursLimitsBelow80() {
        #expect(ChargeBackend.firmwareRange.honoursLimitsBelow80)
    }
```

- [ ] **Step 2: Run to verify failure** — no `firmwareRange` case.

- [ ] **Step 3: Implement**

Add the case with its documentation, and place the check **first** in `resolve`:

```swift
    /// `bfD0`/`bfE0`/`bfF0` — macOS 27-era firmware, which removed `CHTE`. The
    /// firmware enforces a hysteresis band rather than BatFi toggling an inhibit,
    /// so the limit holds while the Mac is asleep — and the battery percentage may
    /// fall below the limit, because the firmware can run the Mac off the battery.
    case firmwareRange
```

```swift
        // Checked first: an older macOS can be carrying newer firmware, so the
        // presence of this key set outranks anything older regardless of the OS.
        if capabilities["bfF0"]?.matches(type: "ui8 ", size: 1, writable: true) == true,
           capabilities["bfD0"]?.matches(type: "ui32", size: 4, writable: true) == true,
           capabilities["bfE0"]?.matches(type: "ui32", size: 4, writable: true) == true {
            return .firmwareRange
        }
```

Add `.firmwareRange` to `honoursLimitsBelow80` (true) and to `isUsable` (true). Add the three keys to `probedKeys`.

- [ ] **Step 4: Verify and commit**

```bash
git add BatFiKit/Sources/Shared/ChargeBackend.swift BatFiKit/Tests/AppSharedTests/ChargeBackendResolverTests.swift
git commit -m "Add the macOS 27 firmware-managed charge range backend

Ranked ahead of CHTE because an older macOS can be running newer firmware.
Requires all three keys at their exact shapes, which is what keeps the
read-only hex_/2 bfD0 on Tahoe firmware from selecting it."
```

---

### Task 2: Little-endian percentage encoding

Every other `ui32` SMC key in this codebase is big-endian. These three are not. That is exactly the kind of detail that produces a wildly wrong limit and no error, so it gets its own pure function and its own tests.

**Files:**
- Modify: `BatFiKit/Sources/Shared/ChargeBackend.swift` (or a new `Shared/FirmwareChargeRange.swift`)
- Test: `BatFiKit/Tests/AppSharedTests/FirmwareChargeRangeTests.swift`

**Interfaces:**
- Produces: `public enum FirmwareChargeRange` with
  `static func encodePercentage(_ value: Int) -> (UInt8, UInt8, UInt8, UInt8)`,
  `static func decodePercentage(_ bytes: (UInt8, UInt8, UInt8, UInt8)) -> Int`,
  `static func band(forLimit limit: Int) -> (upper: Int, lower: Int)`.

- [ ] **Step 1: Write the failing tests**

```swift
//
//  FirmwareChargeRangeTests.swift
//  BatFi
//
//  The macOS 27 firmware keys encode ui32 percentages LITTLE-endian, against the
//  normal SMC convention every other ui32 key in this codebase follows.
//

import Foundation
import Testing

@testable import Shared

@Suite struct FirmwareChargeRangeTests {
    /// 50% is 32 00 00 00, not 00 00 00 32.
    @Test func encodesPercentageLittleEndian() {
        let bytes = FirmwareChargeRange.encodePercentage(50)
        #expect(bytes == (0x32, 0x00, 0x00, 0x00))
    }

    @Test func encodesFullChargeLittleEndian() {
        #expect(FirmwareChargeRange.encodePercentage(100) == (0x64, 0x00, 0x00, 0x00))
    }

    @Test func roundTripsEveryValidPercentage() {
        for value in 0 ... 100 {
            #expect(FirmwareChargeRange.decodePercentage(FirmwareChargeRange.encodePercentage(value)) == value)
        }
    }

    /// A big-endian reading of 50% would be 838860800 — the check that catches a
    /// byte-order regression outright.
    @Test func decodeIsNotBigEndian() {
        #expect(FirmwareChargeRange.decodePercentage((0x32, 0x00, 0x00, 0x00)) == 50)
        #expect(FirmwareChargeRange.decodePercentage((0x00, 0x00, 0x00, 0x32)) != 50)
    }

    /// BatFi has a single limit; the firmware wants a band. Five points of
    /// hysteresis matches what Apple's own limit uses.
    @Test func derivesBandFromSingleLimit() {
        let band = FirmwareChargeRange.band(forLimit: 80)
        #expect(band.upper == 80)
        #expect(band.lower == 75)
    }

    /// The lower bound must not go absurdly low for small limits.
    @Test func clampsLowerBound() {
        #expect(FirmwareChargeRange.band(forLimit: 12).lower >= 10)
        #expect(FirmwareChargeRange.band(forLimit: 10).lower >= 10)
    }

    @Test func upperNeverExceedsLimit() {
        for limit in 10 ... 100 {
            #expect(FirmwareChargeRange.band(forLimit: limit).upper == limit)
        }
    }
}
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**

```swift
/// Encoding for the macOS 27 firmware-managed charge range.
public enum FirmwareChargeRange {
    /// Hysteresis in percentage points between the upper and lower bounds. Matches
    /// the 5 points Apple's own charge limit uses before it resumes charging.
    public static let hysteresis = 5
    /// Floor for the lower bound, so a small limit cannot produce a nonsensical band.
    public static let minimumLowerBound = 10

    /// These keys are little-endian, unlike every other ui32 key here.
    public static func encodePercentage(_ value: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let clamped = UInt32(max(0, min(100, value)))
        return (
            UInt8(clamped & 0xFF),
            UInt8((clamped >> 8) & 0xFF),
            UInt8((clamped >> 16) & 0xFF),
            UInt8((clamped >> 24) & 0xFF)
        )
    }

    public static func decodePercentage(_ bytes: (UInt8, UInt8, UInt8, UInt8)) -> Int {
        let value = UInt32(bytes.0)
            | (UInt32(bytes.1) << 8)
            | (UInt32(bytes.2) << 16)
            | (UInt32(bytes.3) << 24)
        return Int(value)
    }

    /// BatFi exposes one limit; the firmware enforces a band.
    public static func band(forLimit limit: Int) -> (upper: Int, lower: Int) {
        let upper = max(0, min(100, limit))
        let lower = max(minimumLowerBound, upper - hysteresis)
        return (upper, min(lower, upper))
    }
}
```

- [ ] **Step 4: Verify and commit**

```bash
git add BatFiKit/Sources/Shared BatFiKit/Tests/AppSharedTests/FirmwareChargeRangeTests.swift
git commit -m "Encode firmware charge range percentages little-endian

These keys reverse the byte order every other ui32 SMC key in this codebase
uses, which would otherwise produce a wildly wrong limit with no error. BatFi's
single limit becomes a band with five points of hysteresis, matching Apple's."
```

---

### Task 3: Write the range through the mandatory sequence

**Files:**
- Modify: `BatFiKit/Sources/Server/SMC+Keys.swift` — add the three keys
- Modify: `BatFiKit/Sources/Server/SMCService.swift`

- [ ] **Step 1: Add the key definitions**

```swift
    /// macOS 27-era firmware: activation and status. 0x00 charging enabled, 0x02 limited.
    static let firmwareRangeActivation = Self(code: .init(fromStaticString: "bfF0"), info: DataTypes.UInt8)
    /// Upper limit percentage, little-endian ui32.
    static let firmwareRangeUpper = Self(code: .init(fromStaticString: "bfD0"), info: DataTypes.UInt32)
    /// Lower limit percentage, little-endian ui32.
    static let firmwareRangeLower = Self(code: .init(fromStaticString: "bfE0"), info: DataTypes.UInt32)
```

- [ ] **Step 2: Implement the sequence**

Add to `SMCService`. **The order is mandated by the firmware — do not reorder or collapse it.**

```swift
    /// Hands the firmware a charge band. The write order below is required by the
    /// firmware: deactivate, set both bounds, then activate. Percentages are
    /// little-endian, unlike every other ui32 key here.
    private func applyFirmwareRange(_ limit: Int) throws {
        let band = FirmwareChargeRange.band(forLimit: limit)
        let upper = FirmwareChargeRange.encodePercentage(band.upper)
        let lower = FirmwareChargeRange.encodePercentage(band.lower)

        try SMCKit.writeData(.firmwareRangeActivation, uint8: 0x00)
        try SMCKit.writeData(.firmwareRangeUpper, byte0: upper.0, byte1: upper.1, byte2: upper.2, byte3: upper.3)
        try SMCKit.writeData(.firmwareRangeLower, byte0: lower.0, byte1: lower.1, byte2: lower.2, byte3: lower.3)
        try SMCKit.writeData(.firmwareRangeActivation, uint8: 0x02)

        logger.notice("Firmware charge range set to \(band.lower, privacy: .public)-\(band.upper, privacy: .public)%")
    }

    /// Releasing the limit is a single write.
    private func releaseFirmwareRange() throws {
        try SMCKit.writeData(.firmwareRangeActivation, uint8: 0x00)
        logger.notice("Firmware charge range released")
    }
```

- [ ] **Step 3: Route the backend through it**

In `applyChargeLimit(_:)` (added in Phase 3) add the `.firmwareRange` case, calling `applyFirmwareRange` and returning the requested percentage unchanged — this backend honours limits below 80.

In `enableCharging(_ enable: Bool)`, the `.firmwareRange` case calls `releaseFirmwareRange()` when enabling. When inhibiting, charging control is expressed as a band, not an inhibit — so route through `applyChargeLimit` rather than writing an inhibit key.

- [ ] **Step 4: Read status from `bfF0`**

`isChargingEnabled` for `.firmwareRange` reads `bfF0` and returns `value == 0x00`.

- [ ] **Step 5: Verify and commit**

```bash
git add BatFiKit/Sources/Server/SMC+Keys.swift BatFiKit/Sources/Server/SMCService.swift
git commit -m "Apply the firmware charge range on macOS 27 firmware

The deactivate, set bounds, activate order is required by the firmware. Status
comes from the activation key rather than an inhibit flag, because under this
mechanism the firmware owns the charging decision."
```

---

### Task 4: Clear `bfF0` on reset

`resetIfPossible()` blindly zeroes the older inhibit and discharge keys. Under this backend a helper crash would otherwise leave the limit armed with nothing to clear it.

**Files:** `BatFiKit/Sources/Server/SMCService.swift`

- [ ] **Step 1: Add `bfF0` to the reset path**

Add `try? SMCKit.writeData(.firmwareRangeActivation, uint8: 0x00)` alongside the existing best-effort writes. Keep the existing `try?`-and-discard style — reset is best-effort by design and must not throw.

- [ ] **Step 2: Confirm `restoreSystemDefaults()` reaches it**, so quitting BatFi releases the limit.

- [ ] **Step 3: Verify and commit**

```bash
git add BatFiKit/Sources/Server/SMCService.swift
git commit -m "Release the firmware charge range on reset

Without this, a helper crash under the firmware-managed backend leaves the
limit armed and nothing left running to clear it."
```

---

### Task 5: Feature consequences of firmware-owned charging

Under this backend the **firmware** owns the charging decision, which changes what BatFi can honestly offer.

- **MagSafe LED becomes unavailable** — not because `ACLC` is gone, but because BatFi no longer reliably knows the charging state to mirror.
- **Force discharge stays probed independently** — `CHIE` survives on this firmware, including beta 4.
- **The battery percentage can fall** below the limit while on AC, because the firmware may run the Mac off the battery. Any UI or logic assuming "plugged in ⇒ percentage steady" is wrong here.
- **Sleep hooks become unnecessary** — the firmware enforces the limit while asleep.

**Files:** `BatFiKit/Sources/Shared/ChargingDiagnostics.swift`, `BatFiKit/Sources/Server/SMCService.swift`, `BatFiKit/Sources/AppCore/`

- [ ] **Step 1: Report the capabilities** — set `magSafeLEDAvailable` false for `.firmwareRange` even when `ACLC` probes fine, with a comment explaining that the limitation is knowledge, not the key. Keep `forceDischargeAvailable` driven by the `CHIE` probe.

- [ ] **Step 2: Persist the disable** so stale user config cannot re-arm a feature this backend cannot support.

- [ ] **Step 3: Skip sleep-inhibit hooks** under `.firmwareRange`, since the firmware holds the limit through sleep.

- [ ] **Step 4: Verify and commit**

```bash
git add BatFiKit/Sources/Shared/ChargingDiagnostics.swift BatFiKit/Sources/Server BatFiKit/Sources/AppCore
git commit -m "Reflect firmware-owned charging in the available features

Under this backend the firmware decides when to charge, so BatFi cannot mirror
the state on the MagSafe LED and does not need its sleep hooks. Force discharge
stays probed separately because CHIE survives on this firmware."
```

---

### Task 6: UI for the firmware-managed backend

**Files:** the Charging settings pane, `BatFiKit/Sources/L10n/Strings.swift`

- [ ] **Step 1: Add strings** — that the limit is enforced by firmware and holds during sleep; that the battery percentage may dip below the limit by design; and that MagSafe LED control is unavailable on this Mac.
- [ ] **Step 2: Render them** from `ChargingDiagnostics.backend`, and hide or disable the MagSafe LED controls when `magSafeLEDAvailable` is false.
- [ ] **Step 3: Verify and commit.**

---

### Task 7: Version bump and consolidated changelog

Phase 1 committed a `3.1.2` entry that was never released. All four phases ship together as one beta, and they add features rather than only fixing bugs.

**Files:** `Supporting Files/Config.xcconfig`, `CHANGELOG.md`

- [ ] **Step 1:** `APP_VERSION = 3.2.0`. Leave `BUILD_NUMBER = 99999` — it is a placeholder the SMJobBless code-signing requirement depends on.
- [ ] **Step 2:** Rename the unreleased `## [3.1.2]` heading to `## [3.2.0]` with today's date, and fold the Phase 2–4 items into it rather than creating a second unreleased section. Keep the user-facing voice of the existing entries: what changed for the user, not which key moved.
- [ ] **Step 3:** Expect `Helper/Info.plist` to change too — it carries `CFBundleShortVersionString`, generated from `APP_VERSION`. The previous two bump commits touched exactly `CHANGELOG.md`, `Helper/Info.plist` and `Config.xcconfig`; match that.
- [ ] **Step 4: Commit** — `Bump version to 3.2.0`.

---

### Task 8: Phase 4 verification

- [ ] **Step 1:** Full suite and both builds.
- [ ] **Step 2:** `grep -rn '#available\|@available\|operatingSystemVersion' BatFiKit/Sources/Server/` → no output.
- [ ] **Step 3:** Confirm the dev Mac still resolves `.chte` — it has `CHTE` and lacks `bfE0`/`bfF0`, so the new backend must not engage. This is the regression that would matter most.
- [ ] **Step 4:** Confirm `bfF0` appears in `resetIfPossible()`.
- [ ] **Step 5:** Working tree clean; `AnalyticsDSN.swift` uncommitted; `APP_VERSION = 3.2.0`, `BUILD_NUMBER = 99999`.
