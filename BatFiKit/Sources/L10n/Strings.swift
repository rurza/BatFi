// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

import Foundation

// swiftlint:disable superfluous_disable_command file_length implicit_return prefer_self_in_static_references

// MARK: - Strings

// swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:disable nesting type_body_length type_name vertical_whitespace_opening_braces
public enum L10n {
  /// 2023-07-16T14:34:51Z
  public static let texterifyTimestamp = L10n.tr("Localizable", "texterify_timestamp", fallback: "2023-07-16T14:34:51Z")
  public enum About {
    public enum Button {
      public enum Label {
        /// License
        public static let license = L10n.tr("Localizable", "about.button.label.license", fallback: "License")
        /// Twitter
        public static let twitter = L10n.tr("Localizable", "about.button.label.twitter", fallback: "Twitter")
        /// Website
        public static let website = L10n.tr("Localizable", "about.button.label.website", fallback: "Website")
      }
    }
    public enum Label {
      /// Made with ❤️ and 🔋 by
      public static let aboutDescription = L10n.tr("Localizable", "about.label.about_description", fallback: "Made with ❤️ and 🔋 by")
    }
  }
  public enum AppChargingMode {
    public enum State {
      public enum Description {
        /// The limit is %@.
        public static func charging(_ p1: Any) -> String {
          return L10n.tr("Localizable", "app_charging_mode.state.description.charging", String(describing: p1), fallback: "The limit is %@.")
        }
        /// Charging to 100%%
        public static let forceCharge = L10n.tr("Localizable", "app_charging_mode.state.description.force_charge", fallback: "Charging to 100%%")
        /// Using the battery.
        public static let forceDischarge = L10n.tr("Localizable", "app_charging_mode.state.description.force_discharge", fallback: "Using the battery.")
        /// The charging limit is set to %@.
        public static func inhibit(_ p1: Any) -> String {
          return L10n.tr("Localizable", "app_charging_mode.state.description.inhibit", String(describing: p1), fallback: "The charging limit is set to %@.")
        }
      }
      public enum Title {
        /// Charger not connected
        public static let chargerNotConnected = L10n.tr("Localizable", "app_charging_mode.state.title.charger_not_connected", fallback: "Charger not connected")
        /// Charging to the limit
        public static let charging = L10n.tr("Localizable", "app_charging_mode.state.title.charging", fallback: "Charging to the limit")
        /// Charging
        public static let forceCharge = L10n.tr("Localizable", "app_charging_mode.state.title.force_charge", fallback: "Charging")
        /// Discharging
        public static let forceDischarge = L10n.tr("Localizable", "app_charging_mode.state.title.force_discharge", fallback: "Discharging")
        /// Inhibiting charging
        public static let inhibit = L10n.tr("Localizable", "app_charging_mode.state.title.inhibit", fallback: "Inhibiting charging")
        /// Initializing
        public static let initial = L10n.tr("Localizable", "app_charging_mode.state.title.initial", fallback: "Initializing")
      }
    }
  }
  public enum BatteryInfo {
    public enum Label {
      /// Info is missing
      public static let infoMissing = L10n.tr("Localizable", "battery_info.label.info_missing", fallback: "Info is missing")
      public enum Additional {
        /// App mode
        public static let appMode = L10n.tr("Localizable", "battery_info.label.additional.app_mode", fallback: "App mode")
        /// Battery Health
        public static let batteryCapacity = L10n.tr("Localizable", "battery_info.label.additional.battery_capacity", fallback: "Battery Health")
        /// Cycle Count
        public static let cycleCount = L10n.tr("Localizable", "battery_info.label.additional.cycle_count", fallback: "Cycle Count")
        /// Power Source
        public static let powerSource = L10n.tr("Localizable", "battery_info.label.additional.power_source", fallback: "Power Source")
        /// Temperature
        public static let temperature = L10n.tr("Localizable", "battery_info.label.additional.temperature", fallback: "Temperature")
      }
      public enum Main {
        /// Battery
        public static let battery = L10n.tr("Localizable", "battery_info.label.main.battery", fallback: "Battery")
        public enum Time {
          /// Calculating…
          public static let calculating = L10n.tr("Localizable", "battery_info.label.main.time.calculating", fallback: "Calculating…")
          /// Time Left
          public static let timeLeft = L10n.tr("Localizable", "battery_info.label.main.time.time_left", fallback: "Time Left")
          /// Time to Charge
          public static let timeToCharge = L10n.tr("Localizable", "battery_info.label.main.time.time_to_charge", fallback: "Time to Charge")
        }
      }
    }
  }
  public enum Menu {
    public enum Label {
      /// BatFi…
      public static let batfi = L10n.tr("Localizable", "menu.label.batfi", fallback: "BatFi…")
      /// Charge to 100%%
      public static let chargeToHundred = L10n.tr("Localizable", "menu.label.charge_to_hundred", fallback: "Charge to 100%%")
      /// Check for Updates…
      public static let checkForUpdates = L10n.tr("Localizable", "menu.label.check_for_updates", fallback: "Check for Updates…")
      /// Debug
      public static let debug = L10n.tr("Localizable", "menu.label.debug", fallback: "Debug")
      /// Install Helper
      public static let installHelper = L10n.tr("Localizable", "menu.label.install_helper", fallback: "Install Helper")
      /// More
      public static let more = L10n.tr("Localizable", "menu.label.more", fallback: "More")
      /// Onboarding…
      public static let onboarding = L10n.tr("Localizable", "menu.label.onboarding", fallback: "Onboarding…")
      /// Quit BatFi
      public static let quit = L10n.tr("Localizable", "menu.label.quit", fallback: "Quit BatFi")
      /// Remove Helper
      public static let removeHelper = L10n.tr("Localizable", "menu.label.remove_helper", fallback: "Remove Helper")
      /// Reset settings
      public static let resetSettings = L10n.tr("Localizable", "menu.label.reset_settings", fallback: "Reset settings")
      /// Settings…
      public static let settings = L10n.tr("Localizable", "menu.label.settings", fallback: "Settings…")
      /// Stop charging to 100%%
      public static let stopChargingToHundred = L10n.tr("Localizable", "menu.label.stop_charging_to_hundred", fallback: "Stop charging to 100%%")
    }
    public enum Tooltip {
      public enum ChargeToHundred {
        /// Disabled because the charger is not connected
        public static let chargerNotConnected = L10n.tr("Localizable", "menu.tooltip.charge_to_hundred.charger_not_connected", fallback: "Disabled because the charger is not connected")
        /// Disabled because the "Discharge battery when charged over limit" is turned on
        public static let dischargeTurnedOn = L10n.tr("Localizable", "menu.tooltip.charge_to_hundred.discharge_turned_on", fallback: "Disabled because the \"Discharge battery when charged over limit\" is turned on")
      }
    }
  }
  public enum Notifications {
    public enum Alert {
      public enum Title {
        /// Optimized battery charging is turned ON
        public static let optimizedChargingTurnedOn = L10n.tr("Localizable", "notifications.alert.title.optimized_charging_turned_on", fallback: "Optimized battery charging is turned ON")
      }
    }
    public enum Notification {
      public enum Subtitle {
        /// New mode: %@
        public static func newMode(_ p1: Any) -> String {
          return L10n.tr("Localizable", "notifications.notification.subtitle.new_mode", String(describing: p1), fallback: "New mode: %@")
        }
      }
    }
  }
  public enum Onboarding {
    public enum Alert {
      public enum Button {
        public enum Label {
          /// Open System Settings
          public static let openSystemSettings = L10n.tr("Localizable", "onboarding.alert.button.label.open_system_settings", fallback: "Open System Settings")
        }
      }
      public enum Message {
        /// It seems that you didn't give permissions to the helper. If there was no password/Touch ID prompt that's okay – it's a macOS bug and sometimes it happens.
        /// You can always change permissions in the System Settings.
        /// Please keep in mind that the app won't work without the helper tool.
        public static let helperNotInstalled = L10n.tr("Localizable", "onboarding.alert.message.helper_not_installed", fallback: "It seems that you didn't give permissions to the helper. If there was no password/Touch ID prompt that's okay – it's a macOS bug and sometimes it happens.\nYou can always change permissions in the System Settings.\nPlease keep in mind that the app won't work without the helper tool.")
      }
      public enum Title {
        /// Helper (still) not installed
        public static let helperNotInstalled = L10n.tr("Localizable", "onboarding.alert.title.helper_not_installed", fallback: "Helper (still) not installed")
      }
    }
    public enum Button {
      public enum Label {
        /// Complete
        public static let complete = L10n.tr("Localizable", "onboarding.button.label.complete", fallback: "Complete")
        /// Get started
        public static let getStarted = L10n.tr("Localizable", "onboarding.button.label.get_started", fallback: "Get started")
        /// Install helper
        public static let installHelper = L10n.tr("Localizable", "onboarding.button.label.install_helper", fallback: "Install helper")
        /// Open BatFi at login
        public static let launchAtLogin = L10n.tr("Localizable", "onboarding.button.label.launch_at_login", fallback: "Open BatFi at login")
        /// Next
        public static let next = L10n.tr("Localizable", "onboarding.button.label.next", fallback: "Next")
        /// Previous
        public static let previous = L10n.tr("Localizable", "onboarding.button.label.previous", fallback: "Previous")
      }
    }
    public enum Label {
      /// Almost done.
      public static let almostDone = L10n.tr("Localizable", "onboarding.label.almost_done", fallback: "Almost done.")
      /// BatFi helps you optimize your macOS battery performance by managing charging levels intelligently, yet giving you full control – charging to 100%% only when it's needed.
      public static let appDescription = L10n.tr("Localizable", "onboarding.label.app_description", fallback: "BatFi helps you optimize your macOS battery performance by managing charging levels intelligently, yet giving you full control – charging to 100%% only when it's needed.")
      /// The app is ready to use!
      public static let appIsReady = L10n.tr("Localizable", "onboarding.label.app_is_ready", fallback: "The app is ready to use!")
      /// Done.
      public static let done = L10n.tr("Localizable", "onboarding.label.done", fallback: "Done.")
      /// Extend the life of your Mac.
      public static let extendLife = L10n.tr("Localizable", "onboarding.label.extend_life", fallback: "Extend the life of your Mac.")
      /// BatFi will install helper tool, that will work in background and is able to change your computer's charging mode.
      public static let helperDescription = L10n.tr("Localizable", "onboarding.label.helper_description", fallback: "BatFi will install helper tool, that will work in background and is able to change your computer's charging mode.")
      /// Installing the helper tool requires admin permissions and is essential for BatFi's functionality.
      public static let helperRequiresAdmin = L10n.tr("Localizable", "onboarding.label.helper_requires_admin", fallback: "Installing the helper tool requires admin permissions and is essential for BatFi's functionality.")
      /// Recommended. You can change it later in the app's settings.
      public static let launchAtLoginRecommendation = L10n.tr("Localizable", "onboarding.label.launch_at_login_recommendation", fallback: "Recommended. You can change it later in the app's settings.")
      /// Set Charging Limit.
      public static let setLimit = L10n.tr("Localizable", "onboarding.label.set_limit", fallback: "Set Charging Limit.")
      /// Set a maximum charging percentage to prevent keeping charge level at 100%% and improve battery longevity.
      public static let setLimitDescription = L10n.tr("Localizable", "onboarding.label.set_limit_description", fallback: "Set a maximum charging percentage to prevent keeping charge level at 100%% and improve battery longevity.")
      /// You can modify this setting later in the app's settings.
      public static let setLimitSetUpLater = L10n.tr("Localizable", "onboarding.label.set_limit_set_up_later", fallback: "You can modify this setting later in the app's settings.")
    }
    public enum Slider {
      public enum Label {
        /// Turn off charging when battery will reach %@
        public static func setLimit(_ p1: Any) -> String {
          return L10n.tr("Localizable", "onboarding.slider.label.set_limit", String(describing: p1), fallback: "Turn off charging when battery will reach %@")
        }
      }
    }
  }
  public enum Settings {
    public enum Accessibility {
      public enum Title {
        /// Charging pane
        public static let charging = L10n.tr("Localizable", "settings.accessibility.title.charging", fallback: "Charging pane")
        /// General pane
        public static let general = L10n.tr("Localizable", "settings.accessibility.title.general", fallback: "General pane")
        /// Notifications pane
        public static let notifications = L10n.tr("Localizable", "settings.accessibility.title.notifications", fallback: "Notifications pane")
      }
    }
    public enum Button {
      public enum Description {
        /// Works only with the lid opened.
        public static let lidMustBeOpened = L10n.tr("Localizable", "settings.button.description.lid_must_be_opened", fallback: "Works only with the lid opened.")
      }
      public enum Label {
        /// Automatically check for updates
        public static let automaticallyCheckUpdates = L10n.tr("Localizable", "settings.button.label.automatically_check_updates", fallback: "Automatically check for updates")
        /// Automatically download updates
        public static let automaticallyDownloadUpdates = L10n.tr("Localizable", "settings.button.label.automatically_download_updates", fallback: "Automatically download updates")
        /// Automatically manage charging
        public static let automaticallyManageCharging = L10n.tr("Localizable", "settings.button.label.automatically_manage_charging", fallback: "Automatically manage charging")
        /// Show battery percentage
        public static let batteryPercentage = L10n.tr("Localizable", "settings.button.label.battery_percentage", fallback: "Show battery percentage")
        /// Charging status has changed
        public static let chargingStatusDidChange = L10n.tr("Localizable", "settings.button.label.charging_status_did_change", fallback: "Charging status has changed")
        /// Allow the beta version of the app
        public static let checkForBetaUpdates = L10n.tr("Localizable", "settings.button.label.check_for_beta_updates", fallback: "Allow the beta version of the app")
        /// Show Debug menu
        public static let debugMenu = L10n.tr("Localizable", "settings.button.label.debug_menu", fallback: "Show Debug menu")
        /// Delay automatic sleep when charging and the limit's not reached
        public static let disableAutomaticSleep = L10n.tr("Localizable", "settings.button.label.disable_automatic_sleep", fallback: "Delay automatic sleep when charging and the limit's not reached")
        /// Discharge battery when charged over limit
        public static let dischargeBatterWhenOvercharged = L10n.tr("Localizable", "settings.button.label.discharge_batter_when_overcharged", fallback: "Discharge battery when charged over limit")
        /// Open at login
        public static let launchAtLogin = L10n.tr("Localizable", "settings.button.label.launch_at_login", fallback: "Open at login")
        /// Use the green light on the MagSafe when charging is paused
        public static let magsafeUseGreenLight = L10n.tr("Localizable", "settings.button.label.magsafe_use_green_light", fallback: "Use the green light on the MagSafe when charging is paused")
        /// Show monochrome icon
        public static let monochromeIcon = L10n.tr("Localizable", "settings.button.label.monochrome_icon", fallback: "Show monochrome icon")
        /// Automatically pause charging when the Mac goes to sleep
        public static let pauseChargingOnSleep = L10n.tr("Localizable", "settings.button.label.pause_charging_on_sleep", fallback: "Automatically pause charging when the Mac goes to sleep")
        /// Show alert when the optimized battery charging is engaged
        public static let showAlertsWhenOptimizedChargingIsEngaged = L10n.tr("Localizable", "settings.button.label.show_alerts_when_optimized_charging_is_engaged", fallback: "Show alert when the optimized battery charging is engaged")
        /// Automatically turn off charging when the battery gets hot
        public static let turnOffChargingWhenBatteryIsHot = L10n.tr("Localizable", "settings.button.label.turn_off_charging_when_battery_is_hot", fallback: "Automatically turn off charging when the battery gets hot")
      }
      public enum Tooltip {
        /// The app will delay sleep so the computer charge up to the limit and then it'll inhibit charging and put the Mac to sleep
        public static let disableAutomaticSleep = L10n.tr("Localizable", "settings.button.tooltip.disable_automatic_sleep", fallback: "The app will delay sleep so the computer charge up to the limit and then it'll inhibit charging and put the Mac to sleep")
        /// When Macbook's lid is opened, the app can discharge battery until it will reach the limit
        public static let dischargeBatterWhenOvercharged = L10n.tr("Localizable", "settings.button.tooltip.discharge_batter_when_overcharged", fallback: "When Macbook's lid is opened, the app can discharge battery until it will reach the limit")
        /// Turns off charging when the battery is 35°C or more.
        public static let turnOffChargingWhenBatteryIsHot = L10n.tr("Localizable", "settings.button.tooltip.turn_off_charging_when_battery_is_hot", fallback: "Turns off charging when the battery is 35°C or more.")
      }
    }
    public enum Label {
      /// 80%% is the recommended value for a day-to-day usage.
      public static let chargingRecommendationPart1 = L10n.tr("Localizable", "settings.label.charging_recommendation_part1", fallback: "80%% is the recommended value for a day-to-day usage.")
      /// You can manually override this setting by using the "Charge to 100%%" command from the menu.
      public static let chargingRecommendationPart2 = L10n.tr("Localizable", "settings.label.charging_recommendation_part2", fallback: "You can manually override this setting by using the \"Charge to 100%%\" command from the menu.")
    }
    public enum Section {
      /// Advanced
      public static let advanced = L10n.tr("Localizable", "settings.section.advanced", fallback: "Advanced")
      /// Alerts
      public static let alerts = L10n.tr("Localizable", "settings.section.alerts", fallback: "Alerts")
      /// General
      public static let general = L10n.tr("Localizable", "settings.section.general", fallback: "General")
      /// Notifications
      public static let notifications = L10n.tr("Localizable", "settings.section.notifications", fallback: "Notifications")
      /// Status icon
      public static let statusIcon = L10n.tr("Localizable", "settings.section.status_icon", fallback: "Status icon")
      /// Updates
      public static let updates = L10n.tr("Localizable", "settings.section.updates", fallback: "Updates")
    }
    public enum Slider {
      public enum Label {
        /// Turn off charging when battery will reach %@
        public static func turnOffChargingAt(_ p1: Any) -> String {
          return L10n.tr("Localizable", "settings.slider.label.turn_off_charging_at", String(describing: p1), fallback: "Turn off charging when battery will reach %@")
        }
      }
    }
    public enum Tab {
      public enum Title {
        /// Charging
        public static let charging = L10n.tr("Localizable", "settings.tab.title.charging", fallback: "Charging")
        /// General
        public static let general = L10n.tr("Localizable", "settings.tab.title.general", fallback: "General")
        /// Notifications
        public static let notifications = L10n.tr("Localizable", "settings.tab.title.notifications", fallback: "Notifications")
      }
    }
  }
}
// swiftlint:enable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:enable nesting type_body_length type_name vertical_whitespace_opening_braces

// MARK: - Implementation Details

extension L10n {
  private static func tr(_ table: String, _ key: String, _ args: CVarArg..., fallback value: String) -> String {
    let format = BundleToken.bundle.localizedString(forKey: key, value: value, table: table)
    return String(format: format, locale: Locale.current, arguments: args)
  }
}

// swiftlint:disable convenience_type
private final class BundleToken {
  static let bundle: Bundle = {
    #if SWIFT_PACKAGE
    return Bundle.module
    #else
    return Bundle(for: BundleToken.self)
    #endif
  }()
}
// swiftlint:enable convenience_type
