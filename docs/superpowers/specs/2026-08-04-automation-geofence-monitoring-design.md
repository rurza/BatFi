# Automation Geofencing — Demand-Driven Location via CLMonitor

Branch: `claude/adoring-swanson-799244`

Supersedes §1 (location layer), §2 (picker permission UX) and §6 (testing) of
`2026-08-03-automation-location-design.md`, which exists only on branch
`claude/automation-feature-bugs-8bd090` (commit `bd325b3`) and was never implemented. That
document is spec-only; no code from it landed. This spec is self-contained and does not
depend on it. Its §3 (search), §4 (sheet layout) and §5 (module placement) are untouched and
remain valid as written.

## Evidence

BatFi holds `startUpdatingLocation` open for the entire app lifetime whenever automation is
enabled and any enabled rule carries a geofence. Unified log from a stationary Mac shows a
fix arriving roughly every five minutes, all day:

```
09:37:38  LocationClient  Received location 54.466917,18.484595
```

The path is `AutomationManager.reconcileLocationMonitoring` (`AutomationManager.swift:86`)
opening `coordinateUpdates()` and never closing it, which `LocationCoordinator.reconcileUpdating`
(`LocationClient+Live.swift:180`) turns into a `startUpdatingLocation()` that only stops when
the last consumer drops — which never happens.

This is a battery and privacy cost in an app whose stated purpose is saving battery.

The predecessor spec named this and deferred it:

> Out of scope: BatFi holds `startUpdatingLocation` open continuously whenever any enabled rule
> has a geofence — a real battery and privacy cost in a battery utility. Explicitly deferred by
> the user. The snapshot model below does not foreclose it; it makes demand-driven or
> significant-change monitoring easier to add later.

This spec is that follow-up, and it changes the predecessor's conclusion: once geofence
evaluation moves to `CLMonitor`, `AutomationManager` needs no coordinates at all, so the
snapshot stream narrows to the picker instead of becoming the app-wide location channel.

## Alternatives considered

| Option | Verdict |
|---|---|
| `startMonitoringSignificantLocationChanges()` | Rejected. ~500 m threshold is coarser than most geofence radii (slider tops out at 2000 m, defaults far below), so arrival and departure lag badly. |
| Poll `manager.location` on the existing 60 s tick | Rejected as a strategy, retained as an optimization. The SDK defines it as *"The last location received. Will be nil until a location has been received."* With no updates running it is only as fresh as whatever the system last cached — on a Mac with no other location client it can be nil or arbitrarily stale, degrading rule evaluation silently. Still used to seed the picker (§4). |
| Region monitoring via `CLCircularRegion` | Superseded by the API itself. `CLCircularRegion` and `startMonitoringForRegion:` carry `API_DEPRECATED_WITH_REPLACEMENT("Use CLCircularGeographicCondition", macos(10.10, API_TO_BE_DEPRECATED))`. |
| **`CLMonitor` + `CLCircularGeographicCondition`** | **Chosen.** `API_AVAILABLE(macos(14.0))`; `BatFiKit/Package.swift:42` declares `.macOS(.v14)`, so no availability guards. |

The decisive property is that `CLMonitor` inverts the data flow. locationd evaluates the
fences and reports satisfied/unsatisfied per named condition. BatFi stops receiving
coordinates for rule evaluation entirely — a privacy improvement on top of the power one.

**Outcome: with no settings window open, BatFi holds zero location subscriptions and
`startUpdatingLocation` does not run.** Not less often — not at all.

## 1. Model (`AppShared`)

Alongside `Coordinate` in `Automation/GeoFence.swift`. `LocationAuthorization` moves here
from `Clients` so the pure helpers below can see it (`AppShared` depends only on `L10n`;
`Clients` depends on `AppShared`).

```swift
public enum LocationAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case restricted   // split out from .denied; MDM-managed Macs get distinct copy
    case authorized
}

/// Picker/permission UX only. Rule evaluation does not consume coordinates.
public struct LocationSnapshot: Sendable, Equatable {
    public var authorization: LocationAuthorization
    public var servicesEnabled: Bool
    public var lastFix: Coordinate?
    public var lastFixDate: Date?
}

/// A geofence submitted for monitoring, identified by the rule that owns it.
public struct MonitoredFence: Sendable, Equatable {
    public var id: UUID          // == AutomationRule.id
    public var fence: GeoFence
    /// The part CoreLocation actually stores, and the only part reconciliation compares.
    public var region: MonitoredRegion {
        .init(center: fence.center, radiusMeters: fence.monitoredRadiusMeters)
    }
}

/// Centre and radius alone. `CLMonitor` persists no label, so a condition read back from it
/// cannot reconstruct a `GeoFence`; this is what both sides of the comparison reduce to.
public struct MonitoredRegion: Sendable, Equatable {
    public var center: Coordinate
    public var radiusMeters: Double
}
```

