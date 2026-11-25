//
//  TrialStrings.swift
//  BatFi
//
//  Localized strings for the seven-day free trial. Kept in a focused extension rather than
//  the generated Strings.swift. English values are inline defaults.
//

import Foundation

public extension L10n {
    enum Trial {
        /// Too many new trials were started from this network today.
        public static let errorThrottled = String(
            localized: "trial.error.throttled",
            defaultValue: "The trial can’t be started right now. Please try again later.",
            bundle: .module,
            comment: "Shown when the licence server turned down starting a free trial because too many were started from the same network today."
        )

        // Starting

        /// The button that starts the trial. Takes the trial's length in days, which comes from
        /// one constant in the app; days left and the end date never do.
        public static func startTrial(_ days: Int) -> String {
            String.localizedStringWithFormat(
                String(
                    localized: "trial.button.start",
                    defaultValue: "Start %lld-Day Free Trial",
                    bundle: .module,
                    comment: "The button that starts the free trial. The number is the trial's length in days (7)."
                ),
                days
            )
        }

        /// The line under the start button: what the trial is, and what starting it sends.
        public static let startNote = String(
            localized: "trial.label.start_note",
            defaultValue: "Every feature, no card and no account. Starting registers an anonymous identifier of this Mac.",
            bundle: .module,
            comment: "Under the button that starts the free trial. The identifier is a one-way hash of the Mac's serial number."
        )

        /// The title of the alert shown when the trial could not be started; the message is the
        /// failure's own description.
        public static let startFailed = String(
            localized: "trial.alert.start_failed",
            defaultValue: "Trial not started",
            bundle: .module,
            comment: "Title of the alert shown when starting the free trial failed. Styled like \"Unlock failed\"."
        )

        // Running

        /// The heading of the licence screens while the trial runs.
        public static let freeTrial = String(
            localized: "trial.label.free_trial",
            defaultValue: "Free Trial",
            bundle: .module,
            comment: "Heading of the onboarding licence step and the licence window while the free trial runs."
        )

        /// When the running trial ends. Takes the date, already formatted for the user's locale.
        public static func endsOn(_ date: String) -> String {
            String(
                format: String(
                    localized: "trial.label.ends_on",
                    defaultValue: "Your trial ends on %@.",
                    bundle: .module,
                    comment: "Under the heading of the licence screens while the free trial runs. The placeholder is a date, such as \"20 November 2026\"."
                ),
                locale: Locale.current,
                date
            )
        }

        /// The licence pane in Settings while the trial runs. Takes the end date, already
        /// formatted for the user's locale.
        public static func runningUntil(_ date: String) -> String {
            String(
                format: String(
                    localized: "trial.label.running_until",
                    defaultValue: "Free trial — ends %@",
                    bundle: .module,
                    comment: "The licence pane in Settings while the free trial runs. The placeholder is a date, such as \"20 November 2026\"."
                ),
                locale: Locale.current,
                date
            )
        }

        /// The menu's card while the trial runs.
        public static func daysLeft(_ days: Int) -> String {
            daysLeft(days, bundle: .module)
        }

        static func daysLeft(_ days: Int, bundle: Bundle) -> String {
            String.localizedStringWithFormat(
                String(
                    localized: "trial.menu.days_left",
                    defaultValue: "Free trial: %lld days left",
                    bundle: bundle,
                    comment: "A quiet line in a card at the top of the menu while the free trial runs, above a \"Buy BatFi\" button. Needs a plural form for each count."
                ),
                days
            )
        }

        /// The menu's action to buy BatFi, under the days left and on the "trial ended" notice.
        public static let buyBatFi = String(
            localized: "trial.button.buy",
            defaultValue: "Buy BatFi",
            bundle: .module,
            comment: "Button in the menu that opens the store page to buy BatFi, shown during and after the free trial."
        )

        // Ended

        /// The heading of the licence screens, and the menu's notice, once the trial has ended.
        public static let ended = String(
            localized: "trial.label.ended",
            defaultValue: "Your free trial has ended",
            bundle: .module,
            comment: "Heading of the licence screens and the menu's notice once the free trial has ended."
        )

        // Notifications

        public static let endsTomorrowNotificationTitle = String(
            localized: "trial.notification.ends_tomorrow.title",
            defaultValue: "Your BatFi trial ends tomorrow",
            bundle: .module,
            comment: "Notification title, sent once when 24 hours or less of the free trial remain."
        )

        public static let endsTomorrowNotificationBody = String(
            localized: "trial.notification.ends_tomorrow.body",
            defaultValue: "Buy a license to keep your charge limit and automations.",
            bundle: .module,
            comment: "Notification body, sent once when 24 hours or less of the free trial remain."
        )

        public static let endedNotificationTitle = String(
            localized: "trial.notification.ended.title",
            defaultValue: "Your BatFi trial has ended",
            bundle: .module,
            comment: "Notification title, sent once when the free trial has ended."
        )

        public static let endedNotificationBody = String(
            localized: "trial.notification.ended.body",
            defaultValue: "Charging is back under macOS control. Buy a license to continue.",
            bundle: .module,
            comment: "Notification body, sent once when the free trial has ended. BatFi has stopped limiting the charge."
        )

        // Errors

        /// The server refused the request, or could not be reached or understood.
        public static let errorNotStarted = String(
            localized: "trial.error.not_started",
            defaultValue: "The trial couldn’t be started. Check your internet connection and try again.",
            bundle: .module,
            comment: "Shown when starting a free trial failed: no network, the licence server failing, or an answer the app could not use."
        )
    }
}
