# Onboarding Order and Firmware-Aware Charge Limits — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the onboarding charge-limit screen after helper installation so its slider shows the floor this Mac can actually hold, and give the automation rule editor the same firmware-aware floor.

**Architecture:** The backend is only knowable through the helper's XPC channel, so onboarding resolves it in the install-success path before showing the limit pane. A new `lastKnownChargeBackend` default, written at a single choke point in `ChargingClient.liveValue`, gives the automation rule editor — a sheet, which cannot afford an async re-range — a synchronous answer in `init`.

**Tech Stack:** Swift 6 language mode, SwiftUI, `Defaults`, `swift-dependencies`, swift-testing (`@Test`/`#expect`).

**Spec:** `docs/superpowers/specs/2026-08-05-onboarding-order-charge-limit-design.md`

## Global Constraints

- **Never use `swift build` / `swift test`** — both fail on `Bundle.module` in `L10n` and in the third-party `AboutKit`. Everything goes through `xcodebuild` from the repo root.
- Read the explicit `BUILD SUCCEEDED` / `Test run with N tests … passed` line. Piping `xcodebuild` through `grep`/`tail` masks the exit code, so a failing build can look like it succeeded.
- Swift 6 language mode is on for every target touched here (`swiftV6LanguageMode()` in `BatFiKit/Package.swift`).
- Commit messages: plain, no Claude/Co-Authored-By/Generated-with trailers.
- No new user-facing strings. Two existing keys are deleted (Task 4); every other string is reused under its existing key so translations stay earned.
- `ChargeLimitRange` semantics are fixed and must not change: `lowest` 50, `highest` 100, `systemChargeLimitLowest` 80, and unresolved/`.unsupported` both stay permissive at 50.

---

### Task 1: Resolve the floor from a raw backend string

The three call sites added by later tasks all read the backend as the `String` the cache stores. Without this they each repeat `flatMap(ChargeBackend.init(rawValue:))` and each has to remember that an unrecognised value means "unresolved", not "unsupported" — a real case, since a downgrade after a newer build has written the cache leaves a raw value this build does not know.

**Files:**
- Modify: `BatFiKit/Sources/Shared/ChargeControlDisclosure.swift:535-551` (add a method to `ChargeLimitRange`)
- Test: `BatFiKit/Tests/AppSharedTests/ChargeControlDisclosureTests.swift:642` (insert after `anUnresolvedBackendKeepsTheFullRange`)

**Interfaces:**
- Consumes: `ChargeLimitRange.lowestSelectable(for: ChargeBackend?) -> Int`, `ChargeBackend: String` (both already exist).
- Produces: `ChargeLimitRange.lowestSelectable(forRawBackend: String?) -> Int` — used by Task 5 and available to Task 3.

- [ ] **Step 1: Write the failing tests**

Insert into `ChargeControlDisclosureTests.swift` immediately after `anUnresolvedBackendKeepsTheFullRange()` (line 642), inside the same suite:

```swift
    /// The cache stores `ChargingDiagnostics.backend` verbatim, so the readers see a
    /// `String`. Round-tripping it must land on the same floor the enum would give.
    @Test func aRawBackendStringResolvesToItsBackendsFloor() {
        for backend in ChargeBackend.allCases {
            #expect(
                ChargeLimitRange.lowestSelectable(forRawBackend: backend.rawValue)
                    == ChargeLimitRange.lowestSelectable(for: backend),
                "\(backend.rawValue)"
            )
        }
    }

    /// Nil is "this Mac has never answered" and keeps the widest range — the same answer
    /// `lowestSelectable(for: nil)` gives, since the cache's default is nil.
    @Test func anAbsentRawBackendKeepsTheFullRange() {
        #expect(ChargeLimitRange.lowestSelectable(forRawBackend: nil) == ChargeLimitRange.lowest)
    }

    /// A value this build does not recognise — written by a newer build, then downgraded —
    /// is unresolved, not unsupported. Both happen to answer 50 today, but the reason
    /// differs and only "unresolved" survives a future backend that cannot go below 80.
    @Test func anUnrecognisedRawBackendIsTreatedAsUnresolved() {
        #expect(ChargeLimitRange.lowestSelectable(forRawBackend: "someFutureBackend") == ChargeLimitRange.lowest)
        #expect(ChargeLimitRange.lowestSelectable(forRawBackend: "") == ChargeLimitRange.lowest)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -project BatFi.xcodeproj -scheme AppSharedTests -destination 'platform=macOS' -only-testing:AppSharedTests/ChargeControlDisclosureTests
```

