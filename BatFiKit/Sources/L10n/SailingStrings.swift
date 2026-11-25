//
//  SailingStrings.swift
//  BatFi
//
//  Localized strings for sailing (shown to users as "Resume charging below a set level"):
//  holding charge between a resume level and the limit rather than topping the battery up
//  every time it slips below the limit. Kept in a focused
//  extension rather than the generated Strings.swift. English values are inline defaults.
//

import Foundation

public extension L10n {
    enum Sailing {
        /// The state line while sailing holds charge. Takes the resume level, already
        /// formatted as a percentage.
        public static func onHoldTitle(_ resume: String) -> String {
            String(
                format: String(
                    localized: "sailing.state.title",
                    defaultValue: "On hold until below %@",
                    bundle: .module,
                    comment: "The charging state in the menu while the charger is connected and charging is held below the limit until the battery drops below a lower level. The placeholder is that level as a percentage, such as \"70%\"."
                ),
                locale: Locale.current,
                resume
            )
        }

        /// The line under the state while sailing holds charge. Takes the limit and the
        /// resume level, both already formatted as percentages.
        public static func onHoldDescription(_ limit: String, _ resume: String) -> String {
            String(
                format: String(
                    localized: "sailing.state.description",
                    defaultValue: "The limit is %1$@. Charging resumes below %2$@.",
                    bundle: .module,
                    comment: "Under the charging state in the menu while charging is held below the limit. The first placeholder is the charge limit, the second the lower level below which charging starts again; both are percentages, such as \"80%\" and \"70%\"."
                ),
                locale: Locale.current,
                limit,
                resume
            )
        }

        // Settings

        /// The switch under the charge limit slider that turns sailing on.
        public static let toggleLabel = String(
            localized: "sailing.toggle.label",
            defaultValue: "Resume charging below a set level",
            bundle: .module,
            comment: "A checkbox under the charge limit slider in Settings. When on, after charging to the limit the Mac does not top the battery up again straight away: it waits until the battery drops below a second, lower level, chosen with a second handle on the slider, and only then charges again."
        )

        /// The line under the sailing switch: what it does and when it suits.
        public static let toggleDescription = String(
            localized: "sailing.toggle.description",
            defaultValue: "After reaching the limit, charging waits until the battery drops below the second level. Best for a Mac that’s often unplugged.",
            bundle: .module,
            comment: "Under the \"Resume charging below a set level\" checkbox in Settings, on two lines. \"The limit\" is the upper handle of the charge limit slider, \"the second level\" its lower handle. \"Often unplugged\" means the Mac regularly runs on battery, such as a laptop carried around during the day."
        )

        /// The sentence in the Charging pane's help popover while sailing is on: the slow drop
        /// on a charger, which used to make the switch's description three lines long.
        public static let slowDropWhilePluggedIn = String(
            localized: "sailing.help.slow_drop_while_plugged_in",
            defaultValue: "While the Mac stays plugged in, the battery drops very slowly, so it can take days to reach the second level.",
            bundle: .module,
            comment: "In the help popover of the Charging settings pane, shown only while the \"Resume charging below a set level\" checkbox is on. With the charger connected and charging waiting, the battery loses charge only very slowly, so falling to the lower level (the lower handle of the charge limit slider) where charging starts again can take days."
        )

        /// The caption above the slider while sailing is on. Takes the limit and the resume
        /// level, both already formatted as percentages.
        public static func sliderCaption(_ limit: String, _ resume: String) -> String {
            String(
                format: String(
                    localized: "sailing.slider.caption",
                    defaultValue: "Charge to %1$@, resume below %2$@",
                    bundle: .module,
                    comment: "Above the two-handle charge limit slider in Settings while the \"Resume charging below a set level\" checkbox is on, on one line. The first placeholder is the charge limit, the second the lower level below which charging starts again; both are percentages, such as \"80%\" and \"70%\"."
                ),
                locale: Locale.current,
                limit,
                resume
            )
        }

        /// What VoiceOver calls the slider's upper handle.
        public static let limitHandleName = String(
            localized: "sailing.slider.limit_handle",
            defaultValue: "Charge limit",
            bundle: .module,
            comment: "VoiceOver name of the upper handle of the two-handle charge limit slider in Settings: the level charging stops at."
        )

        /// What VoiceOver calls the slider's lower handle.
        public static let resumeHandleName = String(
            localized: "sailing.slider.resume_handle",
            defaultValue: "Resume charging below",
            bundle: .module,
            comment: "VoiceOver name of the lower handle of the two-handle charge limit slider in Settings, read before its value, such as \"Resume charging below, 70%\"."
        )
    }
}
