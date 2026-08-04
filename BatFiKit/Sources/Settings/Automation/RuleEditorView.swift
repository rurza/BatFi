//
//  RuleEditorView.swift
//  BatFi
//
//  Modal editor for a single automation rule: name, charge limit, an optional time
//  condition (one-off or repeating) AND an optional location condition.
//

import AppShared
import AppKit
import L10n
import SwiftUI

struct RuleEditorView: View {
    enum ScheduleKind: Hashable { case oneOff, repeating }

    let isNew: Bool
    let onSave: (AutomationRule) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    private let ruleID: UUID
    private let isEnabled: Bool

    @State private var name: String
    @State private var limit: Double
    @State private var hasSchedule: Bool
    @State private var scheduleKind: ScheduleKind
    @State private var oneOffDate: Date
    @State private var selectedDays: Set<Weekday>
    @State private var fromDate: Date
    @State private var toDate: Date
    @State private var hasLocation: Bool
    @State private var coordinate: Coordinate?
    @State private var radius: Double
    @State private var locationLabel: String

    /// Widest field label in the sheet, measured across both this view and the location picker.
    /// Seeded to the environment default so the first frame is already close to the settled layout.
    @State private var labelColumnWidth: CGFloat = 90

    /// Measured height of the scrollable content. Seeded near the common expanded height so the
    /// sheet does not visibly settle when it opens.
    @State private var contentHeight: CGFloat = 600

