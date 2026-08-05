# Helper connection reliability

Date: 2026-08-05

## Problem

The app's model of helper health is `SMAppService.status`, and that status answers a
different question than the one the app asks of it. `.enabled` means a Background Task
Management record exists. It does not mean the helper is running, reachable, or capable of
answering XPC.

Observed on 2026-08-05. `launchctl print system/software.micropixels.BatFi.Helper` showed:

```
runs = 159
last exit code = 78: EX_CONFIG
job state = spawn failed
```

launchd held a registration it could never spawn. Concurrently:

- `SMAppService.status` returned `.enabled`.
- `register()` threw `SMAppServiceErrorDomain Code=1 "Operation not permitted"` — a record
  already existed, so re-registering was refused.
- Every XPC call failed with `4099 "Connection init failed at lookup with error 3 - No such
  process."`

The user had granted the Login Items permission, and the permission was present. The app
reported nothing wrong. Recovery required toggling the helper off and on in System
Settings → Login Items, followed by a manual app relaunch.

Two defects underlie this.

**1. `.enabled` is trusted as proof of health, in two places, and re-checked in none.**

- `HelperConnectionManager.checkHelperHealth()` is the only code that pings to verify, and
  it runs exactly once, at launch (`BatFiKit/Sources/App/App.swift`).
- `Onboarding` exits its wait loop and declares success the moment status reads `.enabled`,
  without ever pinging (`BatFiKit/Sources/Onboarding/Onboarding.swift`).

**2. Nothing re-drives app state when the helper becomes reachable again.**

After the Login Items toggle restored the helper, timer-polled UI (power usage) recovered
on its own, but the menu bar status item stayed stale until relaunch. `StatusItemManager`
is edge-triggered on `appChargingState.appChargingModeDidChage()`; that mode is written
only by `ChargingManager.updateStatus(...)`, driven by a `combineLatest` of power-source
changes and defaults observations. While the helper was down `fetchChargingState` threw
into a log-only `catch`, latching the mode at `.initial`. When the helper returned, none of
that loop's inputs changed, so `updateStatus` never re-ran.

A contributing factor worth recording: `Onboarding` calls `removeHelper()` → sleep 1s →
`installHelper()` on **every 1.5s poll tick** while status is neither `.enabled` nor
`.requiresApproval`. Repeated re-registration is the behaviour most plausibly associated
with wedging the BTM record.

## Constraints

- Status transitions carry no information for this failure. Status was `.enabled` while
  wedged and remained `.enabled` after the user's manual repair. Detection must be active.
- The mutating recovery action (unregister/register) must be bounded. Hammering it is
  suspected of causing the wedge.
- The wedged BTM state is system state the app cannot fully control, and is not
  reproducible on demand.

## Design

### Layers

`HelperHealth` — new type in `AppShared`, the single authoritative answer:

```swift
public enum HelperHealth: Sendable, Equatable {
    case unknown
    case healthy
    case degraded(Reason)

    public enum Reason: Sendable, Equatable {
        case notRegistered
        case requiresApproval
        case registeredButUnreachable   // .enabled, ping fails — the wedged case
        case installFailed(String)
    }
}
```

`registeredButUnreachable` is the state that previously had no name, which is why no code
could act on it.

`HelperHealthPolicy` — new pure state machine in `AppShared`. Consumes events
(`statusObserved`, `pingSucceeded`, `pingFailed`, `retryFinished`) and returns actions
(`verifyWithPing`, `retryRegistrationOnce`, `publish(HelperHealth)`, `showGuidance`). No
I/O, no XPC, no clock of its own. Placed in `AppShared` because that module has the
existing `AppSharedTests` target, so the bounded-retry rule gets real unit tests.

`XPCClient` (`ClientsLive`) — reports facts only. It already funnels calls through
`remoteService()` and has `invalidationHandler`/`interruptionHandler`. It gains reachability
signals: success on a completed call, unreachable on `4097`/`4099`. It gets no policy.

`HelperConnectionManager` (`App`) — the executor. Subscribes to status and XPC facts, feeds
the policy, performs returned actions, publishes `HelperHealth` to consumers.

Exactly one component interprets `SMAppService.status` after this change, and `.enabled`
alone never means healthy — only a successful ping does.

### Probe versus retry

Two distinct actions that must not be conflated:

