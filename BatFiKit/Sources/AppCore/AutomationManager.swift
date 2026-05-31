//
//  AutomationManager.swift
//  BatFi
//
//  Runtime engine for the calendar/automation feature. Evaluates which rule is active right
//  now (time + location) and pushes its limit into the shared charging state, where
//  ChargingManager treats it as the base charge limit. Also publishes an AutomationStatus
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

    private lazy var logger = Logger(category: "Automation Manager")

    private var latestCoordinate: Coordinate?
    private var locationTask: Task<Void, Never>?
    private var observeTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    private var lastStatus = AutomationStatus()
    private var statusContinuations: [UUID: AsyncStream<AutomationStatus>.Continuation] = [:]

    public init() {}

    public func setUpObserving() {
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
        reconcileLocationMonitoring(enabled: enabled, rules: rules)
        await evaluate()
    }

    private func reconcileLocationMonitoring(enabled: Bool, rules: [AutomationRule]) {
        let needsLocation = enabled && rules.contains { $0.isEnabled && $0.location != nil }
        if needsLocation {
            guard locationTask == nil else { return }
            let client = locationClient
            client.requestAuthorization()
            locationTask = Task { [weak self] in
                for await coordinate in client.coordinateUpdates() {
                    await self?.updateCoordinate(coordinate)
                }
            }
        } else if locationTask != nil {
            locationTask?.cancel()
            locationTask = nil
            latestCoordinate = nil
        }
    }

    private func updateCoordinate(_ coordinate: Coordinate) async {
        latestCoordinate = coordinate
        await evaluate()
    }

    private func evaluate() async {
        let enabled = defaults.value(.automationEnabled)
        let rules = defaults.value(.automationRules)
        let now = date.now

        let active = AutomationEngine.activeRule(
            in: rules, enabled: enabled, at: now, location: latestCoordinate
        )
        let next = AutomationEngine.nextScheduled(in: rules, enabled: enabled, after: now)

        await appChargingState.setAutomationLimit(active?.limit)
        defaults.setValue(.automationActiveRuleID, value: active?.id.uuidString ?? "")

        let status = AutomationStatus(
            enabled: enabled,
            activeRule: active,
            nextRule: next?.rule,
            nextDate: next?.start
        )
        guard status != lastStatus else { return }
        lastStatus = status
        logger.debug("Automation status changed. Active: \(active?.name ?? "none", privacy: .public), limit: \(active?.limit ?? -1)")
        for continuation in statusContinuations.values {
            continuation.yield(status)
        }
    }
}
