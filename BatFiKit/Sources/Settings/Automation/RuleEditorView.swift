//
//  RuleEditorView.swift
//  BatFi
//
//  Modal editor for a single automation rule: name, charge limit, an optional time
//  condition (one-off or repeating) AND an optional location condition.
//

import AppShared
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
                .padding(.trailing, 4)
            }

            footer
        }
        .padding(20)
        .frame(width: 460, height: 600)
    }

    // MARK: - Sections

    private var nameAndLimit: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.Automation.nameField)
                    .frame(width: 90, alignment: .leading)
                TextField(L10n.Automation.namePlaceholder, text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text(L10n.Automation.chargeLimit)
                    .frame(width: 90, alignment: .leading)
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
            ForEach(Weekday.displayOrder) { day in
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