Expected: compile error — `type 'ChargeLimitRange' has no member 'lowestSelectable(forRawBackend:)'`. A compile failure is the correct failing state here; there is no partially-working version to assert against.

- [ ] **Step 3: Write the implementation**

In `ChargeControlDisclosure.swift`, inside `public enum ChargeLimitRange`, immediately after `lowestSelectable(for:)` (after line 540):

```swift
    /// The floor, resolved from the backend as it is *stored* — the raw string the
    /// `lastKnownChargeBackend` cache holds, because `ChargingDiagnostics.backend` is a
    /// `String` and keeping it that way spares `DefaultsKeys` a dependency on this module.
    ///
    /// The decision this centralises is what an unrecognised value means. A newer build can
    /// write a backend this one has never heard of and a downgrade then reads it back; that
    /// is *unresolved*, not `.unsupported`. Both answer 50 today, so a reader open-coding
    /// `flatMap` would look correct — right up until a sixth backend that cannot go below 80
    /// makes the two diverge.
    public static func lowestSelectable(forRawBackend raw: String?) -> Int {
        lowestSelectable(for: raw.flatMap(ChargeBackend.init(rawValue:)))
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild test -project BatFi.xcodeproj -scheme AppSharedTests -destination 'platform=macOS' -only-testing:AppSharedTests/ChargeControlDisclosureTests
```

Expected: the explicit `Test run with N tests … passed` line, with the three new tests included and every pre-existing test still passing.

- [ ] **Step 5: Commit**

```bash
git add BatFiKit/Sources/Shared/ChargeControlDisclosure.swift BatFiKit/Tests/AppSharedTests/ChargeControlDisclosureTests.swift
git commit -m "Resolve the charge-limit floor from a raw backend string"
```

---

### Task 2: Cache the backend at a single write site

**Files:**
- Modify: `BatFiKit/Sources/DefaultsKeys/DefaultsKeys.swift:75` (add a key after `lastKnownForceDischargeAvailable`)
- Modify: `BatFiKit/Sources/ClientsLive/ChargingClient+Live.swift:8-11` (imports) and `:37-39` (the closure)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `Defaults.Keys.lastKnownChargeBackend: Key<String?>` — read by Tasks 3 and 5.

No test: `ClientsLive` has no test target, and the write is a side effect on a live XPC call that cannot be exercised without a helper. Verified by build.

- [ ] **Step 1: Add the defaults key**

In `DefaultsKeys.swift`, directly after line 75 (`lastKnownForceDischargeAvailable`), inside the same `public extension Defaults.Keys`:

```swift
    // The raw `ChargeBackend` this Mac last reported, or nil where it has never answered.
    //
    // Cached for the same reason as the two above — a view cannot wait on an async fetch
    // without visibly correcting itself afterwards — but with one difference that matters:
    // it is written in a single place, the `chargingDiagnostics` closure in
    // `ChargingClient.liveValue`, so every successful fetch anywhere in the app refreshes it
    // and no caller has to remember to. The two keys above are still refreshed per-view in
    // `ChargingView.refreshCapabilityCache()`; moving them here would be an improvement and
    // is deliberately not part of this change.
    //
    // Stored as the raw string rather than the enum so this module needs no dependency on
    // `Shared`. Nil means unresolved, which `ChargeLimitRange.lowestSelectable` answers with
    // the permissive 50% floor — the same answer a Mac that has never been asked deserves.
    static let lastKnownChargeBackend = Key<String?>("lastKnownChargeBackend", default: nil)
```

