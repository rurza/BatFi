# Helper shutdown lifecycle

Date: 2026-08-11

## Problem

The helper is asked to quit by an XPC message, and only by an XPC message. That makes its
lifetime depend on the app being alive, cooperative, and fast enough to send it — three
things that are all false in exactly the case that matters most, an in-place update.

Reported symptom: after a Sparkle update, the app sometimes cannot talk to its helper.

### Why the message is missed

`App/BatFiApp.swift` returns `.terminateLater` and hands off to `BatFi.willQuit()`
(`BatFiKit/Sources/App/App.swift`), which spawns two Tasks that **both** call
`NSApp.reply(toApplicationShouldTerminate: true)`:

```swift
Task { try? await Task.sleep(for: .seconds(5)); NSApp.reply(...) }   // "watchdog"
Task {
    await chargingManager.appWillQuit()      // restoreSystemDefaults ≈ 2s, +~2s SMC reopen
    await magSafeColorManager.appWillQuit()  // another round trip
    try? await helperClient.quitHelper()     // 5s of its own, and it starts last
    NSApp.reply(...)
}
```

The five-second timer is not a fallback. It is an unconditional competitor, and it starts
counting at the top of the sequence while `quitHelper()` starts only after everything ahead
of it has finished. That work routinely consumes most of the budget on its own. On a slow
quit the timer wins, the process exits, the message is never delivered, and the helper
survives.

### Why a surviving helper breaks the next launch

launchd binds a `MachServices` registration to the *running process*, not to the binary on
disk. Sparkle replaces the app bundle underneath the surviving helper; the relaunched app's
first message is routed to the old process, whose `BundleProgram`
(`App/software.micropixels.BatFi.Helper.plist`) now resolves into a bundle that has been
swapped out. That is the `.staleBinary` conflict `HelperOwnership` describes and
`HelperConnectionManager.takeOwnership()` cleans up after the fact — recovery for a
condition that should not arise.

### A second, latent defect

`ListenerDelegate` (`BatFiKit/Sources/Server/Listener.swift`) treats *connection*
invalidation as proof the app is gone and calls `restoreSystemDefaults()` when the count
reaches zero. But connections die for reasons that have nothing to do with a dead app —
notably `XPCClient`'s own 15s watchdog, which deliberately tears a connection down and lets
the next call rebuild it. Today that teardown releases the firmware charge band under a
live app that is still asking for it.

## Constraints

- **`quit()` cannot leave the XPC protocol.** `takeOwnership()` uses it to evict a *foreign*
  helper, where there is no process of ours whose death could stand in for it.
- **NSWorkspace notifications are not available to the helper.** It is a root LaunchDaemon in
  the system context, not a per-user GUI session; app launch/terminate notifications are
  published per login session. Even if bridged, they cannot distinguish "the user quit
  BatFi" from "Sparkle quit BatFi and will relaunch it in two seconds", and on a multi-user
  Mac they would have to guess whose BatFi.
- **Exiting must not be treated as failure.** The job declares `MachServices` with no
  `KeepAlive` and no `RunAtLoad`. It is a pure on-demand daemon; launchd re-spawns it on the
  next mach service lookup, from whatever bundle is on disk at that moment.
- **The firmware charge band must be released before the last process that knows about it
  exits.** It is enforced by hardware, invisible in System Settings, and outlives every
  process. This is the constraint that decides the ordering everywhere below.

## Design

Two independent layers. Layer 1 makes the guarantee; layer 2 makes the common case
deterministic and fast.

### Layer 1 — the helper outlives nobody

`ListenerDelegate` records `newConnection.processIdentifier` at accept time and arms a
`DispatchSource` of type `.processExit` on it. That fires only on genuine process death —
crash, jetsam, force-quit, `SIGKILL` from an installer — and never on a connection
teardown. It is race-free because the source is registered while the client is provably
alive.

The deliberate asymmetry, which is the whole change in one sentence: **a connection dying is
not a reason to release hardware state; a process dying is.**

| Event | Action |
|---|---|
| Connection accepted | first connection for that pid → watch the process |
| Connection invalidated | drop the connection, nothing else — even at zero |
| Client process exited | stop watching; if no client pids remain → restore, then exit |
| `quit()` received | restore, then exit |
| Startup grace expired, no client ever | exit without restoring |

Rejected alternative: checking `kill(pid, 0)` on invalidation. Three lines, but it races the
reap and needs a settle delay, which reintroduces the window this design closes.

### Components

**`HelperShutdownPolicy`** — a pure state machine in `Shared`, following the pattern
`HelperHealthPolicy` establishes: the decision is a value type with no I/O, so it can be
stated and tested without a Mac in a particular state. `AppSharedTests` already depends on
`.shared`, so no new test target is needed.

```swift
public struct HelperShutdownPolicy: Sendable {
    public enum Event {
        case clientConnected(ConnectionID, pid_t)
        case connectionInvalidated(ConnectionID)
        case clientProcessExited(pid_t)
        case quitRequested
        case startupGraceExpired
    }
    public enum Decision: Equatable {
        case watchProcess(pid_t)
        case stopWatching(pid_t)
        case restoreThenExit(Reason)
        case exitWithoutRestoring(Reason)   // startup grace only
    }
    public mutating func handle(_ event: Event) -> [Decision]
}
```

State is `[pid_t: Set<ConnectionID>]` plus a `hasEverHadAClient` flag. Keying by pid rather
than by connection count is what lets two simultaneously connected copies of BatFi behave
correctly: the helper stays up until both processes die.

