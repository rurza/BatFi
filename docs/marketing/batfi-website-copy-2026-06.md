# BatFi — Website Copy Refresh (micropixels.software/apps/batfi)

Repositioned for the post-macOS-26 landscape: macOS now ships a basic charge limit,
so the copy concedes that and pivots to what BatFi does that the built-in toggle can't —
automation by time/place, on-demand discharge, power-mode hotkeys, and battery insight.

Voice: clean, confident prose, no emoji (matches the existing Squarespace page).

---

## Hero

**BatFi**

Requirement line: **macOS Sonoma or newer · Mac with Apple Silicon required**
> ⚠️ Confirm the BatFi app target's minimum macOS (project shows 14.x) and set this accordingly.
> The current site says "macOS Ventura or newer," which is out of date.

Download .dmg   ·   or   ·   `brew install --cask batfi`
A license is required. Obtain one here.

**Intro** (replaces "set a charging limit once, and then you can forget about it"):

BatFi is a native, lightweight menu-bar app that gives you real control over how your Mac
charges. Set a charge limit and hold it indefinitely, automate it by time and place, charge
to 100% the moment you need it, run on battery on demand, and see exactly what's using your
power — well beyond the on/off limit built into macOS.

---

## Why?

Keeping a lithium-ion battery at a high state of charge shortens its life — a real problem if
your Mac lives on a Studio Display or Pro Display XDR and sits at 100% all day.

macOS now lets you cap charging at 80%, and its older Optimised Battery Charging tries to
delay full charges with machine learning. Both help, and both are blunt: the limit is one
fixed percentage with no sense of schedule or place, and Optimised Charging is invisible and
out of your hands.

BatFi gives you the control they don't. Choose any limit and hold it indefinitely. Change it
automatically based on when and where you are. Charge to 100% the instant you need it. And
when you want to, run your Mac off the battery on purpose.

---

## Key Features

### Custom Charge Limit, Held Indefinitely
BatFi launches with your system and watches your battery level. Once it reaches your limit
(yours to set, or 80% by default), the app stops charging while on AC power — and keeps
holding it, for as long as you want. No machine-learning guesswork.

### Automation by Time and Place
Set rules instead of a single number. Hold at 60% at your desk, top up to 90% before you head
out, charge fully on weekends. Each rule can be gated by a schedule — a one-off date or
repeating days and a time window — and by a location, with a map picker, address search,
current-location, and an adjustable radius. Rules are an ordered list, so the top one that
matches right now wins. The menu bar always shows which rule is active and the limit it's
enforcing.

### Charge to 100% — or Run on Battery — on Demand
Need a full charge before a flight? One click from the menu, or a global keyboard shortcut.
Want to deliberately discharge to recalibrate or test? Switch to Run on Battery and BatFi
drains the battery with the lid open.

### Power Modes From the Keyboard
Toggle Low Power Mode, High Power Mode, or Automatic without opening System Settings. Assign a
global hotkey and switch from anywhere.

### Battery and Energy Insight
Click the status icon for the numbers macOS keeps buried: battery health, cycle count,
temperature, time to full, time remaining, and a power-usage graph. BatFi also lists the apps
using significant energy right now, so you know what to quit.

### Informative Notifications
Stay aware when your charging mode changes — and when an automation rule is overriding your
usual limit, BatFi tells you which rule and what limit it's applying. It'll also remind you
when it's time to fully cycle the battery for calibration.

### Customizable Status Icon
The menu-bar icon shows your battery percentage and charging status, with smooth animations as
the state changes. Style it to taste.

### Native and Out of Your Way
A real macOS app — no Electron, no account. Configure it once and it runs quietly in the
background, speaking up only when something changes. Localized into 14 languages.

---

## FAQ

### I can't find my license key. How can I recover it?
*(unchanged — still accurate)*
Search for an email from the store with a subject line starting with "You bought BatFi." and
click the "View Content" button. If you can't find your license and are certain you have one,
use the contact form and provide the email address you used for the purchase. If you used a
temporary or fake email address, unfortunately I won't be able to assist you, and you'll need
to purchase the app again. Please don't contact me about a license if you haven't purchased
the app.

### Why not just use the charge limit built into macOS?
*(replaces the old "How is it better than Optimised Battery Charging?" question)*
The built-in limit does one thing: hold your battery at 80%. BatFi does that too — at any
limit from 50% to 90% — and adds what the toggle can't: rules that change the limit by time
and location, one-click charging to 100%, deliberate discharge / Run on Battery, power-mode
hotkeys, and a full read-out of battery health and energy use. macOS's older Optimised Battery
Charging is different again — it guesses when to delay a full charge using machine learning,
with no way to set or hold a level yourself. BatFi puts that decision in your hands.

### Why isn't it on the Mac App Store?
*(unchanged)*
The Mac App Store prohibits apps that require an admin password to function. BatFi needs that
password to change the charging mode, so it can't be distributed there.

### Where can I find the changelog?
*(unchanged)* It's available here.

---

## Support
Leave this section as-is — it's accurate troubleshooting (sleep behavior, Login Items, .dmg
mounting), not marketing copy, so rewriting it risks introducing wrong steps.
- Small fix: correct the typo "BaFi.app" → "BatFi.app".

---

## Meta / Open Graph

**Page title** (current: "BatFi – maximize your Mac's battery lifespan — micropixels"):
- Keep as-is, or → "BatFi – battery charge control & automation for Mac — micropixels"

**Meta description / og:description / twitter:description**
(replaces "set a charging limit once… charging to 100% only when it's needed"):
- A (recommended, ~145 chars): "Real battery control for your Mac. Set a charge limit, automate it by time and place, run on battery on demand, and see what's draining your power."
- B (feature-forward): "Go beyond the macOS charge limit — automate charging by time and place, run on battery, switch power modes, and track battery health, all from the menu bar."

---

## Pre-publish checklist
1. Remove or re-date the Szlachetna Paczka donation banner (currently "Dec 2–6", reads as live).
2. Confirm the macOS requirement line against the BatFi app target (looks like 14.x → "Sonoma or newer").
3. Fix the "BaFi.app" typo in the Support section.
4. Update og:description / meta description (and optionally page title) per above.
