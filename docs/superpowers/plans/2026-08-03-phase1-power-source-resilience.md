# Phase 1 — Power-Source Resilience & CHIE Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop BatFi appearing dead on macOS 27 by making the power-source stream survive missing IORegistry values, recover on its own, and report *which* field failed — and fix force-discharge by writing the correct `CHIE` byte.

**Architecture:** Extract the IOKit-dictionary→`PowerState` conversion into a pure, testable assembler in `AppShared` that distinguishes **required** fields (absence is an error) from **optional** ones (absence degrades one UI element). `PowerSourceClient+Live` becomes a thin IOKit reader feeding that assembler, wrapped in retry-with-backoff plus a slow re-poll so recovery never depends on an IOPS notification that may not arrive.

**Tech Stack:** Swift 6 language mode, SwiftPM (`BatFiKit`), swift-testing (`import Testing`), point-free swift-dependencies, IOKit.ps / IOKit.pwr_mgt, Core Data (charts only).

## Global Constraints

- **Swift 6 language mode** for all targets — `swiftSettings: swiftV6LanguageMode()` in `BatFiKit/Package.swift`.
- **Minimum macOS is being raised to 15.0** in a later phase. Do **not** change deployment targets in this plan.
- **Tests go in `AppSharedTests`** — the only existing test target, dependency `AppShared` only. Do not add a test target.
- **Test style:** `@Suite struct XTests { @Test func name() { #expect(...) } }`, `@testable import AppShared`.
- **`Server` target = the privileged helper.** It has no test seam in this phase; changes there are minimal and reviewed by inspection.
- **Never `print()`** — use `os.Logger`, matching surrounding code.
- **Version bump to `3.1.2`** in `Supporting Files/Config.xcconfig` (`APP_VERSION`), plus a `CHANGELOG.md` entry. Do not touch `BUILD_NUMBER` (it is `99999`, a signing-requirement placeholder).
- **Commit messages must never mention Claude** and must not carry `Co-Authored-By` or `Generated with` trailers.

## File Structure

| File | Responsibility |
|---|---|
| `BatFiKit/Sources/AppShared/PowerSourceAssembly.swift` | **new** — `PowerSourceReadings`, `PowerSourceField`, `PowerSourceAssemblyError`, `PowerStateAssembler`. Pure, no IOKit. |
| `BatFiKit/Sources/AppShared/PowerState.swift` | make degradable fields optional |
| `BatFiKit/Tests/AppSharedTests/PowerStateAssemblerTests.swift` | **new** — required/optional matrix |
| `BatFiKit/Sources/ClientsLive/PowerSourceClient+Live.swift` | thin IOKit reader + retry/re-poll/coalesce + diagnostics |
| `BatFiKit/Sources/AppCore/ChargingManager.swift` | optional temperature in the hot-battery guard |
| `BatFiKit/Sources/AppCore/StatusItem.swift` | optional `timeLeft` |
| `BatFiKit/Sources/BatteryInfo/BatteryInfoView.swift`, `BatteryInfoView+Model.swift` | optional cycle count / temperature / times |
| `BatFiKit/Sources/Persistence/PowerStateModel+PowerState.swift` | optional temperature → Core Data scalar |
| `BatFiKit/Sources/BatteryIndicator/BatteryIndicatorView.Model.swift`, `PercentageLabel.swift` | `hasReading` — unknown vs 0% |
| `BatFiKit/Sources/App/HelperConnectionManager.swift` | accurate stuck-mode notification |
| `BatFiKit/Sources/Server/SMCService.swift`, `SMC+Keys.swift` | `CHIE` = `0x08` |
| `Supporting Files/Config.xcconfig`, `CHANGELOG.md` | version bump |

---

### Task 1: Make degradable `PowerState` fields optional

Only `batteryLevel`, `isCharging`, `powerSource` and `chargerConnected` are load-bearing for charging decisions. Everything else is display and must not be able to kill the app.

**Files:**
- Modify: `BatFiKit/Sources/AppShared/PowerState.swift`
- Modify: `BatFiKit/Sources/AppCore/ChargingManager.swift:291-294`
- Modify: `BatFiKit/Sources/AppCore/StatusItem.swift:70`
- Modify: `BatFiKit/Sources/BatteryInfo/BatteryInfoView.swift:74,77`
- Modify: `BatFiKit/Sources/BatteryInfo/BatteryInfoView+Model.swift:40-47`
- Modify: `BatFiKit/Sources/Persistence/PowerStateModel+PowerState.swift:20`

**Interfaces:**
- Consumes: nothing.
- Produces: `PowerState` with `timeLeft: Int?`, `timeToCharge: Int?`, `batteryCycleCount: Int?`, `batteryTemperature: Double?`. `batteryHealth` is already `Int?`. All other properties unchanged.

- [ ] **Step 1: Change the four property declarations and the initializer parameters**

In `PowerState.swift`, change these four stored properties and the matching `init` parameters (leave every other property and parameter exactly as-is):

```swift
    public let timeLeft: Int?
    public let timeToCharge: Int?
    public let batteryCycleCount: Int?
    public let batteryTemperature: Double?
```

```swift
        timeLeft: Int?,
        timeToCharge: Int?,
        batteryCycleCount: Int?,
        batteryTemperature: Double?,
```

- [ ] **Step 2: Update `description` to render unknowns**

Replace the `description` body's interpolations for the four fields so a missing value prints `unknown` rather than `Optional(…)`:

```swift
    public var description: String {
        """
        PowerState |==> is charging: \(isCharging), battery level: \(batteryLevel), power source: \(powerSource), time left: \(timeLeft?.description ?? "unknown"), time to charge: \(timeToCharge?.description ?? "unknown"), cycle count: \(batteryCycleCount?.description ?? "unknown"), battery health: \(batteryHealth?.description ?? "unknown"), battery temperature: \(batteryTemperature?.description ?? "unknown")°C, charger connected: \(chargerConnected), optimized battery charging engaged: \(String(describing: optimizedBatteryChargingEngaged))
        """
    }
```

- [ ] **Step 3: Fix the hot-battery safety guard**

`ChargingManager.swift:291`. An **unknown** temperature must not trigger a safety inhibit — and note this is strictly safer than today, where a missing temperature meant no charging decisions happened at all.

