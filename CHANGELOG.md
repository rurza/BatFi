# Changelog

All notable changes to BatFi are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 4.2.0 - 2026-11-26

### Added
- **Try BatFi free for 7 days.** Start the trial from the welcome screen or the licence window,
  with no card, email or account. Every feature works during the trial. The menu shows how many
  days are left, and BatFi tells you a day before the trial ends and when it has ended. After
  that, charging goes back to macOS until you enter a licence key. One trial per Mac. Without a
  licence or a running trial, the menu shows only the battery and your licence options.
- **Resume charging below a set level.** Turn it on in Charging settings and drag the slider's
  second handle: BatFi charges to your limit, then lets the battery drop to the lower level
  before it charges again, instead of topping up every time it slips a point. It works on every
  Mac BatFi can limit, including Macs whose firmware or macOS holds the limit.
- **Each automation rule can have its own resume level.** The rule list and the banner show the
  rule's range, for example 60–80%.

### Changed
- **The menu says so when macOS charges past your limit to calibrate the battery,** instead of
  looking as if your limit stopped working.

### Fixed
- **BatFi no longer gives up your licence when the licence server has a problem.** It now does
  that only when the server says the key isn't valid.
- **A licence key pasted with extra spaces or line breaks is accepted.**

## 4.1.0 - 2026-11-07

### Added
- **Automatic Low Power Mode.** BatFi can turn Low Power Mode on when the battery drops to a
  level you choose, and turn it off again when you plug in.
- **Slow down apps on battery.** Apps you pick run on the Mac's efficiency cores while it's on
  battery, and get full speed back when you switch to them, plug in, or quit BatFi. Apps playing
  audio or on a call are left alone. You can also point at an app in the menu's list of apps
  with high energy usage to slow it down, or to stop slowing it (this needs an active licence).
  Apps on your slow-down list show a tortoise next to their name; it turns grey when the app
  isn't being slowed right now, and pointing at it tells you why.
- **BatFi warns you when another charge-control tool is installed** (the battery CLI, AlDente,
  Battery Toolkit, batt or bclm), because two tools setting the charge limit fight each other.
  The warning shows in Charging settings, in the menu, and in the "charge limit isn't holding"
  notification, and tells you how to remove the other tool and everything it left behind.

### Changed
- **Settings no longer has an Advanced pane.** Its options moved to Charging and General, and
  options your Mac can't use are hidden.
- **Crash reports are off until you turn them on in Settings.**

### Fixed
- **BatFi no longer drops your charge limit right after launch.** While BatFi was still reading
  your licence, it could briefly hand charging back to macOS. It now waits for the licence.
- **Inhibit charging is back in the menu and in Settings › Hotkeys on Macs that use Apple's
  charge limit (macOS 27).** BatFi holds the battery at its current level until you stop it,
  start another override, or leave the Mac unplugged for two minutes.
- **"Automatically turn off charging when the battery gets hot" works on Macs that use Apple's
  charge limit (macOS 27).** While the battery is hot, BatFi holds it at its current level.
- **On Macs whose firmware holds the charge limit itself, BatFi shows charging as paused while
  the battery waits a few points below your limit,** instead of saying it's charging, and the
  MagSafe green light option is available.
- **While macOS calibrates the battery at 100%, the menu no longer flips between "charging to
  100%" and "draining to the limit",** and you no longer get a new banner each time macOS moves
  between its own charging steps.
- **The menu bar icon changes as soon as you plug in or unplug.** Before, it waited until the
  charge limit had been applied, which on macOS 27 with a limit below 80% could take up to 45
  seconds.
- **BatFi no longer keeps the disk busy** by making macOS re-check the app over and over in the
  background.
- **The charging mode banner appears every time you plug in,** not only the first time.
- **The menu bar icon turns yellow as soon as you switch Low Power Mode on in System Settings,**
  instead of up to a minute later.
- **Keyboard shortcuts no longer stay paused after you edit one in Settings.**
- **BatFi no longer delays automatic sleep on Macs where charging can't be paused.**
- **Apps that have already quit no longer appear in the menu's list of apps with high energy
  usage.**
- **Settings tab titles in Russian and Brazilian Portuguese now fit.** They were too long.

## 4.0.3 - 2026-10-02

### Fixed
- **BatFi's newer messages now appear in your language.** If you use BatFi in a language other
  than English, some of the messages added in BatFi 4 showed up in English, or as an internal
  identifier instead of a sentence — for example when macOS charges your battery to 100% on its
  own, when BatFi holds the battery at 100% until you unplug, when your charge limit isn't
  holding, and the warning that running on battery keeps your Mac from sleeping. These messages
  had never been translated. They're now available in all 13 languages BatFi is translated into.

