//
//  PowerSourceClient.swift
//
//
//  Created by Adam on 02/05/2023.
//

import AppShared
import Clients
import Combine
import Dependencies
import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import os
import Shared

extension PowerSourceClient: DependencyKey {
    public static let liveValue: PowerSourceClient = {
        let logger = Logger(category: "Power Source")

        let batteryHealthState = BatteryHealthState()

        /// One-shot gate for the derived-charger-connection notice, for the same reason
        /// `dumpGate` below exists: `getPowerSourceInfo` runs on every power change and
        /// ~6-8 subscribers drive it, so an ungated line is a flood on the one firmware
        /// that would emit it.
        let chargerConnectedGate = DumpGate()

        @Sendable
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

            // The *internal battery*, not whichever source happens to be first. With a UPS
            // attached `first` may be the UPS, and every field below would then describe
            // it. `isRunningOnLaptop` already demonstrates the correct filter; this is the
            // same one. Falls back to `first` so a firmware that stops publishing
            // `kIOPSTypeKey` degrades to today's behaviour rather than to no reading.
            let sources = sourcesRef?.takeUnretainedValue() as? [CFTypeRef] ?? []
            let descriptions = sources.compactMap {
                IOPSGetPowerSourceDescription(snapshot, $0)?.takeUnretainedValue() as? [String: AnyObject]
            }
            let internalBattery = descriptions.first {
                ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            }
            if let info = internalBattery ?? descriptions.first {
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
            //
            // Enumerated rather than taken as one arbitrary match. `IOServiceGetMatchingService`
            // returns whichever conformer the registry hands back first, which is correct on
            // the one Mac available to measure — exactly one node conforms — but broadening
            // the match class to the superclass is what makes a second conformer possible.
            // And because every field read below is now optional, the wrong node would not
            // error: cycle count, temperature and the charger connection would all silently
            // degrade to nil.
            let service = matchingBatteryService()
            defer { if service != IO_OBJECT_NULL { IOObjectRelease(service) } }

            readings.cycleCount = getValue(kIOPMPSCycleCountKey, from: service)
            // `Temperature` as a second source, not as a synonym. Both keys are published on
            // `IOPMPowerSource` today — measured on this Mac as 3084 and 3519 respectively,
            // about 4 °C apart, with `VirtualTemperature` reading hotter — so the fallback
            // trips the hot-battery cutout *later* than the primary and the primary stays
            // first. It exists because the alternative is nil, and a nil temperature does
            // not stop BatFi managing charging: it only removes the cutout, silently.
            readings.temperatureRaw = getValue("VirtualTemperature", from: service)
                ?? getValue("Temperature", from: service)
            // `AppleRawExternalConnected` as a second source, present on this Mac's
            // `IOPMPowerSource` node and carrying the same signal. Worth trying before the
            // power-source-string derivation in `PowerStateAssembler`, which is wrong
            // exactly while BatFi is force-discharging.
            readings.chargerConnected = getValue(kIOPMPSExternalConnectedKey, from: service)
                ?? getValue("AppleRawExternalConnected", from: service)
            if readings.chargerConnected == nil, chargerConnectedGate.shouldDump(.chargerConnected) {
                // The field is derived rather than required, so `assemble` can never throw
                // for it and `logAvailableBatteryProperties` can never fire for it. Without
                // this line, a firmware that renamed `ExternalConnected` produces zero
                // diagnostics about the one signal force discharge depends on.
                logger.error("Neither ExternalConnected nor AppleRawExternalConnected is published; deriving charger connection from the power source string")
            }
            await batteryHealthState.refreshIfStale()
            readings.batteryHealth = await batteryHealthState.currentHealth()

            return try PowerStateAssembler.assemble(readings)
        }

        /// The `IOPMPowerSource` node that is the Mac's own battery.
        ///
        /// Prefers a node reporting `BatteryInstalled == true`, and falls back to the first
        /// match — which is what the single-service call always returned — so a firmware
        /// that stops publishing that property degrades to today's behaviour.
        @Sendable
        func matchingBatteryService() -> io_service_t {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching("IOPMPowerSource"),
                &iterator
            ) == KERN_SUCCESS else { return IO_OBJECT_NULL }
            defer { IOObjectRelease(iterator) }

            var fallback: io_service_t = IO_OBJECT_NULL
            while case let candidate = IOIteratorNext(iterator), candidate != IO_OBJECT_NULL {
                let installed = IORegistryEntryCreateCFProperty(
                    candidate, "BatteryInstalled" as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() as? Bool
                if installed == true {
                    if fallback != IO_OBJECT_NULL { IOObjectRelease(fallback) }
                    return candidate
                }
                if fallback == IO_OBJECT_NULL {
                    fallback = candidate
                } else {
                    IOObjectRelease(candidate)
                }
            }
            return fallback
        }

        /// Launch-time transients (IOKit still settling) resolve within a couple of seconds.
        let initialRetryDelays: [Duration] = [.milliseconds(200), .milliseconds(400), .milliseconds(800), .milliseconds(1600)]
        /// Safety net so recovery never depends on an IOPS notification arriving. Runs for
        /// the life of the stream, not only while failing — see the poll task below.
        let repollInterval: Duration = .seconds(60)

        // `powerSourceChanges()` is subscribed to independently by ~6-8 call sites, each
        // with its own retry ladder, so a single sustained failure would otherwise dump
        // the full IOPMPowerSource property list 6-8 times per attempt and again every
        // 60s. `dumpGate` limits the expensive dump to once per distinct missing field
        // for the life of the process, so the log names the field without flooding.
        let dumpGate = DumpGate()

        /// One report should be enough to identify a renamed property on new firmware.
        @Sendable
        func logAvailableBatteryProperties(missing: PowerSourceField) {
            guard dumpGate.shouldDump(missing) else { return }
            let firmware = SystemFirmware.version() ?? "unknown"
            let service = matchingBatteryService()
            defer { if service != IO_OBJECT_NULL { IOObjectRelease(service) } }
            guard service != IO_OBJECT_NULL else {
                dumpGate.releaseDump(missing)
                logger.error("Missing \(missing.rawValue, privacy: .public); IOPMPowerSource service not found. Firmware \(firmware, privacy: .public).")
                return
            }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else {
                dumpGate.releaseDump(missing)
                logger.error("Missing \(missing.rawValue, privacy: .public); IORegistryEntryCreateCFProperties failed. Firmware \(firmware, privacy: .public).")
                return
            }
            guard let dictionary = properties?.takeRetainedValue() as? [String: Any] else {
                dumpGate.releaseDump(missing)
                logger.error("Missing \(missing.rawValue, privacy: .public); IOPMPowerSource properties cast failed. Firmware \(firmware, privacy: .public).")
                return
            }
            let keys = dictionary.keys.sorted().joined(separator: ", ")
            logger.error("Missing \(missing.rawValue, privacy: .public). Firmware \(firmware, privacy: .public). IOPMPowerSource keys: \(keys, privacy: .public)")
        }

        @Sendable
        func fetchWithRetry() async -> PowerState? {
            for (attempt, delay) in initialRetryDelays.enumerated() {
                guard !Task.isCancelled else { return nil }
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
                if let assemblyError = error as? PowerSourceAssemblyError {
                    logAvailableBatteryProperties(missing: assemblyError.missingField)
                }
                return nil
            }
        }

        let observer = Observer(getPowerSourceInfo: getPowerSourceInfo)
        observer.startObserving()

        logger.notice("System firmware: \(SystemFirmware.version() ?? "unknown", privacy: .public)")

        let client = PowerSourceClient(
            powerSourceChanges: {
                AsyncStream { continuation in
                    let pollTask = Task {
                        // Retries hard at first, then keeps polling at a low rate **for the
                        // life of the stream**. It used to return on the first success,
                        // which made the comment above it ("so recovery never depends on an
                        // IOPS notification arriving") true only up to that point: a Mac
                        // that read fine at launch and then lost a key had no recovery path
                        // but a notification — and read failures correlate with
                        // notifications not arriving.
                        //
                        // The cost of keeping it is one IOKit read a minute, and the yield
                        // is what `powerSourceChanges` consumers already debounce.
                        while !Task.isCancelled {
                            if let state = await fetchWithRetry() {
                                continuation.yield(state)
                            }
                            try? await Task.sleep(for: repollInterval)
                        }
                    }

                    nonisolated(unsafe) let cancellable = observer.subject
                        .sink { powerState in
                            Task {
                                continuation.yield(powerState)
                            }
                        }

                    continuation.onTermination = { _ in
                        cancellable.cancel()
                        pollTask.cancel()
                    }
                }
            },
            currentPowerSourceState: {
                // The retry ladder, not a bare read. Its consumer —
                // `ChargingManager.fetchAndUpdateAppChargingState` — throws out of the
                // whole function on a single bad read, leaving the app's mode at `.initial`,
                // which `BatteryIndicatorViewModel.ChargingMode.init` renders as the
                // exclamation-mark error icon. That is the reported symptom, reached from a
                // transient the stream path already knows how to ride out.
                guard let state = await fetchWithRetry() else {
                    return try await getPowerSourceInfo()
                }
                return state
            },
            isRunningOnLaptop: {
                if let powerSourceInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                   let powerSourcesList = IOPSCopyPowerSourcesList(powerSourceInfo)?.takeRetainedValue() as? [CFTypeRef] {
                    // Check if any power source has a battery
                    for powerSource in powerSourcesList {
                        if let description = IOPSGetPowerSourceDescription(powerSourceInfo, powerSource)?.takeUnretainedValue() as? [String: Any],
                           let type = description[kIOPSTypeKey] as? String,
                           type == kIOPSInternalBatteryType {
                            return true // A built-in battery is found, indicating a laptop
                        }
                    }
                }
                return false // No internal battery found, likely a desktop Mac
            }
        )

        return client
    }()