```swift
        if turnOffChargingWithHotBattery,
           let batteryTemperature = powerState.batteryTemperature,
           batteryTemperature > Constant.batteryTemperatureWarning {
            logger.notice("Battery is hot")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Battery is hot, \(batteryTemperature)")
            await inhibitCharging(chargerConnected: chargerConnected, currentMode: currentMode)
            return
        }
```

- [ ] **Step 4: Fix `StatusItem.swift:70`**

`model.powerState?.timeLeft` is now doubly optional; bind in two steps:

```swift
        guard let powerState = model.powerState, let timeLeft = powerState.timeLeft else { return nil }
        let time = Time.timeLeft(time: timeLeft)
```

- [ ] **Step 5: Fix `BatteryInfoView+Model.swift` `time`**

`Time.init` takes non-optional `Int`s; return `nil` when either is unknown rather than changing `Time`:

```swift
    var time: Time? {
        guard let state, let timeLeft = state.timeLeft, let timeToCharge = state.timeToCharge else { return nil }
        return Time(
            isCharging: state.isCharging,
            timeLeft: timeLeft,
            timeToCharge: timeToCharge,
            batteryLevel: state.batteryLevel
        )
    }
```

`temperatureDescription()` at line 119 already uses `guard let temperature = state?.batteryTemperature` and now compiles unchanged against the doubly-optional chain — leave it.

- [ ] **Step 6: Fix `BatteryInfoView.swift`**

Line 74 — cycle count is now optional:

```swift
                                info: powerState?.batteryCycleCount?.description ?? unknown
```

Line 77 — flatten the double optional:

```swift
                        let batteryReachedFortyDegrees = model.state.flatMap(\.batteryTemperature)
                            .map { $0 >= Constant.batteryTemperatureWarning } ?? false
```

- [ ] **Step 7: Fix the Core Data bridge**

`PowerStateModel+PowerState.swift:20`. The Core Data attribute is a non-optional scalar, and the chart's temperature series is secondary to battery level:

```swift
        // Core Data scalar attribute; temperature is a secondary chart series, so an
        // unknown reading records as 0 rather than dropping the whole sample.
        batteryTemperature = powerState.batteryTemperature ?? 0
```

- [ ] **Step 8: Build and confirm no remaining call sites break**

Run: `xcodebuild build -project BatFi.xcodeproj -scheme BatFi -destination 'platform=macOS'`
Expected: build succeeds. If the compiler flags a site not listed above, fix it the same way (bind the optional, or supply a display fallback) — do not force-unwrap.

- [ ] **Step 9: Commit**

```bash
git add BatFiKit/Sources/AppShared/PowerState.swift BatFiKit/Sources/AppCore/ChargingManager.swift BatFiKit/Sources/AppCore/StatusItem.swift BatFiKit/Sources/BatteryInfo/BatteryInfoView.swift BatFiKit/Sources/BatteryInfo/BatteryInfoView+Model.swift BatFiKit/Sources/Persistence/PowerStateModel+PowerState.swift
git commit -m "Make degradable PowerState fields optional

Time remaining, time to charge, cycle count and temperature are display
values. Modelling them as non-optional forced the power source reader to
throw when any one was missing, which killed the whole power state stream."
```

---

### Task 2: Pure `PowerStateAssembler` with required/optional split

**Files:**
- Create: `BatFiKit/Sources/AppShared/PowerSourceAssembly.swift`
- Test: `BatFiKit/Tests/AppSharedTests/PowerStateAssemblerTests.swift`

**Interfaces:**
- Consumes: `PowerState` from Task 1.
- Produces:
  - `public enum PowerSourceField: String, Sendable, CaseIterable` — cases `batteryLevel`, `isCharging`, `powerSource`, `chargerConnected`, with raw values equal to the IOKit key names.
  - `public struct PowerSourceAssemblyError: Error, Equatable, CustomStringConvertible` — property `missingField: PowerSourceField`.
  - `public struct PowerSourceReadings: Sendable` — memberwise init with **every parameter defaulting to `nil`**.
  - `public enum PowerStateAssembler` — `public static func assemble(_ readings: PowerSourceReadings) throws -> PowerState`.

- [ ] **Step 1: Write the failing tests**

Create `BatFiKit/Tests/AppSharedTests/PowerStateAssemblerTests.swift`:

