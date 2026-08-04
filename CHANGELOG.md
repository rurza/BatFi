# Changelog

All notable changes to BatFi are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.1.2] - 2026-08-03

### Fixed
- **BatFi no longer gets stuck on "Initializing" with an empty battery reading.** A single
  missing value from the system's battery service — which happens when a macOS or firmware
  update renames or removes one — used to abort the entire battery read, leaving the menu bar
  at 0% and BatFi unable to make any charging decision. Quitting and relaunching did not help.
  Battery level, charging state and charger connection are now the only values BatFi requires;
  cycle count, temperature, time remaining and battery health degrade individually and hide
  just their own row. Reads also retry on launch and re-check every minute while failing, so
  BatFi recovers on its own instead of staying stuck.
- **"Run on Battery" now actually discharges on recent firmware.** BatFi was writing the wrong
  value to the charging controller key used by macOS 26-era firmware and newer, so the request
  was accepted but had no effect.

### Changed
- Battery health is no longer measured during the battery read, removing a blocking system
  call from a path that runs on every power change.
- When a battery value is missing, BatFi now records which one and the Mac's firmware version,
  so a single report is enough to diagnose the next firmware change.

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

[3.1.1]: https://github.com/rurza/BatFi-Priv/compare/3.1.0...3.1.1
[3.1.0]: https://github.com/rurza/BatFi-Priv/compare/3.0.4...3.1.0
[3.0.5]: https://github.com/rurza/BatFi-Priv/compare/3.0.4...3.0.5
