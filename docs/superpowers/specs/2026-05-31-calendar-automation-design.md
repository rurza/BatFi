# Calendar / Automation — Design

Branch: `feature/calendar-automation`

## Goal

Let the user automate the charge limit based on **when** (date/time) and **where**
(location). Surfaced as a new **Automation** settings pane. When automation is enabled,
the main menu shows an explanatory label so a user who set a rule and forgot understands
what is currently happening to their charging.

## Model (decided)

A rule applies a **custom charge limit %**, gated by an optional schedule **AND** an
optional location. Rules are an **ordered list**; the top-most rule whose conditions
match *right now* wins (drag to reorder = priority).

```
AutomationRule
  id: UUID
  name: String
  isEnabled: Bool
  limit: Int                 // 0...100
  schedule: Schedule?        // nil = matches any time
  location: GeoFence?        // nil = matches anywhere
  // index in the array = priority (0 wins)

Schedule
  .oneOff(date: Date, time: TimeRange)
  .recurring(days: Set<Weekday>, time: TimeRange)

TimeRange  = from: TimeOfDay, to: TimeOfDay   // minutes-of-day; supports overnight wrap
TimeOfDay  = hour: Int, minute: Int
Weekday    = mon...sun
GeoFence   = latitude, longitude, radiusMeters, label
```

A rule with **both** conditions nil is "always active when enabled" (UI warns about this).
Conditions combine with AND when both present.

**Active-rule resolution** (pure, unit-tested) lives in `AppShared`:
`AutomationRules.activeRule(at date:, location:, enabled:) -> AutomationRule?`
returns the first enabled rule (in list order) whose schedule matches `date` (or is nil)
and whose location contains `location` (or is nil). If automation is disabled → nil.

## Persistence

Two `Defaults` keys (model types are `Codable` → `Defaults.Serializable`):

- `automationEnabled: Bool = false`
- `automationRules: [AutomationRule] = []`

`DefaultsKeys` target gains a dependency on `AppShared` so the keys can reference the model.

## Charging integration (low-risk)

Automation produces a **base limit** that overrides the default `chargeLimit` **only when
no manual override is active** — manual menu overrides (charge to 100 %, discharge, inhibit,
stop) still win. Implementation:

- Add `automationLimit: Int?` to the shared `AppChargingState` actor (getter, setter,
  `automationLimitDidChange()` stream) — mirrors the existing `userTempOverride` channel.
- `ChargingManager`: add one `Task` loop observing `automationLimitDidChange()` →
  `updateStatusWithCurrentState()`. In `updateStatus`, the no-temp-override branch uses
  `let baseLimit = await appChargingState.currentAutomationLimit() ?? chargeLimit`
  instead of `chargeLimit`. The temp-override branch is untouched.
- When the active rule deactivates, automationLimit returns to nil → base limit falls back
  to the user's `chargeLimit`. No change to the recently-fixed temp-override logic.

## Engine

`AutomationManager` (actor, in `AppCore`):
- Re-evaluates the active rule on: a 60 s tick, location updates, and `Defaults` changes to
  `automationEnabled` / `automationRules`.
- On change, sets `appChargingState.setAutomationLimit(activeRule?.limit)` and publishes an
  `AutomationStatus` (`enabled`, `activeRule`, `nextRule` + fire date) for the menu.
- Uses a new `LocationClient` (`Clients` + `ClientsLive`, CoreLocation) for the current
  coordinate + an update stream. Location is only requested/monitored when at least one
  enabled rule defines a `GeoFence` (otherwise we never touch CoreLocation / ask permission).

## UI

### Settings pane — `AutomationView` (Settings module, Approach A: list + modal sheet)

- Master toggle **Enable Charging Automation** (gates/dims the list, like `manageCharging`).
- Reorderable `List` of rule rows: drag handle, per-rule enable toggle, name, an
  auto-generated summary line (`60% · Weekdays 9–18 · @ Office`), and an **ACTIVE** badge on
  the currently-winning rule. `[+ Add Rule]` and a status line at the bottom.
- Tapping a row / Add opens **`RuleEditorView`** as a sheet (room for the map):
  - Name, charge-limit slider.
  - ☑ *Only at certain times* → one-off date **or** repeating (weekday chips + from/to time).
  - ☑ *Only at a location* → MapKit map with address search + draggable pin, radius slider,
    and a **Use current location** shortcut (CoreLocation). Caption warns when both groups
    are unchecked.

### Main-menu label — `StatusItemManager.updateMenu()`

Informational row inserted after the battery `MenuContent`, only when `automationEnabled`:

| Rule active | No rule active now | Master off |
|---|---|---|
| `🗓 Automation · 60% — "Office hours", until 18:00` | `🗓 Automation · idle · next: "Office hours" tomorrow 09:00` | (no row) |

Clicking the row opens Settings directly to the Automation pane.

## Module placement

- Model + resolution logic + tests → **AppShared** (visible to Settings, AppCore, engine).
- Persistence keys → **DefaultsKeys** (+`AppShared` dep).
- `LocationClient` → **Clients** / **ClientsLive**.
- `AutomationManager` engine + charging integration + menu label → **AppCore**.
- Pane + editor + map picker → **Settings**.
- Strings → **L10n** (`Strings.swift`, with English `defaultValue`).

## Out of scope (v1)

Notifications when a rule fires; calendar (EventKit) import; per-rule actions other than a
limit (discharge/inhibit are still reachable manually from the menu); travel-time prediction.

## Testing

- Pure unit tests (swift-testing) for `Schedule` matching (recurring, one-off, overnight
  wrap, weekday sets) and `activeRule` priority/AND resolution.
- UI (SwiftUI + MapKit) and CoreLocation verified manually by running the app.