```swift
//
//  PowerStateAssemblerTests.swift
//  BatFi
//
//  The macOS 27 "stuck initializing" bug: one missing IORegistry value used to
//  throw and take down the entire power state stream. Only genuinely required
//  fields may fail; everything else degrades to nil.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct PowerStateAssemblerTests {
    /// Every required field present, every optional field absent.
    private var minimal: PowerSourceReadings {
        PowerSourceReadings(
            batteryLevel: 80,
            isCharging: false,
            powerSource: "Battery Power",
            chargerConnected: false
        )
    }

    @Test func assemblesWithOnlyRequiredFields() throws {
        let state = try PowerStateAssembler.assemble(minimal)
        #expect(state.batteryLevel == 80)
        #expect(state.isCharging == false)
        #expect(state.powerSource == "Battery Power")
        #expect(state.chargerConnected == false)
        #expect(state.timeLeft == nil)
        #expect(state.timeToCharge == nil)
        #expect(state.batteryCycleCount == nil)
        #expect(state.batteryTemperature == nil)
        #expect(state.batteryHealth == nil)
        #expect(state.optimizedBatteryChargingEngaged == nil)
    }

    @Test func populatesOptionalFieldsWhenPresent() throws {
        var readings = minimal
        readings.timeLeft = 49
        readings.timeToCharge = -1
        readings.cycleCount = 272
        readings.temperatureRaw = 3500
        readings.batteryHealth = 85
        readings.optimizedBatteryChargingEngaged = true

        let state = try PowerStateAssembler.assemble(readings)
        #expect(state.timeLeft == 49)
        #expect(state.timeToCharge == -1)
        #expect(state.batteryCycleCount == 272)
        #expect(state.batteryHealth == 85)
        #expect(state.optimizedBatteryChargingEngaged == true)
    }

    /// AppleSmartBattery reports hundredths of a degree: 3500 -> 35.0 C.
    @Test func convertsRawTemperatureToCelsius() throws {
        var readings = minimal
        readings.temperatureRaw = 3500
        let state = try PowerStateAssembler.assemble(readings)
        #expect(state.batteryTemperature == 35.0)
    }

    /// The regression guard: no single optional value may prevent assembly.
    @Test func anyOptionalMissingIndividuallyStillAssembles() throws {
        var full = minimal
        full.timeLeft = 49
        full.timeToCharge = 0
        full.cycleCount = 272
        full.temperatureRaw = 3500
        full.batteryHealth = 85
        full.optimizedBatteryChargingEngaged = false

        var withoutTime = full;        withoutTime.timeLeft = nil; withoutTime.timeToCharge = nil
        var withoutCycles = full;      withoutCycles.cycleCount = nil
        var withoutTemperature = full; withoutTemperature.temperatureRaw = nil
        var withoutHealth = full;      withoutHealth.batteryHealth = nil
        var withoutOBC = full;         withoutOBC.optimizedBatteryChargingEngaged = nil

        for readings in [withoutTime, withoutCycles, withoutTemperature, withoutHealth, withoutOBC] {
            #expect(throws: Never.self) { try PowerStateAssembler.assemble(readings) }
        }
    }

    @Test func missingRequiredFieldNamesTheField() {
        var noLevel = minimal;   noLevel.batteryLevel = nil
        var noCharging = minimal; noCharging.isCharging = nil
        var noSource = minimal;  noSource.powerSource = nil
        var noCharger = minimal; noCharger.chargerConnected = nil

        let expectations: [(PowerSourceReadings, PowerSourceField)] = [
            (noLevel, .batteryLevel),
            (noCharging, .isCharging),
            (noSource, .powerSource),
            (noCharger, .chargerConnected),
        ]

        for (readings, expectedField) in expectations {
            #expect(throws: PowerSourceAssemblyError(missingField: expectedField)) {
                try PowerStateAssembler.assemble(readings)
            }
        }
    }

    @Test func errorDescriptionNamesTheIOKitKey() {
        let error = PowerSourceAssemblyError(missingField: .chargerConnected)
        #expect(error.description.contains("ExternalConnected"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project BatFi.xcodeproj -scheme AppSharedTests -destination 'platform=macOS' -only-testing:AppSharedTests/PowerStateAssemblerTests`
Expected: FAIL — `cannot find 'PowerSourceReadings' in scope`, `cannot find 'PowerStateAssembler' in scope`.

- [ ] **Step 3: Write the implementation**

Create `BatFiKit/Sources/AppShared/PowerSourceAssembly.swift`:

```swift
//
//  PowerSourceAssembly.swift
//
//
//  Pure conversion from IOKit readings to PowerState.
//
//  Kept free of IOKit so it can be tested directly, and so the required/optional
//  distinction lives in one reviewable place. Only fields that charging decisions
//  depend on are required; display values degrade to nil.
//

import Foundation

/// A power-source value that must be present. Raw values are the IOKit key names,
/// so a log line names exactly which key went missing on a new firmware.
public enum PowerSourceField: String, Sendable, CaseIterable {
    case batteryLevel = "Current Capacity"
    case isCharging = "Is Charging"
    case powerSource = "Power Source State"
    case chargerConnected = "ExternalConnected"
}

public struct PowerSourceAssemblyError: Error, Equatable, CustomStringConvertible {
    public let missingField: PowerSourceField

    public init(missingField: PowerSourceField) {
        self.missingField = missingField
    }

    public var description: String {
        "Required power source field missing: \(missingField.rawValue)"
    }
}

/// Raw values read from IOPS and AppleSmartBattery, before validation.
public struct PowerSourceReadings: Sendable {
    // Required
    public var batteryLevel: Int?
    public var isCharging: Bool?
    public var powerSource: String?
    public var chargerConnected: Bool?

    // Optional — display only
    public var timeLeft: Int?
    public var timeToCharge: Int?
    public var cycleCount: Int?
    /// AppleSmartBattery `VirtualTemperature`, in hundredths of a degree Celsius.
    public var temperatureRaw: Double?
    public var batteryHealth: Int?
    public var optimizedBatteryChargingEngaged: Bool?

    public init(
        batteryLevel: Int? = nil,
        isCharging: Bool? = nil,
        powerSource: String? = nil,
        chargerConnected: Bool? = nil,
        timeLeft: Int? = nil,
        timeToCharge: Int? = nil,
        cycleCount: Int? = nil,
        temperatureRaw: Double? = nil,
        batteryHealth: Int? = nil,
        optimizedBatteryChargingEngaged: Bool? = nil
    ) {
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.powerSource = powerSource
        self.chargerConnected = chargerConnected
        self.timeLeft = timeLeft
        self.timeToCharge = timeToCharge
        self.cycleCount = cycleCount
        self.temperatureRaw = temperatureRaw
        self.batteryHealth = batteryHealth
        self.optimizedBatteryChargingEngaged = optimizedBatteryChargingEngaged
    }
}

public enum PowerStateAssembler {
    public static func assemble(_ readings: PowerSourceReadings) throws -> PowerState {
        guard let batteryLevel = readings.batteryLevel else {
            throw PowerSourceAssemblyError(missingField: .batteryLevel)
        }
        guard let isCharging = readings.isCharging else {
            throw PowerSourceAssemblyError(missingField: .isCharging)
        }
        guard let powerSource = readings.powerSource else {
            throw PowerSourceAssemblyError(missingField: .powerSource)
        }
        guard let chargerConnected = readings.chargerConnected else {
            throw PowerSourceAssemblyError(missingField: .chargerConnected)
        }

        return PowerState(
            batteryLevel: batteryLevel,
            isCharging: isCharging,
            powerSource: powerSource,
            timeLeft: readings.timeLeft,
            timeToCharge: readings.timeToCharge,
            batteryCycleCount: readings.cycleCount,
            batteryHealth: readings.batteryHealth,
            batteryTemperature: readings.temperatureRaw.map { $0 / 100 },
            chargerConnected: chargerConnected,
            optimizedBatteryChargingEngaged: readings.optimizedBatteryChargingEngaged
        )
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -project BatFi.xcodeproj -scheme AppSharedTests -destination 'platform=macOS' -only-testing:AppSharedTests/PowerStateAssemblerTests`
Expected: PASS — 6 tests.

