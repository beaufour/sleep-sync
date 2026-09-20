# Sleep Sync

Sleep Sync is a small SwiftUI iPhone app that reads Sleep Analysis from
HealthKit, groups the last 14 days of stages into sessions, and atomically writes
deterministic JSON to a user-selected iCloud Drive folder.

The repository also contains `sleepd`, the original Swift 5.9 macOS
command-line implementation. It is retained as a reference and for its shared
session-building tests, but current macOS releases do not expose a readable
HealthKit store.

## Important macOS limitation

This program compiles on macOS 14+, but it **cannot retrieve HealthKit data on
macOS**. Apple ships the HealthKit framework on macOS 13 and later for source
compatibility, while explicitly documenting that macOS apps cannot read or write
HealthKit data and that `HKHealthStore.isHealthDataAvailable()` returns `false`:

- [Apple: `isHealthDataAvailable()`](https://developer.apple.com/documentation/healthkit/hkhealthstore/ishealthdataavailable())
- [Apple: Setting up HealthKit](https://developer.apple.com/documentation/healthkit/setting-up-healthkit)

iCloud does not create a Mac-readable HealthKit store. Code signing, the
HealthKit entitlement, and the usage-description key are necessary on supported
platforms, but they do not remove this platform restriction. Consequently, a
macOS build exits with a clear error before requesting authorization and cannot
produce real `sleep.json` data.

A workable architecture is an iPhone app (or an iPhone Shortcut) that reads
HealthKit and writes JSON to iCloud Drive. The Mac can then expose that synced
file to the container. This repository now includes that iOS app.

## iPhone app (Sleep Sync)

The Xcode project is `ios/SleepSync.xcodeproj`. Sleep Sync requires iOS 17 or
later and:

- requests read-only access to Sleep Analysis;
- exports immediately after authorization and when brought to the foreground;
- registers a HealthKit observer with immediate background delivery;
- retries after protected Health data becomes available when the phone unlocks;
- lets you choose an output folder in Files and remembers that folder with a
  security-scoped bookmark;
- writes the same deterministic, atomic `sleep.json` format described below.

Background delivery is event-driven and controlled by iOS; `.immediate` is a
maximum delivery frequency, not a guaranteed timer.

### Install on an iPhone

1. Connect and unlock the iPhone, trust this Mac, and enable Developer Mode if
   iOS requests it.
2. Open the project:

   ```sh
   open ios/SleepSync.xcodeproj
   ```

3. Select the `SleepSync` scheme and the physical iPhone destination.
4. In **Signing & Capabilities**, select your Apple development team. Change the
   bundle identifier if `dev.beaufour.SleepSync` is not available to your team.
5. Press **Run**. If Keychain asks whether `codesign` may use the Apple
   Development private key, choose **Always Allow**.
6. On first launch, grant Sleep Sync access to Sleep Analysis.
7. Tap **Choose Output Folder**, create or select `Sleep Sync` under iCloud
   Drive, then tap **Open**.

The app immediately writes `sleep.json` and shows the sample count, session
count, last export time, and any error. Use **Export Now** to verify it again.

If the selected iCloud Drive folder is named `Sleep Sync`, the expected Mac
path is:

```text
~/Library/Mobile Documents/com~apple~CloudDocs/Sleep Sync/sleep.json
```

Verify it on the Mac with:

```sh
jq 'length' "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Sleep Sync/sleep.json"
```

That `Sleep Sync` directory is the folder to bind to the container as
`/opt/data`, making the container path `/opt/data/sleep.json`.

### Command-line Xcode build

The active `xcode-select` path currently points at Command Line Tools, so use
the full Xcode path explicitly:

```sh
cd /path/to/sleep-sync
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project ios/SleepSync.xcodeproj \
  -scheme SleepSync \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  build
```

HealthKit background delivery and real sleep data must be tested on a physical
iPhone; the Simulator cannot perform that verification.

## Output format and grouping

If Apple enables HealthKit data access on macOS in the future, the current
implementation writes an array like this:

```json
[
  {
    "bed_start": "2026-09-19T03:12:00.000Z",
    "wake_end": "2026-09-19T11:04:00.000Z",
    "duration_minutes": 472,
    "source": "Sleep Cycle",
    "stages": [
      {
        "stage": "asleepCore",
        "start": "2026-09-19T03:20:00.000Z",
        "end": "2026-09-19T03:46:00.000Z"
      }
    ]
  }
]
```

Samples are grouped by source first so overlapping Apple Watch and Sleep Cycle
records do not produce a session with an ambiguous `source`. Within each source,
samples separated by less than two hours are one session. Sessions are sorted by
`wake_end` descending, and stages are sorted chronologically.

## Build and test

Requirements:

- macOS 14 or later
- Full Xcode with its matching macOS SDK selected
- Swift 5.9 or later
- An Apple Development certificate for signing

Select Xcode and verify the toolchain:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
swift --version
xcodebuild -version
```

Build and run the unit tests:

```sh
cd /path/to/sleep-sync
swift test
```

List signing identities and make a signed release build:

```sh
security find-identity -v -p codesigning
./scripts/build-signed.sh "Apple Development: Your Name (TEAMID)"
```

The script builds with SwiftPM, embeds `Resources/Info.plist`, and signs the
result with `Sleep.entitlements`. If the identity argument is omitted, it uses
the first `Apple Development` identity it finds.

If `xcode-select` points at Command Line Tools, either select the full Xcode app
with the command above or set
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for individual build
commands. Xcode automatic signing can create/select an Apple Development
certificate and provisioning profile. A first interactive build may show a
Keychain prompt for private-key access.

## Run

The CLI syntax is:

```sh
./.build/release/sleepd [output-path] [--watch minutes]
```

Examples:

```sh
# Default: ./sleep.json, then exit
./.build/release/sleepd

# Explicit host path, then exit
./.build/release/sleepd "$PWD/sleep.json"

# Keep the process alive and query every 15 minutes
./.build/release/sleepd "$PWD/sleep.json" --watch 15
```

Watch mode compares the encoded JSON with the existing file and only performs
the atomic temp-file/rename operation when bytes have changed.

The checked-in container handoff path is:

- Mac: `/path/to/sleep-sync/sleep.json`
- Container, if that Mac directory is mounted at `/opt/data`:
  `/opt/data/sleep.json`

Change the second argument in `launchd/dev.beaufour.sleepd.plist` if the actual
Mac source directory for the container's `/opt/data` mount is different.

## launchd example

The included LaunchAgent runs once every 15 minutes. It intentionally does not
also pass `--watch`; launchd owns the schedule.

Before loading it, replace every `/ABSOLUTE/PATH/TO/sleep-sync` placeholder in
the plist with the repository's absolute path.

```sh
mkdir -p "$HOME/Library/LaunchAgents"
cp launchd/dev.beaufour.sleepd.plist "$HOME/Library/LaunchAgents/"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/dev.beaufour.sleepd.plist"
launchctl kickstart -k "gui/$(id -u)/dev.beaufour.sleepd"
```

Logs are written to:

```text
/path/to/sleep-sync/sleepd.log
/path/to/sleep-sync/sleepd.error.log
```

To unload it:

```sh
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/dev.beaufour.sleepd.plist"
```

Do not install the LaunchAgent expecting data on current macOS releases; it will
only log the unsupported-platform error described above.
