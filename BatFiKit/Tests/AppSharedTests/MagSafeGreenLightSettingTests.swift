//
//  MagSafeGreenLightSettingTests.swift
//  BatFi
//
//  The regression this suite exists for: a two-second SMC driver hiccup used to make
//  `chargingDiagnostics()` report every key absent, and `MagSafeColorManager` acted on that
//  by writing `showGreenLightMagSafeWhenInhibiting = false` into `Defaults` — permanently,
//  on a perfectly healthy MacBook Pro, with the settings toggle then rendered disabled so
//  the user could not put it back.
//
//  The rule pinned here is that only an answer that is a property of the *firmware* may be
//  persisted. Everything else is suppressed for the session and asked again next launch.
//

import Testing

@testable import Shared

@Suite struct MagSafeGreenLightSettingTests {
    /// The C3 case, stated as a value. "Could not ask" must never reach the persisting arm.
    @Test func aProbeThatCouldNotRunNeverWritesTheSettingOff() {
        for backend in ChargeBackend.allCases where backend.canMirrorChargingStateOnMagSafeLED {
            #expect(
                MagSafeGreenLightSetting.action(magSafeLEDAvailable: nil, backend: backend) == .leaveAlone,
                "\(backend.rawValue)"
            )
        }
        // And with no backend resolved either — the state a Mac is in during the window
        // where the driver connection has not opened.
        #expect(MagSafeGreenLightSetting.action(magSafeLEDAvailable: nil, backend: nil) == .leaveAlone)
    }

    /// A `.chte` MacBook Pro whose `ACLC` probe answered "absent" is not evidence enough to
    /// destroy the setting: the probe runs over the same connection that can be degrading.
    /// Stop driving the light, keep the stored value, ask again next launch.
    @Test func anAbsentLEDKeyIsSuppressedForTheSessionRatherThanPersisted() {
        #expect(
            MagSafeGreenLightSetting.action(magSafeLEDAvailable: false, backend: .chte)
                == .suppressForThisSession
        )
        #expect(
            MagSafeGreenLightSetting.action(magSafeLEDAvailable: false, backend: .systemChargeLimit)
                == .suppressForThisSession
        )
    }

    /// The one durable cause. `.firmwareRange` cannot report when it is holding charge at
    /// all, and that is a property of the machine's firmware rather than of a probe — so
    /// the stored default is turned off, which is what stops every other reader re-arming
    /// the feature.
    @Test func onlyTheBackendJustifiesTurningTheSettingOffForGood() {
        for backend in ChargeBackend.allCases {
            let action = MagSafeGreenLightSetting.action(magSafeLEDAvailable: true, backend: backend)
            #expect(
                (action == .disablePermanently) == !backend.canMirrorChargingStateOnMagSafeLED,
                "\(backend.rawValue)"
            )
        }
    }

    /// The backend is consulted ahead of the probe, deliberately: a `.firmwareRange` Mac
    /// whose LED probe did not answer still gets the durable verdict, because the reason it
    /// cannot show a green light has nothing to do with the LED key.
    @Test func theBackendVerdictSurvivesAnUnansweredProbe() {
        #expect(
            MagSafeGreenLightSetting.action(magSafeLEDAvailable: nil, backend: .firmwareRange)
                == .disablePermanently
        )
    }

    /// A working Mac is left entirely alone.
    @Test func aWorkingMacIsLeftAlone() {
        #expect(MagSafeGreenLightSetting.action(magSafeLEDAvailable: true, backend: .chte) == .leaveAlone)
        #expect(MagSafeGreenLightSetting.action(magSafeLEDAvailable: true, backend: nil) == .leaveAlone)
    }
}