- [ ] **Step 5: Commit**

```bash
git add BatFiKit/Sources/AppShared/PowerSourceAssembly.swift BatFiKit/Tests/AppSharedTests/PowerStateAssemblerTests.swift
git commit -m "Add pure PowerStateAssembler with required/optional field split

Only battery level, charging flag, power source and charger connection are
required. Everything else degrades to nil instead of failing the read.
Missing required fields now name the IOKit key that was absent."
```

---

### Task 3: Rewrite the IOKit reader on top of the assembler

Removes all six `guard … else throw PowerSourceError.infoMissing` sites, matches the stable `IOPMPowerSource` superclass instead of concrete `AppleSmartBattery`, and fixes an `IOServiceClose` called on an `io_service_t`.

**Files:**
- Modify: `BatFiKit/Sources/ClientsLive/PowerSourceClient+Live.swift:60-128`

**Interfaces:**
- Consumes: `PowerSourceReadings`, `PowerStateAssembler` (Task 2).
- Produces: `getPowerSourceInfo()` unchanged in signature — `() async throws -> PowerState` — but now throws only `PowerSourceAssemblyError`.

- [ ] **Step 1: Replace the body of `getPowerSourceInfo()`**

Replace lines 60–128 (from `func getPowerSourceInfo() async throws -> PowerState {` through its closing brace) with:

```swift
        func getPowerSourceInfo() async throws -> PowerState {
            func getValue<DataType>(_ identifier: String, from service: io_service_t) -> DataType? {
                guard service != IO_OBJECT_NULL else { return nil }
                if let valueRef = IORegistryEntryCreateCFProperty(service, identifier as CFString, kCFAllocatorDefault, 0) {
                    let value = valueRef.takeUnretainedValue() as? DataType
                    valueRef.release()
                    return value
                }
                return nil
            }

            var readings = PowerSourceReadings()

            let snapshotRef = IOPSCopyPowerSourcesInfo()
            defer { snapshotRef?.release() }
            let snapshot = snapshotRef?.takeUnretainedValue()
            let sourcesRef = IOPSCopyPowerSourcesList(snapshot)
            defer { sourcesRef?.release() }

            if let sources = sourcesRef?.takeUnretainedValue() as? [CFTypeRef], let first = sources.first,
               let info = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: AnyObject] {
                readings.batteryLevel = info[kIOPSCurrentCapacityKey] as? Int
                readings.isCharging = info[kIOPSIsChargingKey] as? Bool
                readings.powerSource = info[kIOPSPowerSourceStateKey] as? String
                readings.timeLeft = info[kIOPSTimeToEmptyKey] as? Int
                readings.timeToCharge = info[kIOPSTimeToFullChargeKey] as? Int
                readings.optimizedBatteryChargingEngaged = info["Optimized Battery Charging Engaged"] as? Bool
            }

            // Match IOPMPowerSource, the stable superclass, rather than the concrete
            // AppleSmartBattery: the concrete class has been renamed across firmware
            // generations before, and these properties are firmware-sourced.
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMPowerSource"))
            defer { if service != IO_OBJECT_NULL { IOObjectRelease(service) } }

            readings.cycleCount = getValue(kIOPMPSCycleCountKey, from: service)
            readings.temperatureRaw = getValue("VirtualTemperature", from: service)
            readings.chargerConnected = getValue(kIOPMPSExternalConnectedKey, from: service)
            readings.batteryHealth = await batteryHealthState.currentHealth()

            return try PowerStateAssembler.assemble(readings)
        }
```

Note three deliberate changes beyond the assembler swap: the force-unwrapped `sourcesRef!` and `as!` cast on the description dictionary are gone (they would crash rather than degrade); `IOServiceClose(service)` is removed because `service` is an `io_service_t`, not an `io_connect_t`; and battery health is read from a cache rather than computed inline — Task 6 supplies `currentHealth()`.

- [ ] **Step 2: Add a temporary shim so this task builds on its own**

Task 6 replaces this. Add to the `private actor BatteryHealthState` at the bottom of the file:

```swift
    func currentHealth() -> Int? { lastBatteryHealth?.health }
```

- [ ] **Step 3: Add `AppShared` to the `ClientsLive` target if it is not already a dependency**

Check `BatFiKit/Package.swift` for the `ClientsLive` target's `dependencies` array. `PowerSourceClient+Live.swift` already has `import AppShared` at line 8, so it is present — confirm and change nothing.

- [ ] **Step 4: Build**

Run: `xcodebuild build -project BatFi.xcodeproj -scheme BatFi -destination 'platform=macOS'`
Expected: build succeeds. `PowerSourceError.infoMissing` may now be unreferenced — leave the type in place; Task 5 removes it if it is genuinely dead.

- [ ] **Step 5: Commit**

```bash
git add BatFiKit/Sources/ClientsLive/PowerSourceClient+Live.swift
git commit -m "Read power source through the assembler, drop six throw sites

A single missing IORegistry value no longer fails the whole read. Also match
IOPMPowerSource rather than the concrete AppleSmartBattery class, remove two
force-unwraps that would crash instead of degrade, and stop calling
IOServiceClose on an io_service_t."
```

---

### Task 4: Retry, slow re-poll, and burst coalescing

Today the initial fetch is one-shot, and recovery depends entirely on an IOPS notification that stops arriving once power state settles — so the app stays at 0% forever and relaunching reproduces it exactly.

**Files:**
- Modify: `BatFiKit/Sources/ClientsLive/PowerSourceClient+Live.swift` — the `powerSourceChanges` stream and `Observer`

**Interfaces:**
- Consumes: `getPowerSourceInfo()` (Task 3).
- Produces: no API change to `PowerSourceClient`.

- [ ] **Step 1: Add retry and re-poll constants and a bounded-backoff helper**

Add just above `let observer = Observer(getPowerSourceInfo: getPowerSourceInfo)`:

