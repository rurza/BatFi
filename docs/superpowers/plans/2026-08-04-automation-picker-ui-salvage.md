# Automation Picker UI Salvage — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Re-apply, on top of develop's CLMonitor geofencing work, the picker UI and localization fixes that develop does not have.

**Background.** Branch `claude/automation-feature-bugs-8bd090` reworked the automation location feature. In parallel, develop reimplemented the same feature with a different and better architecture (CLMonitor geofencing, 16 commits). Develop supersedes that branch's plumbing, so the plumbing is abandoned. What develop still lacks is the UI half that addressed the original user complaints, plus all localization. Reference implementations live on the abandoned branch and can be read with `git show claude/automation-feature-bugs-8bd090:<path>` — adapt them, do not paste blindly, because the client API differs.

**What develop already has (do NOT re-implement):** permission banner with Allow Access / Open Settings, cancel-while-locating, demand-driven snapshot updates, radius clamping to the CLMonitor floor, fence-based rule evaluation.

## Develop's API (what the ported UI must target)

- `LocationClient.snapshotUpdates() -> AsyncStream<LocationSnapshot>` — same name as the old branch.
- `LocationSnapshot`: `authorization`, `servicesEnabled`, `lastFix: Coordinate?`, `lastFixDate: Date?`, and `hasFix(fresherThan: TimeInterval, now: Date = Date()) -> Bool`. **Note the difference from the old branch:** it returns `Bool`, not the coordinate. Read `lastFix` separately after checking.
- `PermissionBannerState(_ snapshot:)` — develop's name for what the old branch called `LocationPermissionState`.
- The picker holds `@State private var snapshot: LocationSnapshot?` (**optional** on develop) and `@State private var isLocating`, plus `canUseCurrentLocation`, `set(_:)`, `recenter(on:)`, `apply(_:)`, `normalizeRadius()`, `monitoredRadiusMeters`.

## Global Constraints

- Swift 6 language mode, strict concurrency. `MKLocalSearchCompleterDelegate` is not main-actor; on a `@MainActor` class its methods must be `nonisolated` and bridge with `MainActor.assumeIsolated`.
- Every user-visible string goes in `BatFiKit/Sources/L10n/AutomationStrings.swift` as `String(localized:defaultValue:bundle: Bundle.module)` with an `automation.` key prefix.
- Do NOT touch: `LocationClient.swift`, `LocationClient+Live.swift`, `AutomationManager.swift`, `LocationSnapshot.swift`, `FenceReconciliation.swift`, or anything CLMonitor-related. Develop owns those.
- Do NOT alter develop's banner, its radius slider/clamping, or `canUseCurrentLocation`.
- Existing tests must keep passing.
- Commit messages plain: no `Co-Authored-By`, no mention of Claude, no "Generated with".

## Verification Commands

Tests, from `BatFiKit/`:

```bash
xcodebuild test -scheme BatFiKit-Package -destination 'platform=macOS' -only-testing:AppSharedTests
```

App build, from the repository root:

```bash
xcodebuild build -scheme BatFi -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO
```

`swift build` / `swift test` do NOT work in this repo — the `L10n` target's `.xcstrings` isn't picked up as a SwiftPM resource so `Bundle.module` doesn't exist, and the vendored `AboutKit` has the same problem where it can't be patched. Use `xcodebuild` only.

---

### Task 0: Restore the package test loop

`BatFiKit/Package.resolved` has drifted from the pins the app actually builds against (several deps track branches), so `xcodebuild test` fails to build before running anything. Also, `BatFiKit/Sources/ClientsLive/AnalyticsDSN.swift` is gitignored and CI-generated, so a fresh checkout can't build `ClientsLive`.

- [ ] **Step 1: Adopt the app project's pins** (from the repository root)

```bash
cp BatFi.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved BatFiKit/Package.resolved
```

This intentionally moves Sentry 8.42.1 → 8.29.0; 8.29.0 is what ships.

- [ ] **Step 2: Create the gitignored DSN stub**

```bash
printf 'import Foundation\n\n// Locally generated stub (CI generates this from $SENTRY_DSN). Gitignored.\nlet analyticsDSN = ""\n' > BatFiKit/Sources/ClientsLive/AnalyticsDSN.swift
```

- [ ] **Step 3: Verify the baseline suite passes** — run the test command above. Expect a passing run; record the exact count as the baseline.

- [ ] **Step 4: Commit** — only `BatFiKit/Package.resolved` is tracked; confirm with `git status --short` that `AnalyticsDSN.swift` does not appear.

```bash
git add BatFiKit/Package.resolved
git commit -m "Align BatFiKit package pins with the app project so package tests build"
```

---

### Task 1: Address search with visible bounds and real choices

Develop still has the two reported defects: the field is `.textFieldStyle(.plain)` with the magnifier glyph outside it, so its bounds are invisible; and `search()` takes `mapItems.first` with no result list, no region bias and no feedback, which is why searching "wars" dropped a pin in a Warsaw suburb with no sign a choice had been made for the user.