## 4.0.2 - 2026-09-25

### Fixed
- **Closing the menu can no longer leave BatFi frozen.** On rare occasions, closing the menu
  froze BatFi's menu bar icon: it stopped responding to clicks, and the only way out was to
  force quit the app. Your charge limit kept working the whole time, because the part of BatFi
  that enforces it runs separately and was never affected. The cause was a bug in a third-party
  library BatFi uses to combine several live readings into one — stopping it at the wrong moment
  could lock it up. BatFi now uses a version of that library in which the bug is fixed.

## 4.0.1 - 2026-09-16

### Fixed
- **Charging to 100% no longer drains straight back down to your limit while the charger is
  still plugged in.** Asking BatFi to charge to 100% did exactly that, and then — the moment
  the battery arrived — handed control back to your ordinary limit, which found a full battery
  sitting well above it. With "Discharge battery when overcharged" turned on, BatFi began
  running the battery down again within seconds of filling it, and spent the next twenty
  minutes undoing what you had just asked for. BatFi now keeps the battery at 100% once it
  gets there and leaves it there until you unplug the charger, saying so in the menu. Your
  limit — and the discharge, if you have it enabled — take over from the unplug onwards.
- **Lowering your charge limit below the current battery level no longer announces that macOS
  is charging to 100%.** Lowering the limit puts the battery above it immediately, and macOS
  responds by running the battery down to the new limit — but the system goes on reporting a
  charge in progress for up to a minute after the current has already reversed. BatFi believed
  that report, so the menu named Apple's occasional charge to 100% and sent a notification
  saying so, while the power distribution directly below it showed nine watts leaving the
  battery. BatFi now reads which way the current is actually flowing rather than taking the
  system's word for it, and only falls back to that word when the battery is resting and there
  is no current to read. The same reading also keeps a discharge macOS performs on purpose from
  being mistaken for your limit failing to hold.
- **A charge limit below 80% is no longer reported as failed while it is still being applied.**
  Limits below 80% take a route through macOS that can take up to 45 seconds to be accepted, and
  BatFi gave up waiting after 15 — closing the connection to its helper 30 seconds before the
  answer arrived, logging a failure for a limit that was on its way in, and then working from a
  limit that was never in force. BatFi now waits as long as the request can legitimately take.

## 4.0.0 - 2026-08-05

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
- **"Charge to 100%" no longer switches itself off the moment you switch it on.** Both rules
  that retire a temporary override — the two-minute cleanup after the charger comes out, and
  "the battery reached 100%, so this is done" — read the state the click landed in, with no way
  to tell whether that state predated the click. An override switched on while the Mac was
  already running on battery was therefore born past the cleanup deadline and disappeared on the
  next status pass, which is why the first click looked like it did nothing and the second one
  worked. Switching it on with the battery already reading 100% failed the same way through the
  other rule — and that reading persists well into a discharge, so it covered exactly the moment
  the command is worth using. Both rules now measure from the moment the override was switched
  on. It stays on until you turn it off or the charger has genuinely been gone for two minutes,
  and switching it on at 100% holds the charge there rather than handing the battery straight
  back to the limit.
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
- **When macOS refuses to start the helper, BatFi now says exactly how to fix it instead of
  reporting a fault it cannot repair.** macOS attaches a launch constraint to the background
  helper's registration, derived from the copy of BatFi that registered it. If that copy is
  later deleted — one run once from a disk image or Downloads, or a build directory since
  cleaned — the constraint can no longer be resolved and macOS refuses to start the helper at
  all, while still reporting the registration as enabled. BatFi used to answer this by
  unregistering and registering again, which cannot help: unregistering leaves the record in
  place and merely disables it, so registering re-finds the same one and reports success while
  nothing changes. BatFi now recognises when its own repair has made no difference and asks you
  to turn BatFi off and back on in Login Items — the one action that clears the record, and one
  only you can perform — instead of telling you the helper isn't responding and leaving you to
  guess. It also stops re-registering once it knows that won't work, which macOS was rate
  limiting BatFi for, and waits out the delay macOS imposes after a failed start before
  concluding anything, so a helper that was simply slow to come up is no longer reported as
  broken.
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

## 3.1.1 - 2026-06-19

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

## 3.1.0 - 2026-06-03

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

## 3.0.5

### Fixed
- Restore the system charging defaults when BatFi disengages, so charging behaves normally
  after the app stops managing it.
- Defer the menu rebuild on macOS 26 while the menu is open, fixing a blank area at the top
  of the dropdown.
