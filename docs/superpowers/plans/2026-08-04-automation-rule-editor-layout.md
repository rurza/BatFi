# Automation Rule Editor Layout — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Edit Rule sheet fit its content without scrolling, stop clipping the focused text field, and give every field label one shared, self-sizing column.

**Architecture:** Three layout changes to two existing SwiftUI views plus one new file of shared layout vocabulary. A `PreferenceKey` measures the widest field label and an `EnvironmentKey` distributes that width back down, which is what lets `RuleEditorView` and `AutomationLocationPicker` — separate view structs — share a column. The search-completion list moves from an inline stack sibling to a floating overlay so the sheet's height stops changing while the user types. The sheet's height is then driven by its measured content, capped to the screen.

**Tech Stack:** SwiftUI, macOS 14 minimum (`BatFiKit/Package.swift:42`), Swift 6 language mode, MapKit, `L10n` for strings.

**Spec:** `docs/superpowers/specs/2026-08-04-automation-rule-editor-layout-design.md`

## Global Constraints

- Swift 6 language mode, strict concurrency. The `Settings` target uses `swiftV6LanguageMode()` (`BatFiKit/Package.swift:289`).
- macOS 14 deployment target. `onGeometryChange(for:of:action:)` is macOS 15+ and **must not** be used; use `GeometryReader` + `PreferenceKey`.
- **No string changes.** No `L10n.Automation` string is added, removed, or reworded by this plan. If a task appears to need a new string, stop and ask — the app ships in 14 languages.
- **No behavior changes.** Do not touch the picker's race handling (`pinRequestGeneration`, `locatingGeneration`, `selectSequence`, `labelWasAutofilled`) or the comments explaining it, the permission banner logic, `normalizeRadius()`, `monitoredRadiusMeters`, or `canUseCurrentLocation`.
- Do NOT touch: `LocationClient.swift`, `LocationClient+Live.swift`, `AutomationManager.swift`, `LocationSnapshot.swift`, `FenceReconciliation.swift`, or anything CLMonitor-related.
- Commit messages plain: no `Co-Authored-By`, no mention of Claude, no "Generated with".

## Testing Reality — read before Task 1

**There is no automated test coverage for this work, and this plan does not pretend otherwise.**

The only test target in the package is `AppSharedTests`, which depends on `AppShared` and `Shared` (`BatFiKit/Package.swift:292-296`). The `Settings` target has no test target, and adding one would drag `SettingsKit`, `License`, and `Confetti` into a new test binary to cover what is entirely visual layout. That is not worth it.

So every task's verification is **(a) the package builds** and **(b) named manual checks in the running app**. Do not skip the manual checks and do not report a task complete on a green build alone — a build proves nothing about whether a focus ring is clipped.

`swift build` / `swift test` do NOT work in this repo — the `L10n` target's `.xcstrings` isn't picked up as a SwiftPM resource, so `Bundle.module` doesn't exist. Use `xcodebuild` only.

**Build command** (from the repository root), used by every task:

```bash
xcodebuild build -scheme BatFi -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO
```

**Regression command** (from `BatFiKit/`), run once in Task 3:

```bash
xcodebuild test -scheme BatFiKit-Package -destination 'platform=macOS' -only-testing:AppSharedTests
```

**To reach the sheet in the running app:** open BatFi → Settings → Automation tab → click an existing rule row, or "Add Rule".

## File Structure

- **Create** `BatFiKit/Sources/Settings/Automation/AutomationLayout.swift` — shared layout vocabulary for the sheet: the label-width preference key, its environment key, and the `AutomationLabeledRow` component. One responsibility, consumed by both views below.
- **Modify** `BatFiKit/Sources/Settings/Automation/RuleEditorView.swift` — adopt the row component, wire preference→environment, restructure the sheet's frame and padding.
- **Modify** `BatFiKit/Sources/Settings/Automation/AutomationLocationPicker.swift` — adopt the row component, float the completion list.

---

### Task 1: Shared label column

Replaces the two independent hard-coded 90pt label gutters with one measured column that spans both view structs.

**Files:**
- Create: `BatFiKit/Sources/Settings/Automation/AutomationLayout.swift`
- Modify: `BatFiKit/Sources/Settings/Automation/RuleEditorView.swift:121-138` (`nameAndLimit`), `:91-117` (`body`)
- Modify: `BatFiKit/Sources/Settings/Automation/AutomationLocationPicker.swift:192-212` (radius row, place-name row, caption)

**Interfaces:**
- Produces: `AutomationLabelWidthKey: PreferenceKey` (`Value == CGFloat`, reduces with `max`); `EnvironmentValues.automationLabelWidth: CGFloat` (default `90`); `AutomationLabeledRow(_ label: String, @ViewBuilder content: () -> Content)`. Tasks 2 and 3 rely on `automationLabelWidth` existing in the environment and on `AutomationLabeledRow` being the only way a label is rendered.

