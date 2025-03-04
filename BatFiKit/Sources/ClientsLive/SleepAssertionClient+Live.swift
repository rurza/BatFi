//
//  SleepAssertionClient.swift
//
//
//  Created by Adam on 30/05/2023.
//

import Clients
import Dependencies
import Foundation
import IOKit.pwr_mgt
import os
import Shared

extension SleepAssertionClient: DependencyKey {
    public static let liveValue: SleepAssertionClient = {
        let state = SleepState()

        func preventAutomaticSleep(_ preventSleep: Bool) async {
            if preventSleep {
                guard await state.sleepAssertion == nil else {
                    return
                }
                var assertionID: IOPMAssertionID = .init(0)
                let reason: CFString = "BatFi" as NSString
                let cfAssertion: CFString = kIOPMAssertionTypePreventSystemSleep as NSString
                let success = IOPMAssertionCreateWithName(
                    cfAssertion,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    reason,
                    &assertionID
                )
                if success == kIOReturnSuccess {
                    await state.setAssertion(assertionID)
                }
            } else {
                if let assertion = await state.sleepAssertion {
                    IOPMAssertionRelease(assertion)
                    await state.setAssertion(nil)
                }
            }
        }

        return SleepAssertionClient(
            preventAutomaticSleepIfNeeded: { preventSleep in
                await preventAutomaticSleep(preventSleep)
            },
            preventsAutomaticSleep: {
                await state.sleepAssertion != nil
            },
            disableSleep: { disable in
                await preventAutomaticSleep(disable)
                try await XPCClient.shared.setDisableAutosleep(disable)
            }
        )
    }()
}

actor SleepState {
    var sleepAssertion: IOPMAssertionID?

    func setAssertion(_ assertion: IOPMAssertionID?) {
        sleepAssertion = assertion
    }
}
