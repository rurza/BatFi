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
        let logger = Logger(category: "☕️")
        var sleepAssertion: IOPMAssertionID?
        return SleepAssertionClient(
            preventSleepIfNeeded: { preventSleep in

                if preventSleep {
                    logger.debug("Should delay sleep...")
                    guard sleepAssertion == nil else {
                        logger.debug("...already delayed")
                        return
                    }
                    logger.notice("Delaying sleep")
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
                        sleepAssertion = assertionID
                    }
                } else {
                    if let assertion = sleepAssertion {
                        logger.notice("Returning sleep")
                        IOPMAssertionRelease(assertion)
                        sleepAssertion = nil
                    }
                }
            }
        )
    }()
}
