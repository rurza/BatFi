# macOS 27 sub-80% charge limit — SOLVED

**Date:** 2026-08-10 · **Status:** SOLVED and implemented · **Branch:** `feature/mcl-sub-80-limits`
**Machine:** `Mac15,8` (M3 Max), macOS 27.0 build `26A5388g`, firmware `20457.0.125.0.2`

---

## 1. The mechanism

A charge limit below 80% is set by writing **two preference keys in root's own domain** and posting
a Darwin notification:

```
domain: com.apple.smartcharging.topoffprotection
scope:  (kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)   ← as root
        mclLimitValue   = <target>     (Int)
        MCLFeatureState = 1            (Int)
then:   notify_post("com.apple.smartcharging.defaultschanged")
```

`/usr/libexec/PowerUIAgent` runs as root, watches that notification, re-reads the domain, and
registers a `ChargeCtrlPolicy { soclimit: <target>, reason: "manualChargeLimit" }`. powerd
serialises it into `/Library/Preferences/com.apple.powerd.charging.plist` and the firmware
enforces it.

**Adoption is asynchronous and can be slow.** Usually ~1s, but observed taking well over six
seconds and landing roughly half a minute later. This is the single biggest trap in the whole
mechanism: two separate "it does not work" conclusions in this investigation — including a
confident "`enableMCL:` is required" — were nothing but a poll window that expired before
PowerUIAgent got there. Anything that gives up early and then calls `setMCLLimit` as a
fallback **overwrites an adoption that is still in flight**, turning a slow success into a
permanent failure. Wait generously; never treat a short timeout as a refusal.

`enableMCL:` is **not** required. The preference write plus the notification is sufficient on
its own.

**`CurrentUser` must resolve to root** — PowerUIAgent reads root's domain, so the write belongs in a
root helper. From the user's session it is written successfully and then ignored.

Measured working: `soclimit: 72` with `pmset` reporting `AC attached; not charging`.

## 2. Why the 80% floor does not apply

There are two distinct things, and conflating them is what cost the first investigation a day:

| | |
|---|---|
| **`PowerUI.framework`** | A client library loaded into *your* process. `setMCLLimit:` lives here. It validates against `availableChargeLimits` = `[80,85,90,95,100]` and refuses anything else with `PowerUISmartChargingErrorDomain` code 4. |
| **`/usr/libexec/PowerUIAgent`** | A root daemon. Actually creates the policy. **No 80% floor.** |

The floor is client-side validation. AlDente does not defeat it — it never invokes it. It asks the
agent directly, in the agent's own terms.

**`setMCLLimit:` is a red herring and always was.** It is refused for every sub-80 value, on AC and
on battery, MCL enabled and disabled, as user and as root, under any client name — *including while
a sub-80 limit is already in force*. That last datum was recorded by the first investigation and is
conclusive on its own: an API cannot be refusing the value it is currently holding, so something
else must be setting it.

AlDente's own binary contains the string `PowerUI cannot charge to targets below 80`. It knows.

## 3. Why it stayed hidden for a day

Three independent blind spots, each of which produced a confident false negative:

1. **`strings` cannot see the key names.** Swift compiles string literals of ≤15 bytes into
   `movz`/`movk` immediates in `__text`; they never reach `__cstring`. `mclLimitValue` (13) and
   `MCLFeatureState` (15) are both small strings. The first investigation *saw* the fragment
   `MCLFeatuH` and even wrote down that short literals may be invisible — but never decoded them.
2. **`fs_usage` on the helper can never see a CFPreferences write.** `cfprefsd` performs the I/O,
   not the calling process. A zero-line trace was read as proof that the helper touches no files.
3. **The preference sweep hashed `/Library/Preferences/*.plist`.** This lands in *root's ByHost*
   domain, which the sweep never looked at. `/Library/Preferences/ByHost` genuinely does not exist;
   `/var/root/Library/Preferences/ByHost` is a different path.

And one plain misreading: `owner: 510` on the live policy was recorded as "powerd's". **510 is
PowerUIAgent's pid**; powerd is 360. That single misattribution pointed the investigation away from
the daemon doing the work.

## 4. Decoding the key names

The general technique, since it will be needed again:

