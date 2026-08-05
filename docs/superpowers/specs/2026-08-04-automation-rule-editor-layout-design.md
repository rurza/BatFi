# Automation Rule Editor Layout — Design

**Date:** 2026-08-04
**Scope:** `RuleEditorView` and `AutomationLocationPicker` presentation only. No behavior, no persistence, no new strings.

## Problem

The Edit Rule sheet is clipped, forced to scroll, and visually incoherent. Three distinct defects, all in layout code:

### 1. The focused text field's ring is clipped

`RuleEditorView.body` wraps its content in a `ScrollView` whose content carries only `.padding(.trailing, 4)`
(`RuleEditorView.swift:96–111`). SwiftUI draws a focus ring *outside* the control's frame, and a `ScrollView`
clips to its bounds. The Name field is the first row, flush against the scroll view's top edge, so its ring is
shaved on the top and both sides. This is visible whenever the field is focused.

### 2. Content does not fit, so critical controls hide below the fold

The sheet is capped at `maxHeight: 720` (`RuleEditorView.swift:116`), but the fully expanded rule — both the time
and location conditions enabled — measures roughly 748pt. The overflow lands on the bottom of the location
picker, which means the **Radius slider** and **Place name** field are below the fold. There is no scrollbar at
rest to indicate they exist, so the sheet appears to end at the map with the footer directly beneath it.

Worse, the search-completion list is a sibling in the picker's `VStack`
(`AutomationLocationPicker.swift:130–158`). It inserts up to ~170pt of inline content *while the user types*,
displacing the banner and map downward on every keystroke.

### 3. Two competing label-column systems that cannot agree

Both files hand-roll a label gutter with `Text(...).frame(width: 90, alignment: .leading)`:

