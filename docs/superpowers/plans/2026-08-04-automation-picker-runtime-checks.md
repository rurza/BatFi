# Automation Picker — Runtime Verification Checklist

Branch: `claude/automation-picker-ui-salvage`

Everything below needs a human at the keyboard. Automated verification got as far as it could
and then hit two hard platform limits, documented at the bottom.

Build and run:

```bash
xcodebuild build -scheme BatFi -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO
open ~/Library/Developer/Xcode/DerivedData/BatFi-*/Build/Products/Debug/BatFi.app
```

Keep a log stream open in a second terminal throughout:

```bash
log stream --predicate 'process == "BatFi"' --info --style compact
```

## Already verified automatically — no need to repeat

- App launches; `CLMonitor` named `BatFiAutomation` is created at startup.
- Two fence conditions register from existing rules and deliver events
  (`FenceMonitor Fence event. state=…`).
- **No continuous location updates run.** This is develop's battery win and it holds.
- Onboarding appears on first launch; the status menu renders with the expected items.
- Build green, 50 tests in 10 suites green.

## 1. The one that could invalidate a premise — search region bias

The whole point of the search rework is that a short, ambiguous query resolves near you. A
review found the seeded region could be overwritten by MapKit's initial camera callback; a fix
now also sets `cameraPosition` to the seeded region. Whether that actually wins the race is only
observable at runtime.

- [ ] Settings → Automation → Add Rule → tick **Only at a location**.
- [ ] Do **not** touch the map. Type `wars` in the search field.
- [ ] **Pass:** suggestions are ranked near your actual location (Warszawa near the top for a
      Polish user). **Fail:** a US "Warsaw" (Indiana/Texas) ranks first — the seed lost the race
      and the fix is incomplete.
- [ ] Also confirm the map opens near you rather than showing the whole planet.

## 2. Permission states

Reset the grant between runs:

```bash
tccutil reset Location software.micropixels.BatFi
```

- [ ] **Not determined** — banner reads "BatFi needs location access…" with **Allow Access**;
      pressing it produces the real system prompt. *(This is the path most likely behind the
      original "fresh install never asked" report — watch whether the prompt appears at all, and
      whether it appears detached from the Settings window, since BatFi is `LSUIElement`.)*
- [ ] **Denied** — banner offers **Open System Settings**, and it lands on Privacy & Security →
      Location Services. This deep link uses a `?query` form unlike the app's other three, so
      confirm the destination pane specifically.
- [ ] **Services off** (toggle Location Services off system-wide) — banner says the system switch
      is off, not that BatFi was denied.
- [ ] **Authorized** — no banner at all, and no empty padded box where it used to be.
- [ ] With permission denied, confirm search and tap-to-place still work. Only **Use current
      location** should be gated.

## 3. Use current location

- [ ] Click it with a recent fix available → the pin fills essentially instantly.
- [ ] Click it with no recent fix → "Locating…" with a working **Cancel**.
- [ ] It must **never** report "Couldn't determine your location" while the log shows
      `auth=authorizedAlways`. That false failure is the bug that started this work.
- [ ] Revoke permission mid-"Locating…" → the button must not be left disabled and spinning.

## 4. Search results

- [ ] Field bounds are obvious (rounded border, matching the Name field above).
- [ ] Suggestions appear as you type, max 5, with title and subtitle.
- [ ] Clicking one places the pin and fills the place name.
- [ ] A nonsense query shows "No places found." — and it must **not** flash on every keystroke
      while a real query is still in flight.
- [ ] Select a suggestion immediately after typing: the list must not reappear under the now-empty
      field.
- [ ] **Click ordering:** click suggestion A then quickly click B before A resolves. The pin must
      end on **B** — the later click — regardless of which network request returns first. This is
      the regression fixed in `af65afb`; it is the reason two counters exist in `select(_:)`.

## 5. Place name and layout

- [ ] The field is labelled "Place name" with the caption below, and the placeholder reads
      "e.g. Home" (not a second "Place name").
- [ ] Tapping the map fills a name via reverse geocode; typing your own name is never overwritten.
- [ ] **Stale-name check:** click **Use current location** (label becomes "Current location"), then
      tap a different spot across town. The name must update rather than keep describing the old
      place.
- [ ] **Rapid tap-then-select:** tap the map, then immediately pick a search suggestion. The place
      name must match the final pin, not an earlier one.
- [ ] Expand both the time and location conditions so the sheet is at its tallest: nothing clipped
      at the bottom, and a scroll indicator is visible when content overflows.
- [ ] Enable a location condition without picking a place → "Pick a place to finish this rule."
      appears beside a disabled Save.
- [ ] A rule saved with no place name shows "@ Unnamed place" in the rule list — **not**
      "@ e.g. Home".

## 6. Localization spot-check

Switch the system language and reopen the rule editor.

- [ ] **ja / ko / zh-Hans** — flagged as wanting a native eye across the whole `automation.*` set,
      specifically `active_badge`, `menu.idle`, the Korean particle in `charging_override.active`
      (`'%1$@'이(가)`), and zh em-dash spacing in `menu.active`.
- [ ] **uk** — "Location Services" is rendered `Служби локації`; confirm against a Ukrainian macOS,
      the alternative being `Служби геолокації`.
- [ ] **tr** — `menu.active_until` is `%@'a kadar`; Turkish vowel harmony depends on the
      substituted time, so a fixed suffix cannot always be right.
- [ ] Any locale: confirm the disabled-Save message does not truncate beside Delete/Cancel/Save —
      German, French, Italian, Russian and Ukrainian are 40-46 characters against English's 33.

## Why this could not be automated

Two hard limits, both environmental rather than solvable with more effort:

1. **Screen Recording is not granted** to the agent process, so `screencapture` fails with
   "could not create image from display" — no visual verification of banners, field bounds, or
   clipping.
2. **SwiftUI content is opaque to the Accessibility API here.** AppKit surfaces work — the status
   menu enumerated correctly (`Charge to 100%`, `Settings…`, `Quit BatFi`) — but Settings window
   contents expose no buttons or static text, so the picker cannot be driven or read.

Log-level facts *were* verified and are listed at the top. Everything requiring eyes on pixels or
clicks into SwiftUI is what remains.
