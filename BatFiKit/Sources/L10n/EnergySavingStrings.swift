//
//  EnergySavingStrings.swift
//  BatFi
//
//  Localized strings for the energy-saving features: automatic Low Power Mode, and slowing
//  apps down on battery. Kept in a focused extension rather than the generated Strings.swift.
//  English values are inline defaults.
//

import Foundation

public extension L10n {
    enum EnergySaving {
        // Automatic Low Power Mode

        /// Posted when BatFi turns Low Power Mode on for the battery at the user's threshold.
        public static let lowPowerModeTurnedOnTitle = String(localized: "energy_saving.low_power_mode.notification.turned_on.title", defaultValue: "Low Power Mode is on", bundle: Bundle.module)
        /// The promise that makes the automatic switch safe to leave alone: BatFi, not the
        /// user, turns it back off.
        public static let lowPowerModeTurnedOnBody = String(localized: "energy_saving.low_power_mode.notification.turned_on.body", defaultValue: "Your battery is running low. BatFi will turn Low Power Mode off when you plug in.", bundle: Bundle.module)

        // Settings pane

        public static let paneTitle = String(localized: "energy_saving.pane.title", defaultValue: "Energy", bundle: Bundle.module)
        public static let paneAccessibilityTitle = String(localized: "energy_saving.pane.accessibility_title", defaultValue: "Energy pane", bundle: Bundle.module)

        public static let lowPowerModeSectionTitle = String(localized: "energy_saving.low_power_mode.settings.section_title", defaultValue: "Low Power Mode", bundle: Bundle.module)
        /// The switch for the whole feature, naming the threshold the slider below it sets.
        /// Takes the percentage already formatted ("20%").
        public static func lowPowerModeToggle(_ percentage: String) -> String {
            String(
                format: String(
                    localized: "energy_saving.low_power_mode.settings.toggle",
                    defaultValue: "Turn on Low Power Mode when the battery is at %@ or lower",
                    bundle: .module
                ),
                locale: Locale.current,
                percentage
            )
        }
        /// VoiceOver's name for the threshold slider, which has no visible label of its own.
        public static let lowPowerModeThresholdAccessibilityLabel = String(localized: "energy_saving.low_power_mode.settings.threshold_accessibility_label", defaultValue: "Low Power Mode threshold", bundle: Bundle.module)
        /// What makes the switch safe to leave on: BatFi gives Low Power Mode back, never
        /// fights the user over it, and the change System Settings shows is expected.
        ///
        /// Says "on for battery" rather than naming a System Settings choice: which one it
        /// shows depends on the power-adapter half BatFi leaves alone ("Only on Battery"
        /// where Low Power Mode was off on the adapter, "Always" where it was on), so no
        /// single name is right.
        public static let lowPowerModeFootnote = String(localized: "energy_saving.low_power_mode.settings.footnote", defaultValue: "BatFi turns Low Power Mode off when you plug in, and leaves it alone if you change it yourself. It changes only the battery setting, so System Settings › Battery shows Low Power Mode as on for battery.", bundle: Bundle.module)
        /// Shown in place of the footnote when the helper can't report Low Power Mode per
        /// power source — a helper older than this feature, or a `pmset` that publishes
        /// neither key.
        public static let lowPowerModeUnavailable = String(localized: "energy_saving.low_power_mode.settings.unavailable", defaultValue: "Not available. BatFi’s helper can’t read this Mac’s Low Power Mode setting.", bundle: Bundle.module)

        // Slowing apps down on battery: the high-energy list in the menu

