// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

import Foundation

// swiftlint:disable superfluous_disable_command file_length implicit_return prefer_self_in_static_references

// MARK: - Strings

// swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:disable nesting type_body_length type_name vertical_whitespace_opening_braces
public enum L10n {
  public enum About {
    public enum Button {
      public enum Label {
        /// ******************************************************************************
        ///  * Exported from POEditor - https://poeditor.com
        ///  ******************************************************************************
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
  public enum Settings {
    public enum Accessibility {
      public enum Title {
        /// Charging pane
        public static let charging = L10n.tr("Localizable", "settings.accessibility.title.charging", fallback: "Charging pane")
      }
    }
    public enum Button {
      public enum Description {
        /// Works only with the lid opened.
        public static let lidMustBeOpened = L10n.tr("Localizable", "settings.button.description.lid_must_be_opened", fallback: "Works only with the lid opened.")
      }
      public enum Label {
        /// Automatically manage charging
        public static let automaticallyManageCharging = L10n.tr("Localizable", "settings.button.label.automatically_manage_charging", fallback: "Automatically manage charging")
        /// Delay automatic sleep when charging and the limit's not reached
        public static let disableSleep = L10n.tr("Localizable", "settings.button.label.disable_sleep", fallback: "Delay automatic sleep when charging and the limit's not reached")
        /// Discharge battery when charged over limit
        public static let dischargeBatterWhenOvercharged = L10n.tr("Localizable", "settings.button.label.discharge_batter_when_overcharged", fallback: "Discharge battery when charged over limit")
        /// Automatically turn off charging when the battery gets hot
        public static let turnOffChargingWhenBatteryIsHot = L10n.tr("Localizable", "settings.button.label.turn_off_charging_when_battery_is_hot", fallback: "Automatically turn off charging when the battery gets hot")
      }
      public enum Tooltip {
        /// The app will delay sleep so the computer charge up to the limit and then it'll inhibit charging and put the Mac to sleep
        public static let disableSleep = L10n.tr("Localizable", "settings.button.tooltip.disable_sleep", fallback: "The app will delay sleep so the computer charge up to the limit and then it'll inhibit charging and put the Mac to sleep")
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
