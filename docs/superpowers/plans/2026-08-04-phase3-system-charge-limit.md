# Phase 3 — `.systemChargeLimit` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When no SMC mechanism works — the macOS 27 case — drive Apple's own Manual Charge Limit instead, so a limit of 80–100% still applies, and say plainly in the UI what is and is not available.

**Architecture:** Phase 2's resolver gains a `.systemChargeLimit` case, ranked **below** every SMC backend because only those can express a limit under 80%. When it is selected, ownership of the system MCL inverts: instead of overriding it to 100 to get it out of the way, BatFi sets it — snapshotting the user's original value first and restoring it on disengage.

**Tech Stack:** Swift 6, SwiftPM (`BatFiKit`), swift-testing, `PowerUI.framework` private SPI via `dlopen` + `NSSelectorFromString`, NSXPC.

## Global Constraints

- **Swift 6 language mode.**
- **Never gate on the macOS version.** Selection is by capability: `isMCLSupported` from PowerUI, and the SMC key table. No `#available`, `@available`, or `operatingSystemVersion` may pick a mechanism.
- **Exactly one MCL owner at a time.** In every SMC backend BatFi *releases* the system limit (overrides to 100). Under `.systemChargeLimit` it *sets* it. These are mutually exclusive; if both run, the 60-second renewal task will fight the setter.
- **`setMCLLimit:` mutates a value the user can see in System Settings.** Snapshot before the first write, restore on disengage/quit, and disclose it in the UI.
- **Never `print()`** — `os.Logger` only. **No force-unwraps.**
- **All PowerUI access is private SPI.** Every selector must be looked up with `class_getInstanceMethod` and degrade to a logged error if absent — never assume a selector exists.
- **Commit messages must never mention Claude** and must not carry `Co-Authored-By` or `Generated with` trailers.

## Measured PowerUI surface

Dumped from the live framework on the development machine (unprivileged, no entitlement). Objective-C type encodings, which the `@convention(c)` trampolines must match exactly:

| Selector | Encoding | Meaning |
|---|---|---|
| `isMCLSupported` | `B16@0:8` | `-> BOOL` |
| `availableChargeLimitsWithError:` | `@24@0:8^@16` | `(NSError**) -> NSArray` — returned `(80, 85, 90, 95, 100)` |
| `getMCLLimitWithError:` | `C24@0:8^@16` | `(NSError**) -> unsigned char` — **not** an object |
| `isMCLCurrentlyEnabled:` | `Q24@0:8^@16` | `(NSError**) -> unsigned long long` |
| `setMCLLimit:error:` | `B28@0:8C16^@20` | `(UInt8, NSError**) -> BOOL` |
| `temporarilyOverrideMCLTargetSoC:error:` | `B28@0:8C16^@20` | already used by BatFi |

Apple documents the range as 80–100% with charging resuming after a **>5%** drop, and the limit is **not persistent while the Mac is off**.

**Verification commands** (CLI `swift build`/`swift test` do NOT work in this repo — do not attempt them, do not modify `Package.swift`):

```
xcodebuild test  -project BatFi.xcodeproj -scheme AppSharedTests -destination 'platform=macOS'
xcodebuild build -project BatFi.xcodeproj -scheme Server -destination 'platform=macOS'
xcodebuild build -project BatFi.xcodeproj -scheme BatFi  -destination 'platform=macOS'
```

A gitignored `BatFiKit/Sources/ClientsLive/AnalyticsDSN.swift` exists locally so the app compiles — leave it alone, never commit it.

---

### Task 1: `.systemChargeLimit` in the resolver, ranked last

**Files:**
- Modify: `BatFiKit/Sources/Shared/ChargeBackend.swift`
- Test: `BatFiKit/Tests/AppSharedTests/ChargeBackendResolverTests.swift`

**Interfaces:**
- Produces: `ChargeBackend.systemChargeLimit`; `resolve(_:systemChargeLimitSupported:)` — the existing single-argument `resolve(_:)` keeps working by defaulting that parameter to `false`.
- Produces: `ChargeBackend.honoursLimitsBelow80: Bool` — true for every SMC backend, false for `.systemChargeLimit`.

- [ ] **Step 1: Write the failing tests**

Append to `ChargeBackendResolverTests.swift`:

