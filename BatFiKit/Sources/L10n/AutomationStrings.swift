//
//  AutomationStrings.swift
//  BatFi
//
//  Localized strings for the calendar/automation feature. Kept in a focused extension
//  rather than the generated Strings.swift. English values are inline defaults.
//

import Foundation

public extension L10n {
    enum Automation {
        // Pane
        public static let paneTitle = String(localized: "automation.pane.title", defaultValue: "Automation", bundle: Bundle.module)
        public static let paneAccessibilityTitle = String(localized: "automation.pane.accessibility_title", defaultValue: "Automation pane", bundle: Bundle.module)

        public static let enableToggle = String(localized: "automation.enable_toggle", defaultValue: "Enable Charging Automation", bundle: Bundle.module)
        public static let enableDescription = String(localized: "automation.enable_description", defaultValue: "Rules run automatically. The top-most rule whose conditions match right now wins.", bundle: Bundle.module)

        public static let addRule = String(localized: "automation.add_rule", defaultValue: "Add Rule", bundle: Bundle.module)
        public static let noRules = String(localized: "automation.no_rules", defaultValue: "No rules yet. Add one to automate your charge limit by time and place.", bundle: Bundle.module)
        public static let activeBadge = String(localized: "automation.active_badge", defaultValue: "ACTIVE", bundle: Bundle.module)
        public static let untitledRule = String(localized: "automation.untitled_rule", defaultValue: "Untitled rule", bundle: Bundle.module)

        // Editor
        public static let editorAddTitle = String(localized: "automation.editor.add_title", defaultValue: "New Rule", bundle: Bundle.module)
        public static let editorEditTitle = String(localized: "automation.editor.edit_title", defaultValue: "Edit Rule", bundle: Bundle.module)
        public static let nameField = String(localized: "automation.editor.name", defaultValue: "Name", bundle: Bundle.module)
        public static let namePlaceholder = String(localized: "automation.editor.name_placeholder", defaultValue: "e.g. Office hours", bundle: Bundle.module)
        public static let chargeLimit = String(localized: "automation.editor.charge_limit", defaultValue: "Charge limit", bundle: Bundle.module)

        // No "Only" on either condition label: both checkboxes can be ticked at once, and "Only
        // at a location" alongside "Only at certain times" reads as though the two were mutually
        // exclusive. They are ANDed — see `helpConditions`.
        public static let timeCondition = String(localized: "automation.editor.time_condition", defaultValue: "At certain times", bundle: Bundle.module)
        public static let scheduleOneOff = String(localized: "automation.editor.schedule_one_off", defaultValue: "One-off date", bundle: Bundle.module)
        public static let scheduleRepeating = String(localized: "automation.editor.schedule_repeating", defaultValue: "Repeating", bundle: Bundle.module)
        public static let scheduleDate = String(localized: "automation.editor.schedule_date", defaultValue: "Date", bundle: Bundle.module)
        public static let scheduleDays = String(localized: "automation.editor.schedule_days", defaultValue: "Days", bundle: Bundle.module)
        public static let fromTime = String(localized: "automation.editor.from_time", defaultValue: "From", bundle: Bundle.module)
        public static let toTime = String(localized: "automation.editor.to_time", defaultValue: "To", bundle: Bundle.module)

        public static let locationCondition = String(localized: "automation.editor.location_condition", defaultValue: "At a location", bundle: Bundle.module)
        public static let locationSearchPlaceholder = String(localized: "automation.editor.location_search", defaultValue: "Search address…", bundle: Bundle.module)
        public static let locationNoResults = String(localized: "automation.editor.location_no_results", defaultValue: "No places found.", bundle: Bundle.module)
        public static let locationRadius = String(localized: "automation.editor.location_radius", defaultValue: "Radius", bundle: Bundle.module)
        public static let useCurrentLocation = String(localized: "automation.editor.use_current_location", defaultValue: "Use current location", bundle: Bundle.module)
        public static let locationNeedsCoordinate = String(localized: "automation.editor.location_needs_coordinate", defaultValue: "Pick a place to finish this rule.", bundle: Bundle.module)
        public static let locationPermissionDenied = String(localized: "automation.editor.location_denied", defaultValue: "Location access is denied. Enable it in System Settings › Privacy & Security › Location Services.", bundle: Bundle.module)
        public static let locationServicesOff = String(localized: "automation.editor.location_services_off", defaultValue: "Location Services is turned off for this Mac.", bundle: Bundle.module)
        public static let locationNotDetermined = String(localized: "automation.editor.location_not_determined", defaultValue: "BatFi needs location access to match rules to where your Mac is.", bundle: Bundle.module)
        public static let locationRestricted = String(localized: "automation.editor.location_restricted", defaultValue: "Location access is managed by your organization.", bundle: Bundle.module)
        public static let locationAllowAccess = String(localized: "automation.editor.location_allow_access", defaultValue: "Allow Access", bundle: Bundle.module)
        public static let locationOpenSettings = String(localized: "automation.editor.location_open_settings", defaultValue: "Open System Settings", bundle: Bundle.module)
        public static let locating = String(localized: "automation.editor.locating", defaultValue: "Locating…", bundle: Bundle.module)

        public static let unconditionalWarning = String(localized: "automation.editor.unconditional_warning", defaultValue: "This rule has no conditions — it will always be active while enabled.", bundle: Bundle.module)

