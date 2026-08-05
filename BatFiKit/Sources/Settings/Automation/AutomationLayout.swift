//
//  AutomationLayout.swift
//  BatFi
//
//  Shared layout vocabulary for the rule editor sheet. `RuleEditorView` and
//  `AutomationLocationPicker` are separate view structs, so the one thing they cannot do is agree
//  on a label column by themselves — hence the preference/environment pair below.
//

import SwiftUI

/// Collects the intrinsic width of every field label in the rule editor sheet, reducing to the
/// widest. Preferences propagate up through custom `View` boundaries, which is exactly why this is
/// a preference and not an alignment guide: the sheet's label rows are split across two view
/// structs.
struct AutomationLabelWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Reports the rule editor's scrollable content height so the sheet can size itself to fit.
/// A `ScrollView` does not propagate its content's ideal height, so without this the sheet has no
/// way to know how tall it wants to be.
struct AutomationContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct AutomationLabelWidthEnvironmentKey: EnvironmentKey {
    /// The width the sheet hard-coded before the column was measured. Starting here rather than at
    /// zero means the first rendered frame is already close to the settled layout, so the single
    /// correction pass is not visible when the sheet opens.
    static let defaultValue: CGFloat = 90
}

extension EnvironmentValues {
    /// Width of the sheet's shared label column, measured by `AutomationLabelWidthKey` and
    /// published by `RuleEditorView`.
    var automationLabelWidth: CGFloat {
        get { self[AutomationLabelWidthEnvironmentKey.self] }
        set { self[AutomationLabelWidthEnvironmentKey.self] = newValue }
    }
}

/// One `label: control` row, with the label sized to the sheet's shared column.
///
/// Deliberately width-free at the call site. The `frame(width: 90)` this replaces truncated labels
/// in the longer of the app's 14 languages; the column now sizes itself to the longest label in the
/// running locale.
///
/// An alignment guide would be the more idiomatic way to share a column, but not on this sheet: its
/// full-width rows (the map, the search field, the permission banner, the condition checkboxes) sit
/// in the same stack, and a guide would indent every one of them by the label column's width. A
/// measured width leaves them untouched — they simply do not use this view.
struct AutomationLabeledRow<Content: View>: View {
    @Environment(\.automationLabelWidth) private var columnWidth

    private let label: String
    private let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .frame(width: columnWidth, alignment: .trailing)
                .background(alignment: .leading) { measuringCopy }
            content
        }
    }

    /// Reports this label's *intrinsic* width. A hidden `.fixedSize()` duplicate, because measuring
    /// the visible label would report the environment-supplied column width straight back and pin
    /// it at its starting value. `.hidden()` keeps the copy in the layout while drawing nothing.
    private var measuringCopy: some View {
        Text(label)
            .fixedSize()
            .hidden()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: AutomationLabelWidthKey.self, value: proxy.size.width)
                }
            )
    }
}

extension View {
    /// Positions a `.bottomLeading` overlay just below its parent row and gives it an opaque
    /// surface to sit on.
    ///
    /// The alignment guide, rather than a fixed `.offset(y:)`: setting the content's bottom guide
    /// to 4pt above its own top places its top 4pt below the parent's bottom edge, whatever height
    /// that row turns out to be. The search row's height changes when "Locating…" and its
    /// progress spinner appear, so a hard-coded offset would drift.
    ///
    /// `.regularMaterial` because this floats over a map — the old `Color.secondary.opacity(0.10)`
    /// let streets and labels show straight through the text.
    func floatingUnderSearchField() -> some View {
        self
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            .shadow(radius: 8, y: 4)
            .alignmentGuide(.bottom) { $0[.top] - 4 }
    }
}