```swift
    /// Apple's limit is the fallback of last resort: only the SMC backends can
    /// express a limit below 80%, so they must outrank it.
    @Test func smcBackendsOutrankSystemChargeLimit() {
        let chte = table([cap("CHTE", "ui32", 4)])
        #expect(ChargeBackendResolver.resolve(chte, systemChargeLimitSupported: true) == .chte)

        let legacy = table([cap("CH0B", "ui8 ", 1), cap("CH0C", "ui8 ", 1)])
        #expect(ChargeBackendResolver.resolve(legacy, systemChargeLimitSupported: true) == .legacyCH0BC)
    }

    /// The macOS 27 case: no usable SMC key, but Apple's limit is available.
    @Test func fallsBackToSystemChargeLimitWhenNoSMCMechanism() {
        #expect(ChargeBackendResolver.resolve([:], systemChargeLimitSupported: true) == .systemChargeLimit)
    }

    @Test func unsupportedWhenNeitherSMCNorSystemLimit() {
        #expect(ChargeBackendResolver.resolve([:], systemChargeLimitSupported: false) == .unsupported)
    }

    /// A zero-size CHTE placeholder must not beat an available system limit.
    @Test func placeholderKeyDoesNotBeatSystemChargeLimit() {
        let caps = table([cap("CHTE", "ui32", 0)])
        #expect(ChargeBackendResolver.resolve(caps, systemChargeLimitSupported: true) == .systemChargeLimit)
    }

    @Test func onlySMCBackendsHonourLimitsBelow80() {
        #expect(ChargeBackend.chte.honoursLimitsBelow80)
        #expect(ChargeBackend.legacyCH0BC.honoursLimitsBelow80)
        #expect(!ChargeBackend.systemChargeLimit.honoursLimitsBelow80)
        #expect(!ChargeBackend.unsupported.honoursLimitsBelow80)
    }
```

- [ ] **Step 2: Run to verify failure**

`xcodebuild test -project BatFi.xcodeproj -scheme AppSharedTests -destination 'platform=macOS' -only-testing:AppSharedTests/ChargeBackendResolverTests`
Expected: FAIL — no `systemChargeLimit` case, no `systemChargeLimitSupported:` parameter.

- [ ] **Step 3: Implement**

In `ChargeBackend.swift`, add the case with a doc comment:

```swift
    /// Apple's Manual Charge Limit (macOS 26.4+). Fallback when no SMC mechanism
    /// works — notably macOS 27 firmware, which removed `CHTE`. Restricted to
    /// 80–100% in 5% steps, so it cannot honour BatFi's sub-80% limits.
    case systemChargeLimit
```

Add the capability:

```swift
    /// Whether this backend can express a limit below 80%. Apple's own limit cannot,
    /// which is the single most important thing to tell the user when it is active.
    public var honoursLimitsBelow80: Bool {
        switch self {
        case .chte, .legacyCH0BC: return true
        case .systemChargeLimit, .unsupported: return false
        }
    }
```

Update `isUsable` so `.systemChargeLimit` counts as usable. Extend `resolve`:

```swift
    public static func resolve(
        _ capabilities: [String: SMCKeyCapability],
        systemChargeLimitSupported: Bool = false
    ) -> ChargeBackend {
        if capabilities["CHTE"]?.matches(type: "ui32", size: 4, writable: true) == true {
            return .chte
        }
        if capabilities["CH0B"]?.matches(type: "ui8 ", size: 1, writable: true) == true,
           capabilities["CH0C"]?.matches(type: "ui8 ", size: 1, writable: true) == true {
            return .legacyCH0BC
        }
        // Ranked last on purpose: only the SMC backends honour limits below 80%.
        if systemChargeLimitSupported { return .systemChargeLimit }
        return .unsupported
    }
```

- [ ] **Step 4: Verify and commit**

Filtered tests pass (15 in that suite), then the full suite and the app build.

```bash
git add BatFiKit/Sources/Shared/ChargeBackend.swift BatFiKit/Tests/AppSharedTests/ChargeBackendResolverTests.swift
git commit -m "Add the system charge limit as a last-resort backend

Ranked below every SMC mechanism because Apple's limit only spans 80-100% in
5% steps, so it cannot honour the sub-80% limits that are BatFi's reason to
exist. It is the only thing that works on firmware where CHTE is gone."
```

---

