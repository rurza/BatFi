import Foundation

public enum L10n {

    public enum About {
        public enum Button {
            public enum Label {
                /// License
                public static let license = String(localized: "about.button.label.license", defaultValue: "License", bundle: Bundle.module)
                /// Twitter
                public static let twitter = String(localized: "about.button.label.twitter", defaultValue: "Twitter", bundle: Bundle.module)
                /// Website
                public static let website = String(localized: "about.button.label.website", defaultValue: "Website", bundle: Bundle.module)
            }
        }
        public enum Label {
            /// Made with ❤️ and 🔋 by
            public static let aboutDescription = String(localized: "about.label.about_description", defaultValue: "Made with ❤️ and 🔋 by", bundle: Bundle.module)
        }
    }
    public enum AppChargingMode {
        public enum State {
            public enum Description {
                /// The limit is %@.
                public static func charging(_ p1: Any) -> String {
                    return String(
                        format: String(
                            localized: "app_charging_mode.state.description.charging",
                            defaultValue: "The limit is %@.",
                            bundle: .module
                        ),
                        locale: Locale.current,
                        String(describing: p1)
                    )

                }
                /// Charging to 100%
                public static let forceCharge = String(localized: "app_charging_mode.state.description.force_charge", defaultValue: "Charging to 100%", bundle: Bundle.module)
                /// Using the battery.
                public static let forceDischarge = String(localized: "app_charging_mode.state.description.force_discharge", defaultValue: "Using the battery.", bundle: Bundle.module)
                /// The charging limit is set to %@.
                public static func inhibit(_ p1: Any) -> String {
                    return String(
                        format: String(
                            localized: "app_charging_mode.state.description.inhibit",
                            defaultValue: "The charging limit is set to %@.",
                            bundle: .module
                        ),
                        locale: Locale.current,
                        String(describing: p1)
                    )
                }
            }
            public enum Title {
                /// Charger not connected
                public static let chargerNotConnected = String(localized: "app_charging_mode.state.title.charger_not_connected", defaultValue: "Charger not connected", bundle: Bundle.module)
                /// Charging to the limit
                public static let charging = String(localized: "app_charging_mode.state.title.charging", defaultValue: "Charging to the limit", bundle: Bundle.module)
                /// Charging
                public static let forceCharge = String(localized: "app_charging_mode.state.title.force_charge", defaultValue: "Charging", bundle: Bundle.module)
                /// Discharging
                public static let forceDischarge = String(localized: "app_charging_mode.state.title.force_discharge", defaultValue: "Discharging", bundle: Bundle.module)
                /// Inhibiting charging
                public static let inhibit = String(localized: "app_charging_mode.state.title.inhibit", defaultValue: "Inhibiting charging", bundle: Bundle.module)
                /// Initializing
                public static let initial = String(localized: "app_charging_mode.state.title.initial", defaultValue: "Initializing", bundle: Bundle.module)
            }
        }
    }
    public enum BatteryInfo {
        public enum Label {
            /// Info is missing
            public static let infoMissing = String(localized: "battery_info.label.info_missing", defaultValue: "Info is missing", bundle: Bundle.module)
            public enum Additional {
                /// App mode
                public static let appMode = String(localized: "battery_info.label.additional.app_mode", defaultValue: "App mode", bundle: Bundle.module)
                /// Battery Health
                public static let batteryCapacity = String(localized: "battery_info.label.additional.battery_capacity", defaultValue: "Battery Health", bundle: Bundle.module)
                /// Cycle Count
                public static let cycleCount = String(localized: "battery_info.label.additional.cycle_count", defaultValue: "Cycle Count", bundle: Bundle.module)
                /// Power Source
                public static let powerSource = String(localized: "battery_info.label.additional.power_source", defaultValue: "Power Source", bundle: Bundle.module)
                /// Temperature
                public static let temperature = String(localized: "battery_info.label.additional.temperature", defaultValue: "Temperature", bundle: Bundle.module)
            }
            public enum Main {
                /// Battery
                public static let battery = String(localized: "battery_info.label.main.battery", defaultValue: "Battery", bundle: Bundle.module)
                public enum Time {
                    /// Calculating…
                    public static let calculating = String(localized: "battery_info.label.main.time.calculating", defaultValue: "Calculating…", bundle: Bundle.module)
                    /// Time Left
                    public static let timeLeft = String(localized: "battery_info.label.main.time.time_left", defaultValue: "Time Left", bundle: Bundle.module)
                    /// Time to Charge
                    public static let timeToCharge = String(localized: "battery_info.label.main.time.time_to_charge", defaultValue: "Time to Charge", bundle: Bundle.module)
                }
            }
        }
    }
    public enum Menu {
        public enum Label {
            /// BatFi…
            public static let batfi = String(localized: "menu.label.batfi", defaultValue: "BatFi…", bundle: Bundle.module)
            /// Charge to 100%
            public static let chargeToHundred = String(localized: "menu.label.charge_to_hundred", defaultValue: "Charge to 100%", bundle: Bundle.module)
            /// Check for Updates…
            public static let checkForUpdates = String(localized: "menu.label.check_for_updates", defaultValue: "Check for Updates…", bundle: Bundle.module)
            /// Debug
            public static let debug = String(localized: "menu.label.debug", defaultValue: "Debug", bundle: Bundle.module)
            /// Install Helper
            public static let installHelper = String(localized: "menu.label.install_helper", defaultValue: "Install Helper", bundle: Bundle.module)
            /// More
            public static let more = String(localized: "menu.label.more", defaultValue: "More", bundle: Bundle.module)
            /// Onboarding…
            public static let onboarding = String(localized: "menu.label.onboarding", defaultValue: "Onboarding…", bundle: Bundle.module)
            /// Quit BatFi
            public static let quit = String(localized: "menu.label.quit", defaultValue: "Quit BatFi", bundle: Bundle.module)
            /// Remove Helper
            public static let removeHelper = String(localized: "menu.label.remove_helper", defaultValue: "Remove Helper", bundle: Bundle.module)
            /// Reset settings
            public static let resetSettings = String(localized: "menu.label.reset_settings", defaultValue: "Reset settings", bundle: Bundle.module)
            /// Settings…
            public static let settings = String(localized: "menu.label.settings", defaultValue: "Settings…", bundle: Bundle.module)
            /// Stop charging to 100%
            public static let stopChargingToHundred = String(localized: "menu.label.stop_charging_to_hundred", defaultValue: "Stop charging to 100%", bundle: Bundle.module)
        }