```
Swift small string (≤15 UTF-8 bytes), little-endian:
  word0 = first 8 bytes
  word1 = remaining bytes, top byte = 0xE0 | count

0x74696d694c6c636d + "Value"   count 13 → "mclLimitValue"
0x75746165464c434d + "reState" count 15 → "MCLFeatureState"
```

Two traps: decode only on a **completed** `movz`/`movk` chain (otherwise a longer literal's prefix
reads out — `"isProUser"` appears as `"isPr"`), and check **both byte orders**, because FourCC
integers are sometimes packed big-endian (`nISB` in code is SMC key `BSIn`).

Scripts: `tools/smallstrings.py` (dump every small string), `tools/win2.py` (annotated window),
`tools/xref.py` (ADRP+ADD string xrefs), `tools/selrefs.py` (Mach-O loader).
For shared-cache-only frameworks, `lldb -b -o 'disassemble -s <lo> -e <hi>' <binary>` works
without extraction.

## 5. What was checked and eliminated — correctly

These are settled; do not re-litigate them.

- **`bfD0` / `bfE0` / `bfF0` ("Golden Gate")** are genuinely `NotPrivileged` for keyInfo, read
  **and** write, as root, with hardcoded sizes and no `getKeyInfo` call. AlDente contains this code
  path (app `0x100225b90`: `bfF0←0`, `bfD0←UPPER<<24`, `bfE0←LOWER<<24`, `bfF0←2`, dataSize 4/1,
  little-endian into `bytes[]`) and its own error string `Golden Gate SMC keys are unavailable`.
  It is not the mechanism on this firmware.
- **BatFi's `SMCParamStruct` is correct.** Verified empirically: size 80, `result`@0x28,
  `data8`@0x2a, `bytes`@0x30 — byte-identical to what AlDente's helper passes. The explicit
  `padding: UInt16` is load-bearing (Swift lays out nested `keyInfo` by size 9, not stride 12).
- **AlDente uses the same IOKit path BatFi does**: `AppleSMC`, `IOServiceOpen` type 0,
  `IOConnectCallStructMethod` selector 2, operation in `data8`. No entitlements beyond
  `com.apple.application-identifier`. Nothing special about its process.
- **`CHTE`, `CH0B`, `CH0C`, `CH0I`** are absent on this firmware (`kSMCKeyNotFound`).
- **`allowMCLOverride`** (a real string in PowerUIAgent, adjacent to the domain) does **not** gate
  sub-80 `setMCLLimit:` in any of the four preference scopes. Tested and disproved.
- **Writing `com.apple.powerd.charging.plist` directly does nothing.** It is powerd's output.

## 6. Implementation in BatFi

`BatFiKit/Sources/Server/ManualChargeLimitDefaults.swift` — replaces the disproven
`ChargeCtrlPolicyStore.swift`, which has been deleted.

- `apply(limit:)` writes both keys, posts the notification, and **confirms against powerd's own
  `soclimit`** rather than reading back the preference it just wrote.
- `release()` clears both keys and posts the notification. Called on every teardown path, because
  this is persistent root-owned state that outlives BatFi.
- `currentLimit()` reports what powerd is *enforcing*, which is what `SMCService` uses to notice a
  limit that stopped holding.

`SMCService` still tries `setMCLLimit:` first (correct for ≥80, and the only sanctioned path), and
falls through to the defaults channel only once it has actually refused. The old
enable-then-write ordering and its write-fight are gone: nothing in the sub-80 path calls
`setMCLLimit:`, so powerd has nothing to argue with.

`ChargeBackend.honoursLimitsBelow80 == true` for `.systemChargeLimit` is now correct rather than a
regression.

Build: `xcodebuild build -project BatFi.xcodeproj -scheme Server -destination 'platform=macOS'`
Tests: `xcodebuild test -project BatFi.xcodeproj -scheme AppSharedTests -destination 'platform=macOS'`
— 316 tests pass.

## 7. Tools