### Minimum radius

The radius slider is `50...2000, step: 50` (`AutomationLocationPicker.swift:79`) while the
manager requests `kCLLocationAccuracyHundredMeters`. A 50 m fence is already below the
accuracy being asked for, so the smallest fences cannot behave as labelled today; `CLMonitor`
makes that explicit rather than introducing it.

```swift
public extension GeoFence {
    static let minimumMonitoredRadiusMeters: Double = 100
    /// Radius actually submitted to CoreLocation. Never below the accuracy floor.
    var monitoredRadiusMeters: Double { max(radiusMeters, Self.minimumMonitoredRadiusMeters) }
}
```

The slider floor rises to 100 m. Existing saved rules below 100 m keep their stored value and
are monitored at 100 m.

**This clamp must live in `AppShared`, not at the CoreLocation boundary.** If clamping happened
while building the condition, the radius read back from `CLMonitor` (100) would never equal the
desired radius (50), and §3's reconciliation would remove and re-add that condition on every
pass — resetting it to `.unknown` each time and flickering the rule off. Both the comparison
and the condition must use `monitoredRadiusMeters`.

## 2. Client surface (`Clients`)

```swift
@DependencyClient
public struct LocationClient: Sendable {
    /// Current snapshot, then every change. Yields immediately on subscribe. CoreLocation
    /// updates run *only* while at least one consumer iterates. Picker and permission UX only.
    public var snapshotUpdates: @Sendable () -> AsyncStream<LocationSnapshot> = { AsyncStream { _ in } }

    /// Reconcile the monitored set. Passing `[]` removes every condition and stops all
    /// monitoring. Idempotent; unchanged fences are left untouched.
    public var setMonitoredFences: @Sendable ([MonitoredFence]) async -> Void

    /// Satisfied fence IDs: current set immediately, then every change. Backed by CLMonitor;
    /// starts no continuous location updates.
    public var fenceStates: @Sendable () -> AsyncStream<Set<UUID>> = { AsyncStream { _ in } }

    /// Prompt for authorization. No-op unless `.notDetermined`.
    public var requestAuthorization: @Sendable () -> Void
}
```

`authorizationStatus`, `currentCoordinate` and `coordinateUpdates` are **deleted**. Dropping
the synchronous `authorizationStatus()` getter is deliberate: it returned a cached value that
could diverge from CoreLocation's real state, and both call sites
(`AutomationLocationPicker.swift:123` and `:137`) were reading a possible lie. Nothing becomes
slower, because `snapshotUpdates()` yields on subscribe.

`setMonitoredFences` is separate from `fenceStates` on purpose. If the desired set were a
parameter of the stream, every rule edit would tear the stream down, remove and re-add every
condition, and reset each to `.unknown` — rules would visibly flicker off after any edit.
Separating them lets reconciliation touch only what actually changed.

## 3. Monitoring (`ClientsLive`)

### Verified API shape

Type-checked against the macOS 26.5 SDK at `-target arm64-apple-macos14.0`:

```swift
let monitor = await CLMonitor("BatFiAutomation")
let condition = CLMonitor.CircularGeographicCondition(center: center, radius: radius)
await monitor.add(condition, identifier: id, assuming: .unknown)   // note: `assuming:`, not `assumedState:`
let identifiers = await monitor.identifiers
let state = await monitor.record(for: id)?.lastEvent.state
await monitor.remove(id)
for try await event in await monitor.events { /* event.identifier, event.state, event.date */ }
```

Monitor name `"BatFiAutomation"`, persisting to
`~/Library/CoreLocation/<BundleID>/BatFiAutomation.monitor`. The app is not sandboxed (only
`Previews.entitlements` sets `com.apple.security.app-sandbox`), so this is the real home
directory and needs no protected-data handling. Only one `CLMonitor` per name may be open at
a time; `LocationClient.liveValue` is already a singleton, which satisfies that.