        public enum Charts {
            /// Waiting for data…
            public static let waitingForData = String(localized: "menu.charts.waitingForData", defaultValue: "Waiting for (more) data…", bundle: Bundle.module)

            public static let chartsHeader = String(localized: "menu.charts.header", defaultValue: "Last 12 hours", bundle: .module)

            public enum Legend {
                public static let charging = String(localized: "menu.charts.legend.charging", defaultValue: "Charging", bundle: .module)
                public static let inhibiting = String(localized: "menu.charts.legend.inhibiting", defaultValue: "Inhibiting Charging", bundle: .module)
            }
        }

        public enum PowerInfo {
            /// Waiting for data…
            public static let loading = String(localized: "menu.power_info.loading", defaultValue: "Waiting for data…", bundle: Bundle.module)

            /// Power distribution
            public static let header = String(localized: "menu.power_info.header", defaultValue: "Power distribution", bundle: Bundle.module)
        }

        public enum HighEnergyUsage {
            /// Waiting for data…
            public static let loading = String(localized: "menu.high_energy_usage.loading", defaultValue: "Waiting for data…", bundle: Bundle.module)

            /// Apps with high energy usage
            public static let header = String(localized: "menu.high_energy_usage.header", defaultValue: "Apps with high energy usage", bundle: Bundle.module)

            /// No apps with high energy impact
            public static let `none` = String(localized: "battery_info.label.top_coalition.none", defaultValue: "No apps using significant energy", bundle: Bundle.module)
        }

        public enum Tooltip {
            public enum ChargeToHundred {
                /// Disabled because the charger is not connected
                public static let chargerNotConnected = String(localized: "menu.tooltip.charge_to_hundred.charger_not_connected", defaultValue: "Disabled because the charger is not connected", bundle: Bundle.module)
                /// Disabled because the "Discharge battery when charged over limit" is turned on
                public static let dischargeTurnedOn = String(localized: "menu.tooltip.charge_to_hundred.discharge_turned_on", defaultValue: "Disabled because the \"Discharge battery when charged over limit\" is turned on", bundle: Bundle.module)
            }
        }
    }
    public enum Notifications {
        public enum Alert {
            public enum Title {
                /// Optimized battery charging is turned ON
                public static let optimizedChargingTurnedOn = String(localized: "notifications.alert.title.optimized_charging_turned_on", defaultValue: "Optimized battery charging is turned ON", bundle: Bundle.module)
            }
        }
        public enum Notification {
            public enum Subtitle {
                /// New mode: %@
                public static func newMode(_ p1: Any) -> String {
                    String(
                        format: String(
                            localized: "notifications.notification.subtitle.new_mode",
                            defaultValue: "New mode: %@",
                            bundle: .module
                        ),
                        String(describing: p1)
                    )
                }
            }