        /// VoiceOver's name for the row action that slows the app down, and the tooltip of
        /// the button hovering the row shows. Takes the app's name.
        public static func slowDownAppOnBattery(_ appName: String) -> String {
            String(
                format: String(localized: "energy_saving.slow_down.menu.slow_down", defaultValue: "Slow down %@ on battery", bundle: .module),
                locale: Locale.current,
                appName
            )
        }
        /// The same, for an app already slowed down. Takes the app's name.
        public static func stopSlowingAppOnBattery(_ appName: String) -> String {
            String(
                format: String(localized: "energy_saving.slow_down.menu.stop_slowing", defaultValue: "Stop slowing %@ on battery", bundle: .module),
                locale: Locale.current,
                appName
            )
        }
        public static let slowDownAction = String(localized: "energy_saving.slow_down.menu.action.slow", defaultValue: "Slow on battery", bundle: Bundle.module)
        public static let stopSlowingAction = String(localized: "energy_saving.slow_down.menu.action.stop", defaultValue: "Stop slowing", bundle: Bundle.module)

        // What the button's tooltip says first, for an app in the list: whether BatFi is
        // slowing it down right now, and if not, why. Each takes the app's name.

        public static func appIsSlowedNow(_ appName: String) -> String {
            String(
                format: String(localized: "energy_saving.slow_down.menu.status.slowed", defaultValue: "%@ is slowed down right now.", bundle: .module),
                locale: Locale.current,
                appName
            )
        }
        /// Where no reason can be given — before BatFi has looked, say.
        public static func appIsNotSlowedNow(_ appName: String) -> String {
            String(
                format: String(localized: "energy_saving.slow_down.menu.status.not_slowed", defaultValue: "%@ isn’t slowed down right now.", bundle: .module),
                locale: Locale.current,
                appName
            )
        }
        public static func appIsNotSlowedWithoutLicense(_ appName: String) -> String {
            String(
                format: String(localized: "energy_saving.slow_down.menu.status.not_slowed.license", defaultValue: "%@ isn’t slowed down right now: BatFi’s license isn’t active.", bundle: .module),
                locale: Locale.current,
                appName
            )
        }
        /// BatFi's own force discharge counts as plugged in.
        public static func appIsNotSlowedWhilePluggedIn(_ appName: String) -> String {
            String(
                format: String(localized: "energy_saving.slow_down.menu.status.not_slowed.charger", defaultValue: "%@ isn’t slowed down right now: your Mac is plugged in.", bundle: .module),
                locale: Locale.current,
                appName
            )
        }
        /// The couple of seconds BatFi waits after the charger comes out.
        public static func appIsNotSlowedJustUnplugged(_ appName: String) -> String {
            String(
                format: String(localized: "energy_saving.slow_down.menu.status.not_slowed.just_unplugged", defaultValue: "%@ isn’t slowed down right now: your Mac was just unplugged.", bundle: .module),
                locale: Locale.current,
                appName
            )
        }
        public static func appIsNotSlowedNotRunning(_ appName: String) -> String {
            String(
                format: String(localized: "energy_saving.slow_down.menu.status.not_slowed.not_running", defaultValue: "%@ isn’t slowed down right now: it isn’t running.", bundle: .module),
                locale: Locale.current,
                appName
            )
        }
        /// "Background only": the app is in front, or was a moment ago.
        public static func appIsNotSlowedInUse(_ appName: String) -> String {
            String(
                format: String(localized: "energy_saving.slow_down.menu.status.not_slowed.in_use", defaultValue: "%@ isn’t slowed down right now: you’re using it.", bundle: .module),
                locale: Locale.current,
                appName
            )
        }
        public static func appIsNotSlowedPlayingAudio(_ appName: String) -> String {
            String(
                format: String(localized: "energy_saving.slow_down.menu.status.not_slowed.audio", defaultValue: "%@ isn’t slowed down right now: it’s playing audio or on a call.", bundle: .module),
                locale: Locale.current,
                appName
            )
        }
        /// The high-energy list's Quit asked it to quit a moment ago.
        public static func appIsNotSlowedQuitting(_ appName: String) -> String {
            String(
                format: String(localized: "energy_saving.slow_down.menu.status.not_slowed.quitting", defaultValue: "%@ isn’t slowed down right now: it was just asked to quit.", bundle: .module),
                locale: Locale.current,
                appName
            )
        }
        /// The kernel refused to slow its processes down.
        public static func appIsNotSlowedRefused(_ appName: String) -> String {
            String(
                format: String(localized: "energy_saving.slow_down.menu.status.not_slowed.refused", defaultValue: "%@ isn’t slowed down right now: macOS won’t let BatFi slow it down.", bundle: .module),
                locale: Locale.current,
                appName
            )
        }