```swift
        /// Launch-time transients (IOKit still settling) resolve within a couple of seconds.
        let initialRetryDelays: [Duration] = [.milliseconds(200), .milliseconds(400), .milliseconds(800), .milliseconds(1600)]
        /// Safety net so recovery never depends on an IOPS notification arriving.
        let failureRepollInterval: Duration = .seconds(60)

        @Sendable
        func fetchWithRetry() async -> PowerState? {
            for (attempt, delay) in initialRetryDelays.enumerated() {
                do {
                    return try await getPowerSourceInfo()
                } catch {
                    logger.error("Power source read failed (attempt \(attempt + 1)): \(error, privacy: .public)")
                    try? await Task.sleep(for: delay)
                }
            }
            do {
                return try await getPowerSourceInfo()
            } catch {
                logger.error("Power source read failed after retries: \(error, privacy: .public)")
                return nil
            }
        }
```

- [ ] **Step 2: Replace the stream's initial-fetch task with retry plus a failing re-poll**

Replace the `Task { … }` block inside `powerSourceChanges`' `AsyncStream` (currently lines 136–143) with:

```swift
                    let pollTask = Task {
                        // Retry, then keep re-polling only while failing. Stops on first success;
                        // the IOPS notification drives updates from then on.
                        while !Task.isCancelled {
                            if let state = await fetchWithRetry() {
                                continuation.yield(state)
                                return
                            }
                            try? await Task.sleep(for: failureRepollInterval)
                        }
                    }
```

and extend the existing termination handler so the task is cancelled:

```swift
                    continuation.onTermination = { _ in
                        cancellable.cancel()
                        pollTask.cancel()
                    }
```

- [ ] **Step 3: Coalesce the notification burst**

In `Observer`, replace the stored `getPowerSourceInfo` call site so overlapping callbacks collapse into one in-flight read. Replace the `Task { … }` inside the `IOPSNotificationCreateRunLoopSource` callback body with:

```swift
                        Task { await observer.refresh() }
```

and add to `Observer`:

```swift
        private var inFlight: Task<Void, Never>?

        /// macOS 27 raises a full system power-source change per charge-inhibit toggle,
        /// so callbacks arrive in bursts. Collapse them into one read.
        func refresh() async {
            if let inFlight, !inFlight.isCancelled { return await inFlight.value }
            let task = Task { [weak self] in
                guard let self else { return }
                do {
                    let powerState = try await self.getPowerSourceInfo()
                    self.logger.debug("New power state: \(powerState)")
                    self.subject.send(powerState)
                } catch {
                    self.logger.error("Power source read failed on notification: \(error, privacy: .public)")
                }
            }
            inFlight = task
            await task.value
            inFlight = nil
        }
```

Because `refresh()` mutates `inFlight`, mark `Observer` as an `actor` instead of `final class`, and delete its `@unchecked Sendable` conformance. Update the `Unmanaged<Observer>` bridging in `setUpObserving()` to call `Task { await observer.refresh() }` as shown, and move `setUpObserving()` out of `init` into an explicit call after construction:

```swift
        let observer = Observer(getPowerSourceInfo: getPowerSourceInfo)
        Task { await observer.startObserving() }
```

renaming `setUpObserving()` to `startObserving()`.

- [ ] **Step 4: Build**

Run: `xcodebuild build -project BatFi.xcodeproj -scheme BatFi -destination 'platform=macOS'`
Expected: build succeeds with no concurrency diagnostics. If the `Unmanaged` context bridging fights the actor conversion, keep `Observer` a `final class` and guard `inFlight` with an `NSLock` instead — the coalescing behaviour is what matters, not the isolation mechanism.

- [ ] **Step 5: Commit**

```bash
git add BatFiKit/Sources/ClientsLive/PowerSourceClient+Live.swift
git commit -m "Retry power source reads and re-poll while failing

The initial read was one-shot and recovery depended on an IOPS notification
that stops arriving once power state settles, so a transient failure became
permanent and relaunching did not help. Adds bounded backoff, a 60s re-poll
that stops on first success, and coalescing for notification bursts."
```

---

### Task 5: Diagnostics — name the failing field, log the firmware

Every current report says only `Can't get the current power source info`, which is why this bug still is not pinned to a specific key. One report should be enough.

**Files:**
- Modify: `BatFiKit/Sources/ClientsLive/PowerSourceClient+Live.swift`

**Interfaces:**
- Consumes: `PowerSourceField` (Task 2).
- Produces: `systemFirmwareVersion()` — `@Sendable () -> String?`, file-private.

- [ ] **Step 1: Add the firmware token reader**

Add near the top of the `liveValue` closure, after `let logger = …`:

```swift
        /// Opaque identity token, e.g. "mBoot-18000.161.9". Never parsed or compared —
        /// SMC behaviour tracks firmware, not macOS, so this is what belongs in a bug report.
        /// Note the prefix changed from "iBoot-" to "mBoot-" in macOS 26.4.
        @Sendable
        func systemFirmwareVersion() -> String? {
            let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/chosen")
            guard entry != IO_OBJECT_NULL else { return nil }
            defer { IOObjectRelease(entry) }
            for key in ["system-firmware-version", "firmware-version"] {
                guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() else { continue }
                if let string = value as? String, !string.isEmpty { return string }
                if let data = value as? Data {
                    // Fixed-size NUL-padded buffer; truncate at the first NUL.
                    let bytes = data.prefix(while: { $0 != 0 })
                    if let string = String(data: bytes, encoding: .utf8), !string.isEmpty { return string }
                }
            }
            return nil
        }
```

- [ ] **Step 2: Log the firmware token once at startup**

Immediately after `let observer = Observer(...)` / `startObserving()` wiring from Task 4, add:

```swift
        logger.notice("System firmware: \(systemFirmwareVersion() ?? "unknown", privacy: .public)")
```

- [ ] **Step 3: Dump the available battery properties when a required field is missing**

Add inside the `liveValue` closure:

```swift
        /// One report should be enough to identify a renamed property on new firmware.
        @Sendable
        func logAvailableBatteryProperties(missing: PowerSourceField) {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMPowerSource"))
            defer { if service != IO_OBJECT_NULL { IOObjectRelease(service) } }
            guard service != IO_OBJECT_NULL else {
                logger.error("Missing \(missing.rawValue, privacy: .public); IOPMPowerSource service not found")
                return
            }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return }
            let keys = dictionary.keys.sorted().joined(separator: ", ")
            logger.error("Missing \(missing.rawValue, privacy: .public). Firmware \(systemFirmwareVersion() ?? "unknown", privacy: .public). IOPMPowerSource keys: \(keys, privacy: .public)")
        }
```

