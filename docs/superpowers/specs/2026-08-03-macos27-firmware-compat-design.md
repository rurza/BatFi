# BatFi — firmware-generation compatibility (macOS 27 / Golden Gate)

**Date:** 2026-08-03
**Status:** design, pending review
**Scope:** charge-control capability detection, power-source resilience, Apple Charge Limit coexistence

---

## 1. Problem

BatFi does not work on macOS 27. More importantly, BatFi breaks on *most* macOS releases, because its
charge-control model assumes SMC behaviour is a function of the macOS version. It is not: SMC behaviour is a
function of **firmware**, and firmware moves independently of the OS.

Three facts make version-gating structurally wrong:

- Installing macOS 27 on **any volume** flashes firmware for the whole Mac. Every other OS on that machine
  then sees macOS 27 SMC behaviour.
- Downgrading macOS does **not** downgrade firmware. Only a DFU restore/revive does, and only while Apple
  still signs that build.
- macOS **26.6, 15.7.8 and 14.8.8 all ship identical firmware** `18000.161.9`. Three OS majors, one firmware —
  the OS version carries no usable information about the SMC.

The corollary the user identified is real and common: a user upgrades macOS, gets new firmware, downgrades
macOS, and keeps the new firmware. BatFi must handle that machine.

### Goal

Not an unbreakable architecture — that isn't achievable against an undocumented, changing firmware interface.
The goal is **resilience**: when firmware changes, BatFi should degrade honestly and legibly rather than
silently report success, and it should never let an unrelated missing value take down the whole app.

### Non-goals

- Chasing the `bf**` mechanism on macOS 27 developer beta 4 (`20457.0.125.0.2`+). It broke again and no tool
  has a fix as of 2026-08-03. Those machines fall back to `.systemChargeLimit` (§4.6a) where possible — which
  gives 80–100% limiting — and to an honest "unsupported firmware" state otherwise.
- Replacing SMC control with Apple's public API. None exists; `IOPSLimitBatteryLevel` is entitlement-locked.

### Decision: minimum supported macOS

Raised from **14.8 to 15.0**. This drops the Sonoma-only migration shim and the orphaned
`turnOnSystemChargeLimitingWhenGoingToSleep` default. It removes almost no firmware variety, because firmware
generations do not align with OS majors.

---

## 2. Evidence

### 2.1 Firmware generations

| Generation | Firmware | Inhibit charge | Force discharge | Notes |
|---|---|---|---|---|
| Legacy | `≤ 101xx` | `CH0B` + `CH0C` (ui8/1) | `CH0I`, `CH0J` (ui8/1, `0x01`) | |
| Tahoe-era | `118xx`–`18xxx` | `CHTE` (ui32/4) | `CHIE` (hex_/1, **`0x08`**) | First shipped in **macOS 15.7**, not 26 |
| Golden Gate | `20xxx` | **`bfD0`/`bfE0`/`bfF0`** | `CHIE` survives | `CHTE` **removed**; firmware owns enforcement |

Golden Gate mechanism — write order is **mandatory**, percentages are **little-endian** ui32 (against normal
SMC convention):

```
bfF0 ← 0x00        deactivate
bfD0 ← upper %     ui32 LE, e.g. 50% = 32 00 00 00
bfE0 ← lower %     ui32 LE
bfF0 ← 0x02        activate
```

Re-enable charging with `bfF0 ← 0x00`. Status reads from `bfF0`: `0x00` charging enabled, `0x02` limited.

### 2.2 Measured on the development machine

`Mac15,8` / M3 Max / macOS 26.6 (25G72) / firmware `mBoot-18000.161.9`, via a read-only probe:

```
CHTE  ui32  size 4  attr 0xd4   present, writable
CHIE  hex_  size 1  attr 0xd4   present, writable
ACLC  ui8   size 1  attr 0xd4   present, writable
BCF0  ui32  size 4  attr 0x94   -> pre-27 firmware fingerprint
bfD0  hex_  size 2  attr 0x84   PRESENT but wrong type/size  <-- decoy
bfE0, bfF0                       absent
CH0B, CH0C, CH0I, CHWA, BCLM     kSMCKeyNotFound
CH0J, CHLS, BDFU                 kIOReturnNotPrivileged (exist, privilege-gated)
#KEY = 2802 keys
```

### 2.3 Three detection traps

