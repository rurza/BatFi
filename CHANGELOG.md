# Changelog

All notable changes to BatFi are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[3.1.0]: https://github.com/rurza/BatFi-Priv/compare/3.0.4...3.1.0
[3.0.5]: https://github.com/rurza/BatFi-Priv/compare/3.0.4...3.0.5
