//
//  Charging.swift
//  BatFi
//
//  Created by Adam on 25/04/2023.
//

import Cocoa
import IOKit.pwr_mgt
import os
import SecureXPC

final class Charging {
    private let client: XPCClient
    private lazy var logger = Logger(category: "🪫🔋")

    init(client: XPCClient) {
        self.client = client
        setUpObserving()
    }

    private var sleepAssertion: IOPMAssertionID?

    func autoChargingMode() async throws {
       try await changeChargingMode(.auto)
    }

    func turnOffCharging() async throws {
        let status = try await client.sendMessage(SMCStatusCommand.status, to: XPCRoute.smcStatus)
        if status.lidClosed {
            try await changeChargingMode(.inhibitCharging)
        } else {
            try await changeChargingMode(.forceDischarging)
        }
    }

    func changeChargingMode(_ command: SMCChargingCommand) async throws {
        do {
            try await client.sendMessage(
                command,
                to: XPCRoute.charging
            )
        } catch {
            logger.error("SMC charging error: \(error, privacy: .public)")
            throw error
        }
        if case .auto = command {
            if let sleepAssertion {
                IOPMAssertionRelease(sleepAssertion)
            }
        } else {
            var assertionID: IOPMAssertionID = IOPMAssertionID(0)
            let reason: CFString = "BatFi" as NSString
            let cfAssertion: CFString = kIOPMAssertionTypePreventSystemSleep as NSString
            let success = IOPMAssertionCreateWithName(
                cfAssertion,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &assertionID
            )
            if success == kIOReturnSuccess {
                sleepAssertion = assertionID
            }
        }
    }

    // Sleep/Wake
    // https://developer.apple.com/library/archive/qa/qa1340/_index.html
    //

    // MARK: - Notifications

    private func setUpObserving() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(receiveSleepNote(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(receiveSleepNote(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(receiveDidChangeScreenParametersNote(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc
    func receiveSleepNote(_ note: Notification) {
        logger.debug(#function)
    }

    @objc
    func receiveWakeNote(_ note: Notification) {
        logger.debug(#function)
    }

    @objc
    func receiveDidChangeScreenParametersNote(_ note: Notification) {
        logger.debug(#function)
    }
}