### Task 2: Snapshot, set and restore the system limit

**Files:**
- Modify: `BatFiKit/Sources/Server/PowerUICharging.swift`

**Interfaces:**
- Produces on `PowerUICharging`: `var isMCLSupported: Bool` (added in Phase 2 — reuse it), `func availableLimits() -> [Int]`, `func currentSystemLimit() -> Int?`, `func adoptSystemLimit(_ percentage: Int) throws`, `func releaseSystemLimit()`.
- Produces: `PowerUIChargingError.limitOutOfRange(requested: Int, available: [Int])`.

- [ ] **Step 1: Add the read-only queries**

Follow the existing `clearMCLOverride` pattern exactly — look the selector up with `class_getInstanceMethod`, bail if absent, `unsafeBitCast` the IMP to a `@convention(c)` matching the measured encoding.

```swift
    /// Values Apple accepts, measured as (80, 85, 90, 95, 100). Queried rather than
    /// hardcoded so a future macOS that widens the range works without a code change.
    func availableLimits() -> [Int] {
        guard let client, let clientClass else { return [] }
        let selector = NSSelectorFromString("availableChargeLimitsWithError:")
        guard let method = class_getInstanceMethod(clientClass, selector) else { return [] }
        typealias Query = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> NSArray?
        let query = unsafeBitCast(method_getImplementation(method), to: Query.self)
        var error: NSError?
        guard let values = query(client, selector, &error) as? [NSNumber], error == nil else { return [] }
        return values.map(\.intValue).sorted()
    }

    /// The user's own System Settings value. Note the selector returns an unsigned
    /// char, not an object.
    func currentSystemLimit() -> Int? {
        guard let client, let clientClass else { return nil }
        let selector = NSSelectorFromString("getMCLLimitWithError:")
        guard let method = class_getInstanceMethod(clientClass, selector) else { return nil }
        typealias Query = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> UInt8
        let query = unsafeBitCast(method_getImplementation(method), to: Query.self)
        var error: NSError?
        let value = query(client, selector, &error)
        guard error == nil else { return nil }
        return Int(value)
    }
```

- [ ] **Step 2: Add snapshot-set-restore**

```swift
    /// The user's System Settings value, captured before BatFi first changed it.
    private var userSystemLimitSnapshot: Int?

    /// Drives Apple's Manual Charge Limit. Only for the `.systemChargeLimit` backend —
    /// every other backend releases the system limit instead of setting it, and the two
    /// must never run together or the renewal task will fight this setter.
    func adoptSystemLimit(_ percentage: Int) throws {
        guard let client, let clientClass else { throw PowerUIChargingError.frameworkUnavailable }

        let available = availableLimits()
        guard available.contains(percentage) else {
            throw PowerUIChargingError.limitOutOfRange(requested: percentage, available: available)
        }

        if userSystemLimitSnapshot == nil {
            userSystemLimitSnapshot = currentSystemLimit()
            logger.notice("Captured user's system charge limit: \(self.userSystemLimitSnapshot?.description ?? "unknown", privacy: .public)")
        }

        let selector = NSSelectorFromString("setMCLLimit:error:")
        guard let method = class_getInstanceMethod(clientClass, selector) else {
            throw PowerUIChargingError.selectorUnavailable("setMCLLimit:error:")
        }
        typealias Setter = @convention(c) (AnyObject, Selector, UInt8, AutoreleasingUnsafeMutablePointer<NSError?>?) -> ObjCBool
        let setter = unsafeBitCast(method_getImplementation(method), to: Setter.self)

        var error: NSError?
        let success = setter(client, selector, UInt8(percentage), &error).boolValue
        if let error { throw PowerUIChargingError.apiCallFailed(error) }
        guard success else { throw PowerUIChargingError.apiCallReturnedFalse }
        logger.notice("System charge limit set to \(percentage, privacy: .public)%")
    }

    /// Puts the user's own value back. Safe to call when nothing was ever adopted.
    func releaseSystemLimit() {
        guard let snapshot = userSystemLimitSnapshot else { return }
        userSystemLimitSnapshot = nil
        do {
            try adoptSystemLimitWithoutSnapshotting(snapshot)
            logger.notice("Restored user's system charge limit to \(snapshot, privacy: .public)%")
        } catch {
            logger.error("Could not restore the user's system charge limit: \(error, privacy: .public)")
        }
    }
```