- [ ] **Step 4: Call it from the retry helper's final failure**

In `fetchWithRetry()` (Task 4), replace the final `catch` body with:

```swift
            } catch {
                logger.error("Power source read failed after retries: \(error, privacy: .public)")
                if let assemblyError = error as? PowerSourceAssemblyError {
                    logAvailableBatteryProperties(missing: assemblyError.missingField)
                }
                return nil
            }
```

- [ ] **Step 5: Fix the discarded error**

`PowerSourceClient+Live.swift` previously logged `observer.logger.error("")` — an empty string that threw the error away entirely. Task 4 already replaced that call site with a message that interpolates `error`. Confirm by searching:

Run: `grep -n 'logger.error("")' BatFiKit/Sources/ClientsLive/PowerSourceClient+Live.swift`
Expected: no output.

- [ ] **Step 6: Remove `PowerSourceError` if it is now unused**

Run: `grep -rn 'PowerSourceError' BatFiKit/Sources`
If the only hit is its own declaration, delete it. If anything still references it, leave it alone.

- [ ] **Step 7: Build**

Run: `xcodebuild build -project BatFi.xcodeproj -scheme BatFi -destination 'platform=macOS'`
Expected: build succeeds.

- [ ] **Step 8: Commit**

```bash
git add BatFiKit/Sources/ClientsLive/PowerSourceClient+Live.swift
git commit -m "Name the missing power source field and log firmware in diagnostics

Reports previously carried only 'Can't get the current power source info',
which was not enough to identify which key a firmware update had removed.
Failures now name the IOKit key, record the firmware token, and dump the
properties the battery service actually exposes."
```

---

### Task 6: Battery health off the hot path

`getBatteryHealthIfNeeded()` spawns `system_profiler` with blocking `readDataToEndOfFile()` and `waitUntilExit()` inside the async read, on a path also driven by IOPS callbacks.

**Files:**
- Modify: `BatFiKit/Sources/ClientsLive/PowerSourceClient+Live.swift:23-57` and `private actor BatteryHealthState`

**Interfaces:**
- Consumes: nothing.
- Produces: `BatteryHealthState.currentHealth() -> Int?` (non-blocking cache read) and `BatteryHealthState.refreshIfStale() async` (does the work).

- [ ] **Step 1: Move the subprocess into the actor and make the read non-blocking**

Replace `private actor BatteryHealthState` with:

```swift
private actor BatteryHealthState {
    private var lastBatteryHealth: BatteryHealth?
    private var refreshTask: Task<Void, Never>?

    private static let maxAge: TimeInterval = 60 * 60
    private static let timeout: Duration = .seconds(10)

    /// Non-blocking: whatever we last computed, possibly nil. Never awaits a subprocess.
    func currentHealth() -> Int? { lastBatteryHealth?.health }

    /// Kicks off a refresh when the cache is cold or stale. Returns immediately.
    func refreshIfStale() {
        if let lastBatteryHealth, lastBatteryHealth.date.timeIntervalSinceNow > -Self.maxAge { return }
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            let health = await Self.readMaximumCapacity()
            await self?.store(health)
        }
    }

    private func store(_ health: Int?) {
        if let health { lastBatteryHealth = BatteryHealth(health: health, date: .now) }
        refreshTask = nil
    }

    /// Apple's reported "Maximum Capacity" is not a simple IORegistry ratio — on a test
    /// machine NominalChargeCapacity/DesignCapacity gave 82% and AppleRawMaxCapacity/
    /// DesignCapacity gave 80% where system_profiler reported 85%. Do not substitute one.
    private static func readMaximumCapacity() async -> Int? {
        await withTaskGroup(of: Int?.self) { group in
            group.addTask {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
                process.arguments = ["SPPowerDataType"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do { try process.run() } catch { return nil }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard let output = String(data: data, encoding: .utf8) else { return nil }
                for line in output.split(separator: "\n") where line.contains("Maximum Capacity") {
                    let components = line.components(separatedBy: ":")
                    guard components.count == 2 else { return nil }
                    let trimmed = components[1].trimmingCharacters(in: .whitespaces.union(.decimalDigits.inverted))
                    return Int(trimmed)
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: Self.timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

private struct BatteryHealth {
    let health: Int
    let date: Date
}
```

- [ ] **Step 2: Delete the old inline `getBatteryHealthIfNeeded()`**

Remove the whole `@Sendable func getBatteryHealthIfNeeded() async -> Int?` function (lines 23–57) — nothing calls it after Task 3.

- [ ] **Step 3: Trigger the refresh from the read without awaiting it**

In `getPowerSourceInfo()` (Task 3), replace the health line with:

```swift
            await batteryHealthState.refreshIfStale()
            readings.batteryHealth = await batteryHealthState.currentHealth()
```

`refreshIfStale()` returns as soon as the task is scheduled, so the first read after launch reports `nil` health and the next one picks it up. Health is optional per Task 2, so this degrades one label and nothing else.

- [ ] **Step 4: Remove the shim from Task 3**

The temporary `func currentHealth() -> Int? { lastBatteryHealth?.health }` added in Task 3 Step 2 is now the real implementation above — confirm there is exactly one definition.

Run: `grep -c 'func currentHealth' BatFiKit/Sources/ClientsLive/PowerSourceClient+Live.swift`
Expected: `1`

- [ ] **Step 5: Build**

Run: `xcodebuild build -project BatFi.xcodeproj -scheme BatFi -destination 'platform=macOS'`
Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add BatFiKit/Sources/ClientsLive/PowerSourceClient+Live.swift
git commit -m "Compute battery health off the power source read path