- [ ] **Step 2: Write the cache on every successful fetch**

In `ChargingClient+Live.swift`, add two imports to the existing block at lines 8-11, keeping alphabetical order:

```swift
import AppKit
import Clients
import Defaults
import DefaultsKeys
import Dependencies
import Shared
```

Then replace the `chargingDiagnostics` closure (lines 37-39):

```swift
            chargingDiagnostics: {
                let diagnostics = try await XPCClient.shared.getChargingDiagnostics()
                // The one write site for `lastKnownChargeBackend`. Every pane and sheet that
                // needs this Mac's floor synchronously reads that cache, and putting the
                // refresh here means none of them has to remember to fetch first. A nil
                // result is a helper that answered without a snapshot, which is not evidence
                // the backend changed — so the previous value stands rather than being
                // cleared.
                if let diagnostics {
                    Defaults[.lastKnownChargeBackend] = diagnostics.backend
                }
                return diagnostics
            }
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild build -project BatFi.xcodeproj -scheme ClientsLive -destination 'platform=macOS'
```

Expected: `BUILD SUCCEEDED`.

If Swift 6 strict concurrency rejects the `Defaults[...]` write from this non-isolated async closure, the fix is to hop rather than to loosen the closure: wrap the assignment in `await MainActor.run { Defaults[.lastKnownChargeBackend] = diagnostics.backend }`. Do not make the closure `@MainActor` — it is called from `ChargingManager` and `MagSafeColorManager` off the main actor.

- [ ] **Step 4: Commit**

```bash
git add BatFiKit/Sources/DefaultsKeys/DefaultsKeys.swift BatFiKit/Sources/ClientsLive/ChargingClient+Live.swift
git commit -m "Cache the last known charge backend on every diagnostics fetch"
```

---

### Task 3: Reorder the onboarding screens and rework the model

**Files:**
- Modify: `BatFiKit/Sources/Onboarding/Onboarding.swift` (enum at `:20-33`, view at `:48-140`, model at `:142-251`)

