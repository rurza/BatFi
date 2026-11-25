//
//  OtherChargeToolsStrings.swift
//  BatFi
//
//  Localized strings for the warning about other charge-control tools installed on this Mac
//  (battery CLI, AlDente, Battery Toolkit, batt, bclm): in Charging settings, and as a row in the
//  menu. Kept in a focused extension rather than the generated Strings.swift. English values
//  are inline defaults.
//
//  Tool names and Terminal commands are always format arguments: they are product names and
//  literal commands, and are never translated.
//

import Foundation

public extension L10n {
    enum OtherChargeTools {
        // Charging settings: what the tool fights BatFi over. The first line of the warning.

        /// For a tool that writes the charge limit itself. Takes the tool's name ("AlDente").
        public static func chargeLimitProblem(_ toolName: String) -> String {
            String(
                format: String(
                    localized: "other_charge_tools.settings.problem.charge_limit",
                    defaultValue: "%@ is also installed on this Mac. It controls charging too, and can override BatFi’s charge limit.",
                    bundle: .module,
                    comment: "Warning in Charging settings, first line. %@ is the name of another charge-control app (never translated)."
                ),
                locale: Locale.current,
                toolName
            )
        }

        /// For the battery CLI on macOS 27-era firmware, where it can no longer change the
        /// charge limit but still overrides the MagSafe light and ends discharging. "Run on
        /// Battery" is BatFi's menu command (menu.label.discharge_battery) — translate it the
        /// same way. Takes the tool's name ("battery CLI").
        public static func magSafeLightAndDischargeProblem(_ toolName: String) -> String {
            String(
                format: String(
                    localized: "other_charge_tools.settings.problem.magsafe_light_and_discharge",
                    defaultValue: "%@ is also installed on this Mac. It can’t change your charge limit, but it can override the MagSafe light and stop Run on Battery.",
                    bundle: .module,
                    comment: "Warning in Charging settings, first line, for the battery command-line tool on newer Macs where it can no longer change the limit. %@ is its name (never translated). Run on Battery is BatFi's menu command: translate it as in menu.label.discharge_battery."
                ),
                locale: Locale.current,
                toolName
            )
        }

        // Charging settings: how to remove the tool. The second line of the warning: one
        // sentence starting "To remove …", then, when there is more to do, sentences
        // starting "Then …", joined with a space.

        /// Takes the tool's name and one Terminal command, already wrapped in backticks
        /// ("`battery uninstall`"); the backticks display it as code.
        public static func removeWithCommand(_ toolName: String, command: String) -> String {
            String(
                format: String(
                    localized: "other_charge_tools.settings.removal.command",
                    defaultValue: "To remove %1$@, run %2$@ in Terminal.",
                    bundle: .module,
                    comment: "Warning in Charging settings, second line. %1$@ is the app's name, %2$@ a Terminal command in backticks, shown as code. Keep both untranslated."
                ),
                locale: Locale.current,
                toolName,
                command
            )
        }

        /// Takes the tool's name and several Terminal commands, already joined into a
        /// localized list ("`a` and `b`"), to be run in that order.
        public static func removeWithCommands(_ toolName: String, commands: String) -> String {
            String(
                format: String(
                    localized: "other_charge_tools.settings.removal.commands",
                    defaultValue: "To remove %1$@, run %2$@ in Terminal, in that order.",
                    bundle: .module,
                    comment: "Warning in Charging settings, second line. %1$@ is the app's name, %2$@ a list of Terminal commands in backticks, already joined (e.g. `a` and `b`). Keep both untranslated."
                ),
                locale: Locale.current,
                toolName,
                commands
            )
        }

        /// The first sentence when the only thing to do is trash the app. Takes the tool's
        /// name and the app's file name ("Battery.app"), or several joined into a list.
        public static func removeByMovingToTrash(_ toolName: String, apps: String) -> String {
            String(
                format: String(
                    localized: "other_charge_tools.settings.removal.trash",
                    defaultValue: "To remove %1$@, move %2$@ to the Trash.",
                    bundle: .module,
                    comment: "Warning in Charging settings, second line. %1$@ is the tool's name, %2$@ an app's file name such as Battery.app (or several, already joined). Keep both untranslated. Trash is the Finder's Trash: use its name on macOS in your language."
                ),
                locale: Locale.current,
                toolName,
                apps
            )
        }

        /// The first sentence for batt.app, which uninstalls its daemon from inside the
        /// app. "Uninstall Daemon" is the English name of batt.app's own command for that.
        /// Takes the tool's name ("batt") and the app's file name ("batt.app").
        public static func removeBattApp(_ toolName: String, app: String) -> String {
            String(
                format: String(
                    localized: "other_charge_tools.settings.removal.batt_app",
                    defaultValue: "To remove %1$@, open %2$@ and choose Uninstall Daemon.",
                    bundle: .module,
                    comment: "Warning in Charging settings, second line. %1$@ is batt, %2$@ its app's file name (batt.app); keep both untranslated. Uninstall Daemon is the English label of a command in batt's own app, which is not translated: keep it in English."
                ),
                locale: Locale.current,
                toolName,
                app
            )
        }

        /// A follow-on sentence: one more Terminal command, already wrapped in backticks.
        public static func thenRunCommand(_ command: String) -> String {
            String(
                format: String(
                    localized: "other_charge_tools.settings.removal.then_command",
                    defaultValue: "Then run %@ in Terminal.",
                    bundle: .module,
                    comment: "Warning in Charging settings, a sentence following the one that starts To remove…. %@ is a Terminal command in backticks, shown as code. Keep it untranslated."
                ),
                locale: Locale.current,
                command
            )
        }