- [ ] **Step 1: Create the shared layout file**

Create `BatFiKit/Sources/Settings/Automation/AutomationLayout.swift`:

```swift
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
```

- [ ] **Step 2: Adopt the row in `RuleEditorView.nameAndLimit`**

In `BatFiKit/Sources/Settings/Automation/RuleEditorView.swift`, replace the whole `nameAndLimit` property (currently lines 121-138) with:

```swift
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
```

- [ ] **Step 3: Publish the measured width from the sheet root**

In the same file, add this stored property alongside the other `@State` declarations (after `@State private var locationLabel: String` on line 35):

```swift
    /// Widest field label in the sheet, measured across both this view and the location picker.
    /// Seeded to the environment default so the first frame is already close to the settled layout.
    @State private var labelColumnWidth: CGFloat = 90
```

Then, in `body`, attach the preference reader and the environment publisher to the outermost `VStack` — immediately after the existing `.padding(20)` on line 115:

```swift
        .onPreferenceChange(AutomationLabelWidthKey.self) { width in
            labelColumnWidth = width
        }
        .environment(\.automationLabelWidth, labelColumnWidth)
```

Order matters: `.environment` must be applied *after* `.onPreferenceChange` in source order so the value flows down to the rows.

There is no feedback loop here — `measuringCopy` is `.fixedSize()`, so what it reports depends only on the label's text, never on the width being distributed.

- [ ] **Step 4: Build, and fix the Swift 6 sendability error if it appears**

Run the build command. Under some SDKs `onPreferenceChange`'s closure is `@Sendable`, and the plain assignment in Step 3 fails with an actor-isolation error. **Only if that error appears**, change the closure to:

```swift
        .onPreferenceChange(AutomationLabelWidthKey.self) { width in
            // `onPreferenceChange`'s closure is `@Sendable` under strict concurrency, but SwiftUI
            // always delivers it on the main actor. Same bridge the picker uses for its
            // non-isolated `MKLocalSearchCompleterDelegate` callbacks.
            MainActor.assumeIsolated { labelColumnWidth = width }
        }
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Adopt the row in the location picker**

In `BatFiKit/Sources/Settings/Automation/AutomationLocationPicker.swift`, add this property next to the other `@Environment`/`@Dependency` declarations (after line 23, `@Dependency(\.locationClient) private var locationClient`):

```swift
    /// Published by `RuleEditorView`. Used to indent the place-name caption so it lines up under
    /// the field rather than under the label.
    @Environment(\.automationLabelWidth) private var labelColumnWidth
```

Then replace the radius row and the place-name block (currently lines 192-212) with:

```swift
            AutomationLabeledRow(L10n.Automation.locationRadius) {
                Slider(value: $radiusMeters, in: Self.radiusRange, step: 50)
                Text("\(Int(monitoredRadiusMeters)) m")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 2) {
                AutomationLabeledRow(L10n.Automation.locationLabelField) {
                    TextField(L10n.Automation.locationLabelPlaceholder, text: labelBinding)
                        .textFieldStyle(.roundedBorder)
                }
                Text(L10n.Automation.locationLabelCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, labelColumnWidth + 8)
            }