system_profiler was spawned with blocking reads inside the async power source
read, which is also driven by IOPS notification callbacks. Health is now
refreshed on its own schedule into the existing one hour cache, with a timeout,
and read non-blocking. Keeps system_profiler deliberately: Apple's reported
Maximum Capacity is not a simple IORegistry capacity ratio."
```

---

### Task 7: Fix the `CHIE` force-discharge byte

`CHIE` takes `0x08` to isolate the adapter, while the legacy `CH0I`/`CH0J` take `0x01`. BatFi writes `1` to all three, so force-discharge has been inert on every Tahoe-era firmware — matching issue #147, reported as broken "since macOS 26", which is exactly when `CHIE` became the active key.

**Files:**
- Modify: `BatFiKit/Sources/Server/SMC+Keys.swift`
- Modify: `BatFiKit/Sources/Server/SMCService.swift:308-331`

**Interfaces:**
- Consumes: nothing.
- Produces: `SMCKey.forceDischargeEngagedValue: UInt8` — per-key "engage" byte.

- [ ] **Step 1: Add the per-key engage value**

In `SMC+Keys.swift`, append inside `extension SMCKey`:

```swift
    /// Byte that engages adapter isolation for this key.
    ///
    /// CHIE is asymmetric: it takes 0x08, while the legacy CH0I/CH0J take 0x01.
    /// Verified against charlie0129/batt (`pkg/smc/adapter.go` writes 0x1 for
    /// AdapterKey1/2 and 0x8 for AdapterKey3), mhaeuser/Battery-Toolkit and
    /// actuallymentor/battery. Writing 0x01 to CHIE is accepted but inert.
    var forceDischargeEngagedValue: UInt8 {
        code == SMCKey.disableCharging3.code ? 0x08 : 0x01
    }
```

- [ ] **Step 2: Use it in `enableForceDischarge`**

In `SMCService.swift`, replace the body of `enableForceDischarge(_:)` from `let enableByte` to the end of the function with:

```swift
        func engageByte(for key: SMCKey) -> UInt8 { enable ? key.forceDischargeEngagedValue : 0 }

        do {
            try SMCKit.writeData(.disableCharging3, uint8: engageByte(for: .disableCharging3))
            logger.notice("Force discharge changed using new firmware")
        } catch {
            logger.error("Force discharge state change failed with new firmware. Using old as fallback")
            do {
                try? SMCKit.writeData(.disableCharging1, uint8: engageByte(for: .disableCharging1))
                try SMCKit.writeData(.disableCharging2, uint8: engageByte(for: .disableCharging2))
                logger.notice("Force discharge changed using old firmware")
            } catch {
                logger.error("Force discharge failed with old firmware")
                throw error
            }
        }
```

- [ ] **Step 3: Confirm the disengage path still writes zero**

`engageByte` returns `0` whenever `enable` is `false`, for every key — matching the previous behaviour and `resetIfPossible()`. Verify by reading the function; no separate change needed.

- [ ] **Step 4: Build**

Run: `xcodebuild build -project BatFi.xcodeproj -scheme BatFi -destination 'platform=macOS'`
Expected: build succeeds.

- [ ] **Step 5: Manual verification on this Mac**

This is the one change in this plan that touches hardware behaviour, and it has no automated test seam.

1. Build and run the app with the helper installed.
2. Enable "Run on Battery" with the charger connected.
3. Confirm the battery actually discharges: `ioreg -r -c AppleSmartBattery -w0 | tr ',' '\n' | grep -E '"(IsCharging|ExternalConnected)"'` and `pmset -g batt`.
4. Turn it off and confirm charging resumes.

Expected: discharge now engages. Before this change it did not on Tahoe-era firmware.

- [ ] **Step 6: Commit**

```bash
git add BatFiKit/Sources/Server/SMC+Keys.swift BatFiKit/Sources/Server/SMCService.swift
git commit -m "Write 0x08 to CHIE to engage force discharge

CHIE is asymmetric: it isolates the adapter on 0x08, while the legacy CH0I and
CH0J use 0x01. BatFi wrote 0x01 to all three, so force discharge was accepted
but inert on every Tahoe era firmware, where CHIE is the active key."
```

---

### Task 8: Distinguish "unknown" from 0%, and stop the misleading advice

`BatteryIndicatorViewModel.batteryLevel` is `Int = 0` and is only assigned when a power state arrives — so a
failed read renders as a confident **0%**. Separately, `HelperConnectionManager` tells the user to restart
their Mac when the app sits in `.initial`, which is wrong for this bug: the helper is healthy and charge
limiting may still be working.

**Files:**
- Modify: `BatFiKit/Sources/BatteryIndicator/BatteryIndicatorView.Model.swift:24,61`
- Modify: `BatFiKit/Sources/BatteryIndicator/PercentageLabel.swift:17-22`
- Modify: `BatFiKit/Sources/AppCore/StatusItem.swift:45`
- Modify: `BatFiKit/Sources/App/HelperConnectionManager.swift:52-68`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `BatteryIndicatorViewModel.hasReading: Bool` — `false` until the first successful power-source read.

- [ ] **Step 1: Add `hasReading` to the indicator model**

In `BatteryIndicatorView.Model.swift`, add below the `batteryLevel` declaration (line 24):

```swift
    /// False until the first successful power source read. Without this, a failed read is
    /// indistinguishable from a genuine 0% battery.
    @Published
    public var hasReading: Bool = false
```

and set it in `setUpObserving()`, immediately after `self.batteryLevel = powerState.batteryLevel` (line 61):

```swift
                self.hasReading = true
