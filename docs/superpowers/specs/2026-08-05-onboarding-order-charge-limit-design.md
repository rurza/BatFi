# Onboarding Order and Firmware-Aware Charge Limits — Design

**Date:** 2026-08-05
**Scope:** Onboarding screen order and completion state; a new cached backend default; the automation rule
editor's limit slider. No helper changes, no XPC changes, no changes to `ChargeLimitRange` itself.

## Problem

### 1. Onboarding asks the limit question before it can be answered

`OnboardingScreen` orders the panes `welcome, license, charging, helper` (`Onboarding.swift:20–33`). The limit
pane therefore renders *before* the helper is installed.

`ChargingLimitView` resolves the slider's floor from the helper (`ChargingLimitView.swift:84–91`):

```swift
if let diagnostics = try? await chargingClient.chargingDiagnostics() {
    backend = ChargeBackend(rawValue: diagnostics.backend)
}
```

On the third screen there is no helper yet, so the call fails, `backend` stays nil, and
`ChargeLimitRange.lowestSelectable(for: nil)` returns the permissive `50`
(`ChargeControlDisclosure.swift:535–540`). The pane's own comment already concedes this — it calls nil "the
normal state here."

On a `.systemChargeLimit` Mac the real floor is `80`. So a new user is walked through choosing 55% on the one
pane every new user sees, then opens Settings and finds a slider that will not go below 80%. The app
contradicts itself within a minute of first launch.

**There is no app-side fix.** `ChargingDiagnostics.backend` is produced by the helper reading the SMC
(`SMCService.chargingDiagnostics()`) and reaches the app only over XPC. The backend must be detected from
firmware rather than inferred from the macOS version, so nothing short of having the helper installed can
answer the question. Reordering is not a nicety here; it is the only honest fix.

### 2. The automation rule editor is firmware-blind

`RuleEditorView.swift:196` is:

```swift
Slider(value: $limit, in: 0...100, step: 5)
```

Two defects. It ignores the backend entirely, so it offers values below the floor on every Mac that has one.
And its lower bound is `0`, offering the 0–45% band that no backend has ever honored — `ChargeLimitRange.lowest`
is `50`.

Unlike `ChargingView`, this is a **sheet**. An async fetch to resolve the backend would render the slider at a
50% floor and snap it to 80% a moment later, which is worse than the bug being fixed.

## Design

### Screen order and completion state

`OnboardingScreen` becomes:

```swift
case welcome
case license
case helper
case charging
```

Nothing persists these raw values — `changeScreenToOneWithIndex` receives a transient index from `PageControl`,
and `OnboardingPlayerViewModel` maps cases to filenames — so renumbering is free.

**`InstallHelperView` becomes install-only.** It keeps the video, the `almostDone` header, `helperDescription`
and `helperRequiresAdmin`. It loses the `done`/`appIsReady` cross-fade `ZStack` and the Launch at Login toggle
with its recommendation line.

**`ChargingLimitView` becomes the finish.** It keeps its header, description and slider, and gains the Launch at
Login toggle, `launchAtLoginRecommendation`, and `appIsReady`.

The confetti modifier stays exactly where it is, on the root `VStack` (`Onboarding.swift:88–95`), still bound to
the renamed flag. It needs no change: the flag flips at install success, which is now the same instant the
charging pane appears, so the cannon fires over the final screen for free.

**`nextAction()` gains a `.charging` case that calls `completeOnboarding()`.** This is load-bearing and easy to
miss. Today `.charging` falls into `default:`, which advances to `currentScreen.next()`; as the last screen its
`next()` is nil, so the Complete button would silently do nothing. `completeOnboarding()` is currently reached
only through the `.helper` guard, which no longer runs last.

**`onboardingIsFinished` is renamed `helperIsInstalled`.** The property is set at helper-install success, which
until now was also the end of onboarding; after the reorder those are two different moments and the old name
would be read as the wrong one. Its three readers change accordingly:

| Reader | Before | After |
| --- | --- | --- |
| `InstallHelperView` header/body cross-fade | switched on it | removed with the cross-fade |
| `nextButtonTitle` on `.helper` | `complete` when set, else `installHelper` | always `installHelper` — a successful install advances away from this pane |
| `nextButtonTitle` on `.charging` | `next` (via `default:`) | always `complete` |
| Previous button visibility | `.helper && !finished` | `.helper && !helperIsInstalled` (unchanged in effect) |

No Previous button on `.charging`: returning to the helper pane after a successful install does nothing.

**`Defaults[.onboardingIsDone]` keeps being written at install success**, not at Complete. The helper is what
makes the app functional, and a user who closes the window on the final screen should not be prompted to redo
onboarding. This is unchanged from today's behavior.

### Backend resolution

A new key beside the two existing capability caches in `DefaultsKeys.swift:74–75`:

```swift
static let lastKnownChargeBackend = Key<String?>("lastKnownChargeBackend", default: nil)
```

Stored as the raw string, matching `ChargingDiagnostics.backend`'s own type (`ChargingDiagnostics.swift:50`), so
`DefaultsKeys` gains no dependency on `Shared`. `nil` means unresolved, which `lowestSelectable(for:)` already
answers with the permissive 50% floor — the same direction the code takes today.