```

The `+ 8` matches `AutomationLabeledRow`'s `HStack` spacing, so the caption starts exactly under its field.

- [ ] **Step 6: Confirm no hard-coded gutter survives**

Run:

```bash
grep -rn "width: 90\|leading, 90" BatFiKit/Sources/Settings/Automation/
```

Expected: no output. If anything is listed, convert it to `AutomationLabeledRow` or `labelColumnWidth` before continuing.

- [ ] **Step 7: Build and check visually**

Run the build command. Expected: BUILD SUCCEEDED.

Then run the app, open the sheet, and enable "Only at a location". Confirm:
1. **Name**, **Charge limit**, **Radius**, and **Place name** labels sit in one right-aligned column, and all four controls start at the same x.
2. The "Shown in the menu and rule list." caption starts under the Place name *field*, not under its label.
3. The map, search field, and both condition checkboxes still run full-width from the sheet's left margin — they must NOT be indented to the label column.

Check 3 is the one that catches a regression to the alignment-guide approach; do not skip it.

- [ ] **Step 8: Commit**

```bash
git add BatFiKit/Sources/Settings/Automation/AutomationLayout.swift BatFiKit/Sources/Settings/Automation/RuleEditorView.swift BatFiKit/Sources/Settings/Automation/AutomationLocationPicker.swift
git commit -m "Give the rule editor one measured label column across both views"
```

---

### Task 2: Float the search completions

Moves the completion list out of the layout flow so the sheet stops resizing on every keystroke. This must land before Task 3, which measures the sheet's content height — leaving the list inline would make that measurement chase the user's typing.

**Files:**
- Modify: `BatFiKit/Sources/Settings/Automation/AutomationLocationPicker.swift:94-159` (the search block in `body`)

**Interfaces:**
- Consumes: nothing from Task 1 beyond the file compiling.
- Produces: a `body` whose height no longer varies with `search.completions`. Task 3 depends on this.

- [ ] **Step 1: Replace the inline search block with a row plus overlay**

In `AutomationLocationPicker.body`, replace the outer `VStack(alignment: .leading, spacing: 4) { ... }` that currently wraps the search `HStack` and the completion list (lines 95-159) with just the `HStack`, carrying the overlay:

```swift
            HStack {
                TextField(L10n.Automation.locationSearchPlaceholder, text: $search.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        // A field that is only whitespace (or empty) has nothing to search
                        // for — leave Return a no-op rather than showing "No places found."
                        // for text the user never really typed.
                        guard !search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        if let first = search.completions.first {
                            Task { await select(first) }
                        }
                        // Else: the completer hasn't answered this query yet, or answered
                        // with nothing. Either way `search.hasSearched` drives the "No places
                        // found." message below reactively, so it surfaces on its own as soon
                        // as the completer responds — nothing further to do here.
                    }
                if isLocating {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                    Text(L10n.Automation.locating)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isLocating {
                    Button(L10n.Automation.cancel) { isLocating = false }
                        .controlSize(.small)
                } else {
                    Button(L10n.Automation.useCurrentLocation) { useCurrentLocation() }
                        .controlSize(.small)
                        .disabled(!canUseCurrentLocation)
                }
            }
            .overlay(alignment: .bottomLeading) { completions }
            // SwiftUI paints stack siblings in order, so the map — which comes after this row —
            // would otherwise draw over the dropdown and swallow its clicks. Raising this row
            // puts the dropdown above the map for both drawing and hit-testing.
            .zIndex(1)
```

- [ ] **Step 2: Add the floating completions view**

Add this property to `AutomationLocationPicker`, immediately before the existing `banner` property (which begins at line 253 with its `/// Rendered above the map on purpose:` doc comment):

```swift
    /// The completion list, floating over the map rather than sitting in the layout.
    ///
    /// It used to be a stack sibling, which meant up to ~170pt of content appearing and
    /// disappearing *while the user typed* — displacing the banner and map on every keystroke, and
    /// resizing the whole sheet along with them.
    @ViewBuilder private var completions: some View {
        if !search.completions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(search.completions, id: \.self) { completion in
                    Button {
                        Task { await select(completion) }
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(completion.title)
                            if !completion.subtitle.isEmpty {
                                Text(completion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .floatingUnderSearchField()
        } else if search.hasSearched {
            Text(L10n.Automation.locationNoResults)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .floatingUnderSearchField()
        }
    }
```

- [ ] **Step 3: Add the positioning modifier**

Add this to the bottom of `AutomationLayout.swift`, after `AutomationLabeledRow`:

```swift
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
```

- [ ] **Step 4: Build**

Run the build command. Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Check visually**

Run the app, open the sheet, enable "Only at a location", and type a partial address into the search field. Confirm:
1. The suggestion list floats **over** the map — the map does not move down, and the sheet does not change height as suggestions appear and disappear.
2. The list is opaque: no map streets or labels visible through the suggestion text.
3. Clicking a suggestion selects it. (If clicks land on the map instead and drop a pin, `.zIndex(1)` is missing from Step 1.)
4. Type something with no matches — "No places found." appears in the same floating position, not inline.
5. Click "Use current location" while a fix is pending so "Locating…" and the spinner appear, then type — the dropdown still sits just below the row, not overlapping it.

- [ ] **Step 6: Verify the race handling still holds**

This is the check that matters most in this task — the selection path has been fixed twice already (`af65afb`, `abf28cc`) and moving its call site is exactly how that regresses.

In the sheet: type a search, click a suggestion, then immediately click a different point on the map, then click "Use current location". The pin and the place name must end up reflecting **the most recent action**, not whichever request happened to resolve first. Repeat once with two suggestions clicked in quick succession — the second one must win.

- [ ] **Step 7: Commit**

```bash
git add BatFiKit/Sources/Settings/Automation/AutomationLocationPicker.swift BatFiKit/Sources/Settings/Automation/AutomationLayout.swift
git commit -m "Float automation location suggestions over the map"
```

---

### Task 3: Content-driven sheet height and focus-ring room

Removes the fixed `maxHeight: 720` that pushed the Radius slider and Place name field below the fold, and gives the focused text field room to draw its ring.

**Files:**
- Modify: `BatFiKit/Sources/Settings/Automation/RuleEditorView.swift:91-117` (`body`)
- Modify: `BatFiKit/Sources/Settings/Automation/AutomationLayout.swift` (add the content-height preference key)

**Interfaces:**
- Consumes: `AutomationLabelWidthKey`, `automationLabelWidth`, `AutomationLabeledRow` from Task 1; the height-stable picker from Task 2.
- Produces: final state. Nothing depends on this.

- [ ] **Step 1: Add the content-height preference key**

Append to `AutomationLayout.swift`, after `AutomationLabelWidthKey`:

```swift
/// Reports the rule editor's scrollable content height so the sheet can size itself to fit.
/// A `ScrollView` does not propagate its content's ideal height, so without this the sheet has no
/// way to know how tall it wants to be.
struct AutomationContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
```

- [ ] **Step 2: Add the sizing state and constants to `RuleEditorView`**

Add alongside the `@State` properties, next to `labelColumnWidth` from Task 1:

```swift
    /// Measured height of the scrollable content. Seeded near the common expanded height so the
    /// sheet does not visibly settle when it opens.
    @State private var contentHeight: CGFloat = 600
```

And add these type properties in the `// MARK: - Sections` area, just above `nameAndLimit`:

```swift
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
```

`NSScreen` needs AppKit. Add `import AppKit` to the file's imports (after `import AppShared` on line 9).

- [ ] **Step 3: Rewrite `body`**

Replace `RuleEditorView.body` (lines 91-117) with:

```swift
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
```

Note `.scrollIndicators(.visible)` is gone — with the content fitting, a permanently visible indicator is noise.

**If Task 1 Step 4 needed the `MainActor.assumeIsolated` bridge**, note that this rewrite drops it from the label closure — re-apply it to *both* `onPreferenceChange` closures above, not just the new one.

There is no layout feedback loop: the content is a `VStack` whose height is intrinsic at a fixed width, so what the `GeometryReader` measures never depends on the height being assigned to the `ScrollView`.

- [ ] **Step 4: Build**

Run the build command. Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Run the regression tests**

From `BatFiKit/`:

```bash
xcodebuild test -scheme BatFiKit-Package -destination 'platform=macOS' -only-testing:AppSharedTests
```

Expected: all tests pass. These do not cover the layout — they confirm nothing in `AppShared` was disturbed.

- [ ] **Step 6: Check visually — the two original complaints**

Run the app and open the sheet. Confirm, in order:

1. **Click into the Name field.** The focus ring draws complete on all four sides — no flattened top edge, no shaved left or right. This is the reported bug; look closely at the top corners.
2. **Enable both "Only at certain times" and "Only at a location".** The Radius slider and Place name field are visible without scrolling, and no scrollbar appears.
3. **Toggle each condition off and on.** The sheet grows and shrinks to fit; it never scrolls and never leaves a band of empty space.
4. **Open the sheet for a rule with no conditions.** It is compact — no large empty area below the charge limit.
5. **Focus the Place name field** with the location condition on. Its ring is complete too.

- [ ] **Step 7: Check the small-display fallback**

In System Settings → Displays, switch the built-in display to its most "Larger Text" scaled resolution (the smallest logical size available), then reopen the sheet with both conditions enabled. Confirm the sheet fits on screen and scrolls internally rather than being clipped by the screen edge. Restore the display setting afterward.

If no scaled resolution is small enough to trigger it, note that in the task report rather than claiming the path was verified.

- [ ] **Step 8: Commit**

```bash
git add BatFiKit/Sources/Settings/Automation/RuleEditorView.swift BatFiKit/Sources/Settings/Automation/AutomationLayout.swift
git commit -m "Size the rule editor sheet to its content and stop clipping focus rings"
```

---

## Final Verification

After all three tasks, with the app running and the sheet open:

- [ ] Focused Name field draws a complete focus ring (original complaint 1).
- [ ] Fully expanded rule shows every control without scrolling (original complaint 2).
- [ ] Name, Charge limit, Radius, Place name share one right-aligned column; map, search field and checkboxes are full-width and un-indented (original complaint 3).
- [ ] Search suggestions float over the map; sheet height is stable while typing.
- [ ] Pin and place name still follow the most recent of {suggestion click, map tap, use current location}.
- [ ] `xcodebuild build -scheme BatFi …` succeeds.
- [ ] `xcodebuild test … -only-testing:AppSharedTests` passes.
- [ ] Switch the Mac to German (System Settings → General → Language & Region) and reopen the sheet: no label is truncated, and the column has widened to fit. Restore the language afterward.
