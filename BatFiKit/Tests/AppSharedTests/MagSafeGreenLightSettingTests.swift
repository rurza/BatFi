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

    /// The one durable cause is a backend that cannot tell when it is holding charge — a
    /// property of the firmware rather than of a probe — and no backend is one today.
    @Test func onlyTheBackendJustifiesTurningTheSettingOffForGood() {
        for backend in ChargeBackend.allCases {
            let action = MagSafeGreenLightSetting.action(magSafeLEDAvailable: true, backend: backend)
            #expect(
                (action == .disablePermanently) == !backend.canMirrorChargingStateOnMagSafeLED,
                "\(backend.rawValue)"
            )
        }
    }

    /// The firmware range used to be the durable cause, when BatFi called the band's drift
    /// `.charging`. It now reports the hold (`FirmwareRangeHold`), so the setting is left to
    /// the user there like anywhere else — default off, never written off.
    @Test func theFirmwareRangeNoLongerTurnsTheSettingOff() {
        #expect(MagSafeGreenLightSetting.action(magSafeLEDAvailable: true, backend: .firmwareRange) == .leaveAlone)
        #expect(MagSafeGreenLightSetting.action(magSafeLEDAvailable: nil, backend: .firmwareRange) == .leaveAlone)
        #expect(
            MagSafeGreenLightSetting.action(magSafeLEDAvailable: false, backend: .firmwareRange)
                == .suppressForThisSession
        )
    }

    /// A working Mac is left entirely alone.
    @Test func aWorkingMacIsLeftAlone() {
        #expect(MagSafeGreenLightSetting.action(magSafeLEDAvailable: true, backend: .chte) == .leaveAlone)
        #expect(MagSafeGreenLightSetting.action(magSafeLEDAvailable: true, backend: nil) == .leaveAlone)
    }

    // MARK: - Who drives the green light

    /// The MPX-40 regression. A Mac that has had macOS 27 installed keeps its firmware when
    /// it runs macOS 26, and on that firmware it resolves to `.systemChargeLimit` there too
    /// — but macOS 26 leaves the LED amber while its limit holds. Treating the backend alone
    /// as "the system drives the light" hid the toggle and left nobody lighting it.
    @Test func appleLimitOnMacOS26LeavesTheLightToBatFi() {
        #expect(!MagSafeGreenLightSetting.isSystemDriven(backend: .systemChargeLimit, osMajorVersion: 26))
    }

    /// Measured on 27.0.1: powerd turns the LED green itself at the limit.
    @Test func appleLimitOnMacOS27DrivesTheLightItself() {
        #expect(MagSafeGreenLightSetting.isSystemDriven(backend: .systemChargeLimit, osMajorVersion: 27))
        #expect(MagSafeGreenLightSetting.isSystemDriven(backend: .systemChargeLimit, osMajorVersion: 28))
    }

    /// No other backend hands the light to macOS, on any version.
    @Test func noOtherBackendIsEverSystemDriven() {
        for backend in ChargeBackend.allCases where backend != .systemChargeLimit {
            for version in [26, 27] {
                #expect(
                    !MagSafeGreenLightSetting.isSystemDriven(backend: backend, osMajorVersion: version),
                    "\(backend.rawValue) on \(version)"
                )
            }
        }
    }

    // MARK: - Whether the settings pane shows the toggle at all

    /// Shown only where it is a real, editable control. Under Apple's own limit on macOS 27
    /// the system drives the light itself — the user cannot change it, so the pane hides the
    /// toggle, the same treatment it gives pause-on-sleep and the hot-battery cutout on that
    /// firmware.
    @Test func theToggleIsHiddenWhereTheUserCanNeverChangeIt() {
        #expect(!MagSafeGreenLightSetting.isShownInSettings(backend: .systemChargeLimit, osMajorVersion: 27))
    }

    /// The same backend on macOS 26 is BatFi's to light, so the user gets the switch.
    @Test func theToggleIsShownUnderAppleLimitOnMacOS26() {
        #expect(MagSafeGreenLightSetting.isShownInSettings(backend: .systemChargeLimit, osMajorVersion: 26))
    }

    @Test func theToggleIsShownWhereBatFiDrivesTheLight() {
        for version in [26, 27] {
            #expect(MagSafeGreenLightSetting.isShownInSettings(backend: .firmwareRange, osMajorVersion: version))
            #expect(MagSafeGreenLightSetting.isShownInSettings(backend: .chte, osMajorVersion: version))
            #expect(MagSafeGreenLightSetting.isShownInSettings(backend: .legacyCH0BC, osMajorVersion: version))
        }
    }

    /// Before the backend is known the toggle stays. Every Mac shipping today can drive its
    /// light, and the pane is sized once at first layout, so the decision has to be right
    /// then rather than flicker the control away on every ordinary Mac.
    @Test func anUnknownBackendShowsTheToggle() {
        #expect(MagSafeGreenLightSetting.isShownInSettings(backend: nil, osMajorVersion: 26))
        #expect(MagSafeGreenLightSetting.isShownInSettings(backend: nil, osMajorVersion: 27))
    }

    /// The disarm logic does not depend on the OS: Apple's limit mirrors the charging state
    /// on every version, so a working LED is never turned off for good under it — on macOS
    /// 26, where BatFi lights it, that would take away the only thing lighting it.
    @Test func appleLimitNeverDisablesTheSettingForGood() {
        #expect(
            MagSafeGreenLightSetting.action(magSafeLEDAvailable: true, backend: .systemChargeLimit)
                == .leaveAlone
        )
    }
}