**One write site:** the `chargingDiagnostics` closure in `ChargingClient+Live.swift:37–39`. Every successful
fetch anywhere in the app refreshes the cache, so no caller has to remember to. `ClientsLive` already depends on
`.defaults`, `.defaultsKeys` and `.shared`.

> The two existing `lastKnown*` caches are refreshed per-view instead, in `ChargingView.refreshCapabilityCache()`
> (`ChargingView.swift:237–241`). Moving them to the same choke point would be an improvement, but it is not
> needed for this change and is out of scope.

**Onboarding** resolves the backend inside the install-success path in `Onboarding.Model.nextAction()`, before
`changeScreenTo(.charging)`. The final screen's first frame therefore already carries the real floor.
`ChargingLimitView` drops its own `.task` fetch and its `@State private var backend`, reading the value the
model resolved.

**Navigation gains a ceiling.** `changeScreenToOneWithIndex` (`Onboarding.swift:229–233`) currently admits any
index once the license is valid, which after the reorder would let a user tap the last dot and reach the limit
pane with no helper — reintroducing the exact bug. The highest reachable screen becomes
`helperIsInstalled ? .charging : .helper`. Dots for locked screens stay visible but inert, matching how the
license gate already behaves.

### Automation rule editor

`RuleEditorView.init` reads the cache synchronously, where it already computes `_limit`
(`RuleEditorView.swift:61`):

```swift
let backend = Defaults[.lastKnownChargeBackend].flatMap(ChargeBackend.init(rawValue:))
let floor = ChargeLimitRange.lowestSelectable(for: backend)
_limit = State(initialValue: Double(max(rule.limit, floor)))
```

and the slider becomes:

```swift
Slider(value: $limit, in: Double(floor)...Double(ChargeLimitRange.highest), step: 5)
```

`floor` is computed once in `init` and stored as a `let` on the view, so `init` and `body` cannot disagree.

**Stale rules are raised on open.** A rule saved under the old `0...100` slider can hold 30%; on an 80%-floor Mac
the knob would pin at 80 while `Text("\(Int(limit))%")` still read 30%. Initializing to `max(rule.limit, floor)`
keeps knob and label in agreement, at the cost of quietly rewriting the value upward if the user then saves — a
value that was never honorable on that Mac.

This deliberately differs from `ChargingView.limitSliderBinding` (`ChargingView.swift:263–269`), which displays
at the floor but never writes back, preserving a stored 55% in case the Mac later regains a mechanism that
honors it. That asymmetry is a judgment call, made because the automation editor is a modal that already
rewrites the whole rule on save, and because per-rule limits are cheap to re-enter. **If it later proves wrong,
the fix is to adopt `displayedLimit` here too.**

New rules are unaffected: `AutomationRule.init` already defaults `limit` to `80`
(`AutomationRule.swift:26`), which is valid under both floors.

`Settings` already depends on `.defaultsKeys` and `.shared`.

## Strings

- `Label.appIsReady` moves from `InstallHelperView` to `ChargingLimitView`, keeping its translations earned.
- `Label.done` loses its only reader and is deleted from `Strings.swift:444` and the string catalog.
- No new strings. The Launch at Login toggle and its recommendation move with their existing keys.

## Layout risk

The onboarding window is a fixed `420×620` (`Onboarding.swift:112`). `ChargingLimitView` is already video +
header + description + a `GroupBackground` containing the slider; adding the toggle, its recommendation and
`appIsReady` may overflow.

If it does, the fallback is to drop `setLimitSetUpLater` ("You can modify this setting later") — Settings is one
click away and it is the least load-bearing line on the pane. Resolved during implementation by running the app,
not guessed at here.

## Testing

`ChargeLimitRange` is already covered by `AppSharedTests/ChargeControlDisclosureTests.swift:623–697`, including
the floors this change depends on. Those tests are unaffected and must keep passing.

Everything added here is view wiring in the `Onboarding` and `Settings` targets, neither of which has a test
target. **This change ships verified by build and manual run, not by tests.** Standing up a test target for the
onboarding state machine is not proposed as part of it.

Manual verification, on a Mac whose backend is known:

1. Fresh install (clear `onboardingIsDone`): the limit pane appears after the helper pane, and its slider floor
   matches what Settings shows.
2. Before installing the helper, the last page dot does not navigate.
3. On an 80%-floor Mac, a pre-existing automation rule saved at 30% opens showing 80% with the knob at 80%.
4. Opening the rule editor shows its final range immediately, with no visible re-ranging.

## Out of scope

- Moving the two existing `lastKnown*` caches to the client choke point.
- A help button or disclosures in the rule editor.
- `displayedLimit`-style preservation of sub-floor automation limits.
- Any change to how limits are applied by the helper.

## Known trade-off

Installing the helper now precedes the limit slider, so the admin-password prompt arrives before the user has
seen the limit do anything. The welcome pane carries the pitch and `helperRequiresAdmin` states that it is
essential, so this is judged acceptable — but if the helper install rate drops after this ships, this is the
first thing to look at.