### Reconciliation

Pure, in `AppShared`, so it is testable without CoreLocation:

```swift
public enum FenceReconciliation {
    public struct Plan: Sendable, Equatable {
        public var toRemove: [UUID]
        public var toAdd: [MonitoredFence]
    }
    public static func plan(desired: [MonitoredFence], current: [UUID: MonitoredRegion]) -> Plan
}
```

- Present in `current`, absent from `desired` → remove.
- Absent from `current`, present in `desired` → add.
- Present in both with a changed `region` → remove **then** add.
- Present in both, unchanged → absent from the plan entirely. This is the case that must not
  regress, since re-adding resets state to `.unknown`.

Comparison tolerates round-tripping through the persisted file: centres equal within `1e-6`
degrees, radii within `0.5` m. Exact `Double` equality would churn.

`current` is built in `ClientsLive` from `monitor.identifiers` plus
`monitor.record(for:)?.condition as? CLMonitor.CircularGeographicCondition`, mapping each
condition's `center` and `radius` into a `MonitoredRegion`. That mapping is the only place
CoreLocation types cross into the pure layer.

### Authorization gating

`CLMonitor` requires `authorizedAlways` — the only granted state on macOS, and what
`requestAlwaysAuthorization()` already asks for. `Info.plist` supplies
`NSLocationUsageDescription`.

The coordinator retains the desired set regardless of authorization and applies it when
authorization becomes `.authorized`. While `.notDetermined` with a non-empty desired set, it
calls `requestAlwaysAuthorization()`. On `.denied` or `.restricted` it publishes an empty
satisfied set, so geofenced rules stop matching rather than holding a stale verdict.

### Cold start

`CLMonitor` persists conditions and their last event across launches. At startup, after
reconciling, seed the satisfied set from `record(for:)?.lastEvent.state` for each monitored
identifier, publish it, then iterate `monitor.events`.

A Mac that was inside a fence when BatFi quit reports `.satisfied` immediately with no new
fix. This is strictly better than the current behaviour, where `latestCoordinate` starts nil
and a geofenced rule cannot match until a fix arrives.

`.unknown` and `.unmonitored` are treated as unsatisfied. This fails closed and matches the
existing nil-coordinate semantics in `AutomationRule.matches`.

### Staleness

**The predecessor spec's 30-minute staleness rule is not implemented and is not needed.** It
existed because `AutomationManager.latestCoordinate` was retained indefinitely, so a "Home"
rule could stay matched hours after the Mac left. Under `CLMonitor` there is no coordinate to
go stale: locationd owns the state and reports transitions. The policy area is deleted rather
than ported.

### Snapshot coordinator

The snapshot half keeps the two facts documented in the current file header, both of which
survive the rewrite:

- The manager must live on a thread with an active run loop or the prompt may not appear and
  delegate callbacks never fire. `@MainActor final class` satisfies this structurally rather
  than by convention, replacing the `NSLock` / `onMain` pairing.
- `startUpdatingLocation` beats `requestLocation` on Macs relying on Wi-Fi positioning. The
  subscription model keeps `startUpdatingLocation`; it does not revert to `requestLocation`.

Init seeds `lastFix` / `lastFixDate` from `manager.location` when non-nil. `servicesEnabled`
reads `CLLocationManager.locationServicesEnabled()` on a detached task (it can block) at init
and after each authorization change, hopping back to the main actor to publish; it is `true`
optimistically for the first moments after launch, which is acceptable because it drives a
recovery hint and gates nothing.

Updates run when there is ≥1 snapshot consumer **and** authorization is `.authorized`.
Monitoring conditions are independent of snapshot consumers — they are not a consumer and do
not start updates.

## 4. `AutomationManager` (`AppCore`)

`latestCoordinate: Coordinate?` becomes `satisfiedFenceIDs: Set<UUID>`.

`reconcileLocationMonitoring` computes the desired set — enabled rules carrying a fence, when
automation is enabled — and calls `setMonitoredFences`. A single long-lived task consumes
`fenceStates()`, started when the desired set first becomes non-empty and cancelled when it
becomes empty. Passing `[]` removes every condition, which is how disabling automation stops
locationd work completely.

The existing `requestAuthorization()` call on reconcile is retained. The 60 s tick is
unchanged and re-evaluates against the latest known satisfied set.

## 5. Engine (`AppShared`)