        // Slowing apps down on battery: the Energy pane

        public static let slowDownSectionTitle = String(localized: "energy_saving.slow_down.settings.section_title", defaultValue: "Apps on battery", bundle: Bundle.module)
        /// The master switch. The list of apps it applies to is right below it.
        public static let slowDownToggle = String(localized: "energy_saving.slow_down.settings.toggle", defaultValue: "Slow down the apps below on battery", bundle: Bundle.module)
        /// What slowing down does, when, and what it spares.
        public static let slowDownFootnote = String(localized: "energy_saving.slow_down.settings.footnote", defaultValue: "While your Mac is on battery, slowed apps run on the efficiency cores, with lower disk and network priority. “Background only” lets an app run at full speed while you’re using it. Apps playing audio or on a call are left alone. An app that depends on a slowed app’s service slows down too.", bundle: Bundle.module)
        public static let slowDownModeBackgroundOnly = String(localized: "energy_saving.slow_down.settings.mode.background_only", defaultValue: "Background only", bundle: Bundle.module)
        public static let slowDownModeAlways = String(localized: "energy_saving.slow_down.settings.mode.always", defaultValue: "Always", bundle: Bundle.module)
        /// Shown while any app is slowed "Always", and as the mode picker's tooltip. What the
        /// owner accepted for that mode, measured: a slowed app, its windows included, can get
        /// no processor time at all while other work keeps the Mac busy, and a build it ran
        /// took about ten times as long.
        public static let slowDownAlwaysWarning = String(localized: "energy_saving.slow_down.settings.always_warning", defaultValue: "With “Always”, the app also runs slowly while you use it. It can stop responding while other work fully loads the Mac, and builds, tests and scripts it launches can take about ten times longer.", bundle: Bundle.module)
        public static let slowDownAddApp = String(localized: "energy_saving.slow_down.settings.add_app", defaultValue: "Add App…", bundle: Bundle.module)
        public static let slowDownDropApps = String(localized: "energy_saving.slow_down.settings.drop_apps", defaultValue: "Drop apps here", bundle: Bundle.module)
        /// Shown at the top of the panel "Add App…" opens.
        public static let slowDownAddAppPanelMessage = String(localized: "energy_saving.slow_down.settings.add_app.panel_message", defaultValue: "Choose the apps to slow down on battery.", bundle: Bundle.module)
        /// The remove button's tooltip and VoiceOver name. Takes the app's name.
        public static func slowDownRemoveApp(_ appName: String) -> String {
            String(
                format: String(localized: "energy_saving.slow_down.settings.remove_app", defaultValue: "Remove %@", bundle: .module),
                locale: Locale.current,
                appName
            )
        }
        /// The alert for apps chosen in "Add App…" that BatFi won't slow down. Takes their
        /// names, already joined into a list ("Finder and Dock").
        public static func slowDownCannotAddTitle(_ appNames: String) -> String {
            String(
                format: String(localized: "energy_saving.slow_down.settings.add_app.rejected.title", defaultValue: "BatFi can’t slow down %@", bundle: .module),
                locale: Locale.current,
                appNames
            )
        }
        /// Why, for a part of macOS or BatFi itself.
        public static let slowDownCannotAddMessage = String(localized: "energy_saving.slow_down.settings.add_app.rejected.message", defaultValue: "BatFi never slows down parts of macOS, or itself.", bundle: Bundle.module)
        /// Why, for a menu bar or background app: one that never comes to the front would stay
        /// slowed for good.
        public static let slowDownCannotAddNoDockIcon = String(localized: "energy_saving.slow_down.settings.add_app.rejected.no_dock_icon", defaultValue: "BatFi can only slow down apps that show in the Dock.", bundle: Bundle.module)
    }
}