- `RuleEditorView.swift:125` (Name) and `:131` (Charge limit)
- `AutomationLocationPicker.swift:204` (Place name) and `:211` (its caption's `.padding(.leading, 90)`)

They are separate `View` structs, so neither knows about the other's column, and the picker's remaining
controls — the search field, the permission banner, the map, the radius row — are not in any gutter at all. They
run full-width from the leading edge. The result on screen: "Search address…" begins a full label-column to the
left of where the Name field begins.

The fixed 90pt is also a latent localization bug. The app ships in 14 languages; `frame(width: 90)` truncates any
label longer than 90pt rather than growing.

## Design

### Shared, measured label column

The column must be shared across the `RuleEditorView` / `AutomationLocationPicker` boundary, which rules out the
two obvious native answers:

- **`Form` (`.columns` style)** enumerates its *immediate* children. The whole picker would be one opaque row and
  its internal labels would never join the parent's column. Same for `Grid`, which needs `GridRow` as a direct
  child. Dissolving the picker into its parent is not an option — it owns ~15 `@State` properties and the
  CoreLocation `.task`, so it has to stay a `View`.
- **A custom `HorizontalAlignment` guide** breaks on this sheet's *full-width* rows. In
  `VStack(alignment: .automationLabel)` every child aligns its guide to a common x. A labeled row's guide is its
  label's trailing edge; the map, search field, permission banner and both condition checkboxes have no explicit
  guide, so theirs defaults to `context[.leading]`. The stack resolves that by placing their leading edge where
  the labels' trailing edges are, **indenting every full-width row by the label column's width.** A guide only
  works when all siblings are labeled rows, and here most are not.

So the column is measured instead. A `PreferenceKey` collects each label's intrinsic width and reduces with
`max`; preferences propagate up through custom `View` boundaries by design, which is precisely the property
needed. The sheet root reads the maximum into `@State` and pushes it back down through an `EnvironmentKey`, which
each labeled row reads to size its label.

The measuring copy of each label is a hidden `.fixedSize()` duplicate in the label's `.background`. Measuring the
*visible* label would report the environment-supplied column width straight back and pin it at its starting
value.

There is no feedback loop: the measured value depends only on the label's intrinsic text width, never on the
width being distributed. The environment default is 90 — today's hard-coded value — so the first rendered frame
is already close to the settled layout and the single correction pass is not visible.

Full-width rows — the two condition checkboxes, the search field, the permission banner, the map, the
unconditional-rule warning — simply do not use the row component and are unaffected. The checkboxes continue to
read as section headers.

Because no width is declared at any call site, the column sizes itself to the longest label in whatever locale is
running, which fixes the truncation risk in point 3.

### Content-driven height with a screen-size cap

Replace `minHeight: 520, idealHeight: 640, maxHeight: 720` with a measured height.

The content reports its height through a `GeometryReader` in `.background` feeding a `PreferenceKey`.
(`onGeometryChange(for:of:action:)` is macOS 15+; this package targets macOS 14 — see `Package.swift:42` — so the
`GeometryReader` + `PreferenceKey` form is required.)

The sheet's height is then:

```
min(measuredContentHeight, (NSScreen.main?.visibleFrame.height ?? 800) - 80)
```

The 80pt margin covers the sheet's own titlebar inset and leaves the parent window edge visible. The 800pt
fallback is only reached if `NSScreen.main` is nil, in which case the cap is 720 — the height the sheet already
uses today, so that path is no worse than current behavior.

There is no layout feedback loop: the content is a `VStack` that sizes to fit and the map has a fixed
`.frame(height: 220)`, so the measured height never depends on the height being assigned.

Width goes 480 → 520 to give the map and search field room. This stays narrower than the settings pane's own
`settingsContentWidth` of 540 (`Constants.swift:10`).

Practical effect: at ~748pt fully expanded the sheet fits without scrolling on every current Mac display. The cap
engages only on a small panel such as 1280×800, where scrolling is preferable to a sheet clipped by the screen.
Toggling a condition resizes the sheet, which is the intended behavior — it is a response to a deliberate user
action.

### Padded scroll container

The `ScrollView` is retained purely as the small-display fallback above, but its content gets symmetric padding
on all four edges in place of `.padding(.trailing, 4)`. The Name field is no longer flush against a clipping
bound, so the focus ring has room to draw. `.scrollIndicators(.visible)` is dropped — with the content fitting,
a permanently visible indicator is noise.

### Floating search completions

Move the completion list from a `VStack` sibling to an `.overlay(alignment: .topLeading)` on the search row,
with `.zIndex(1)` on that row.

The `zIndex` is load-bearing: SwiftUI draws stack siblings in order, so the map — which comes *after* the search
row in the `VStack` — would otherwise paint over the overlay and take its taps. Raising the search row's
z-index puts the completion list above the map for both drawing and hit-testing.

Result: the list floats over the map like a standard search dropdown, and the sheet's height stops changing on
every keystroke.

## Explicitly unchanged

- The generation/sequence race handling in the picker (`pinRequestGeneration`, `locatingGeneration`,
  `selectSequence`, `labelWasAutofilled`) and every comment explaining it.
- The permission banner and its `PermissionBannerState` switch.
- Radius clamping, `normalizeRadius()`, `monitoredRadiusMeters`, and the CLMonitor floor.
- All `L10n.Automation` strings. No strings are added, removed, or reworded, so no re-localization is needed.
- `AutomationView`, the rules list, and the save/delete/reorder logic.
- Rule persistence and `AutomationRule` itself.

## Verification

Build (repository root):

```bash
xcodebuild build -scheme BatFi -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO
```

Tests (from `BatFiKit/`):

```bash
xcodebuild test -scheme BatFiKit-Package -destination 'platform=macOS' -only-testing:AppSharedTests
```

`swift build` / `swift test` do not work in this repo — the `L10n` target's `.xcstrings` is not picked up as a
SwiftPM resource, so `Bundle.module` does not exist.

There is no test target covering Settings views; these changes are visual and must be confirmed by running the
app. Manual checks, all in the Edit Rule sheet:

1. Focus the Name field — the focus ring draws complete on all four sides.
2. Enable both conditions — Radius slider and Place name field are visible without scrolling; no scrollbar.
3. Type in the search field — the completion list floats over the map and the sheet height does not change.
4. Click a completion, then a map point, then "Use current location" — the pin and label still follow the most
   recent action (guards against a regression in the race handling).
5. Toggle each condition off and on — the sheet resizes smoothly.
6. Confirm Name, Charge limit, Radius, and Place name labels share one right-aligned column.
7. Run in a language with long labels (German) — labels are not truncated.
8. Click a search suggestion that visually overlaps the map and confirm the pin lands on the resolved place, not
   on the click point. The code asserts `.zIndex(1)` wins hit-testing over a MapKit-hosted view; that is
   unverified, and if it falls through, `Map.onTapGesture` drops a pin at the cursor instead.
9. Confirm the dropdown is genuinely opaque over map tiles — no streets or labels showing through the suggestion
   text. `.regularMaterial` does not always sample an AppKit-hosted layer.
10. Confirm the Charge limit and Radius sliders sit correctly against their labels under baseline alignment.
11. Confirm the permission banner is not permanently occluded by the dropdown during a first-run flow — the
    floating dropdown now paints over the banner rather than pushing it down, so the banner's "Allow Access"
    button is unclickable while suggestions are showing.
