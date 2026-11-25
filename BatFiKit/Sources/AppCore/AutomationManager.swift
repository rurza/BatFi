//
//  AutomationManager.swift
//  BatFi
//
//  Runtime engine for the calendar/automation feature. Evaluates which rule is active right
//  now (time + location) and pushes its limit and resume level into the shared charging state,
//  where ChargingManager treats them as the base charge limit and the sailing levels. Also publishes an AutomationStatus
//  for the menu label.
//

import AppShared
import AsyncAlgorithms
import Clients
import DefaultsKeys
import Dependencies
import Foundation
import os

public actor AutomationManager {
    @Dependency(\.defaults) private var defaults
    @Dependency(\.locationClient) private var locationClient
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.suspendingClock) private var clock
    @Dependency(\.date) private var date
    @Dependency(\.sleepClient) private var sleepClient
    @Dependency(\.networkPathClient) private var networkPathClient

    private lazy var logger = Logger(category: "Automation Manager")

    private var satisfiedFenceIDs: Set<UUID> = []
    private var fenceStatesTask: Task<Void, Never>?
    private var fenceCheckTriggersTask: Task<Void, Never>?
    private var observeTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    private var lastStatus = AutomationStatus()
    private var statusContinuations: [UUID: AsyncStream<AutomationStatus>.Continuation] = [:]

    public init() {}

    public func setUpObserving() {
        // Retained, but reassigned without cancelling, so a second call left the first loop
        // running and every config change was handled twice. Same flaw as
        // `ChargingManager.setUpObserving()`; here the stored reference makes it cheap to fix.
        observeTask?.cancel()
        let defaults = self.defaults
        observeTask = Task { [weak self] in
            let enabled = defaults.observe(.automationEnabled)
            let rules = defaults.observe(.automationRules)
            for await (isEnabled, rules) in combineLatest(enabled, rules) {
                await self?.handleConfigChange(enabled: isEnabled, rules: rules)
            }
        }

        // Periodic re-evaluation so schedule windows opening/closing take effect even when
        // nothing else changes.
        let clock = self.clock
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await clock.sleep(for: .seconds(60))
                await self?.evaluate()
            }
        }
    }

    /// Current snapshot, then live updates. Used by the menu.
    public func statusChanges() -> AsyncStream<AutomationStatus> {
        AsyncStream { continuation in
            let id = UUID()
            statusContinuations[id] = continuation
            continuation.yield(lastStatus)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeStatusContinuation(id) }
            }
        }
    }

    public func currentStatus() -> AutomationStatus {
        lastStatus
    }

    // MARK: - Private

    private func removeStatusContinuation(_ id: UUID) {
        statusContinuations[id] = nil
    }

    private func handleConfigChange(enabled: Bool, rules: [AutomationRule]) async {
        await reconcileLocationMonitoring(enabled: enabled, rules: rules)
        await evaluate()
    }

    private func reconcileLocationMonitoring(enabled: Bool, rules: [AutomationRule]) async {
        let fences: [MonitoredFence] = enabled
            ? rules.compactMap { rule in
                guard rule.isEnabled, let fence = rule.location else { return nil }
                return MonitoredFence(id: rule.id, fence: fence)
            }
            : []

        if !fences.isEmpty {
            locationClient.requestAuthorization()
        }

        // Passing [] removes every condition, which is how disabling automation stops all
        // locationd work. No continuous location updates run in either direction.
        await locationClient.setMonitoredFences(fences)

        if fences.isEmpty {
            fenceStatesTask?.cancel()
            fenceStatesTask = nil
            fenceCheckTriggersTask?.cancel()
            fenceCheckTriggersTask = nil
            satisfiedFenceIDs = []
        } else if fenceStatesTask == nil {
            let client = locationClient
            fenceStatesTask = Task { [weak self] in
                for await ids in client.fenceStates() {
                    await self?.updateSatisfiedFences(ids)
                }
            }
            startFenceCheckTriggers()
        }
    }

    /// CLMonitor alone has been seen to report nothing for a whole day while the Mac travelled,
    /// so the location client also checks fences itself from a one-shot fix. It covers launch
    /// and fence changes on its own; these are the moments only the app knows about. Each check
    /// costs a few seconds of location updates, which is why there is no tighter cadence.
    private func startFenceCheckTriggers() {
        let client = locationClient
        let sleepClient = sleepClient
        let networkPathClient = networkPathClient
        let clock = clock
        fenceCheckTriggersTask = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await _ in sleepClient.macDidWake() {
                        await client.checkFences(.wake)
                    }
                }
                group.addTask {
                    // Joining Wi-Fi changes the path several times within seconds; one check
                    // after it settles is enough.
                    for await _ in networkPathClient.pathChanges().debounce(for: .seconds(5), clock: AnyClock(clock)) {
                        await client.checkFences(.networkChange)
                    }
                }
                group.addTask {
                    // Backstop for a move that neither woke the Mac nor changed its network.
                    while !Task.isCancelled {
                        try? await clock.sleep(for: .seconds(15 * 60))
                        guard !Task.isCancelled else { break }
                        await client.checkFences(.periodic)
                    }
                }
            }
        }
    }

    private func updateSatisfiedFences(_ ids: Set<UUID>) async {
        guard ids != satisfiedFenceIDs else { return }
        satisfiedFenceIDs = ids
        await evaluate()
    }

    private func evaluate() async {
        let enabled = defaults.value(.automationEnabled)
        let rules = defaults.value(.automationRules)
        let now = date.now

        let active = AutomationEngine.activeRule(
            in: rules, enabled: enabled, at: now, satisfiedFenceIDs: satisfiedFenceIDs
        )
        let next = AutomationEngine.nextScheduled(in: rules, enabled: enabled, after: now)

        await appChargingState.setAutomationTarget(active.map(AutomationTarget.init(rule:)))
        defaults.setValue(.automationActiveRuleID, value: active?.id.uuidString ?? "")

        let status = AutomationStatus(
            enabled: enabled,
            activeRule: active,
            nextRule: next?.rule,
            nextDate: next?.start
        )
        guard status != lastStatus else { return }
        let activeChanged = status.activeRule != lastStatus.activeRule
        lastStatus = status
        // The active rule at notice, since a customer's log must show which rule was in force
        // and when; the rest of the status (the next scheduled rule) moves too often for that.
        if activeChanged {
            logger.notice(
                "Active rule changed: \(active?.name ?? "none", privacy: .public) id=\(active?.id.uuidString ?? "-", privacy: .public) limit=\(active?.limit ?? -1) resume=\(active?.sailingLevels?.resumeLevel ?? -1) satisfiedFences=\(self.satisfiedFenceIDs.count)"
            )
        } else {
            logger.debug("Automation status changed. Next: \(next?.rule.name ?? "none", privacy: .public)")
        }
        for continuation in statusContinuations.values {
            continuation.yield(status)
        }
    }
}
