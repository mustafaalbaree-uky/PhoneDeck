# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

PhoneDeck is a macOS menu bar app (SwiftUI + AppKit, no Dock icon). It is the one place to rebuild and install Mustafa's iPhone apps to the phone: pick the apps, press the button, watch the build output stream past.

**It used to be an expiry tracker, and it is not one any more.** Free Apple ID provisioning killed a sideloaded app seven days after the profile was issued, so PhoneDeck counted days, starred at most three apps for unattended renewal, warned before each one fired, and scheduled notifications for the ones about to lapse. Mustafa moved to a paid Apple Developer Program membership on 29 Aug 2026, on the same team ID (34ZCK63GEC), and profiles now last a year. All of that machinery is gone: no expiry reading, no day ring or badge, no stars or slots, no auto reinstall loop, no scheduled warnings. Do not reintroduce any of it. If a year long expiry ever needs surfacing, that is a new feature and a new conversation, not a restoration of the old one.

## Build and run

```
./build.sh              # release build, sign, install to /Applications, relaunch
./build.sh --no-install  # build and sign into ./build only, no install/relaunch
./build.sh --debug       # debug configuration
```

There is no separate test suite or lint step; `swift build` is the only verification available. `build.sh` uses `swift build --disable-sandbox` because the install scripts it eventually shells out to need network and process access the sandbox blocks.

Signing prefers a real "Apple Development" or "Developer ID Application" identity found via `security find-identity`, falling back to ad hoc signing. Override with `PHONEDECK_SIGN_ID`.

## Architecture

**Registry, not discovery, drives what PhoneDeck can act on.** `AppRegistry.known` (`Sources/PhoneDeck/AppRegistry.swift`) is a hardcoded array of `KnownApp` entries, each with a bundle ID, repo path, and install script path. Only apps listed there can be installed. `AppRegistry.scanForUnregistered()` separately walks `~/Code` for stray `.xcodeproj` directories not covered by a known app, purely so a new iOS project is visible in the UI rather than invisible until someone remembers to register it. It never becomes installable through discovery alone.

Registering a new app (see the user's global CLAUDE.md for the full checklist) always means: the target repo gets a `tools/install.sh` that builds, installs via `devicectl`, and stamps `~/.<shortname>/last_install` with the current epoch seconds on success, and this repo's `AppRegistry.known` gets a matching entry, then a rebuild of PhoneDeck itself.

**`last_install` is a record, not a countdown.** `InstallRecord.swift` reads a timestamp and nothing else, and the UI renders it as "Installed Aug 29, 10:11 AM". It answers whether the build on the phone is the one you made after your last change. It is not a clock, and nothing in the app derives a deadline from it.

There are two stamps now that more than one phone is in play. `last_install` is the original file, written on every install wherever the build went, so a date read from it cannot say which phone got it. `last_install_<UDID>` is written alongside it and can. `InstallRecord.reading(stateDir:deviceID:)` prefers the per phone stamp, falls back to `last_install` only for an app with no per phone history at all (everything installed before the picker existed), and otherwise reports `.notThisDevice`, which the UI renders as "Never installed to this iPhone".

**Device presence is polled, not pushed, and gates on one specific JSON field.** `DeviceMonitor` polls `xcrun devicectl list devices` every 3 seconds while the popover is open and every 20 seconds while it is closed (`setForeground`, driven by `AppDelegate`), so a phone arriving opens the popover within 20 seconds rather than 3. The popover's SwiftUI tree is likewise built on open and dropped on close, because a hosting controller left alive keeps rendering its repeating animations off screen. It filters on `connectionProperties.transportType` (`wired` or `localNetwork`), not on the `State` column or `tunnelState`, both of which flip during devicectl's own tunnel setup and teardown even while the physical link never moves. This was tuned through real flapping bugs; do not reintroduce a `State` or `tunnelState` check without reading the comment above `queryDevicectl()` first.

**Which phone gets the build is Mustafa's choice, and a choice made is honoured strictly.** `DeviceMonitor` keeps every reachable iPhone in `devices`, sorted cabled first, and `target` resolves the one an install would go to. With nothing picked, `target` is the automatic pick (a cabled phone, else the first) and the header looks the way it always did. `choose(_:)` pins a phone by hardware UDID and remembers it in `UserDefaults`, and from then on `target` is that phone or nothing: when the picked phone is away, PhoneDeck says so, disables Install, and does **not** fall through to another reachable phone. That refusal is the point of the feature. Several of the phones on this network belong to other people (Amanah installs to his mother's), and silently installing to the wrong one is the failure being designed out. The header turns into a menu only when there is a choice to make (`devices.count > 1`, or a phone already picked), so a one phone day is unchanged.

**The chosen phone reaches the install scripts through the environment.** `AppState.installSelected()` refuses to start without a resolved `target`, then `Installer.run` layers `PHONEDECK_DEVICE_ID` (the hardware UDID, which is what `xcodebuild -destination id:` and `devicectl device install --device` both want) and `PHONEDECK_DEVICE_NAME` over PhoneDeck's own environment. Every registered script reads `PHONEDECK_DEVICE_ID` and builds for that phone instead of choosing one; with the variable unset, which is how the script runs from a terminal, it falls back to the first destination `xcodebuild -showdestinations` lists exactly as before. A new app's `tools/install.sh` has to honour it too, or PhoneDeck's picker will be a lie for that one app.

**Every install is something Mustafa pressed.** `AppState.installSelected()` is the only entry point. It runs each app's script through `Installer.run`, which streams merged stdout and stderr line by line into `statusLine` for live UI feedback. Scripts run under `bash -l` specifically so `/opt/homebrew/bin` (Homebrew, `pod`, `xcodegen`) is on PATH, since a GUI app's inherited PATH is the bare macOS default. Nothing builds or installs on a timer, on a phone connecting, or on any other trigger.

**One notification, and it is a result rather than a prompt.** `NotificationManager.installFinished` fires when the last selected app finishes, because a build takes minutes and the popover closes the moment you click away. Clicking the banner reopens the popover. There are no scheduled notifications and no notification actions.

**Two UIs share one state object.** `RootView` switches between `ContentView` (current) and `ClassicContentView` (old, kept behind a right-click toggle, `LookSettings.useClassic`) purely as a user preference; both bind to the same `AppState` and `DeviceMonitor` instances, there is no functional difference in what they can do.

## File map

- `AppRegistry.swift` — the hardcoded list of installable apps, and the `~/Code` scanner for unregistered ones
- `AppState.swift` — `@MainActor` `ObservableObject` root: rows, selection, and the install flow
- `InstallRecord.swift` — reads an app's install stamps, per phone and overall
- `DeviceMonitor.swift` — polls devicectl for reachable phones, and holds the picked one
- `Installer.swift` — runs an install script as a subprocess, streaming output
- `NotificationManager.swift` — the single install result notification
- `AppDelegate.swift` — menu bar item, popover wiring, launch at login registration
- `RootView.swift` / `ContentView.swift` / `ClassicContentView.swift` — the two SwiftUI UIs
- `LoginItem.swift`, `Theme.swift`, `AppIcons.swift` — small support utilities