1. **The `bfD0` decoy.** `bfD0` exists on Tahoe-era firmware as `hex_`/2 bytes, read-only. An existence-only
   probe selects the Golden Gate backend on a macOS 26 machine and fails. Must match **type + size**.
2. **Zero-size placeholder keys.** Some firmware exposes key metadata with `dataSize == 0`. Such a key cannot
   be read or written and must not select a control mode. This is batt's macOS 27 "key has no data" symptom.
3. **Privilege-gated keys.** `CH0J`, `CHLS`, `BDFU` return `kIOReturnNotPrivileged` from `kSMCGetKeyInfo` for
   an unprivileged caller. **Capability probing must run in the root helper**, and `keyNotFound` must be
   distinguished from `notPrivileged`.

### 2.4 Verification cannot rely on read-back

On Golden Gate firmware, `CHTE` accepts a write and reads back the written value **while the firmware ignores
it**. Read-back is therefore not proof of effect. Out-of-band ground truth:

- **`CHNC`** (hex_/8, little-endian) — "not charging reason" bitfield. Bits: `BATTERY_FULL` (0),
  `NO_CHARGER` (7), `NOCHG_CH0C` (14), `NOCHG_CH0B_CH0K` (15), `BMS_BUSY` (23), `CHLS_LIMIT` (24),
  `NOAC_CH0J` (53), `NOAC_CH0I` (54). Confirms whether *our* inhibit is the actual reason charging stopped.
  Validated against live firmware: this machine read `8000000000000000` = `BIT(7) NO_CHARGER` while unplugged.
- **`AppleSmartBattery` → `ChargerData`** — `ChargerInhibitReason`, `NotChargingReason`, `ChargingCurrent`.
  Unprivileged, no SMC needed.

### 2.5 Apple's built-in Charge Limit (macOS 26.4+)

Apple Silicon only, range **80–100%** in 5% steps (80/85/90/95/100 — confirmed by dumping
`availableChargeLimitsWithError:` on this machine). Charging resumes after a **>5%** drop. Not persistent
while the Mac is off.

Implemented via `IOPSLimitBatteryLevel` → powerd → the entitlement-locked `CHLS` key — **not** the
`CHTE`/`CH0B` inhibit keys BatFi uses. There is no evidence Apple's limiter overwrites third-party SMC writes;
the two are independent policies whose outcomes combine. This is why both AlDente and batt tell users to set
the system limit to 100%.

BatFi's existing `PowerUICharging` bridge is correct in shape and correctly typed (verified against the real
ObjC type encodings). Sub-80% limits remain BatFi's differentiator.

---

## 3. Root causes

