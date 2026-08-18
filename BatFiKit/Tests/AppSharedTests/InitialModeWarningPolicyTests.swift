//
//  InitialModeWarningPolicyTests.swift
//  BatFi
//
//  A charging mode still sitting at `.initial` means one of two opposite things, and the
//  notification it produces — "BatFi can't read battery information" — is only true for one
//  of them. During onboarding the app has deliberately not been set up yet, so `.initial` is
//  the expected state rather than a fault, and reporting it interrupts someone who is part
//  way through installing the very helper the warning is about.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct InitialModeWarningPolicyTests {
    @Test func warnsWhenTheAppIsRunningNormallyAndTheModeNeverLeftInitial() {
        #expect(
            InitialModeWarningPolicy.shouldWarn(
                mode: .initial,
                health: .healthy,
                onboardingIsUp: false
            )
        )
    }

    /// The reported bug. A helper left registered by a previous install answers pings, so
    /// health is `.healthy` and the only guard the watchdog had passed — while onboarding was
    /// on screen offering to install a helper.
    @Test func staysQuietWhileOnboardingIsUpEvenWithAHealthyHelper() {
        #expect(
            !InitialModeWarningPolicy.shouldWarn(
                mode: .initial,
                health: .healthy,
                onboardingIsUp: true
            )
        )
    }

    @Test func staysQuietWhenTheHelperIsNotHealthy() {
        for health: HelperHealth in [
            .unknown,
            .degraded(.notRegistered),
            .degraded(.requiresApproval),
            .degraded(.registeredButUnreachable),
        ] {
            #expect(
                !InitialModeWarningPolicy.shouldWarn(
                    mode: .initial,
                    health: health,
                    onboardingIsUp: false
                ),
                "\(health) is not evidence that macOS is withholding battery details"
            )
        }
    }

    /// The watchdog exists for a mode that never *left* `.initial`. Any other mode means the
    /// battery details arrived and were acted on.
    @Test func staysQuietForEveryModeThatIsNotInitial() {
        for mode: ChargingMode in [.charging, .inhibit, .forceDischarge] {
            #expect(
                !InitialModeWarningPolicy.shouldWarn(
                    mode: mode,
                    health: .healthy,
                    onboardingIsUp: false
                ),
                "\(mode) means the mode moved on"
            )
        }
    }
}
