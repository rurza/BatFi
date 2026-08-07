# Changelog

All notable changes to BatFi are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.0.0] - 2026-08-05

### Added
- **BatFi keeps working on Macs whose firmware has dropped the charge-limit mechanism BatFi
  has always used.** Rather than assuming what a given version of macOS supports, BatFi now
  asks the Mac itself which charging mechanisms its firmware offers and uses the best one
  available. On Macs that still have the familiar mechanism, nothing changes.
- **On the newest firmware, the charge limit is held by the Mac itself.** Where the firmware
  offers its own charge range, BatFi hands it your limit and steps back — so the limit is meant
  to keep being enforced even while the Mac is asleep. BatFi hands the range back when you quit
  it or turn charge management off. Because the firmware manages the range on its own terms, the
  battery may sit a few points below your limit before it tops back up; the Charging pane says
  so. This firmware is new enough that nobody has been able to test it on real hardware yet, so
  please report anything that looks wrong.
- **Where only Apple's own charge limit is available, BatFi drives that instead.** Apple's
  limit cannot be set below 80%, so if you have chosen a lower one BatFi now says plainly that
  it could not be applied and which limit is actually in force.
- **The Charging pane reports which mechanism is in use** on your Mac, along with its firmware
  version, and lists the features that mechanism does and doesn't support.

### Fixed
- **BatFi now notices when the helper it is talking to belongs to a different copy of the
  app, and takes it back.** Every copy of BatFi on a Mac registers the same background
  helper, and macOS keys that registration to whichever copy asked first. A second
  copy — one still in Downloads, one on a mounted disk image, a build in Xcode's Derived
  Data — was told its installation had succeeded while macOS quietly kept running the other
  copy's helper. Everything looked healthy, because the helper answering really was a
  genuine BatFi helper; it just wasn't that copy's, so it could be an older build, and it
  disappeared the moment the other copy was updated or deleted. BatFi now identifies the
  helper process it is connected to, and if it is not the one this copy ships, it stops the
  other one, reclaims the registration, and starts its own. If two copies of BatFi are open
  at once — the one case BatFi cannot settle on its own, since each would take the helper
  straight back — it now says which other copy is running and where to find it, instead of
  competing with it. Onboarding no longer reports a successful installation on the strength
  of another copy's helper either.
- **A helper left running from a previous version after an in-place update is now
  restarted.** Replacing BatFi on disk did not replace the helper already running in memory,
  so an updated app could keep talking to the previous release's helper until the next
  reboot. BatFi now detects this and asks that process to quit so macOS starts the current
  one — no approval needed, since the registration was already correct.
- **BatFi no longer gets stuck on "Initializing" with an empty battery reading.** A single
  missing value from the system's battery service — which happens when a macOS or firmware
  update renames or removes one — used to abort the entire battery read, leaving the menu bar
  at 0% and BatFi unable to make any charging decision. Quitting and relaunching did not help.
  Battery level, charging state and charger connection are now the only values BatFi requires;
  cycle count, temperature, time remaining and battery health degrade individually and hide
  just their own row. Reads also retry on launch and re-check every minute while failing, so
  BatFi recovers on its own instead of staying stuck.
- **"Run on Battery" should now discharge on recent firmware.** BatFi was writing the wrong
  value to the charging controller key used by macOS 26-era firmware and newer, so the request
  was accepted but had no effect. The corrected value has not yet been confirmed on hardware.
- **"Run on Battery" and the MagSafe discharge blink no longer depend on the charge limit
  working.** Both used to be switched off together with the charge limit whenever BatFi couldn't
  use its usual mechanism. They are now checked on their own, so on firmware that has dropped
  that mechanism they keep working. The green MagSafe light is a separate setting with a separate
  answer — see Known issues.

### Changed
- Battery health is no longer measured during the battery read, removing a blocking system
  call from a path that runs on every power change.
- When a battery value is missing, BatFi now records which one and the Mac's firmware version,
  so a single report is enough to diagnose the next firmware change.

### Known issues
- **Pausing charging on demand doesn't take effect where the mechanism only sets a ceiling.**
  Neither Apple's charge limit nor the newest firmware's own charge range has a way to stop
  charging right now — both hold the battery at a percentage instead — so on Macs using either
  of them, the pause when the battery gets too hot and the pause while the Mac sleeps have no
  effect. Your charge limit is still enforced, and "Run on Battery" is unaffected. The Charging
  pane says so on the Macs it applies to.
- **On the newest firmware, BatFi can say "charging" while the Mac is actually holding.** That
  firmware doesn't report when it's holding the battery inside its charge range, so BatFi works
  the status out from the battery level — which means the menu bar and the charging
  notifications can be wrong for the few points between topping up and the limit. Your limit is
  still enforced exactly and the battery percentage shown is real; only the charging label is a
  guess. For the same reason, the green MagSafe light can't be used on those Macs; the blink
  when BatFi discharges the battery still works.
- **After quitting BatFi, the charge limit in System Settings can read 100% for a while.** When
  BatFi raises Apple's charge limit temporarily, current versions of macOS give it no way to
  hand that back early, so System Settings can keep showing 100% until the temporary change
  lapses on its own. This isn't new in this release — it was simply diagnosed during this work.

## [3.1.1] - 2026-06-19

### Added
- **Automation overrides are now visible where they take effect.** When an automation rule
  overrides your configured charge limit, the charging notification now reports the
  *effective* limit and names the rule responsible (e.g. "The limit is 85% (set by
  automation "Work").") instead of showing the configured value, and the Charging settings
  pane shows a live banner while a rule is actively in control. A manual temporary override
  still takes precedence and suppresses the automation attribution.

### Fixed
- **"Run on Battery" no longer turns itself off.** The automatic cleanup that clears a
  leftover charge override after the charger has been unplugged for a couple of minutes was
  also clearing the *Run on Battery* (discharge) override — so deliberately running on
  battery would silently stop after a short while. The cleanup is now limited to charge/hold
  overrides; *Run on Battery* stays on until you turn it off.

## [3.1.0] - 2026-06-03

### Added
- **Calendar / Automation.** A new **Automation** settings pane lets you automate your
  charge limit by **time and place**. Each rule applies a custom charge-limit %, gated by an
  optional schedule (one-off date or repeating weekdays + time window) **and** an optional
  location (map picker with address search, current-location, and an adjustable radius).
  Rules are an ordered, drag-to-prioritize list — the top-most rule whose conditions match
  right now wins. A help button in the pane explains how it works.
- When automation is enabled, the menu-bar dropdown shows a status section: the active rule,
  the limit it's enforcing and until when — or "idle" with the next upcoming rule.
- The whole feature is localized into all 14 supported languages.

### Fixed
- **"Charge to 100%" now turns itself off.** The temporary charge-to-full override is
  cleared automatically once the battery reaches 100%, or after the charger has been
  disconnected for roughly two minutes — so it no longer lingers after you've unplugged or
  topped up.

## [3.0.5]

### Fixed
- Restore the system charging defaults when BatFi disengages, so charging behaves normally
  after the app stops managing it.
- Defer the menu rebuild on macOS 26 while the menu is open, fixing a blank area at the top
  of the dropdown.

[4.0.0]: https://github.com/rurza/BatFi-Priv/compare/3.1.1...4.0.0
[3.1.1]: https://github.com/rurza/BatFi-Priv/compare/3.1.0...3.1.1
[3.1.0]: https://github.com/rurza/BatFi-Priv/compare/3.0.4...3.1.0
[3.0.5]: https://github.com/rurza/BatFi-Priv/compare/3.0.4...3.0.5