**`ClientProcessWatcher`** — in `Server`. A thin wrapper over
`DispatchSource.makeProcessSource(identifier:eventMask: .exit)`, arming and disarming by
pid.

**`ListenerDelegate`** — reduced to plumbing: translate XPC events into policy events,
execute the returned decisions. The `liveConnections` counter and the restore-on-invalidate
logic are both removed.

**`XPCServiceHandler.quit()`** — must now restore explicitly. This is load-bearing and easy
to miss. `SMCService.close()` only flips a bool; it restores nothing. Today the restore on
the takeover path happens *entirely* through `ListenerDelegate`'s invalidation handler,
exactly as the comment on `HelperConnectionManager.takeOwnership()` documents. Since
invalidation no longer triggers a restore, `quit()` has to do it itself — otherwise
`takeOwnership()` silently stops releasing the firmware band, which is the precise failure
that comment exists to prevent. That comment must be updated in the same change.

**Startup grace** — if launchd spawns the helper and no client ever connects (for instance
the code-signing requirement rejects it), exit after ~60s rather than sitting as an idle
root process forever. No restore: by construction it never had a client and holds nothing.

### Layer 2 — a deterministic quit sequence in the app

`willQuit()`'s watchdog becomes a genuine fallback instead of a second racer for
`NSApp.reply(toApplicationShouldTerminate:)`: a single `TerminateReply` answers once,
whichever path reaches it first.

The three timeouts are sized as one chain, and the ordering between them is the point:

| Budget | Value | Why |
|---|---|---|
| Helper's restore before exiting | 5s | Covers several PowerUI round trips plus a ~2s SMC reopen |
| App's `quitHelper()` | 6s | Must *clear* the helper's restore ceiling, not expire on top of it |
| App's terminate fallback | 10s | Must clear the sequence it backs up, not interrupt it |

With layer 1 in place the app can afford to overshoot: a missed `quit()` is no longer a
leaked root process, so the cost of the fallback firing is an untidy quit rather than a
stranded root daemon. Layer 2 exists for ordering, not for safety. It matters because
Sparkle relaunches within a second or two, and the relaunched app must not connect while the
old helper is still mid-restore and still holding the mach service.

## Error handling

**Already-dead pid at arm time.** `DispatchSource.makeProcessSource` registers an
`EVFILT_PROC` kqueue filter; if the process is already gone, registration fails with `ESRCH`
and the source never fires, leaving the helper waiting forever for an exit that already
happened. After arming, `kill(pid, 0)`; on `ESRCH`, synthesize `.clientProcessExited(pid)`.
The window is sub-millisecond, but the failure mode is a permanently stranded root process.

**pid reuse.** The pid is recorded at accept and watched immediately. Not hardened further:
audit-token pidversion buys nothing measurable at this window size.

**A restore that never returns.** `restoreSystemDefaults()` makes several PowerUI round
trips and can spend ~2s reopening the SMC. `restoreThenExit` awaits it under a hard cap
(~5s), logs on timeout, then exits regardless. Without the cap, one wedged PowerUI call
turns "the helper always exits" back into "the helper usually exits", which is the defect
being fixed.

**In-flight calls at exit.** On the `clientProcessExited` path, impossible by construction:
the helper exits only when no client pids remain, so there is no caller to strand. Asserted
by test rather than by comment.

The `quitRequested` path is the exception — it exits on request, and a second client could
in principle have a call in flight. That is intended: `quit()` means "stop being the helper
now", and `takeOwnership()` sends it precisely to end another copy's session. It is also
already the behaviour today. `takeOwnership()` refuses to compete when another copy of the
app is running (`HelperConnectionManager`), which keeps the two-client case rare.

**Reconnect churn.** `XPCClient`'s watchdog teardown becomes a no-op for the helper: no
restore, no exit, SMC state intact.

## Out of scope

**A wedged helper.** If the helper hangs on an SMC call, PROC_EXIT will not help — the app
is alive, so staying up is correct. Recovery remains `HelperHealthPolicy`'s job (ping fails
twice → unregister/re-register). Recorded here so nobody expects this change to fix it.

**Unregistering the daemon on quit.** Would cost the user a System Settings approval on the
next launch to achieve what process exit already achieves.

## Testing

`HelperShutdownPolicyTests` in `AppSharedTests`, swift-testing, matching
`HelperHealthPolicyTests`. Pure: no hardware, no XPC, no root.

- connect emits `watchProcess` once per pid, not once per connection
- every connection for a live pid invalidates → no exit, no restore
- reconnect after invalidate → no duplicate watch
- process exit, one client → `restoreThenExit`
- process exit, two clients → nothing until the second dies
- `quitRequested` → `restoreThenExit` even with a live client (the takeover path)
- startup grace, never had a client → `exitWithoutRestoring`
- startup grace after a client connected → nothing

`swift test` is broken in this package (`Bundle.module`); these run via `xcodebuild` against
the `AppSharedTests` scheme.

### Manual verification

Cannot be unit-tested; belongs on the runtime-verification list.

1. PROC_EXIT genuinely fires for a root daemon watching a user process across the privilege
   boundary.
2. Force-quit BatFi → `ps` shows no `BatFiHelper`.
3. Sparkle update end to end → the relaunched app talks to the new helper build, and
   `HelperConnectionManager` reports no `.staleBinary` conflict.
4. `takeOwnership()` still releases the firmware band after the `quit()` change. This is the
   regression this design is most likely to introduce, and the one with the worst
   consequence — a Mac capped by a limit its owner can neither see nor remove.
