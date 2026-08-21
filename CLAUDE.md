# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

PhoneDeck is a macOS menu bar app (SwiftUI + AppKit, no Dock icon). It tracks the 7 day expiry that free Apple ID provisioning puts on sideloaded iPhone apps, and reinstalls them (which resets the clock) either by hand or unattended when the phone is reachable.

## Build and run

```
./build.sh              # release build, sign, install to /Applications, relaunch
./build.sh --no-install  # build and sign into ./build only, no install/relaunch
./build.sh --debug       # debug configuration
```

There is no separate test suite or lint step; `swift build` is the only verification available. `build.sh` uses `swift build --disable-sandbox` because the reinstall scripts it eventually shells out to need network and process access the sandbox blocks.

Signing prefers a real "Apple Development" or "Developer ID Application" identity found via `security find-identity`, falling back to ad hoc signing. Override with `PHONEDECK_SIGN_ID`.

## Architecture

**Registry, not discovery, drives what PhoneDeck can act on.** `AppRegistry.known` (`Sources/PhoneDeck/AppRegistry.swift`) is a hardcoded array of `KnownApp` entries, each with a bundle ID, repo path, and reinstall script path. Only apps listed there can be reinstalled. `AppRegistry.scanForUnregistered()` separately walks `~/Code` for stray `.xcodeproj` directories not covered by a known app, purely so a new iOS project is visible in the UI rather than invisible until someone remembers to register it, it never becomes installable through discovery alone.

Registering a new app (see the user's global CLAUDE.md for the full checklist) always means: the target repo gets a `tools/install.sh` that builds, installs via `devicectl`, and stamps `~/.<shortname>/last_install` with the current epoch seconds on success, and this repo's `AppRegistry.known` gets a matching entry, then a rebuild of PhoneDeck itself.

**Expiry is read two ways, and the two disagree in ways that matter.** `ExpiryInfo.swift` prefers `ProvisioningProfiles.earliestExpiry(forBundleID:)`, the real expiry pulled from the profile on disk (`isMeasured: true`). Absent a profile, it estimates `last_install + 7 days` from the state file's stamp (`isMeasured: false`), flagged as a guess because Xcode's habit of reusing a still-valid profile means a fresh install can inherit an expiry only days away, not a fresh 7.

**Device presence is polled, not pushed, and gates on one specific JSON field.** `DeviceMonitor` polls `xcrun devicectl list devices` every 3 seconds. It filters on `connectionProperties.transportType` (`wired` or `localNetwork`), not on the `State` column or `tunnelState`, both of which flip during devicectl's own tunnel setup/teardown even while the physical link never moves. This was tuned through real flapping bugs; do not reintroduce a `State`/`tunnelState` check without reading the comment above `queryDevicectl()` first.

**Reinstall is one code path for both manual and unattended runs.** `AppState.performInstalls(_:)` is called by both `reinstallSelected()` (user pressed the button) and the auto loop (`AutoReinstall.swift`), running each app's script via `Installer.run`, which streams merged stdout/stderr line by line into `statusLine` for live UI feedback. Scripts run under `bash -l` specifically so `/opt/homebrew/bin` (Homebrew, `pod`, `xcodegen`) is on PATH, a GUI app's inherited PATH is the bare macOS default.

**Unattended reinstall is opt in per app and always announces itself first.** At most `AutoReinstallSettings.maxAutoReinstallApps` (3, matching the free Apple ID sideload cap) apps can be starred for auto-reinstall; everything else in the registry stays manual-only forever. A due app doesn't reinstall immediately: `armAuto` sets a `PendingAuto` with a 5 minute `fireAt`, notifies, and only then fires, giving a real window to cancel or skip. This mirrors the user's general "nothing acts on its own without warning" preference from their global CLAUDE.md, even though PhoneDeck (unlike tools built for the user's supervisor) is allowed to default this feature on.

**Two UIs share one state object.** `RootView` switches between `ContentView` (current) and `ClassicContentView` (old, kept behind a right-click toggle, `LookSettings.useClassic`) purely as a user preference; both bind to the same `AppState` and `DeviceMonitor` instances, there is no functional difference in what they can do.

## File map

- `AppRegistry.swift` — the hardcoded list of installable apps, and the `~/Code` scanner for unregistered ones
- `AppState.swift` — `@MainActor` `ObservableObject` root: rows, selection, manual install flow, auto-reinstall settings surface
- `AutoReinstall.swift` — the unattended reinstall state machine (`AppState` extension) and its persisted settings (`AutoReinstallSettings`)
- `DeviceMonitor.swift` — polls devicectl for phone presence/transport
- `Installer.swift` — runs a reinstall script as a subprocess, streaming output
- `ExpiryInfo.swift` / `ProvisioningProfiles.swift` — expiry computation from install-date state files and on-disk provisioning profiles
- `NotificationManager.swift` — local notifications for pending/finished/unreachable auto-reinstall events
- `AppDelegate.swift` — menu bar item, popover wiring, launch-at-login registration
- `RootView.swift` / `ContentView.swift` / `ClassicContentView.swift` — the two SwiftUI UIs
- `LoginItem.swift`, `Theme.swift`, `AppIcons.swift` — small support utilities