Factor the raw setter call into `adoptSystemLimitWithoutSnapshotting(_:)` so `releaseSystemLimit` cannot re-capture a snapshot while restoring. Add the new error case with a `description` naming the requested and available values.

- [ ] **Step 3: Verify and commit**

Build `Server` and `BatFi`; suite unchanged.

```bash
git add BatFiKit/Sources/Server/PowerUICharging.swift
git commit -m "Drive Apple's charge limit, snapshotting the user's own value first

setMCLLimit changes something the user can see in System Settings, so the
original is captured before the first write and restored on release. The
accepted values are queried rather than hardcoded."
```

---

### Task 3: Wire `.systemChargeLimit` into `SMCService`

**Files:**
- Modify: `BatFiKit/Sources/Server/SMCService.swift`

- [ ] **Step 1: Feed MCL support into backend resolution**

In `currentBackend()`, pass PowerUI's answer to the resolver:

```swift
        let backend = ChargeBackendResolver.resolve(
            capabilities,
            systemChargeLimitSupported: await PowerUICharging.shared.isMCLSupported
        )
```

- [ ] **Step 2: Make MCL ownership exclusive**

`setChargingMode` currently overrides the MCL to 100 on `.auto`. That must happen **only** when an SMC backend owns charging. Under `.systemChargeLimit`, BatFi is the setter and must not also release.

Restructure so that, after the SMC writes:

```swift
        switch await currentBackend() {
        case .chte, .legacyCH0BC:
            // An SMC backend owns charging; get Apple's limit out of the way.
            if message == .auto { try? await PowerUICharging.shared.overrideMCLTarget(100) }
        case .systemChargeLimit, .unsupported:
            // BatFi either owns the system limit or has no mechanism. Either way it
            // must not also hold a temporary override, which would fight the setter.
            await PowerUICharging.shared.clearMCLOverride()
        }
```

- [ ] **Step 3: Route inhibit through the system limit**

`enableCharging(_:)` throws `.unsupported` for the `.systemChargeLimit` case today. Charging control under this backend is expressed as a *limit*, not an inhibit, so add a service method the manager calls instead:

```swift
    /// Applies a charge limit using whichever mechanism this firmware supports.
    /// Returns the limit actually applied, which may be higher than requested when
    /// the system limit is in use — it cannot go below 80%.
    func applyChargeLimit(_ percentage: Int) async throws -> Int {
        switch await currentBackend() {
        case .chte, .legacyCH0BC:
            return percentage        // handled by the existing inhibit path
        case .systemChargeLimit:
            let available = await PowerUICharging.shared.availableLimits()
            let applied = available.first(where: { $0 >= percentage }) ?? available.last ?? 100
            try await PowerUICharging.shared.adoptSystemLimit(applied)
            if applied != percentage {
                logger.notice("Requested \(percentage, privacy: .public)% raised to \(applied, privacy: .public)% — the system limit cannot go lower")
            }
            return applied
        case .unsupported:
            throw SMCError.keyNotFound(code: "CHTE")
        }
    }
```

Rounding **up** to the nearest available value is deliberate: it is the safe direction. Rounding down would charge past what the user asked for.

- [ ] **Step 4: Release on disengage**

`restoreSystemDefaults()` must call `await PowerUICharging.shared.releaseSystemLimit()` alongside its existing clearing, so quitting BatFi puts the user's System Settings value back.

- [ ] **Step 5: Report it in diagnostics**

`ChargingDiagnostics` (Phase 2) already carries `backend`. Add the applied limit and whether it was raised, so the UI can explain itself. Extend the type and its `NSSecureCoding` implementation following the existing field pattern.

- [ ] **Step 6: Verify and commit**

Build both schemes; run the suite.

```bash
git add BatFiKit/Sources/Server/SMCService.swift BatFiKit/Sources/Shared/ChargingDiagnostics.swift
git commit -m "Apply the charge limit through Apple's limit when no SMC key works

Ownership of the system limit inverts under this backend: BatFi sets it rather
than overriding it to 100, and the two paths are mutually exclusive. A limit
below 80% is raised to the nearest value Apple accepts, which is the safe
direction."
```

---

### Task 4: Per-capability feature gating