            public enum Title {
                public static let lowBattery = String(localized: "notifications.notification.title.low_battery", defaultValue: "Battery is low", bundle: Bundle.module)
            }

            public enum Body {
                public static let lowBattery = String(localized: "notifications.notification.body.low_battery", defaultValue: "I need more juice!", bundle: Bundle.module)
            }
        }
    }
    public enum Onboarding {
        public enum Alert {
            public enum Button {
                public enum Label {
                    /// Open System Settings
                    public static let openSystemSettings = String(localized: "onboarding.alert.button.label.open_system_settings", defaultValue: "Open System Settings", bundle: Bundle.module)
                }
            }
            public enum Message {
                /// It seems that you didn't give permissions to the helper. If there was no password/Touch ID prompt that's okay – it's a macOS bug and sometimes it happens.
                /// You can always change permissions in the System Settings.
                /// Please keep in mind that the app won't work without the helper tool.
                public static let helperNotInstalled = String(localized: "onboarding.alert.message.helper_not_installed", defaultValue: "It seems that you didn't give permissions to the helper. If there was no password/Touch ID prompt that's okay – it's a macOS bug and sometimes it happens.\nYou can always change permissions in the System Settings.\nPlease keep in mind that the app won't work without the helper tool.", bundle: Bundle.module)
            }
            public enum Title {
                /// Helper (still) not installed
                public static let helperNotInstalled = String(localized: "onboarding.alert.title.helper_not_installed", defaultValue: "Helper (still) not installed", bundle: Bundle.module)
            }
        }
        public enum Button {
            public enum Label {
                /// Complete
                public static let complete = String(localized: "onboarding.button.label.complete", defaultValue: "Complete", bundle: Bundle.module)
                /// Get started
                public static let getStarted = String(localized: "onboarding.button.label.get_started", defaultValue: "Get started", bundle: Bundle.module)
                /// Install helper
                public static let installHelper = String(localized: "onboarding.button.label.install_helper", defaultValue: "Install helper", bundle: Bundle.module)
                /// Open BatFi at login
                public static let launchAtLogin = String(localized: "onboarding.button.label.launch_at_login", defaultValue: "Open BatFi at login", bundle: Bundle.module)
                /// Next
                public static let next = String(localized: "onboarding.button.label.next", defaultValue: "Next", bundle: Bundle.module)
                /// Previous
                public static let previous = String(localized: "onboarding.button.label.previous", defaultValue: "Previous", bundle: Bundle.module)
            }
        }
        public enum Label {
            /// Almost done.
            public static let almostDone = String(localized: "onboarding.label.almost_done", defaultValue: "Almost done.", bundle: Bundle.module)
            /// BatFi helps you optimize your macOS battery performance by managing charging levels intelligently, yet giving you full control – charging to 100% only when it's needed.
            public static let appDescription = String(localized: "onboarding.label.app_description", defaultValue: "BatFi helps you optimize your macOS battery performance by managing charging levels intelligently, yet giving you full control – charging to 100% only when it's needed.", bundle: Bundle.module)
            /// The app is ready to use!
            public static let appIsReady = String(localized: "onboarding.label.app_is_ready", defaultValue: "The app is ready to use!", bundle: Bundle.module)
            /// Done.
            public static let done = String(localized: "onboarding.label.done", defaultValue: "Done.", bundle: Bundle.module)
            /// Extend the life of your Mac.
            public static let extendLife = String(localized: "onboarding.label.extend_life", defaultValue: "Extend the life of your Mac.", bundle: Bundle.module)
            /// BatFi will install helper tool, that will work in background and is able to change your computer's charging mode.
            public static let helperDescription = String(localized: "onboarding.label.helper_description", defaultValue: "BatFi will install helper tool, that will work in background and is able to change your computer's charging mode.", bundle: Bundle.module)
            /// Installing the helper tool requires admin permissions and is essential for BatFi's functionality.
            public static let helperRequiresAdmin = String(localized: "onboarding.label.helper_requires_admin", defaultValue: "Installing the helper tool requires admin permissions and is essential for BatFi's functionality.", bundle: Bundle.module)
            /// Recommended. You can change it later in the app's settings.
            public static let launchAtLoginRecommendation = String(localized: "onboarding.label.launch_at_login_recommendation", defaultValue: "Recommended. You can change it later in the app's settings.", bundle: Bundle.module)
            /// Set Charging Limit.
            public static let setLimit = String(localized: "onboarding.label.set_limit", defaultValue: "Set Charging Limit.", bundle: Bundle.module)
            /// Set a maximum charging percentage to prevent keeping charge level at 100% and improve battery longevity.
            public static let setLimitDescription = String(localized: "onboarding.label.set_limit_description", defaultValue: "Set a maximum charging percentage to prevent keeping charge level at 100% and improve battery longevity.", bundle: Bundle.module)
            /// You can modify this setting later in the app's settings.
            public static let setLimitSetUpLater = String(localized: "onboarding.label.set_limit_set_up_later", defaultValue: "You can modify this setting later in the app's settings.", bundle: Bundle.module)
        }
        public enum Slider {
            public enum Label {
                /// Turn off charging when battery will reach %@
                public static func setLimit(_ p1: Any) -> String {
                    String(
                        format: String(
                            localized: "onboarding.slider.label.set_limit",
                            defaultValue: "Turn off charging when battery will reach %@",
                            bundle: Bundle.module
                        ),
                        String(describing: p1)
                    )
                }
            }
        }
    }
    public enum Settings {
        public enum Accessibility {
            public enum Title {
                /// Charging pane
                public static let charging = String(localized: "settings.accessibility.title.charging", defaultValue: "Charging pane", bundle: Bundle.module)
                /// General pane
                public static let general = String(localized: "settings.accessibility.title.general", defaultValue: "General pane", bundle: Bundle.module)
                /// Notifications pane
                public static let notifications = String(localized: "settings.accessibility.title.notifications", defaultValue: "Notifications pane", bundle: Bundle.module)
                /// Menu bar pane
                public static let statusBar = String(localized: "settings.accessibility.title.statusBar", defaultValue: "Menu bar pane", bundle: Bundle.module)
                /// Advanced pane
                public static let advanced = String(localized: "settings.accessibility.title.advanced", defaultValue: "Advanced pane", bundle: Bundle.module)
            }
        }
        public enum Button {
            public enum Description {
                /// Works only with the lid opened.
                public static let lidMustBeOpened = String(localized: "settings.button.description.lid_must_be_opened", defaultValue: "Works only with the lid opened.", bundle: Bundle.module)
            }
            public enum Label {
                /// Automatically check for updates
                public static let automaticallyCheckUpdates = String(localized: "settings.button.label.automatically_check_updates", defaultValue: "Automatically check for updates", bundle: Bundle.module)
                /// Automatically download updates
                public static let automaticallyDownloadUpdates = String(localized: "settings.button.label.automatically_download_updates", defaultValue: "Automatically download updates", bundle: Bundle.module)
                /// Automatically manage charging
                public static let automaticallyManageCharging = String(localized: "settings.button.label.automatically_manage_charging", defaultValue: "Automatically manage charging", bundle: Bundle.module)
                /// Show battery percentage
                public static let batteryPercentage = String(localized: "settings.button.label.battery_percentage", defaultValue: "Show battery percentage", bundle: Bundle.module)
                /// Blink the LED on MagSafe a few times when the app begins to discharge the battery
                public static let blinkMagSafeWhenDischarging = String(localized: "settings.button.label.blink_magSafe_when_discharging", defaultValue: "Blink the LED on MagSafe a few times when the app begins to discharge the battery", bundle: Bundle.module)
                /// Charging status has changed
                public static let chargingStatusDidChange = String(localized: "settings.button.label.charging_status_did_change", defaultValue: "Charging status has changed", bundle: Bundle.module)
                /// Allow the beta version of the app
                public static let checkForBetaUpdates = String(localized: "settings.button.label.check_for_beta_updates", defaultValue: "Allow the beta version of the app", bundle: Bundle.module)
                /// Show Debug menu
                public static let debugMenu = String(localized: "settings.button.label.debug_menu", defaultValue: "Show Debug menu", bundle: Bundle.module)
                /// Delay automatic sleep when charging and the limit's not reached
                public static let disableAutomaticSleep = String(localized: "settings.button.label.disable_automatic_sleep", defaultValue: "Delay automatic sleep when charging and the limit's not reached", bundle: Bundle.module)
                /// Discharge battery when charged over limit
                public static let dischargeBatterWhenOvercharged = String(localized: "settings.button.label.discharge_batter_when_overcharged", defaultValue: "Discharge battery when charged over limit", bundle: Bundle.module)
                /// Open at login
                public static let launchAtLogin = String(localized: "settings.button.label.launch_at_login", defaultValue: "Open at login", bundle: Bundle.module)
                /// Use the green light on the MagSafe when charging is paused
                public static let magsafeUseGreenLight = String(localized: "settings.button.label.magsafe_use_green_light", defaultValue: "Use the green light on the MagSafe when charging is paused", bundle: Bundle.module)
                /// Show monochrome icon
                public static let monochromeIcon = String(localized: "settings.button.label.monochrome_icon", defaultValue: "Show monochrome icon", bundle: Bundle.module)
                /// Automatically pause charging when the Mac goes to sleep
                public static let pauseChargingOnSleep = String(localized: "settings.button.label.pause_charging_on_sleep", defaultValue: "Automatically pause charging when the Mac goes to sleep", bundle: Bundle.module)
                /// Show alert when the optimized battery charging is engaged
                public static let showAlertsWhenOptimizedChargingIsEngaged = String(localized: "settings.button.label.show_alerts_when_optimized_charging_is_engaged", defaultValue: "Show alert when the optimized battery charging is engaged", bundle: Bundle.module)
                /// Automatically turn off charging when the battery gets hot
                public static let turnOffChargingWhenBatteryIsHot = String(localized: "settings.button.label.turn_off_charging_when_battery_is_hot", defaultValue: "Automatically turn off charging when the battery gets hot", bundle: Bundle.module)
                /// Show the battery percentage chart in the menu
                public static let showBatteryChartInMenu = String(localized: "settings.button.label.show_battery_chart_in_menu", defaultValue: "Show the battery percentage chart in the menu", bundle: Bundle.module)
                public static let showBatteryLowNotification = String(localized: "settings.button.label.show_battery_low_notification", defaultValue: "Battery is low at 20%", bundle: Bundle.module)
                /// Automatically enable system charge limit (80%) when the Mac goes to sleep
                public static let enableSystemChargeLimitOnSleep = String(localized: "settings.button.label.enable_system_charge_limit_on_sleep", defaultValue: "Automatically enable system charge limit (80%) when the Mac goes to sleep", bundle: Bundle.module)
                /// Show power distribution
                public static let showPowerDiagram = String(localized: "settings.button.label.show_power_diagram", defaultValue: "Show power distribution", bundle: Bundle.module)
                /// Show apps with high energy usage
                public static let showHighEnergyImpactProcesses = String(localized: "settings.button.label.high_energy_impact_processes_show", defaultValue: "Show apps with high energy usage", bundle: .module)
            }
            public enum Tooltip {
                /// The app will delay sleep so the computer charge up to the limit and then it'll inhibit charging and put the Mac to sleep
                public static let disableAutomaticSleep = String(localized: "settings.button.tooltip.disable_automatic_sleep", defaultValue: "The app will delay sleep so the computer charge up to the limit and then it'll inhibit charging and put the Mac to sleep", bundle: Bundle.module)
                /// When Macbook's lid is opened, the app can discharge battery until it will reach the limit
                public static let dischargeBatterWhenOvercharged = String(localized: "settings.button.tooltip.discharge_battery_when_overcharged", defaultValue: "When Macbook's lid is opened, the app can discharge battery until it will reach the limit", bundle: Bundle.module)
                /// Turns off charging when the battery is 35°C or more.
                public static let turnOffChargingWhenBatteryIsHot = String(localized: "settings.button.tooltip.turn_off_charging_when_battery_is_hot", defaultValue: "Turns off charging when the battery is 35°C or more.", bundle: Bundle.module)
            }
        }
        public enum Label {
            /// 80% is the recommended value for a day-to-day usage.
            public static let chargingRecommendationPart1 = String(localized: "settings.label.charging_recommendation_part1", defaultValue: "80% is the recommended value for a day-to-day usage.", bundle: Bundle.module)
            /// You can manually override this setting by using the "Charge to 100%" command from the menu.
            public static let chargingRecommendationPart2 = String(localized: "settings.label.charging_recommendation_part2", defaultValue: "You can manually override this setting by using the \"Charge to 100%\" command from the menu.", bundle: Bundle.module)