- **Probe** — read-only `pingHelper()`. Mutates nothing, repeats safely.
- **Retry** — `unregister()` → delay → `register()`. Mutates BTM state, happens at most
  once per app launch.

### Detection triggers

1. At launch, replacing today's one-shot `checkHelperHealth()`.
2. On XPC connection failure reported by `XPCClient` (`4097`/`4099`).
3. While `degraded`, on a backoff timer: probe at 5s, backing off to a 60s ceiling.

No polling while healthy; organic call failures cover that, so the steady state costs
nothing. Trigger 3 is what lets the app notice a manual Login Items repair without a
relaunch.

### Policy

```
.enabled + ping fails
   → verify once more (guards against a single transient failure)
   → still failing: retryRegistrationOnce   [mutating, at most once per launch]
   → ping again
       → success: publish .healthy
       → failure: publish .degraded(.registeredButUnreachable) + showGuidance
                  keep probing on backoff, never retry registration again
```

The mutating retry is skipped for `.requiresApproval` and `.notRegistered`; re-registering
cannot fix either. `.notRegistered` installs, as today. `.requiresApproval` goes straight to
guidance.

`Onboarding`'s success condition becomes "status `.enabled` **and** ping succeeded". Its
per-tick `removeHelper`/`installHelper` call is replaced by the shared bounded-retry
policy, so onboarding stops holding its own opinion about health.

### Consumers

`ChargingManager` subscribes to the health stream and calls the existing
`updateStatusWithCurrentState()` on a `degraded → healthy` transition. That method already
reads current power state and defaults and calls `updateStatus`; the reconnect bug was only
that nothing re-entered it.

Trigger 2's producer is `XPCClient.connectionDidInvalidate()`, which already runs from the
connection's `invalidationHandler`/`interruptionHandler` — the handlers that fire for
exactly the `4097`/`4099` errors observed. It posts a connection-failure notification.

This replaces an earlier plan to report from the swallowed `catch` in
`fetchChargingState`. That would have been redundant with the connection handlers and would
have required classifying arbitrary call errors as connection failures — untested logic on
a path where SMC errors and connection errors are easy to confuse. The `catch` keeps
logging only.

`StatusItemManager` takes health as another input to its existing `combineLatest`. While
degraded it renders a warning icon and inserts a "Helper not responding" menu item that
opens the guidance.

### Out of scope

The main loop's `combineLatest` fragility — the `logger.warning("The main loop did quit")`
path in `ChargingManager` — is a real robustness concern and is adjacent, but it is a
distinct failure mode from helper connectivity and would widen this change considerably.
Recorded, not addressed.

### Guidance

The alert reuses `showHelperIsNotInstalled()`'s shape but gets correct copy; the current
text claims the helper is not installed, which is misleading for the wedged case, where it
is installed.

- Message: the helper is registered but not responding.
- Steps: open System Settings → Login Items, turn BatFi off and back on. The existing
  deep-link button already targets that pane.
- No relaunch instruction. The probing and the `ChargingManager` fix together make the app
  detect the repair and re-drive itself; without both, this copy would be false.
- Shown once per app launch, guarded by a flag. The status item remains in warning state
  throughout, so suppressing the repeat does not hide the problem.
- Suppressed during onboarding, which has its own helper UI.

New strings go through `L10n` / `Localizable.xcstrings`.

## Testing

`HelperHealthPolicy` is covered by the existing `AppSharedTests` target, run via
`xcodebuild` with the `AppSharedTests` scheme (`swift test` is broken in this package on
`Bundle.module`). Cases:

- A single ping failure does not trigger registration retry.
- Sustained failure triggers registration retry exactly once, never twice.
- `.requiresApproval` and `.notRegistered` never trigger the mutating retry.
- `degraded → healthy` publishes the transition consumers key off.
- Backoff advances 5s → 60s ceiling and resets on recovery.

Clock is injected, matching existing `AnyClock`/`self.clock` usage in `ChargingManager`.

### Manual verification

The wedged BTM state is not reproducible on demand, so the `registeredButUnreachable` path
cannot be integration-tested against a genuinely wedged record. The closest real test:

1. With the app running, toggle BatFi off in System Settings → Login Items. The app should
   go degraded and show guidance.
2. Toggle it back on. The app should return to healthy and the status item should
   repopulate **without a relaunch**.

Step 2 is the direct regression test for the reported bug.