**Interfaces:**
- Consumes: `Defaults.Keys.lastKnownChargeBackend` (Task 2, indirectly — the model's own fetch goes through `chargingClient`, which now populates it).
- Produces: `Onboarding.Model.helperIsInstalled: Bool` and `Onboarding.Model.backend: ChargeBackend?` — both read by Task 4's `ChargingLimitView`.

No test: the `Onboarding` target has no test target and this is view/model wiring. Verified by build here and by the runtime pass in Task 6.

- [ ] **Step 1: Reorder the screen enum**

Replace lines 20-25 of `Onboarding.swift`:

```swift
enum OnboardingScreen: Int, CaseIterable {
    case welcome
    case license
    case helper
    case charging
```

The raw values are never persisted — `changeScreenToOneWithIndex` receives a transient index from `PageControl` and `OnboardingPlayerViewModel` switches on the cases — so renumbering is free. Leave `next()`/`previous()` unchanged.

- [ ] **Step 2: Add the `Shared` import**

`ChargeBackend` lives in `Shared`, which `Onboarding.swift` does not yet import. Add it to the block at lines 8-18, in alphabetical position between `ServiceManagement` and `SwiftUI`:

```swift
import ServiceManagement
import Shared
import SwiftUI
```

`Onboarding` already depends on `.shared` in `BatFiKit/Package.swift`, so no manifest change is needed.

- [ ] **Step 3: Swap the two pane rows in the `PageView`**

Replace lines 58-59 so the panes match the new order:

```swift
                InstallHelperView(model: model).id(OnboardingScreen.helper.rawValue)
                ChargingLimitView(model: model).id(OnboardingScreen.charging.rawValue)
```

- [ ] **Step 4: Rename the completion flag and add the resolved backend**

In `Onboarding.Model`, replace the `onboardingIsFinished` property (lines 151-152) with:

```swift
        /// Whether the helper went in. Until this reorder that was also the end of
        /// onboarding, which is why it used to be called `onboardingIsFinished`; the limit
        /// pane now comes after it, so the two are different moments and the old name would
        /// be read as the wrong one.
        @MainActor @Published
        private(set) var helperIsInstalled = false

        /// What this Mac's charge mechanism turned out to be, resolved once the helper can
        /// answer and before the limit pane is shown. Held here rather than fetched by
        /// `ChargingLimitView` so that pane's very first frame already carries the real
        /// floor — there is no correct value to draw before this is known, which is the
        /// whole reason the pane moved.
        @MainActor @Published
        private(set) var backend: ChargeBackend?
```

Add the client dependency beside the existing ones (after line 155, `@Dependency(\.defaults)`):

```swift
        @Dependency(\.chargingClient) private var chargingClient
```

- [ ] **Step 5: Resolve the backend before advancing to the limit pane**

In `nextAction()`, inside `observeHelperStatus`, replace the `status == .enabled` branch (lines 178-187):

```swift
                            if status == .enabled {
                                self.helperError = nil
                                // The first moment BatFi can ask, and it must be answered
                                // before the pane that renders the floor appears — a slider
                                // that draws at 50% and corrects itself to 80% is the defect
                                // this reorder exists to remove.
                                await resolveBackend()
                                didInstallHelper()
                                defaults.setValue(.onboardingIsDone, value: true)
                                // Set before the screen change so the navigation ceiling in
                                // `changeScreenToOneWithIndex` has already risen by the time
                                // the limit pane is on screen and its dot is live.
                                helperIsInstalled = true
                                if let next = currentScreen.next() {
                                    changeScreenTo(next)
                                }
                                NSSound(named: "Funk")?.play()
                                break
                            }
```

Then add the resolver as a new method on the model, directly after `previousAction()` (after line 226):

```swift
        /// Asks the freshly installed helper what this Mac's mechanism is. A failed fetch
        /// leaves `backend` nil, which `ChargeLimitRange` reads as unresolved and answers
        /// with the widest range — the same permissive direction this pane has always taken,
        /// and the only honest one when nothing has been claimed.
        @MainActor
        private func resolveBackend() async {
            if let diagnostics = try? await chargingClient.chargingDiagnostics() {
                backend = ChargeBackend(rawValue: diagnostics.backend)
            }
        }
```

- [ ] **Step 6: Give `.charging` a completion action, and `.helper` a re-entry path**

Still in `nextAction()`, replace the `.helper` guard (lines 168-172) so a user who walks back to an already-installed helper pane simply moves forward:

```swift
            case .helper:
                // Reachable again after a successful install if the user taps back through
                // the dots; there is nothing left to install, so advance.
                guard !helperIsInstalled else {
                    if let next = currentScreen.next() {
                        changeScreenTo(next)
                    }
                    return
                }
```

And add a `.charging` case before `default:` (before line 214):

```swift
            case .charging:
                // Load-bearing. `.charging` is the last screen, so its `next()` is nil and
                // the old `default:` arm would have made the Complete button do nothing at
                // all. `completeOnboarding()` used to be reached only through the `.helper`
                // guard, which no longer runs last.
                completeOnboarding()
```

- [ ] **Step 7: Stop the dots from jumping past the helper**

Replace `changeScreenToOneWithIndex` (lines 228-233) and add the ceiling beside it:

```swift
        /// The furthest screen the page dots may jump to. The limit pane is deliberately
        /// unreachable until the helper is in: that install is the only moment BatFi can
        /// learn this Mac's floor, and a limit slider shown before it is the bug this
        /// ordering fixes — reachable by tapping the last dot even though the flow no
        /// longer leads there.
        @MainActor
        private var highestReachableScreen: OnboardingScreen {
            helperIsInstalled ? .charging : .helper
        }

        @MainActor
        func changeScreenToOneWithIndex(_ index: Int) {
            guard let screen = OnboardingScreen(rawValue: index),
                  licenseModel.hasValidLicense,
                  screen.rawValue <= highestReachableScreen.rawValue
            else { return }
            changeScreenTo(screen)
        }
```

- [ ] **Step 8: Update the three view-level readers of the old flag**

In `Onboarding`'s `body`, the Previous button condition (line 62):

```swift
                if model.currentScreen == .helper && !model.helperIsInstalled {
```

The confetti binding (line 89) — the modifier itself stays on the root `VStack` and needs no other change, because the flag now flips at the same instant the limit pane appears, so the cannon fires over the final screen for free:

```swift
            counter: Binding(get: { model.helperIsInstalled ? 1 : 0 }, set: { _ in }),
```

And `nextButtonTitle` (lines 115-135), which becomes exhaustive — every screen now has an answer, so the `default:` arm goes:

```swift
    var nextButtonTitle: String {
        let l10n = L10n.Onboarding.Button.Label.self
        switch model.currentScreen {
        case .welcome:
            return l10n.getStarted
        case .license:
            if licenseModel.hasValidLicense {
                return l10n.next
            } else {
                return L10n.License.activateBatFi
            }
        case .helper:
            // Unconditional now: a successful install advances off this pane, so it never
            // has to offer to complete anything.
            return l10n.installHelper
        case .charging:
            return l10n.complete
        }
    }
```

- [ ] **Step 9: Build to verify**

```bash
xcodebuild build -project BatFi.xcodeproj -scheme Onboarding -destination 'platform=macOS'
```

Expected: `BUILD SUCCEEDED`. Two errors are expected *first* and are fixed in Task 4 — `InstallHelperView` and `ChargingLimitView` still reference `model.onboardingIsFinished` and the old fetch. If the build fails only on those two files, proceed to Task 4 and build again there; do not commit a broken build.

- [ ] **Step 10: Commit (after Task 4 builds)**

This task and Task 4 share one compilable state. Stage both together at the end of Task 4.

---

### Task 4: Rework the two panes and retire the strings they drop

**Files:**
- Modify: `BatFiKit/Sources/Onboarding/InstallHelperView.swift` (whole file)
- Modify: `BatFiKit/Sources/Onboarding/ChargingLimitView.swift` (whole file)
- Modify: `BatFiKit/Sources/L10n/Strings.swift:443-444` and `:457-458`
- Modify: `BatFiKit/Sources/L10n/Localizable.xcstrings`

**Interfaces:**
- Consumes: `Onboarding.Model.helperIsInstalled`, `Onboarding.Model.backend` (Task 3).
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Strip `InstallHelperView` to an install pane**

Replace the whole body of `BatFiKit/Sources/Onboarding/InstallHelperView.swift`. It loses the `done`/`appIsReady` cross-fade, the Launch at Login toggle, and with them the `Defaults`/`DefaultsKeys` imports:

```swift
//
//  InstallHelperView.swift
//
//
//  Created by Adam on 01/06/2023.
//

import Foundation
import L10n
import SwiftUI

struct InstallHelperView: View {
    @ObservedObject var model: Onboarding.Model

    var body: some View {
        VStack(spacing: 20) {
            let l10n = L10n.Onboarding.Label.self
            AVPlayerViewRepresented(player: model.player)
                .edgesIgnoringSafeArea(.all)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.33333, contentMode: .fill)
            VStack(alignment: .leading, spacing: 10) {
                Text(l10n.almostDone)
                    .font(.system(size: 24, weight: .bold))
                Text(l10n.helperDescription)
                    .fixedSize(horizontal: false, vertical: true)
                Text(l10n.helperRequiresAdmin)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            // Required, otherwise the text renders centred — a SwiftUI quirk the previous
            // version of this file worked around on its own last row.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.leading, .bottom, .trailing], 20)
        }
    }
}
```

- [ ] **Step 2: Make `ChargingLimitView` the finish**

Replace the whole of `BatFiKit/Sources/Onboarding/ChargingLimitView.swift`:

```swift
//
//  ChargingLimitView.swift
//
//
//  Created by Adam on 01/06/2023.
//

import AppShared
import Defaults
import DefaultsKeys
import L10n
import Shared
import SharedUI
import SwiftUI

struct ChargingLimitView: View {
    @Default(.chargeLimit) private var chargeLimit
    @Default(.launchAtLogin) private var launchAtLogin
    @ObservedObject var model: Onboarding.Model

    var body: some View {
        VStack(spacing: 0) {
            let l10n = L10n.Onboarding.Label.self
            AVPlayerViewRepresented(player: model.player)
                .edgesIgnoringSafeArea(.all)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.4, contentMode: .fill)
            VStack(alignment: .leading, spacing: 20) {
                Text(l10n.setLimit)
                    .font(.system(size: 24, weight: .bold))
                    .padding(.bottom, -10) // so the space between header and the text is -10
                Text(l10n.setLimitDescription)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                GroupBackground {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            // Resolved by the model at helper-install time, so this is the
                            // real floor from the first frame rather than a permissive guess
                            // that corrects itself. That is the entire point of this pane
                            // coming after the helper.
                            let lowestLimit = ChargeLimitRange.lowestSelectable(for: model.backend)
                            let displayedLimit = ChargeLimitRange.displayedLimit(
                                configured: chargeLimit,
                                for: model.backend
                            )
                            // No force-unwrap. A formatter that declines the conversion
                            // falls back to the plain number rather than crashing the one
                            // pane every new user sees.
                            Text(L10n.Onboarding.Slider.Label.setLimit(percentageLabel(displayedLimit)))
                            Slider(
                                value: .convert(from: $chargeLimit),
                                in: Double(lowestLimit) ... Double(ChargeLimitRange.highest),
                                step: 5
                            ) {
                                EmptyView()
                            } minimumValueLabel: {
                                Text(percentageLabel(lowestLimit))
                            } maximumValueLabel: {
                                Text(percentageLabel(ChargeLimitRange.highest))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle(L10n.Onboarding.Button.Label.launchAtLogin, isOn: $launchAtLogin)
                            Text(l10n.launchAtLoginRecommendation)
                                .foregroundStyle(.secondary)
                                // Required, otherwise it will render in center, SwiftUI bug
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                }
                Text(l10n.appIsReady)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
    }

    private func percentageLabel(_ percentage: Int) -> String {
        percentageFormatter.string(from: NSNumber(value: Double(percentage) / 100)) ?? "\(percentage)%"
    }
}
```

Note what left: `@Dependency(\.chargingClient)`, `@State private var backend`, the `.task` fetch, and the `Clients`/`Dependencies` imports. The pane no longer asks anything — the model already knows.

`setLimitSetUpLater` ("You can modify this setting later in the app's settings.") is **dropped**, and this is a deviation from the spec worth stating: the spec held it as a fallback if the pane overflowed, but it is redundant on the page regardless. `launchAtLoginRecommendation` already reads "Recommended. You can change it later in the app's settings.", and two near-identical reassurances stacked in one group box read as filler. If the pane still overflows `420×620` after this, the next thing to cut is `setLimitDescription`, not `appIsReady` — the payoff line is the reason this pane is the finish.

- [ ] **Step 3: Delete the two orphaned strings from `Strings.swift`**

Remove these declarations, which now have no readers:

- lines 443-444, `Label.done` ("Done.")
- lines 457-458, `Label.setLimitSetUpLater` ("You can modify this setting later in the app's settings.")

Leave `almostDone`, `appIsReady`, `helperDescription`, `helperRequiresAdmin`, `launchAtLoginRecommendation`, `setLimit` and `setLimitDescription` exactly as they are — all still have readers.

- [ ] **Step 4: Delete the same two keys from the string catalog**

Both keys carry 14 localizations that go with them.

```bash
python3 - <<'PY'
import json
p = 'BatFiKit/Sources/L10n/Localizable.xcstrings'
d = json.load(open(p))
for k in ('onboarding.label.done', 'onboarding.label.set_limit_set_up_later'):
    removed = d['strings'].pop(k, None)
    print(('removed ' if removed is not None else 'ABSENT  ') + k)
json.dump(d, open(p, 'w'), ensure_ascii=False, indent=2, sort_keys=True)
open(p, 'a').write('\n')
PY
```

Expected output: two `removed` lines. Then confirm the diff touches only those keys:

```bash
git diff --stat BatFiKit/Sources/L10n/Localizable.xcstrings
```

If the stat shows a very large change, the re-serialisation reformatted the file. Check `git diff` and, if the formatting churn is wholesale, revert and delete the two entries by hand instead:

```bash
git checkout -- BatFiKit/Sources/L10n/Localizable.xcstrings
```

- [ ] **Step 5: Build the two modules that changed**

```bash
xcodebuild build -project BatFi.xcodeproj -scheme Onboarding -destination 'platform=macOS'
```

Expected: `BUILD SUCCEEDED` — this is the first point at which Task 3's changes compile.

```bash
xcodebuild build -project BatFi.xcodeproj -scheme L10n -destination 'platform=macOS'
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit Tasks 3 and 4 together**

```bash
git add BatFiKit/Sources/Onboarding BatFiKit/Sources/L10n
git commit -m "Show the charging limit after the helper is installed"
```

---

### Task 5: Give the automation rule editor the same floor

**Files:**
- Modify: `BatFiKit/Sources/Settings/Automation/RuleEditorView.swift:9-12` (imports), `:22-23` (stored properties), `:46-61` (init), `:196` (slider)

**Interfaces:**
- Consumes: `Defaults.Keys.lastKnownChargeBackend` (Task 2), `ChargeLimitRange.lowestSelectable(forRawBackend:)` (Task 1).
- Produces: nothing.

No test: `Settings` has no test target. The logic that *is* testable — the floor resolution — was tested in Task 1.

- [ ] **Step 1: Add the imports**

Replace lines 9-12:

```swift
import AppKit
import AppShared
import Defaults
import DefaultsKeys
import L10n
import Shared
import SwiftUI
```

`Settings` already depends on `.defaultsKeys` and `.shared` in `BatFiKit/Package.swift`.

- [ ] **Step 2: Store the floor**

Add beside the other `let` properties, after `isEnabled` (line 23):

```swift
    /// The lowest limit this Mac's charge mechanism can actually hold.
    ///
    /// Read once from the cache in `init` rather than fetched, because this is a **sheet**:
    /// a slider that re-ranges a moment after it opens is the same class of defect as one
    /// that shows the wrong range, and it would land while the user is already dragging.
    private let lowestLimit: Int
```

- [ ] **Step 3: Resolve the floor and raise a stale limit onto it**

In `init`, replace line 61 (`_limit = State(initialValue: Double(rule.limit))`) with:

```swift
        let lowestLimit = ChargeLimitRange.lowestSelectable(forRawBackend: Defaults[.lastKnownChargeBackend])
        self.lowestLimit = lowestLimit
        // Raised onto the floor rather than displayed at it. A rule saved under the old
        // 0...100 slider can hold 30%, which on an 80%-floor Mac would pin the knob at 80
        // while the label beside it still read 30% — the two contradicting each other in the
        // one place the user is editing the number.
        //
        // `ChargingView.limitSliderBinding` makes the opposite trade for the *global* limit,
        // preserving a stored 55% in case this Mac ever regains a mechanism that honours it.
        // That value is the user's single charging setting and is worth protecting; a
        // per-rule limit is cheap to re-enter, and this editor already rewrites the whole
        // rule on save. If that judgement proves wrong, the fix is to adopt `displayedLimit`
        // here too.
        _limit = State(initialValue: Double(max(rule.limit, lowestLimit)))
```

Place these lines with the other `_`-prefixed `State` assignments, after `_name` (line 60). Assigning the local `lowestLimit` first keeps `init` and `body` reading one value.

- [ ] **Step 4: Bound the slider**

Replace line 196:

```swift
                Slider(value: $limit, in: Double(lowestLimit)...Double(ChargeLimitRange.highest), step: 5)
```

This also retires the old `0...100`, which offered the 0–45% band that no backend has ever honoured — `ChargeLimitRange.lowest` is 50.

- [ ] **Step 5: Build to verify**

```bash
xcodebuild build -project BatFi.xcodeproj -scheme Settings -destination 'platform=macOS'
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add BatFiKit/Sources/Settings/Automation/RuleEditorView.swift
git commit -m "Bound automation rule limits by what this Mac's firmware can hold"
```

---

### Task 6: Whole-app verification

**Files:** none modified.

- [ ] **Step 1: Run the full test suite**

```bash
xcodebuild test -project BatFi.xcodeproj -scheme AppSharedTests -destination 'platform=macOS'
```

Expected: the explicit `Test run with N tests … passed` line. Every pre-existing test must still pass — this change alters no `ChargeLimitRange` semantics.

- [ ] **Step 2: Build the shipping app**

```bash
xcodebuild build -project BatFi.xcodeproj -scheme BatFi -destination 'platform=macOS'
```

Expected: `BUILD SUCCEEDED`. This is the gate that catches any remaining reader of the renamed flag or the deleted strings anywhere in the app or `Previews` target.

- [ ] **Step 3: Record what still needs a human**

The following cannot be verified from here and must be checked by hand on a Mac whose backend is known. Installing the helper requires an admin authorisation prompt, which is not something an agent should drive.

1. Fresh onboarding (with `onboardingIsDone` cleared): the limit pane appears **after** the helper pane, and its slider floor matches what the Settings Charging pane shows on the same Mac.
2. The final pane fits `420×620` without clipping — video, header, description, group box with slider and Launch at Login, and the closing "The app is ready to use!" line.
3. Before installing the helper, the last page dot does not navigate.
4. Confetti fires as the limit pane appears, and the button on it reads "Complete" and closes the window.
5. On an 80%-floor Mac, an automation rule saved at 30% opens showing 80% with the knob at 80%, and the sheet shows its final range immediately with no visible re-ranging.

- [ ] **Step 4: Commit nothing**

This task changes no files. If Steps 1-2 fail, fix the cause in the owning task rather than patching here.

---

## Self-review notes

- **Spec coverage.** Screen order → Task 3 Steps 1/3. Completion-state rename and `onboardingIsDone` timing → Task 3 Steps 4-6, 8. Navigation ceiling → Task 3 Step 7. Defaults key and single write site → Task 2. Onboarding backend resolution → Task 3 Step 5. Rule editor floor and raise-on-open → Task 5. Strings → Task 4 Steps 3-4. Layout risk → Task 4 Step 2 and Task 6 Step 3 item 2. Testing honesty → Task 6 Step 3.
- **One deviation from the spec**, flagged at Task 4 Step 2: `setLimitSetUpLater` is dropped up front on copy-redundancy grounds rather than held as an overflow fallback, and its string is deleted alongside `done`.
- **Naming consistency.** `helperIsInstalled` (not `onboardingIsFinished`), `backend`, `highestReachableScreen`, `resolveBackend()`, `lowestLimit`, `lowestSelectable(forRawBackend:)` are each used under one name across every task.
