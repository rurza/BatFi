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
      /// Charge to 100%%
      public static let chargeToHundred = L10n.tr("Localizable", "menu.label.charge_to_hundred", fallback: "Charge to 100%%")
      /// More
      public static let more = L10n.tr("Localizable", "menu.label.more", fallback: "More")
      /// Quit BatFi
      public static let quit = L10n.tr("Localizable", "menu.label.quit", fallback: "Quit BatFi")
      /// Settings…
      public static let settings = L10n.tr("Localizable", "menu.label.settings", fallback: "Settings…")
      /// Stop charging to 100%%
      public static let stopChargingToHundred = L10n.tr("Localizable", "menu.label.stop_charging_to_hundred", fallback: "Stop charging to 100%%")
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
