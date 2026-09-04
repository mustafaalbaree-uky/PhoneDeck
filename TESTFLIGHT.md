# Moving the iPhone apps to TestFlight

Written 21 Aug 2026, from the question "can my phone detect a push to main and
update itself." Short answer: not on free provisioning, and this is the route
that makes it true.

## What is actually blocking it today

A sideloaded app cannot install a new build of itself. There is no iOS API for
it, at any privilege level available without a paid account. OTA install is
App Store, TestFlight, MDM, or enterprise distribution, and nothing else. Every
workaround at the free tier ends at the same place: the Mac does the install
over the cable or over Wi-Fi, and the phone is a passenger.

The second, larger cost is the seven day provisioning clock, which is the whole
reason PhoneDeck exists.

## What $99 a year buys

| | Free Apple ID today | Paid account + TestFlight |
|---|---|---|
| Install a new build | Mac must build and push it | Phone downloads it, anywhere |
| Profile lifetime | 7 days, then the app dies | 90 days per build |
| Apps installed at once | 3 | Unlimited |
| Mac required | Yes, for every reinstall | Only to build, and CI can do that |
| Push notifications | Not available | Available |
| Widgets and Live Activities | Work, but die with the profile | Work |

The 3-app limit is worth noticing: it is why `AutoReinstallSettings.maxAutoReinstallApps`
is 3 and why only Shadiliya, ClipKeyboard and OnTime are starred. That
constraint disappears too.

## The pipeline

1. **Enroll.** developer.apple.com, Apple Developer Program, $99/yr. Individual
   enrollment, not organization: no D-U-N-S number, usually approved in a day
   or two.
2. **App Store Connect record per app.** One per bundle id. The three ids
   already exist and stay as they are: `com.mammer55.hu` (Shadiliya, renamed
   from Hu but the id deliberately never changed), `com.mammer55.clipkeyboard`,
   `com.mammer55.ontime`.
3. **Signing.** Switch each `project.yml` from automatic free provisioning to a
   distribution certificate and an App Store provisioning profile. XcodeGen
   handles this in the target settings; the install scripts' profile-deletion
   block becomes dead code and should be removed rather than left to confuse
   the next reader.
4. **CI.** A GitHub Actions workflow per repo, on push to main: `xcodegen
   generate`, `xcodebuild archive`, `xcodebuild -exportArchive`, then
   `xcrun altool --upload-app` or Fastlane's `pilot`. Secrets needed are an App
   Store Connect API key (issuer id, key id, .p8), the distribution certificate
   as a base64 .p12, and its password.
5. **Internal testing group.** Add yourself. Internal builds skip App Review
   entirely and are available within minutes of processing. This is the part
   that makes it feel like what you described: push to main, phone buzzes,
   tap update.

Build numbers have to increase monotonically across uploads. Use the GitHub run
number, not a timestamp: `CURRENT_PROJECT_VERSION = $GITHUB_RUN_NUMBER`.

## What happens to PhoneDeck

Most of it becomes unnecessary, and that is the honest read. `ProvisioningProfiles`,
`ExpiryInfo`, `AutoReinstall`, the whole expiry-warning surface, all of it exists
to fight a seven day clock that TestFlight removes.

Three parts survive and are worth keeping:

- `Installer` and the `tools/install.sh` scripts stay the fastest path for
  iterating on a change without waiting on CI and TestFlight processing. Build
  and install over Wi-Fi is still seconds against minutes.
- `DeviceMonitor` and the wireless-presence logic (`connectionProperties.transportType`,
  never the State column) is the piece that took the longest to get right and is
  reusable for anything that talks to the phone.
- The registry itself is a useful index of what is installed and where its repo
  lives.

The sensible end state is PhoneDeck as a developer tool for fast local installs,
with the expiry machinery deleted rather than left running against a condition
that can no longer occur. Deleting it is the tell that the migration finished.

## Migrate one app first

ClipKeyboard. It is the smallest, it has a keyboard extension so it proves the
multi-target signing case, and if the pipeline is wrong it is the least
disruptive of the three to have broken for a day. Shadiliya last, since it holds
the most data and its bundle id has the most history behind it.