Under `.systemChargeLimit` BatFi no longer owns the charging decision, but two features depend on separate keys that may still work. **Probe them; do not blanket-disable.**

- **Force discharge** uses `CHIE`, which survives on Golden Gate firmware including beta 4, where the charge-limit keys broke.
- **MagSafe LED** uses `ACLC`, which is present on macOS 27. Under `.systemChargeLimit` BatFi still knows the state — via `isMCLCurrentlyEnabled:` and `CHNC` bit 24 (`systemChargeLimit`) from Phase 2 — so the LED can still mirror it.

**Files:**
- Modify: `BatFiKit/Sources/Server/SMCService.swift`, `BatFiKit/Sources/Shared/ChargingDiagnostics.swift`

- [ ] **Step 1: Report per-feature availability**

Add to `ChargingDiagnostics`: `forceDischargeAvailable: Bool`, `magSafeLEDAvailable: Bool`. Populate them from `SMCKit.probeCapability("CHIE") != nil` and `SMCKit.probeCapability("ACLC") != nil` — the key table, not the backend.

- [ ] **Step 2: Drive the LED from gate attribution under the system limit**

Where `MagSafeColorManager` decides colour from BatFi's own inhibit flag, use the diagnostics' `notChargingReasons` containing `systemChargeLimit` as the "we are holding charge" signal when the backend is `.systemChargeLimit`. Keep the existing behaviour for SMC backends unchanged.

- [ ] **Step 3: Verify and commit**

```bash
git add BatFiKit/Sources/Server BatFiKit/Sources/Shared/ChargingDiagnostics.swift BatFiKit/Sources/AppCore/MagSafeColorManager.swift
git commit -m "Gate force discharge and the MagSafe LED on their own keys

Both use keys independent of the charge-limit mechanism, so they are probed
rather than assumed unavailable. CHIE in particular survives on firmware where
the charge-limit keys do not."
```

---

### Task 5: Tell the user what is and is not available

The honest label is not "reduced functionality on macOS 27" — it is that **limits below 80% cannot be applied on this firmware**. A user set to 55% needs to know their setting is not being honoured.

**Files:**
- Modify: the Charging settings pane and `BatFiKit/Sources/L10n/Strings.swift`

- [ ] **Step 1: Add the strings**

Add to `L10n` following the existing key naming convention:
- a banner for `.systemChargeLimit`: BatFi is using the macOS charge limit on this Mac, which only supports 80–100%;
- a specific warning when the user's configured limit is below 80: their limit cannot be applied and *N*% is being used instead;
- a note that BatFi is managing the System Settings value and will restore it on quit;
- a line for `.unsupported`: BatFi cannot control charging on this firmware.

- [ ] **Step 2: Render them**

In the Charging pane, drive the banner from `ChargingDiagnostics.backend` and the applied-limit fields. Disable or annotate the limit slider below 80% when `!backend.honoursLimitsBelow80`, rather than letting the user set a value that will be silently raised.

- [ ] **Step 3: Verify and commit**

```bash
git add BatFiKit/Sources/Settings BatFiKit/Sources/L10n/Strings.swift
git commit -m "Say plainly when a limit below 80% cannot be applied

The useful message is not that macOS 27 is unsupported but that this firmware
only accepts 80-100%, so a user set to 55% learns their limit is not in effect."
```

---

### Task 6: Phase 3 verification

- [ ] **Step 1: Suite and builds** — full suite, `BatFi` and `Server` schemes.
- [ ] **Step 2: No version gates** — `grep -rn '#available\|@available\|operatingSystemVersion' BatFiKit/Sources/Server/` → no output.
- [ ] **Step 3: MCL ownership is exclusive** — read `setChargingMode` and confirm no path can both `overrideMCLTarget(100)` and `adoptSystemLimit(_:)`.
- [ ] **Step 4: Behaviour unchanged on this machine** — the dev Mac resolves `.chte`, so the system-limit path must not engage. Confirm the helper logs `chte` and that setting a limit still inhibits charging.
- [ ] **Step 5: On this Mac, the MCL queries work** — macOS 26.6 supports MCL, so `availableLimits()` should return `[80, 85, 90, 95, 100]`. Log it once at startup to confirm the SPI bridge is correct, since this is the one part testable locally.
- [ ] **Step 6: Working tree clean**, `AnalyticsDSN.swift` uncommitted.