        public static let cancel = String(localized: "automation.editor.cancel", defaultValue: "Cancel", bundle: Bundle.module)
        public static let save = String(localized: "automation.editor.save", defaultValue: "Save", bundle: Bundle.module)
        public static let delete = String(localized: "automation.editor.delete", defaultValue: "Delete Rule", bundle: Bundle.module)


        // Summaries / menu
        public static let anyTime = String(localized: "automation.summary.any_time", defaultValue: "Any time", bundle: Bundle.module)
        public static let anywhere = String(localized: "automation.summary.anywhere", defaultValue: "Anywhere", bundle: Bundle.module)
        /// "Within 300 m" — the location condition, stated as what it constrains.
        ///
        /// Replaces "@ Place name". A fence no longer carries a name of its own, because the
        /// rule beside it already has one; the radius is the part a rule's name cannot imply.
        public static func withinRadius(_ p1: Any) -> String {
            String(
                format: String(
                    localized: "automation.summary.within_radius",
                    defaultValue: "Within %@",
                    bundle: .module
                ),
                locale: Locale.current,
                String(describing: p1)
            )
        }
        public static let daysEveryDay = String(localized: "automation.summary.every_day", defaultValue: "Every day", bundle: Bundle.module)
        public static let daysWeekdays = String(localized: "automation.summary.weekdays", defaultValue: "Weekdays", bundle: Bundle.module)
        public static let daysWeekends = String(localized: "automation.summary.weekends", defaultValue: "Weekends", bundle: Bundle.module)

        /// "60%" charge-limit fragment.
        public static func limitFragment(_ limit: Int) -> String {
            String(localized: "automation.summary.limit", defaultValue: "\(limit)%", bundle: Bundle.module)
        }

        // Menu label
        ///
        /// Rule first, limit second. The other way round — "85%: “Dom”" — leads with the
        /// number, which is the rule's property rather than its identity, and reads as
        /// though the percentage were the thing being named. It also sat directly under a
        /// heading that already says "Automation", so the row's job is to say *which* rule
        /// is running; the limit is what it happens to be doing.
        ///
        /// The interpolation order is load-bearing: `String(localized:defaultValue:)` hands
        /// the arguments over in the order they appear here, and the catalog's format
        /// consumes them positionally. Name must stay ahead of limit in both, or `%@` is
        /// handed the integer.
        public static func menuActive(limit: Int, name: String) -> String {
            String(localized: "automation.menu.active", defaultValue: "“\(name)”: \(limit)%", bundle: Bundle.module)
        }
        public static let menuIdle = String(localized: "automation.menu.idle", defaultValue: "Idle", bundle: Bundle.module)
        public static func menuNext(name: String, when: String) -> String {
            String(localized: "automation.menu.next", defaultValue: "next: “\(name)” \(when)", bundle: Bundle.module)
        }

        // Help popover
        public static let helpButtonAccessibility = String(localized: "automation.help.button_accessibility", defaultValue: "About automation", bundle: Bundle.module)
        public static let helpHeading = String(localized: "automation.help.heading", defaultValue: "How automation works", bundle: Bundle.module)
        public static let helpRules = String(localized: "automation.help.rules", defaultValue: "Each rule sets a charge limit that applies while its conditions are met.", bundle: Bundle.module)
        public static let helpConditions = String(localized: "automation.help.conditions", defaultValue: "Conditions are optional. Restrict a rule to a schedule (a one-off date or repeating days and times) and/or a location. When you set both, both must match.", bundle: Bundle.module)
        public static let helpPriority = String(localized: "automation.help.priority", defaultValue: "Rules are checked from top to bottom — the first rule whose conditions match right now wins. Drag to reorder them.", bundle: Bundle.module)
        public static let helpMenu = String(localized: "automation.help.menu", defaultValue: "While a rule is active, the menu bar shows which rule and limit are in effect.", bundle: Bundle.module)
        public static let helpLocation = String(localized: "automation.help.location", defaultValue: "Location rules need Location Services permission and Wi-Fi, which your Mac uses to determine where it is.", bundle: Bundle.module)

        // Charging-state attribution (notifications). Full sentences — no runtime concatenation.
        /// "The limit is 85% (set by automation “Work”)."
        public static func chargingByAutomation(_ limit: String, name: String) -> String {
            String(localized: "automation.charging_state.charging", defaultValue: "The limit is \(limit) (set by automation “\(name)”).", bundle: Bundle.module)
        }
        /// "The charging limit is set to 85% (set by automation “Work”)."
        public static func inhibitByAutomation(_ limit: String, name: String) -> String {
            String(localized: "automation.charging_state.inhibit", defaultValue: "The charging limit is set to \(limit) (set by automation “\(name)”).", bundle: Bundle.module)
        }
        /// "Using the battery (set by automation “Work”)."
        public static func forceDischargeByAutomation(name: String) -> String {
            String(localized: "automation.charging_state.force_discharge", defaultValue: "Using the battery (set by automation “\(name)”).", bundle: Bundle.module)
        }

        // Charging settings pane override banner.
        /// "Automation “Work” is overriding the charge limit to 85% right now."
        public static func overrideBannerActive(limit: Int, name: String) -> String {
            String(localized: "automation.charging_override.active", defaultValue: "Automation “\(name)” is overriding the charge limit to \(limit)% right now.", bundle: Bundle.module)
        }
    }
}