            /// Show up to %@ processes
            public static func highEnergyImpactProcessesCapacity(_ p1: Int) -> String {
                String.localizedStringWithFormat(
                    NSLocalizedString(
                        "settings.label.high_energy_impact_processes_capacity",
                        bundle: .module,
                        value: "Show up to %lld processes",
                        comment: ""
                    ),
                    p1
                )
            }

            /// Sample duration:
            public static func highEnergyImpactProcessesDuration(_ p1: String) -> String {
                String.localizedStringWithFormat(
                    NSLocalizedString(
                        "settings.label.high_energy_impact_processes_duration",
                        bundle: .module,
                        value: "Sample duration: %@",
                        comment: ""
                    ),
                    p1
                )
            }

            /// Threshold of the energy impact: %lld
            public static func highEnergyImpactProcessesThreshold(_ p1: Int) -> String {
                String.localizedStringWithFormat(
                    NSLocalizedString(
                        "settings.label.high_energy_impact_processes_threshold",
                        bundle: .module,
                        value: "Threshold of the energy impact: %lld",
                        comment: ""
                    ),
                    p1
                )
            }

            /// 30s
            public static let highEnergyImpactProcessesMinDuration = String(localized: "settings.label.high_energy_impact_processes_min_duration", defaultValue: "30s", bundle: .module)