    init(
        rule: AutomationRule,
        isNew: Bool,
        onSave: @escaping (AutomationRule) -> Void,
        onDelete: (() -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        self.ruleID = rule.id
        self.isEnabled = rule.isEnabled

        _name = State(initialValue: rule.name)
        _limit = State(initialValue: Double(rule.limit))

        switch rule.schedule {
        case let .recurring(days, time):
            _hasSchedule = State(initialValue: true)
            _scheduleKind = State(initialValue: .repeating)
            _selectedDays = State(initialValue: days)
            _oneOffDate = State(initialValue: Date())
            _fromDate = State(initialValue: Self.date(from: time.start))
            _toDate = State(initialValue: Self.date(from: time.end))
        case let .oneOff(day, time):
            _hasSchedule = State(initialValue: true)
            _scheduleKind = State(initialValue: .oneOff)
            _selectedDays = State(initialValue: [.monday, .tuesday, .wednesday, .thursday, .friday])
            _oneOffDate = State(initialValue: day)
            _fromDate = State(initialValue: Self.date(from: time.start))
            _toDate = State(initialValue: Self.date(from: time.end))
        case nil:
            _hasSchedule = State(initialValue: false)
            _scheduleKind = State(initialValue: .repeating)
            _selectedDays = State(initialValue: [.monday, .tuesday, .wednesday, .thursday, .friday])
            _oneOffDate = State(initialValue: Date())
            _fromDate = State(initialValue: Self.date(from: TimeOfDay(hour: 9, minute: 0)))
            _toDate = State(initialValue: Self.date(from: TimeOfDay(hour: 18, minute: 0)))
        }

        if let fence = rule.location {
            _hasLocation = State(initialValue: true)
            _coordinate = State(initialValue: fence.center)
            _radius = State(initialValue: fence.radiusMeters)
            _locationLabel = State(initialValue: fence.label)
        } else {
            _hasLocation = State(initialValue: false)
            _coordinate = State(initialValue: nil)
            _radius = State(initialValue: 150)
            _locationLabel = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? L10n.Automation.editorAddTitle : L10n.Automation.editorEditTitle)
                .font(.headline)
                .padding(.horizontal, Self.focusRingInset)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    nameAndLimit
                    Divider()
                    scheduleSection
                    Divider()
                    locationSection
                    if !hasSchedule && !hasLocation {
                        Label(L10n.Automation.unconditionalWarning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(Self.focusRingInset)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: AutomationContentHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            // Sized to the content instead of scrolling it: the old `maxHeight: 720` left the
            // Radius slider and Place name field below the fold with no scrollbar to hint they
            // were there.
            .frame(height: min(contentHeight, maxContentHeight))

            footer
                .padding(.horizontal, Self.focusRingInset)
        }
        .padding(Self.sheetPadding)
        .onPreferenceChange(AutomationContentHeightKey.self) { height in
            contentHeight = height
        }
        .onPreferenceChange(AutomationLabelWidthKey.self) { width in
            labelColumnWidth = width
        }
        .environment(\.automationLabelWidth, labelColumnWidth)
        .frame(width: Self.sheetWidth)
    }

    // MARK: - Sections

    private static let sheetWidth: CGFloat = 520
    /// Room for the focus ring, which SwiftUI draws *outside* a control's frame. Without it the
    /// `ScrollView` clips the ring on the Name field, which is flush against its top edge.
    private static let focusRingInset: CGFloat = 6
    /// Outer padding. Title and footer add `focusRingInset` back so every element lines up at 20pt
    /// from the sheet edge, while the scrolling content keeps its ring room.
    private static let sheetPadding: CGFloat = 14
    /// Title, footer, their spacings and the outer padding. Deliberately generous — it is only used
    /// to size the scroll cap on displays too small to fit the sheet, where a few unused points
    /// cost nothing.
    private static let chromeAllowance: CGFloat = 140

    /// Tallest the scrolling content may be before it starts scrolling. At ~748pt fully expanded
    /// the sheet fits without scrolling on every current Mac display; this only engages on a small
    /// panel such as 1280×800, where scrolling beats a sheet clipped by the screen.
    ///
    /// The 800pt fallback is reached only if `NSScreen.main` is nil, which lands the cap at 720 —
    /// exactly the height the sheet used before this change, so that path is no worse than before.
    private var maxContentHeight: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 800
        return max(240, visible - 80 - Self.chromeAllowance)
    }

    private var nameAndLimit: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationLabeledRow(L10n.Automation.nameField) {
                TextField(L10n.Automation.namePlaceholder, text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            AutomationLabeledRow(L10n.Automation.chargeLimit) {
                Slider(value: $limit, in: 0...100, step: 5)
                Text("\(Int(limit))%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(L10n.Automation.timeCondition, isOn: $hasSchedule)
                .toggleStyle(.checkbox)
            if hasSchedule {
                Picker("", selection: $scheduleKind) {
                    Text(L10n.Automation.scheduleOneOff).tag(ScheduleKind.oneOff)
                    Text(L10n.Automation.scheduleRepeating).tag(ScheduleKind.repeating)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if scheduleKind == .oneOff {
                    DatePicker(L10n.Automation.scheduleDate, selection: $oneOffDate, displayedComponents: .date)
                } else {
                    weekdayChips
                }

                HStack {
                    Text(L10n.Automation.fromTime)
                    DatePicker("", selection: $fromDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text(L10n.Automation.toTime)
                    DatePicker("", selection: $toDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
        }
    }

    private var weekdayChips: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.localizedOrder()) { day in
                let isOn = selectedDays.contains(day)
                Button {
                    if isOn { selectedDays.remove(day) } else { selectedDays.insert(day) }
                } label: {
                    Text(AutomationFormatting.singleLetter(day))
                        .frame(width: 28, height: 28)
                        .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(L10n.Automation.locationCondition, isOn: $hasLocation)
                .toggleStyle(.checkbox)
            if hasLocation {
                AutomationLocationPicker(coordinate: $coordinate, radiusMeters: $radius, label: $locationLabel)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let onDelete, !isNew {
                Button(L10n.Automation.delete, role: .destructive, action: onDelete)
            }
            if !canSave {
                Text(L10n.Automation.locationNeedsCoordinate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.Automation.cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(L10n.Automation.save, action: save)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
    }

    // MARK: - Save

    private var canSave: Bool {
        // A location condition without a chosen coordinate is incomplete.
        !(hasLocation && coordinate == nil)
    }

    private func save() {
        let schedule: Schedule?
        if hasSchedule {
            let range = TimeRange(start: Self.timeOfDay(from: fromDate), end: Self.timeOfDay(from: toDate))
            switch scheduleKind {
            case .oneOff:
                schedule = .oneOff(day: oneOffDate, time: range)
            case .repeating:
                schedule = .recurring(days: selectedDays, time: range)
            }
        } else {
            schedule = nil
        }

        let location: GeoFence?
        if hasLocation, let coordinate {
            location = GeoFence(center: coordinate, radiusMeters: radius, label: locationLabel)
        } else {
            location = nil
        }

        let rule = AutomationRule(
            id: ruleID,
            name: name,
            isEnabled: isEnabled,
            limit: Int(limit),
            schedule: schedule,
            location: location
        )
        onSave(rule)
    }

    // MARK: - Time conversion

    private static func timeOfDay(from date: Date) -> TimeOfDay {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
    }

    private static func date(from tod: TimeOfDay) -> Date {
        Calendar.current.date(bySettingHour: tod.hour, minute: tod.minute, second: 0, of: Date()) ?? Date()
    }
}