    private final class Observer: @unchecked Sendable {
        let getPowerSourceInfo: () async throws -> PowerState
        let subject = PassthroughSubject<PowerState, Never>()
        private let logger = Logger(category: "PowerSourceClienty.Observer")
        private let inFlightLock = NSLock()
        private var inFlight: Task<Void, Never>?
        /// Set when a notification arrives while a read is already running, so that read
        /// loops once more rather than the notification being answered with the older
        /// sample. See `refresh()`.
        private var needsRerun = false

        init(getPowerSourceInfo: @escaping () async throws -> PowerState) {
            self.getPowerSourceInfo = getPowerSourceInfo
        }

        /// macOS 27 raises a full system power-source change per charge-inhibit toggle,
        /// so callbacks arrive in bursts. Collapse them — into **two** reads, never into
        /// one stale one.
        ///
        /// Joining an in-flight task was not enough, and `Task` is why: it has no "is
        /// finished" property, so `!inFlight.isCancelled` is true both for a running task
        /// and for a completed one. A notification arriving mid-read joined that read and
        /// was answered with a sample taken *before* the change it was reporting; one
        /// arriving in the window between the task finishing and `inFlight` being cleared
        /// joined an already-finished task, so no IOKit read happened at all — the read the
        /// notification existed to trigger was dropped.
        ///
        /// `needsRerun` makes the running task loop instead. Any number of notifications
        /// during a read collapse into exactly one more read afterwards, which is the
        /// coalescing that was wanted and is the guarantee the design doc's untested
        /// "a burst of notifications coalesces" case asks for.
        func refresh() async {
            let task = inFlightLock.withLock { () -> Task<Void, Never> in
                if let inFlight, !inFlight.isCancelled {
                    needsRerun = true
                    return inFlight
                }
                let task = Task { [weak self] in
                    guard let self else { return }
                    repeat {
                        do {
                            let powerState = try await self.getPowerSourceInfo()
                            self.logger.debug("New power state: \(powerState)")
                            self.subject.send(powerState)
                        } catch {
                            self.logger.error("Power source read failed on notification: \(error, privacy: .public)")
                        }
                    } while self.takeNeedsRerun()
                }
                inFlight = task
                return task
            }
            await task.value
            inFlightLock.withLock {
                if inFlight == task { inFlight = nil }
            }
        }

