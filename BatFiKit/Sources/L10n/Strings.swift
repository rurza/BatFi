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