| # | Bug | Evidence | Fix phase |
|---|---|---|---|
| **A** | Power-source stream dies on one missing value → app stuck "initializing", 0%, blank UI | [#146](https://github.com/rurza/BatFi/issues/146) | 1 |
| **B** | `CHIE` force-discharge writes `0x01`; correct value is `0x08` | [#147](https://github.com/rurza/BatFi/issues/147) | 1 |
| **C** | No `bfD0`/`bfE0`/`bfF0` support; `CHTE` gone on macOS 27 firmware | batt, Asahi, PR #469 | 4 |
| **D** | Capability detection is exception-driven, uncached, and cannot see type/size/attributes | `SMCService.swift` | 2 |
| **E** | `resetIfPossible()` does not clear `bfF0` — helper crash leaves limit armed | `SMCService.swift:100` | 4 |
| **F** | MCL gated on `#available(macOS 26.4, *)` instead of `isMCLSupported` | `SMCService.swift:56,75,94` | 2 |
| — | Menu-bar lightning bolt while paused | [#143](https://github.com/rurza/BatFi/issues/143) | **not our bug** — cosmetic macOS 26.4.1 change |

### Bug A detail

`BatFiKit/Sources/ClientsLive/PowerSourceClient+Live.swift` `getPowerSourceInfo()` has **six**
`guard … else throw PowerSourceError.infoMissing`. A single throw means `powerSourceChanges` yields nothing,
so `ChargingManager` never receives a power state and no charging decision is ever made.

A reporter proved `IOPSCopyPowerSourcesInfo/List/GetPowerSourceDescription` returns a normal dictionary on
macOS 27 beta — but that test only covered IOPS. **Four of the six throw sites read the `AppleSmartBattery`
IORegistry service** (`CycleCount`, `VirtualTemperature`, `ExternalConnected`), which the test never touched.

This is the same failure class as the earlier "3.0.5 blank on macOS 15.7.7" report.

**Bug A is firmware-keyed, not OS-keyed.** A dual-boot user updated one volume to macOS 27 and their *Sequoia*
install became stuck in Initializing at the same moment; another reports the identical thing happened at
Sequoia→Tahoe and was fixed then. `VirtualTemperature`, `CycleCount` and `ExternalConnected` are
firmware-sourced properties on `AppleSmartBattery`, so new firmware breaks them on every OS on the machine.
This is why the bug recurs each cycle, and it means the fix must be tolerance, not a per-release patch.

Note also that one reporter on build `26A5368g` had the **charge limit still enforcing at 55%** while the
menubar read 0%. For a meaningful share of users, Bug A *is* the entire "BatFi doesn't work" experience —
independent of Bug C.

### Bug A2 — no retry, no recovery, no diagnosis

Distinct from the missing-field problem and worth fixing on its own merits:

- **The initial fetch is one-shot.** `powerSourceChanges` spawns a single `Task`; on throw it logs and yields
  nothing. There is no retry.
- **Recovery depends entirely on IOPS notifications.** If the callback never fires again — the common case
  once power state settles — the app stays at 0% forever. Quitting and relaunching reproduces it exactly,
  because the failure is deterministic.
- **The error is thrown away.** `PowerSourceClient+Live.swift:203` is `observer.logger.error("")` — an empty
  message. The error value is discarded entirely.
- **`PowerSourceError.infoMissing` carries no field name**, so the six `guard`s are indistinguishable in logs.
  Every user report says only "Can't get the current power source info", which is why this bug took weeks to
  localise and still isn't pinned to a specific key.
- **The UI has no failure state.** `AppChargingState` stays `.initial`, so the menu reads "Initializing"
  indefinitely and the menubar reads 0% — presented as data rather than as "unknown".
- **The 30 s advice is wrong.** `HelperConnectionManager` eventually suggests "Restarting your Mac may help".
  It won't; the helper is fine and the fault is app-side.

---

## 4. Design

### 4.1 `SMCKeyProbe` — metadata-based capability detection (helper-side)

Surface the `dataAttributes` byte that `SMC.swift:201` already parses and discards. Measured semantics:
`0x80` = readable, `0x40` = writable.

```swift
struct SMCKeyProbe {
    let type: FourCharCode, size: UInt32, attributes: UInt8
    var isReadable: Bool { attributes & 0x80 != 0 }
    var isWritable: Bool { attributes & 0x40 != 0 }
}

enum ProbeResult { case usable(SMCKeyProbe), placeholder, absent, denied }
```

`probe(_:)` maps `kSMCGetKeyInfo` results: `dataSize == 0` → `.placeholder` (trap 2),
`SMCError.keyNotFound` → `.absent`, `SMCError.notPrivileged` → `.denied` (trap 3).

`supports(code:type:size:writable:)` requires name **and** type **and** size **and** writability — defeating
trap 1.

### 4.2 Backend selection

```swift
enum ChargeBackend { case firmwareRange, chte, legacyCH0BC, systemChargeLimit, unsupported }
```

Order is deliberate — `bfF0` first, because old macOS carries new firmware; SMC backends outrank
`.systemChargeLimit` because only they can express a limit below 80%:

```
bfF0(ui8/1) + bfD0(ui32/4) + bfE0(ui32/4) → .firmwareRange
CHTE(ui32/4)                              → .chte
CH0B(ui8/1) + CH0C(ui8/1)                 → .legacyCH0BC
isMCLSupported                            → .systemChargeLimit   (fallback, 80–100% only)
otherwise                                  → .unsupported
```

Secondary fingerprint for diagnostics and sanity-checking: `BCF0` **data size** — 4 = pre-27, 1 = fw ≥ 27.
This is what mainline Linux `macsmc-power.c` does, in a field named `fw_ge_27`.

### 4.3 Firmware-keyed cache

Read `system-firmware-version` from `IODeviceTree:/chosen`; fall back to `firmware-version` (a 256-byte
NUL-padded buffer — **must truncate at the first NUL**).

**Parser trap:** the prefix was renamed `iBoot-` → `mBoot-` in macOS 26.4. Treat the whole string as an
opaque identity token. Do **not** parse it into a version and do **not** branch on it — firmware→macOS is
many-to-one and unstable. Its only jobs are cache identity and bug-report diagnostics.

Cache the probed backend keyed on that string; invalidate whenever it changes. This is precisely the
upgrade-then-downgrade case: the OS moves, the token doesn't, and the cache follows the firmware.

### 4.4 Resilient power source

Split fields:

- **Required:** battery level, charger connected, power source state. Absence is a real error.
- **Optional:** cycle count, temperature, time-to-empty, time-to-full, health. Absence degrades one UI
  element and nothing else.

Match `IOPMPowerSource` (the stable superclass) rather than the concrete `AppleSmartBattery`. Also fix the
`IOServiceClose(service)` call on an `io_service_t` in the `defer` at `PowerSourceClient+Live.swift:98` —
wrong API for that handle type.

The stream must never terminate because an optional value is missing.

### 4.4a Failure handling and recovery

Tolerating missing fields fixes the common case. This section fixes the behaviour when a **required** field is
genuinely unavailable — so a future firmware change degrades legibly instead of bricking the UI.

**Retry.** Replace the one-shot initial fetch with bounded exponential backoff (e.g. 5 attempts, 200 ms →
~3 s). Transient failures at launch, when IOKit is still settling, resolve on their own.

**Periodic safety net.** Add a low-frequency re-poll (60 s) that runs while the last fetch is failing and
stops once one succeeds. Recovery must not depend on an IOPS notification that may never arrive. This alone
turns "permanently stuck until the user notices" into "self-heals within a minute".

**Coalesce the burst.** Debounce the notification-driven fetches so a storm of IOPS callbacks produces one
attempt, not eight. Under Golden Gate firmware this matters more — every inhibit toggle now generates a full
system power-source transition.

**Diagnosability.** These are the changes that shorten the *next* macOS cycle:

- `PowerSourceError.infoMissing(field:)` — name the field that was absent.
- Fix `PowerSourceClient+Live.swift:203`, which currently logs an empty string and discards the error.
- Log the firmware token (§4.3) once at startup, so every bug report carries it.
- On repeated failure, log the full set of keys actually present on `AppleSmartBattery`, so one user report is
  enough to identify a renamed property.

**Honest UI.** Distinguish "unknown" from "0%". After retries are exhausted, show an explicit unavailable
state with a one-line reason, not a plausible-looking zero. Replace the "Restarting your Mac may help"
notification with something accurate for this failure, and don't show it when the helper is healthy — in this
bug the helper is fine and charge limiting may still be working.

### 4.5 Effect verification

After a mode change, confirm via `CHNC` and/or `ChargerData` rather than SMC read-back. On mismatch, surface
a real "charge control is not taking effect on this firmware" state instead of reporting success.

### 4.6 Apple Charge Limit coexistence

- Gate the MCL path on `isMCLSupported`, not `#available(macOS 26.4, *)`.
- Read `getMCLLimitWithError:` / `isMCLCurrentlyEnabled:` to detect a user-set system limit.
- Display `MCLStatus` — it is already plumbed across XPC (`XPCService.getMCLStatus`) and rendered nowhere.
- If the system limit is not 100%, tell the user plainly that it will interact with BatFi's limit.

The two are **independent gates**: the effective ceiling is the lower of the two, and neither overwrites the
other's keys. Attribute which gate is holding via `AppleSmartBattery` → `ChargerData` → `NotChargingReason`,
**bit 24** (`0x1000000`) = system charge limit active. Verified on the development machine: the field reads
`128` = `BIT(7) NO_CHARGER` while unplugged, matching Asahi's `CHNC` bitfield exactly. This is readable
unprivileged with no SMC access, so the *app* can attribute state without a round trip to the helper.

### 4.6a `.systemChargeLimit` — delegating to Apple's limit

When no SMC charge-control backend is usable but `isMCLSupported` is true, drive Apple's Manual Charge Limit
instead of inhibiting via SMC. This is what AlDente appears to do on macOS 27 (their `useTahoeNativeLimit`
pref), and BatFi already owns the necessary bridge — `PowerUISmartChargeClient`, with `setMCLLimit:error:`
confirmed present on the live framework alongside the `temporarilyOverrideMCLTargetSoC:` already in use.

**Inverted ownership.** In every other backend BatFi *releases* the system limit (overrides MCL to 100) to
keep it out of the way. Here BatFi *sets* it. These must be mutually exclusive — a single rule keyed on the
active backend, or the renewal task will fight the setter.

**`setMCLLimit:` mutates a user-visible System Settings value.** Snapshot the user's original value before
first write, restore it on quit/disengage, and disclose in the UI that BatFi is managing the system setting.

**Honest constraints, surfaced in UI:**

| Constraint | Consequence |
|---|---|
| Range 80–100%, 5% steps (80/85/90/95/100) | **A limit below 80% cannot be honoured at all** |
| Hysteresis fixed at >5% drop | BatFi's own hysteresis is ignored |
| Not persistent while the Mac is off | Limit does not hold through shutdown |

The floor is the real limitation, not the feature count. The label should say "limits below 80% aren't
available on this firmware", not a vague "reduced functionality" — a user on 55% needs to know their setting
is not being applied.

**Do not blanket-disable the other features — probe them.**

- **Force discharge:** `CHIE` reportedly survives on Golden Gate firmware, including beta 4 where the
  charge-limit keys broke. If `CHIE` probes usable, keep the feature.
- **MagSafe LED:** `ACLC` is present on macOS 27. The reason batt drops LED control is that under
  `.firmwareRange` the firmware owns the charging decision so batt cannot know the state — but under
  `.systemChargeLimit` BatFi *does* know it, via `isMCLCurrentlyEnabled:` and `NotChargingReason` bit 24.
  Drive colour from gate attribution rather than from BatFi's own inhibit flag.

Feature availability is therefore per-capability, not per-backend: each feature is enabled by its own probe,
and the UI explains what is reduced and why.

### 4.6b Battery health off the hot path

`getBatteryHealthIfNeeded()` spawns `system_profiler SPPowerDataType` with blocking `readDataToEndOfFile()`
and `waitUntilExit()` **inside** the async `getPowerSourceInfo()`, using deprecated `launchPath`/`launch()`.
On a cold cache that is a ~1 s block on a path also driven by IOPS notification callbacks.

Decouple it: compute health on its own schedule into the existing 1-hour cache, and have `getPowerSourceInfo()`
read the cached value without ever awaiting a subprocess. Health becomes an optional field per §4.4 — a
missing value degrades one UI element and nothing else. Also move to `executableURL`/`run()` with a timeout,
and tolerate non-zero exit.

**Do not replace it with an IORegistry ratio.** Measured on the development machine:
`NominalChargeCapacity/DesignCapacity` = 82%, `AppleRawMaxCapacity/DesignCapacity` = 80%, while
`system_profiler` reports **85%**. Apple's figure is not a simple ratio, so substituting one would silently
change a user-visible number.

### 4.7 Firmware-range mode is a different feature

Under `.firmwareRange` the firmware owns the charging decision. Consequences that must reach the UI:

- Battery percentage **can fall** below the limit while on AC — the firmware may run the Mac off battery.
- **MagSafe LED control is unavailable** — BatFi no longer reliably knows the charging state.
- **Force discharge** is not BatFi's to own.
- **Sleep hooks are unnecessary** — the firmware enforces the limit while asleep.

Persist these capability disables so stale config cannot re-arm a feature the firmware doesn't support.

Note also: on macOS 27 each inhibit toggle surfaces as a full system Power Source change. One AlDente user
logged 1617 AC↔battery transitions in 3 hours, blanking external displays. Toggle frequency now has a real
cost — the 30 s poll and 100 ms debounce need review under this backend.

### 4.8 Safety

`resetIfPossible()` must clear `bfF0` in addition to `CHTE`/`CH0B`/`CH0C`/`CH0I`/`CH0J`. A helper crash in
firmware-range mode currently leaves the limit armed with nothing to clear it.

---

## 5. Phasing

**Phase 1 — ship immediately, no macOS 27 hardware needed.**
Bug A (required/optional field split), Bug A2 (retry, periodic re-poll, per-field diagnostics, honest
unavailable state) and Bug B (`CHIE` = `0x08`). Phase 1 is what makes the app stop looking dead for every
macOS 27 user, and it is independently testable. A2 is the part that makes the *next* firmware change a
degraded reading rather than a dead app, so it should not be deferred as polish. Also §4.6b — battery health
off the hot path.

**Phase 2 — the durability fix.**
`SMCKeyProbe`, backend selection, firmware-keyed cache, `isMCLSupported` gating, `MCLStatus` UI, effect
verification via `CHNC`. Behaviour on existing firmware is unchanged; this is what stops the recurrence.

**Phase 3 — `.systemChargeLimit`, the macOS 27 stopgap.**
Delegate to Apple's Manual Charge Limit (§4.6a), plus per-capability UI and the "below 80% unavailable" label.

Deliberately ahead of Golden Gate support: this works on **any** macOS 26.4+ machine including every macOS 27
build, whereas the `bf**` mechanism is currently broken on the newest beta. It restores partial function to
affected users without betting on a moving target.

**Phase 4 — Golden Gate `bf**` support.**
`.firmwareRange` backend, `bfF0` in the reset path. Strictly better than Phase 3 when it works — it honours
limits below 80% and is enforced during sleep — but it ships behind the honest `.unsupported` state, because
beta 4 (`20457.0.125.0.2`+) broke it and no tool has a fix as of 2026-08-03. Revisit when the GM key set
settles.

---

## 6. Testing

The SMC layer currently has **no test seam**: `SMCKit` is an enum of statics over a global `io_connect_t`,
and `SMCService` calls it directly. Phase 2 introduces a protocol so the backend ladder is testable with a
fake key table.

- **Unit, fake SMC:** each firmware generation's key table selects the right backend; the `bfD0` decoy selects
  `.chte`, not `.firmwareRange`; zero-size placeholders select nothing; `denied` ≠ `absent`.
- **Unit, power source:** every optional field missing individually and in combination still yields a
  `PowerState`; each required field missing yields a clean error without tearing down the stream.
- **Unit, recovery:** a fetch that fails N times then succeeds produces a `PowerState` without any IOPS
  notification; a permanently failing fetch keeps retrying at the slow interval and never terminates the
  stream; a burst of notifications coalesces to one attempt; `infoMissing(field:)` names the right field.
- **Cache:** a changed firmware token invalidates; an unchanged one does not.
- **Manual, on 26.6:** read-only probe output matches §2.2; charge inhibit still works; `CHNC` reports our
  inhibit as the reason.

**Testing constraint.** The development machine has never run macOS 27, and firmware cannot be rolled forward
for testing without committing the machine to Golden Gate firmware permanently (only a DFU revive undoes it).
So Phases 2–3 cannot be verified locally:

- Phase 1 and Phase 2 are fully testable against a **fake SMC key table** — that is the main reason the probe
  layer needs a protocol seam rather than statics over a global connection.
- Phase 3 and `.systemChargeLimit` need volunteers. The issue threads already contain capable reporters who
  have supplied logs, standalone Swift test results and `ioreg` dumps — recruit from there, and ship the §4.4a
  diagnostics first so their next report carries the firmware token and the failing field name.

The `assert` on `MemoryLayout<SMCParamStruct>.stride == 80` is compiled out in Release. Make it a real
precondition or a startup check.

---

## 7. Open questions

- **Beta 4 (`20457.0.125.0.2`+)** — nobody has published a dump or root cause. Design assumes `.unsupported`.
- **`CHLS` byte order** is disputed between sources. Only relevant if we ever pursue the entitled path, which
  requires SIP off and is therefore out of scope.
- **`CHTC`** exists on Tahoe firmware; its function is unknown. Explicitly rejected as a `CHTE` replacement by
  the person who found the real mechanism. Do not assume.
- **macOS 27 failure signature for BatFi specifically** is inferred from issue reports, not reproduced. Phase 1
  is designed to be correct regardless of which of the six throw sites fires.

---

## 8. References

- batt `pkg/smc/consts_arm64.go`, `charging.go`, `adapter.go` — <https://github.com/charlie0129/batt>
- batt PR #140, `bfF0`/`bfD0`/`bfE0` disclosure (2026-07-12) — <https://github.com/charlie0129/batt/pull/140#issuecomment-4950731214>
- actuallymentor/battery PR #469 (2026-07-10) — <https://github.com/actuallymentor/battery/pull/469>
- Linux `macsmc-power.c`, macOS 27 support, commit `f7b253a6e217` (2026-07-11) — <https://github.com/torvalds/linux/commit/f7b253a6e217>
- Asahi `CHLS` thresholds, commit `c6ccbdd` (2024-08-15) — <https://github.com/AsahiLinux/linux/commit/c6ccbdd693e7d0944642064aa5df1010fe29c35d>
- Apple — Optimized Battery Charging and Charge Limit (2026-04-06) — <https://support.apple.com/en-us/102338>
- AlDente #1771, macOS 27 tracking — <https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring/issues/1771>
- mhaeuser, `IOPSLimitBatteryLevel` RE — <https://github.com/charlie0129/batt/issues/34>