```swift
public func matches(at date: Date, satisfiedFenceIDs: Set<UUID>, calendar: Calendar = .current) -> Bool {
    guard isEnabled else { return false }
    if let schedule, !schedule.matches(date, calendar: calendar) { return false }
    if location != nil { guard satisfiedFenceIDs.contains(id) else { return false } }
    return true
}
```

`AutomationEngine.activeRule(in:enabled:at:location:)` takes `satisfiedFenceIDs: Set<UUID>` in
place of `location: Coordinate?`. It stays pure and free of system dependencies.

**This overrides the predecessor spec's constraint that `AutomationRule.matches` and
`AutomationEngineTests` pass unchanged.** That constraint assumed the coordinate model. The
churn is contained: 12 `location:` sites in `AutomationEngineTests`, most of them
`location: nil` → `satisfiedFenceIDs: []`.

`GeoFence.contains` loses its only runtime caller (`AutomationRule.swift:49`) and keeps its
two direct assertions in `AutomationEngineTests:86-87`. It is retained — it is the natural
place to express containment, and the picker's map circle is drawn from the same values.

## 6. Picker permission UX (`Settings`)

A banner directly beneath the "Only at a location" toggle and **above the map**, so failures
are not stranded at the bottom of scrollable content.

| Snapshot | Message | Action |
|---|---|---|
| `servicesEnabled == false` | Location Services is turned off for this Mac. | Open System Settings |
| `.notDetermined` | BatFi needs location access to match rules to where your Mac is. | **Allow Access** |
| `.denied` | (existing `locationPermissionDenied` copy) | Open System Settings |
| `.restricted` | Location access is managed by your organization. | — |
| `.authorized` | (no banner) | — |

**Open System Settings** uses the established `NSWorkspace.shared.open("x-apple.systempreferences:…")`
pattern from `Onboarding.swift:104`, targeting
`com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices`.

The snapshot subscription is tied to sheet lifetime via `.task`, so CoreLocation updates run
only while the picker is on screen.

**"Use current location"** stops being a request-and-await with a timeout. A fix fresher than
5 minutes fills the field immediately; otherwise the button becomes "Locating…" with a Cancel
affordance and waits for the next snapshot carrying a fix. The 12-second timer is deleted,
along with the false *"Couldn't determine your location…"* it produced while authorization was
`authorizedAlways`.

**The picker stays fully usable without any permission.** Search and tap-to-place require
none; only "Use current location" is gated.

## 7. Module placement

- `LocationSnapshot`, `LocationAuthorization`, `MonitoredFence`, `MonitoredRegion`,
  `monitoredRadiusMeters`, `FenceReconciliation`, banner-state mapping (all pure) →
  **AppShared**, with tests.
- `LocationClient` → **Clients**.
- Coordinator rewrite and `CLMonitor` integration → **ClientsLive**.
- `AutomationManager` → **AppCore**.
- Banner, slider floor, sheet wiring → **Settings**.
- New strings → **L10n** with English `defaultValue`, then the 14-language pass matching
  commit `117fd77`.

## 8. Testing

swift-testing in `BatFiKit/Tests/AppSharedTests/`. CoreLocation cannot be tested directly, so
the decisions are extracted as pure functions:

- `FenceReconciliation.plan` — add, remove, replace-on-change, and the load-bearing case: an
  unchanged fence produces an empty plan. Includes a 50 m fence, which must compare as 100 m
  on both sides and therefore not churn.
- `GeoFence.monitoredRadiusMeters` — clamping at and around the 100 m floor.
- `AutomationRule.matches(at:satisfiedFenceIDs:)` — geofenced rule unsatisfied when its ID is
  absent, satisfied when present, and schedule/location interaction.
- Cold-start mapping from `CLMonitoringState` to the satisfied set, including `.unknown` and
  `.unmonitored` failing closed.
- `PermissionBanner.State(from: LocationSnapshot)` — the §6 table, so which message appears is
  tested rather than buried in a view body.
- `LocationClient.testValue` gains controllable snapshot and fence-state streams, making
  `AutomationManager` reconciliation testable.

`AutomationEngineTests` is updated to the new signature per §5.

Manual verification, as in the original spec: MapKit rendering, the live authorization
prompt, and — new here — confirming via unified log that a stationary Mac with an active
geofenced rule and no settings window open receives **no** periodic location fixes.