            /// 5 minutes
            public static let highEnergyImpactProcessesMaxDuration = String(localized: "settings.label.high_energy_impact_processes_max_duration", defaultValue: "5 minutes", bundle: .module)
        }
        public enum Section {
            /// Advanced
            public static let advanced = String(localized: "settings.section.advanced", defaultValue: "Advanced", bundle: Bundle.module)
            /// Alerts
            public static let alerts = String(localized: "settings.section.alerts", defaultValue: "Alerts", bundle: Bundle.module)
            /// General
            public static let general = String(localized: "settings.section.general", defaultValue: "General", bundle: Bundle.module)
            /// MagSafe
            public static let magSafe = String(localized: "settings.section.magSafe", defaultValue: "MagSafe", bundle: Bundle.module)
            /// Notifications
            public static let notifications = String(localized: "settings.section.notifications", defaultValue: "Notifications", bundle: Bundle.module)
            /// Status icon
            public static let statusIcon = String(localized: "settings.section.status_icon", defaultValue: "Status icon", bundle: Bundle.module)
            /// Updates
            public static let updates = String(localized: "settings.section.updates", defaultValue: "Updates", bundle: Bundle.module)
            /// Menu
            public static let menu = String(localized: "settings.section.menu", defaultValue: "Menu", bundle: Bundle.module)
            /// Charging
            public static let charging = String(localized: "settings.section.charging", defaultValue: "Charging", bundle: Bundle.module)
            /// Debug
            public static let debug = String(localized: "settings.section.debug", defaultValue: "Debug", bundle: Bundle.module)
            /// Apps with high energy usage
            public static let highEnergyImpactProcesses = String(localized: "settings.section.high_energy_impact_processes", defaultValue: "Apps with high energy usage", bundle: .module)
        }
        public enum Slider {
            public enum Label {
                /// Turn off charging when battery will reach %@
                public static func turnOffChargingAt(_ p1: Any) -> String {
                    String(
                        format: String(
                            localized: "settings.slider.label.turn_off_charging_at",
                            defaultValue: "Turn off charging when battery will reach %@",
                            bundle: .module),
                        String(describing: p1)
                    )
                }
            }
        }
        public enum Tab {
            public enum Title {
                /// Charging
                public static let charging = String(localized: "settings.tab.title.charging", defaultValue: "Charging", bundle: Bundle.module)
                /// General
                public static let general = String(localized: "settings.tab.title.general", defaultValue: "General", bundle: Bundle.module)
                /// Notifications
                public static let notifications = String(localized: "settings.tab.title.notifications", defaultValue: "Notifications", bundle: Bundle.module)
                /// Status bar
                public static let statusBar = String(localized: "settings.tab.title.statusbar", defaultValue: "Menu Bar", bundle: Bundle.module)
                /// Advanced
                public static let advanced = String(localized: "settings.tab.title.advanced", defaultValue: "Advanced", bundle: Bundle.module)
            }
        }
    }
}