| tool | purpose | root? |
|---|---|---|
| `mclset.swift` | **the mechanism, minimal** — apply / `--off` / `--status` / `--strict` | yes |
| `mclprefs.swift` | same, tried across all four preference scopes | yes |
| `mcloverride.swift` | the disproved `allowMCLOverride` experiment, kept as a negative result | yes |
| `goldengate.swift` | AlDente's SMC band sequence, reproduced exactly; returns `NOTPRIVILEGED` | yes |
| `mcl.swift` | ground truth — `getMCLLimit`, `availableChargeLimits`, selector list | no |
| `smcdump.swift`, `gapcheck.swift`, `qs.swift`, `uctype.swift`, `bypass.swift`, `rootprobe.swift`, `writetest.swift`, `sweep.swift`, `asynctest.swift`, `override.swift`, `pmsettings.swift` | earlier probes | mixed |

## 8. Method rules that earned their place

- **State the disproof before running the test, and require the disproof to fail.** Used throughout
  this session; it killed three wrong hypotheses (struct layout, IOKit selector, `allowMCLOverride`)
  before any of them reached code.
- **Verify enforcement, never a read-back.** `getMCLLimit` returning 72 proved only that something
  echoed 72. The proof is `pmset` showing `AC attached; not charging` **and** powerd's `soclimit`.
  A preference read-back proves only that you wrote it.
- **A null result from an instrument that cannot observe the thing is not evidence.** `fs_usage`
  and CFPreferences; `strings` and small literals; `nm -u` and `dlsym`.
- **Charger must be connected** for any charging-behaviour test, and the target must require action.
  Confirm the power source in the same breath as the observation — "discharging" during an unplug
  is not a limit working.

## 8a. Verified on hardware

BatFi applied **60%** end-to-end through its own helper on 2026-08-10: `soclimit = 60`,
`pmset` reporting `AC attached; not charging`, adopted 1.1s after the write, held stable across
30s with powerd's plist untouched — no write-fight. 320 tests pass.

Three real bugs were found only by running it, none of which any test would have caught:

1. **Actor reentrancy.** `ManualChargeLimitDefaults` is an actor, but `apply` awaits inside its
   polling loop, and actors are reentrant across suspension points. Four concurrent applies
   interleaved, each rewriting the keys and re-posting the notification while PowerUIAgent was
   settling. Actor isolation does not serialise this; an explicit in-flight guard does.
2. **A 3s adoption budget**, which is roughly an order of magnitude too small.
3. **A fallback that destroyed its own request** — on timeout it called `setMCLLimit(80)`,
   overwriting the pending adoption seconds before it would have landed.

## 9. Open follow-ups

1. **`ACLC` (MagSafe LED) is still unmodelled.** Observed: with a limit of 72% held at 80% charge,
   the LED goes **green**. That matches Apple's native behaviour for a system limit (`ACLC = 2`);
   AlDente instead forces `1` (off). BatFi has no opinion here yet — decide one deliberately.
2. ~~`release()` does not actually retire the policy.~~ **Retracted — it does.** Measured:
   quitting BatFi with 50% in force took `soclimit` to 80 within ten seconds, with the restore
   write *failing*, so clearing the preference is what retired it. The original claim came from
   reading `soclimit` 1.5s after clearing — retirement is as slow as adoption, and this was the
   third instance of the same impatience artifact in one session.

   It did expose a real defect, since fixed: `captureUserLimitIfNeeded` recorded the user's
   System Settings limit from `getMCLLimitWithError:`, which now **echoes BatFi's own
   preference-channel value** (observed reporting 62 while powerd enforced 80). BatFi could
   therefore snapshot a sub-80 number as "the user's value", which `setMCLLimit:` can never
   write back — and since the snapshot is cleared only on a successful restore, it failed with
   `code=4` on *every* teardown, forever, while having lost the user's real setting. Both
   `captureUserLimitIfNeeded` and `releaseSystemLimit` now refuse values below
   `systemChargeLimitLowest`, on the grounds that System Settings cannot produce one. Verified:
   teardown is now silent and the limit still retires.
3. **Startup fires ~8 concurrent `applyChargeLimit` passes.** Only one now writes, thanks to the
   in-flight guard, but the duplicate "System limit refused / re-applying" pairs in the log point
   at several redundant status-driven invocations worth collapsing.
4. The MagSafe LED claim in `magSafeGreenLightSystemDriven` — that macOS drives `ACLC` green
   under this backend — rests on one observation plus an `ACLC = 2` reading. It is user-facing
   copy making a factual claim; worth a deliberate check.