        /// A follow-on sentence: several more Terminal commands, already joined into a
        /// localized list ("`a` and `b`"), to be run in that order.
        public static func thenRunCommands(_ commands: String) -> String {
            String(
                format: String(
                    localized: "other_charge_tools.settings.removal.then_commands",
                    defaultValue: "Then run %@ in Terminal, in that order.",
                    bundle: .module,
                    comment: "Warning in Charging settings, a sentence following the one that starts To remove…. %@ is a list of Terminal commands in backticks, already joined (e.g. `a` and `b`). Keep it untranslated."
                ),
                locale: Locale.current,
                commands
            )
        }

        /// A follow-on sentence: trash the app. Takes the app's file name ("Battery.app"),
        /// or several joined into a list.
        public static func thenMoveToTrash(_ apps: String) -> String {
            String(
                format: String(
                    localized: "other_charge_tools.settings.removal.then_trash",
                    defaultValue: "Then move %@ to the Trash.",
                    bundle: .module,
                    comment: "Warning in Charging settings, a sentence following the one that starts To remove…. %@ is an app's file name such as batt.app (or several, already joined); keep it untranslated. Trash is the Finder's Trash: use its name on macOS in your language."
                ),
                locale: Locale.current,
                apps
            )
        }

        /// AlDente removes itself from its own settings. "Remove AlDente" is the English name
        /// of AlDente's button for that. Takes the tool's name ("AlDente").
        public static func removeAlDente(_ toolName: String) -> String {
            String(
                format: String(
                    localized: "other_charge_tools.settings.removal.aldente",
                    defaultValue: "To remove %@, open its settings and choose Remove AlDente.",
                    bundle: .module,
                    comment: "Warning in Charging settings, second line. %@ is AlDente (never translated). Remove AlDente is the English label of a button in AlDente's own settings."
                ),
                locale: Locale.current,
                toolName
            )
        }

        /// Battery Toolkit runs a background service it installs from inside the app; that has
        /// to be removed from the app before the app is deleted. Takes the tool's name
        /// ("Battery Toolkit").
        public static func removeBatteryToolkit(_ toolName: String) -> String {
            String(
                format: String(
                    localized: "other_charge_tools.settings.removal.battery_toolkit",
                    defaultValue: "To remove %@, first remove its background service from inside the app, then delete the app.",
                    bundle: .module,
                    comment: "Warning in Charging settings, second line. %@ is Battery Toolkit (never translated); its background service must be removed from inside that app first."
                ),
                locale: Locale.current,
                toolName
            )
        }

        // Notification: raised once the charge limit has not held for ten minutes while a
        // tool that can write it is installed. Its title is the generic warning's
        // (notifications.notification.title.charge_limit_not_holding).

        /// Takes the limit, already formatted ("80%"), the tool's name ("AlDente"), and the
        /// removal advice from the sentences above — one, or several joined with spaces when
        /// the tool left more than one footprint — already filled in, with commands in
        /// quotation marks rather than backticks: a notification is not rendered as Markdown.
        public static func notificationChargeLimitNotHolding(limit: String, toolName: String, removal: String) -> String {
            String(
                format: String(
                    localized: "other_charge_tools.notification.body.charge_limit_not_holding",
                    defaultValue: "BatFi re-applied your %1$@ limit, but the battery went past it anyway. %2$@ is installed on this Mac and may be controlling charging. %3$@",
                    bundle: .module,
                    comment: "Notification body. %1$@ is the charge limit (e.g. 80%). %2$@ is another charge-control app's name (never translated). %3$@ is one or more complete sentences saying how to remove that app (other_charge_tools.settings.removal.*), already translated. Translate the first sentence as in notifications.notification.body.charge_limit_not_holding."
                ),
                locale: Locale.current,
                limit,
                toolName,
                removal
            )
        }

        // Menu: a row shown while any such tool is installed. Clicking it opens Charging
        // settings. Keep these short: the menu is about 250 points wide.

        /// The row for one tool. Takes the tool's name ("battery CLI").
        public static func menuOneTool(_ toolName: String) -> String {
            String(
                format: String(
                    localized: "other_charge_tools.menu.title.one",
                    defaultValue: "%@ may conflict with BatFi",
                    bundle: .module,
                    comment: "Menu row, about 250 pt wide: keep short. %@ is another charge-control app's name (never translated). Clicking opens Charging settings."
                ),
                locale: Locale.current,
                toolName
            )
        }

        /// The row for two or more tools, which are not named here.
        public static let menuSeveralTools = String(localized: "other_charge_tools.menu.title.several", defaultValue: "Other charge-control apps may conflict with BatFi", bundle: Bundle.module,
                    comment: "Menu row, about 250 pt wide: keep short. Shown when two or more other charge-control apps are installed. Clicking opens Charging settings.")

        /// Small grey text under the row for one tool.
        public static let menuDetailOneTool = String(localized: "other_charge_tools.menu.detail.one", defaultValue: "Charging settings shows how to remove it.", bundle: Bundle.module,
                    comment: "Small grey text under the menu row about one other charge-control app.")

        /// Small grey text under the row for two or more tools.
        public static let menuDetailSeveralTools = String(localized: "other_charge_tools.menu.detail.several", defaultValue: "Charging settings shows how to remove them.", bundle: Bundle.module,
                    comment: "Small grey text under the menu row about two or more other charge-control apps.")
    }
}
