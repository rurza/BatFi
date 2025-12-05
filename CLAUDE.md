# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BatFi is a macOS menu bar application for intelligent battery charging management on Apple Silicon Macs. It allows users to set custom charge limits and control when the battery charges to 100%, extending battery lifespan.

**Requirements**: macOS Ventura (13.0) or later, Apple Silicon Mac

## Build & Development

This is an Xcode project with a Swift Package Manager local package. Open `BatFi.xcodeproj` in Xcode.

**Schemes**:
- `BatFi` - Main app (release)
- `BatFi Beta` - Beta channel build
- `Helper` - Privileged helper daemon
- `Installer` - Helper installation component

**Code formatting**: SwiftFormat with `.swiftformat` configuration
```bash
swiftformat .
```

## Architecture

### Multi-Process Design

BatFi uses a **privileged helper architecture** for SMC (System Management Controller) access:

```
┌─────────────────┐         XPC          ┌─────────────────┐
│   BatFi.app     │◄───────────────────► │     Helper      │
│   (Main App)    │                      │  (LaunchDaemon) │
│                 │                      │                 │
│  Menu bar UI    │                      │  SMC commands   │
│  Settings       │                      │  Power control  │
│  Notifications  │                      │  MagSafe LED    │
└─────────────────┘                      └─────────────────┘
```

- **App** (`App/`): Entry point, App Intents for Siri Shortcuts
- **Helper** (`Helper/`): Privileged daemon that communicates with SMC

### BatFiKit Package Structure

Local Swift package at `BatFiKit/` containing all core modules:

| Module | Purpose |
|--------|---------|
| `App` | Main app coordinator (`BatFi` class), lifecycle management |
| `AppCore` | Core business logic - `ChargingManager`, `StatusItemManager` |
| `Clients` | Protocol definitions for all system interfaces |
| `ClientsLive` | Live implementations including `XPCClient` for helper communication |
| `Server` | Helper daemon XPC listener and service implementation |
| `Shared` | Types shared between app and helper (`XPCService` protocol, `SMCChargingStatus`) |
| `Settings` | Settings UI and `SettingsController` |
| `Onboarding` | First-run setup flow with helper installation |
| `L10n` | Localization (String Catalogs at `L10n/Localizable.xcstrings`) |

### Key Patterns

**Dependency Injection**: Uses [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) throughout. Clients are defined as protocols in `Clients/`, with live implementations in `ClientsLive/`.

**Settings/Defaults**: User preferences via [Defaults](https://github.com/sindresorhus/Defaults) library. Keys defined in `DefaultsKeys/DefaultsKeys.swift`.

**Async Streams**: Reactive state observation using `AsyncAlgorithms` with `combineLatest` for multiple stream coordination (see `ChargingManager.setUpObserving()`).

### XPC Communication

The app communicates with the helper via XPC:
- Protocol: `XPCService` in `Shared/XPCService.swift`
- Client: `XPCClient` actor in `ClientsLive/XPCClient.swift`
- Server: `Server` class in `Server/Server.swift`

Service name: `software.micropixels.BatFi.Helper`

### Charging Modes

Managed in `AppCore/ChargingManager.swift`:
- `charging` - Normal charging enabled
- `inhibit` - Charging paused at current level
- `forceDischarge` - Discharge battery while connected to power

## Localization

Uses Xcode String Catalogs (`.xcstrings`):
- App UI: `BatFiKit/Sources/L10n/Localizable.xcstrings`
- App Intents: `App/Localizable.xcstrings`

## CI/CD

Xcode Cloud scripts in `ci_scripts/`:
- `ci_post_clone.sh` - Generates `AnalyticsDSN.swift` from environment variables
- `ci_post_xcodebuild.sh` - Post-build processing