**Files:** Create `BatFiKit/Sources/Settings/Automation/LocationSearchModel.swift`; modify `AutomationLocationPicker.swift` and `AutomationStrings.swift`.

**Reference:** `git show claude/automation-feature-bugs-8bd090:BatFiKit/Sources/Settings/Automation/LocationSearchModel.swift`. That file is self-contained (MapKit only, no LocationClient), so it ports essentially as-is. It already contains fixes from two review rounds — keep all of them:
- `didSet` clears `completer.queryFragment` on an empty query, so a late callback can't repopulate the list after selection.
- Delegate callbacks guard on the current query being non-empty before writing.
- `hasSearched` flips only when the completer actually responds, so "No places found." doesn't flash on every keystroke.
- Results capped at 5; `resolve(_:)` turns a chosen completion into a coordinate.

- [ ] **Step 1: Port `LocationSearchModel.swift`** from the reference, unchanged except where develop's conventions differ.

- [ ] **Step 2: Add the string** to `AutomationStrings.swift` if not already present:

```swift
        public static let locationNoResults = String(localized: "automation.editor.location_no_results", defaultValue: "No places found.", bundle: Bundle.module)
```

- [ ] **Step 3: Replace the search row** in the picker. Delete `@State private var searchText` and the `private func search() async`. Add `@State private var search = LocationSearchModel()`. Give the field `.textFieldStyle(.roundedBorder)` and remove the leading `Image(systemName: "magnifyingglass")` — the bordered field with its placeholder carries the affordance, and a glyph outside the border was part of why the bounds were unreadable. Keep develop's `isLocating` progress view, its Cancel button, and its `useCurrentLocation()` button with `canUseCurrentLocation` gating exactly as they are.

Add a suggestion list beneath the field (max 5 rows, title plus subtitle, click to select, Return selects the first) and an inline "No places found." shown only when `search.hasSearched` is true and there are no completions. Reference the old branch's picker for the exact list markup.

- [ ] **Step 4: Bias the completer region.** Add `.onMapCameraChange { context in search.updateRegion(context.region) }` to the map. Additionally seed the region once from `snapshot?.lastFix` when the rule has no coordinate yet, so the very first search on a new rule is biased — this is exactly the "wars" case. The old branch does this with a `didSeedSearchRegion` flag inside its `.task` loop; adapt it, remembering develop's `snapshot` is optional.

- [ ] **Step 5: Selecting a suggestion** resolves it, places the pin via develop's `set(_:)`, recenters, fills `label` only when empty, and clears the search.

- [ ] **Step 6: Build** using the app build command. Expect `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git commit -m "Give location search visible bounds and real result choices"
```

---

### Task 2: Place name, sheet sizing, and the save-disabled reason

Three remaining reported defects: the place-name field is unlabelled so its purpose is unclear; the rule sheet is fixed-height so its bottom content clips; and Save greys out with no explanation.

**Files:** `AutomationLocationPicker.swift`, `RuleEditorView.swift`, `AutomationFormatting.swift`, `AutomationStrings.swift`.

- [ ] **Step 1: Add the strings**

```swift
        public static let locationLabelField = String(localized: "automation.editor.location_label_field", defaultValue: "Place name", bundle: Bundle.module)
        public static let locationLabelCaption = String(localized: "automation.editor.location_label_caption", defaultValue: "Shown in the menu and rule list.", bundle: Bundle.module)
        public static let locationNeedsCoordinate = String(localized: "automation.editor.location_needs_coordinate", defaultValue: "Pick a place to finish this rule.", bundle: Bundle.module)
        public static let unnamedPlace = String(localized: "automation.summary.unnamed_place", defaultValue: "Unnamed place", bundle: Bundle.module)
```

Also change the existing `locationLabelPlaceholder` `defaultValue` from `"Place name"` to `"e.g. Home"` — it is a placeholder showing an example, and the label above now carries the name. Keep its key `automation.editor.location_label` unchanged. **Its existing 14 translations, including `en`, are now stale and must be redone in Task 3** — a catalogue entry beats the inline `defaultValue` at runtime, so without that the app keeps rendering the old text.

- [ ] **Step 2: Label the place-name field** in the picker, matching the Name and Charge-limit rows in `RuleEditorView` (leading `Text` with `.frame(width: 90, alignment: .leading)`), with the caption below at `.padding(.leading, 90)`. Reference the old branch's picker.

- [ ] **Step 3: Fix the summary fallback.** `AutomationFormatting.locationSummary` uses `L10n.Automation.locationLabelPlaceholder` as the fallback for an unnamed fence. Once Step 1 lands, that would render `@ e.g. Home` in the rule list. Switch it to `L10n.Automation.unnamedPlace`. This state is reachable — `canSave` requires a coordinate but not a label.

- [ ] **Step 4: Reverse-geocode prefill on map tap** so the field is rarely empty. Port `prefillLabelIfEmpty` from the old branch. Keep both of its properties: failure is swallowed with `try?` (an unnamed pin is fine; a blocking error for a nicety is not), and `label.isEmpty` is re-checked *after* the `await` so a name the user typed during the geocode wins.