```

- [ ] **Step 2: Render a placeholder in the percentage label**

In `PercentageLabel.swift`, replace the condition at line 17 so an unknown reading shows an em dash rather than a number:

```swift
            if !model.hasReading {
                Text(verbatim: "–")
            } else if model.batteryLevel < 100 || model.chargingMode == .discharging {
```

Leave the existing `Text`/`initialValue:` body that follows unchanged — it is now the `else if` branch.

- [ ] **Step 3: Render a placeholder in the status item**

In `StatusItem.swift`, replace line 45:

```swift
                if batteryIndicatorModel.hasReading {
                    Text(batteryIndicatorModel.batteryLevel, format: .percent)
                } else {
                    Text(verbatim: "–")
                }
```

Keep the `.id("batteryLevel")` and any other modifiers applied to that view, attaching them to the enclosing
`if`/`else` group so layout is unchanged.

- [ ] **Step 4: Make the stuck-mode notification accurate**

In `HelperConnectionManager.swift`, replace the `showUserNotification` call inside `observerHelperConnection()`:

```swift
                try await userNotificationsClient.showUserNotification(
                    title: "⚠️ BatFi can't read battery information",
                    body: "macOS isn't reporting the battery details BatFi needs. Your charge limit may still be active. Please report this — the app's log names the missing value.",
                    identifier: "software.micropixels.BatFi.notifications.initial_mode",
                    threadIdentifier: nil,
                    delay: nil
                )
```

The surrounding `guard status == .enabled else { continue }` already ensures this only fires when the helper is
healthy — which is precisely the case where "restart your Mac" was wrong advice.

- [ ] **Step 5: Build**

Run: `xcodebuild build -project BatFi.xcodeproj -scheme BatFi -destination 'platform=macOS'`
Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add BatFiKit/Sources/BatteryIndicator/BatteryIndicatorView.Model.swift BatFiKit/Sources/BatteryIndicator/PercentageLabel.swift BatFiKit/Sources/AppCore/StatusItem.swift BatFiKit/Sources/App/HelperConnectionManager.swift
git commit -m "Show unknown rather than 0% when the battery cannot be read

The indicator defaulted to 0 and was only assigned on a successful read, so a
failed read looked like a real empty battery. Also replaces the stuck mode
notification's restart advice, which was wrong for this failure: the helper is
healthy and charging control may still be active."
```

---

### Task 9: Version bump and changelog

**Files:**
- Modify: `Supporting Files/Config.xcconfig:14`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Bump the app version**

In `Supporting Files/Config.xcconfig`, change:

```
APP_VERSION = 3.1.2
```

Leave `BUILD_NUMBER = 99999` untouched — it is a placeholder consumed by the SMJobBless code-signing requirement, not a real build number.

- [ ] **Step 2: Add the changelog entry**

Insert directly below the `[Semantic Versioning]` intro paragraph and above `## [3.1.1] - 2026-06-19`:

```markdown
## [3.1.2] - 2026-08-03

### Fixed
- **BatFi no longer gets stuck on "Initializing" with an empty battery reading.** A single
  missing value from the system's battery service — which happens when a macOS or firmware
  update renames or removes one — used to abort the entire battery read, leaving the menu bar
  at 0% and BatFi unable to make any charging decision. Quitting and relaunching did not help.
  Battery level, charging state and charger connection are now the only values BatFi requires;
  cycle count, temperature, time remaining and battery health degrade individually and hide
  just their own row. Reads also retry on launch and re-check every minute while failing, so
  BatFi recovers on its own instead of staying stuck.
- **"Run on Battery" now actually discharges on recent firmware.** BatFi was writing the wrong
  value to the charging controller key used by macOS 26-era firmware and newer, so the request
  was accepted but had no effect.

### Changed
- Battery health is no longer measured during the battery read, removing a blocking system
  call from a path that runs on every power change.
- When a battery value is missing, BatFi now records which one and the Mac's firmware version,
  so a single report is enough to diagnose the next firmware change.
```

- [ ] **Step 3: Commit**

```bash
git add "Supporting Files/Config.xcconfig" CHANGELOG.md
git commit -m "Bump version to 3.1.2"
```

---

### Task 10: Full verification

- [ ] **Step 1: Run the whole test suite**

Run: `xcodebuild test -project BatFi.xcodeproj -scheme AppSharedTests -destination 'platform=macOS'`
Expected: PASS — the three pre-existing suites plus `PowerStateAssemblerTests`.

- [ ] **Step 2: Build the app target**

Run: `xcodebuild -project BatFi.xcodeproj -scheme BatFi -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Confirm no throw sites remain in the power source read**

Run: `grep -n 'infoMissing' BatFiKit/Sources/ClientsLive/PowerSourceClient+Live.swift`
Expected: no output.

- [ ] **Step 4: Smoke-test the running app**

1. Launch the app; confirm the menu bar shows the real battery percentage, not 0%.
2. Open Battery Info; confirm cycle count, temperature and health all populate.
3. Check Console for `System firmware: mBoot-…` at startup.
4. Set a charge limit below the current level; confirm charging is inhibited.
5. Quit; confirm charging resumes.

- [ ] **Step 5: Confirm optional-field degradation manually**

Temporarily change `readings.temperatureRaw = getValue("VirtualTemperature", from: service)` to
`readings.temperatureRaw = nil`, rebuild, and confirm the app still runs normally with the
temperature row hidden and the menu bar correct. **Revert the change afterwards** — this is a
verification step, not a code change, and must not be committed.

- [ ] **Step 6: Confirm required-field failure degrades honestly**

This simulates the macOS 27 report. Temporarily change
`readings.chargerConnected = getValue(kIOPMPSExternalConnectedKey, from: service)` to
`readings.chargerConnected = nil`, rebuild and run.

Expected:
- The menu bar shows `–`, **not** `0%`.
- Console shows `Missing ExternalConnected. Firmware mBoot-…. IOPMPowerSource keys: …`.
- The read retries on launch and again roughly every 60 seconds — visible as repeated log lines,
  rather than 8 failures in the first second followed by silence.
- After ~30 s the notification reads "BatFi can't read battery information", not the restart advice.

**Revert the change afterwards.** Confirm with `git status` that the working tree is clean before
finishing.

---

## Notes for the implementer

- **Do not add macOS version checks.** SMC and battery-service behaviour tracks *firmware*, which
  moves independently of macOS: installing macOS 27 on any volume updates firmware for the whole
  Mac, downgrading macOS does not roll it back, and macOS 26.6 / 15.7.8 / 14.8.8 all ship
  identical firmware. Version gating is the bug class this phase exists to remove.
- **The development machine has never run macOS 27**, so none of this can be verified against the
  firmware that triggered the reports. That is deliberate: every change here is designed to be
  correct regardless of *which* value goes missing, and Task 5's diagnostics exist so the next
  report identifies it precisely.
- **Out of scope for this phase:** SMC capability probing, the firmware-keyed cache, delegating to
  Apple's built-in Charge Limit, and the macOS 27 `bfD0`/`bfE0`/`bfF0` keys. See
  `docs/superpowers/specs/2026-08-03-macos27-firmware-compat-design.md` phases 2–4.