        /// Consumes the re-run request, so the flag cannot make the loop spin forever.
        private func takeNeedsRerun() -> Bool {
            inFlightLock.withLock {
                defer { needsRerun = false }
                return needsRerun
            }
        }

        func startObserving() {
            let context = Unmanaged.passUnretained(self).toOpaque()
            let loop: CFRunLoopSource = IOPSNotificationCreateRunLoopSource(
                {
                    context in
                    if let context {
                        let observer = Unmanaged<Observer>.fromOpaque(context).takeUnretainedValue()
                        observer.logger.debug("Power state did change.")
                        Task { await observer.refresh() }
                    }
                },
                context
            ).takeRetainedValue() as CFRunLoopSource
            CFRunLoopAddSource(CFRunLoopGetMain(), loop, CFRunLoopMode.commonModes)
        }
    }
}

/// Backs `logAvailableBatteryProperties`'s once-per-field firing policy. A plain
/// lock-protected class rather than an actor: the call site is synchronous
/// (inside a `catch`), and the set is tiny, so a lock is simpler than adding
/// `await` through `fetchWithRetry`'s error path.
private final class DumpGate: @unchecked Sendable {
    private let lock = NSLock()
    private var dumped: Set<PowerSourceField> = []

    /// Returns `true` the first time `field` is seen; `false` on every
    /// subsequent call, for the lifetime of the process.
    func shouldDump(_ field: PowerSourceField) -> Bool {
        lock.withLock { dumped.insert(field).inserted }
    }