The old branch also carries a `pinRequestGeneration` counter so a newer pin request supersedes an older one — without it, tapping A then quickly tapping B can let A's slower geocode name a point the pin has left. Port that too, and make sure every async writer of `label` participates.

- [ ] **Step 5: Sheet sizing.** In `RuleEditorView.swift`, replace `.frame(width: 460, height: 600)`. Note `.frame(width:minHeight:...)` does **not** compile — SwiftUI has no overload mixing `width:` with `minHeight:`/`maxHeight:`. Use:

```swift
        .frame(minWidth: 480, idealWidth: 480, maxWidth: 480, minHeight: 520, idealHeight: 640, maxHeight: 720)
```

Also add `.scrollIndicators(.visible)` to the editor's `ScrollView`. A macOS sheet sizes to *ideal*, not max, so the window will be 640 pt and content can still overflow — the indicator is what tells the user there is more, and it was half the fix for the reported "error hidden below the fold" complaint.

- [ ] **Step 6: Explain the disabled Save.** In `RuleEditorView`'s `footer`, show `L10n.Automation.locationNeedsCoordinate` when `!canSave`, before the `Spacer()`. Do not change `canSave` itself.

- [ ] **Step 7: Build**, then **Step 8: Commit**

```bash
git commit -m "Label the place name field, size the rule sheet to its content, explain disabled Save"
```

---

### Task 3: Localize into all 14 languages

**Files:** `BatFiKit/Sources/L10n/Localizable.xcstrings` only.

The catalogue localizes into exactly: cs, de, en, fr, it, ja, ko, nl, pl, pt-BR, ru, tr, uk, zh-Hans. Existing `automation.*` entries are hand-localized and are the tone reference.

- [ ] **Step 1: Find what's missing**

```bash
python3 - <<'PY'
import json, re, pathlib
cat = json.load(open('BatFiKit/Sources/L10n/Localizable.xcstrings'))
src = pathlib.Path('BatFiKit/Sources/L10n/AutomationStrings.swift').read_text()
used = set(re.findall(r'String\(localized: "([^"]+)"', src))
missing = sorted(k for k in used if k not in cat['strings'])
print("keys missing from the catalogue:", len(missing))
for k in missing: print(" ", k)
PY
```

- [ ] **Step 2: Translate.** New keys from S1/S2, plus a full re-translation of `automation.editor.location_label` in **all 14 locales including `en`** (its meaning changed from the label "Place name" to the placeholder "e.g. Home"). Reference translations exist on the abandoned branch: `git show claude/automation-feature-bugs-8bd090:BatFiKit/Sources/L10n/Localizable.xcstrings` already contains vetted 14-locale entries for `location_label`, `location_label_field`, `location_label_caption`, `location_needs_coordinate`, `location_no_results`, and `unnamed_place`. Reuse them rather than re-translating from scratch, but verify each still fits develop's wording.

"Location Services", "System Settings", and "Privacy & Security" are Apple product names — use Apple's official rendering per locale, not a literal translation.

- [ ] **Step 3: Verify coverage**

```bash
python3 - <<'PY'
import json
cat = json.load(open('BatFiKit/Sources/L10n/Localizable.xcstrings'))
langs = {'cs','de','en','fr','it','ja','ko','nl','pl','pt-BR','ru','tr','uk','zh-Hans'}
bad = [(k, sorted(langs - set(e.get('localizations', {}))))
       for k, e in cat['strings'].items()
       if k.startswith('automation.') and langs - set(e.get('localizations', {}))]
print("automation keys missing languages:", len(bad))
for k, m in bad: print(" ", k, "->", m)
PY
```

Expect `0`. If pre-existing `en`-only keys block it, report them rather than silently backfilling unrelated strings.

- [ ] **Step 4: Build**, then **Step 5: Commit**

```bash
git commit -m "Localize the reworked automation picker strings"
```

---

## Final Verification

- [ ] Tests pass; app builds.
- [ ] `grep -rn "searchText" BatFiKit/Sources/Settings/Automation/` returns nothing. (Do NOT grep for `mapItems.first` — `LocationSearchModel.resolve(_:)` legitimately uses it to resolve a completion the user explicitly chose. The defect was blind free-text search taking `.first`, not the call itself.)
- [ ] Nothing under CLMonitor's ownership was modified: `git diff develop --name-only` must not list `LocationClient.swift`, `LocationClient+Live.swift`, `AutomationManager.swift`, `LocationSnapshot.swift`, or `FenceReconciliation.swift`.
- [ ] **Runtime verification, still entirely owed** — no automated step covers it: the four banner states; first-run permission prompt on a clean machine; "Use current location" answering rather than stalling; MapKit completions appearing and being region-biased; the sheet with the location section expanded, checking the place-name row is not clipped; rapid map-tap-then-search-select not leaving a stale place name.
- [ ] Translations for the 12 non-en/pl locales are machine-produced and want a native pass before a release build.
