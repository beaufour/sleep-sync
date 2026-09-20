# Sleep Sync

Sleep Sync is a small SwiftUI iPhone app that reads Sleep Analysis from
HealthKit, groups the last 14 days of sleep stages into sessions, and writes
deterministic JSON to a user-selected iCloud Drive folder.

## Features

- Read-only access to HealthKit Sleep Analysis
- Core, deep, REM, unspecified, awake, and in-bed stages
- Sessions grouped by source and separated by gaps of two hours or more
- Automatic export after authorization and whenever the app becomes active
- HealthKit observer with immediate background delivery
- Retry after protected Health data becomes available when the phone unlocks
- Atomic writes that avoid replacing an unchanged file
- Persistent access to a user-selected Files folder

Background delivery is event-driven and controlled by iOS. `.immediate` is the
maximum notification frequency, not a guaranteed schedule.

## Requirements

- iOS 17 or later
- Xcode 15 or later
- An Apple development team capable of using HealthKit
- A physical iPhone; HealthKit background delivery cannot be verified in the
  Simulator

## Install

1. Clone the repository and open the project:

   ```sh
   git clone https://github.com/beaufour/sleep-sync.git
   cd sleep-sync
   open ios/SleepSync.xcodeproj
   ```

2. Select the `SleepSync` target, open **Signing & Capabilities**, and select
   your development team.
3. Change the bundle identifier if `dev.beaufour.SleepSync` is unavailable to
   your team.
4. Connect and unlock an iPhone, trust the Mac, and enable Developer Mode if
   requested.
5. Select the physical iPhone as the run destination and press **Run**.
6. Grant read access to Sleep Analysis on first launch.
7. Tap **Choose Output Folder** and select or create a folder in iCloud Drive.

The app immediately exports and displays the sample count, session count, last
export time, and any error. **Export Now** performs an on-demand refresh.

## Output location

If the selected folder is named `Health Sync`, the corresponding Mac path is:

```text
~/Library/Mobile Documents/com~apple~CloudDocs/Health Sync/sleep.json
```

For example:

```sh
jq 'length' "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Health Sync/sleep.json"
```

To make the data available to a container as `/opt/data/sleep.json`, bind-mount
the selected iCloud Drive folder to `/opt/data` using your existing container
configuration.

## JSON format

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

Samples are grouped by source so overlapping records from different apps do not
produce an ambiguous `source`. Sessions are sorted by `wake_end` descending;
stages are sorted chronologically.

## Command-line build

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project ios/SleepSync.xcodeproj \
  -scheme SleepSync \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  build
```

The first signed build may display a Keychain prompt allowing `codesign` to use
the Apple Development private key.