    /// Hands `field`'s one-shot budget back after a failed dump attempt (service not
    /// found, properties call failed, cast failed) so a later attempt can still
    /// produce the full key list instead of the budget being spent on nothing.
    func releaseDump(_ field: PowerSourceField) {
        lock.withLock { _ = dumped.remove(field) }
    }
}

private actor BatteryHealthState {
    private var lastBatteryHealth: BatteryHealth?
    private var refreshTask: Task<Void, Never>?
    /// When the last attempt failed, so a permanently unreadable health does not fork a
    /// `system_profiler` on every read. `store(_:)` clears `refreshTask` on every
    /// completion but only records a value on success, so without this `refreshIfStale()`
    /// became eligible again immediately — and with ~6-8 subscribers to
    /// `powerSourceChanges()` and macOS 27 raising a power-source change per inhibit
    /// toggle, that is a lot of subprocesses.
    private var lastFailureDate: Date?

    private static let maxAge: TimeInterval = 60 * 60
    /// How long to wait before retrying after a failed read. Shorter than `maxAge`: a
    /// failure is more likely to be transient than a successful reading is to be stale.
    private static let failureBackoff: TimeInterval = 10 * 60
    private static let timeout: Duration = .seconds(10)
    private static let logger = Logger(category: "Battery Health")

    /// Non-blocking: whatever we last computed, possibly nil. Never awaits a subprocess.
    func currentHealth() -> Int? { lastBatteryHealth?.health }

    /// Kicks off a refresh when the cache is cold or stale. Returns immediately.
    func refreshIfStale() {
        if let lastBatteryHealth, lastBatteryHealth.date.timeIntervalSinceNow > -Self.maxAge { return }
        if let lastFailureDate, lastFailureDate.timeIntervalSinceNow > -Self.failureBackoff { return }
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            let health = await Self.readMaximumCapacity()
            await self?.store(health)
        }
    }

    private func store(_ health: Int?) {
        if let health {
            lastBatteryHealth = BatteryHealth(health: health, date: .now)
            lastFailureDate = nil
        } else {
            lastFailureDate = .now
        }
        refreshTask = nil
    }

    /// Apple's reported "Maximum Capacity" is not a simple IORegistry ratio — on a test
    /// machine NominalChargeCapacity/DesignCapacity gave 82% and AppleRawMaxCapacity/
    /// DesignCapacity gave 80% where system_profiler reported 85%. Do not substitute one.
    ///
    /// `static` (hence nonisolated) is deliberate, not incidental: this function blocks on
    /// subprocess I/O and must run on the cooperative thread pool, never on this actor's
    /// executor. If `NonisolatedNonsendingByDefault` is ever enabled for this target
    /// (BatFiKit/Package.swift:308, currently commented out), nonisolated async functions
    /// stop hopping off their actor by default, and these blocking calls would run on
    /// `BatteryHealthState`'s executor instead — serializing with, and blocking, every
    /// other actor method, including the non-blocking `currentHealth()` read on the hot path.
    private static func readMaximumCapacity() async -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        // Cancelling a task cannot interrupt the blocking reads below, so the only
        // real timeout is signalling the child. SIGTERM closes the pipe's write end,
        // which unblocks readDataToEndOfFile() and lets waitUntilExit() reap.
        let box = ProcessBox(process)
        let watchdog = Task {
            try await Task.sleep(for: Self.timeout)
            if box.process.isRunning {
                logger.error("system_profiler did not exit before the timeout; terminating it and reporting no health reading")
                box.process.terminate()
            }
        }
        defer { watchdog.cancel() }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else { return nil }
        for line in output.split(separator: "\n") where line.contains("Maximum Capacity") {
            let components = line.components(separatedBy: ":")
            guard components.count == 2 else { return nil }
            let trimmed = components[1].trimmingCharacters(in: .whitespaces.union(.decimalDigits.inverted))
            return Int(trimmed)
        }
        return nil
    }
}

/// `Process` is not `Sendable`. The watchdog touches only `isRunning` and
/// `terminate()` while the owning task blocks in `waitUntilExit()`.
private final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}

private struct BatteryHealth {
    let health: Int
    let date: Date
}
