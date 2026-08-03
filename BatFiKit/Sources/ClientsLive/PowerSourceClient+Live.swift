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

        let batteryHealthState = BatteryHealthState()

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
            await batteryHealthState.refreshIfStale()
            readings.batteryHealth = await batteryHealthState.currentHealth()

            return try PowerStateAssembler.assemble(readings)
        }

        /// Launch-time transients (IOKit still settling) resolve within a couple of seconds.
        let initialRetryDelays: [Duration] = [.milliseconds(200), .milliseconds(400), .milliseconds(800), .milliseconds(1600)]
        /// Safety net so recovery never depends on an IOPS notification arriving.
        let failureRepollInterval: Duration = .seconds(60)

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

        logger.notice("System firmware: \(systemFirmwareVersion() ?? "unknown", privacy: .public)")

        let client = PowerSourceClient(
            powerSourceChanges: {
                AsyncStream { continuation in
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
                try await getPowerSourceInfo()
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

        init(getPowerSourceInfo: @escaping () async throws -> PowerState) {
            self.getPowerSourceInfo = getPowerSourceInfo
        }

        /// macOS 27 raises a full system power-source change per charge-inhibit toggle,
        /// so callbacks arrive in bursts. Collapse them into one read.
        func refresh() async {
            let task = inFlightLock.withLock { () -> Task<Void, Never> in
                if let inFlight, !inFlight.isCancelled { return inFlight }
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
                return task
            }
            await task.value
            inFlightLock.withLock {
                if inFlight == task { inFlight = nil }
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
}

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
