# Training for iOS

Native SwiftUI client for the training tracker. The Cloudflare Worker stays the source of truth: the app only reads
and writes through `/api` with the API token, the same endpoints the web app uses. Nothing in the Worker, the web app
or `scripts/fetch-data.sh` changes because of this folder.

## Run it

1. Open `ios/Training.xcodeproj` in Xcode, pick an iPhone, press Run.
2. On first launch enter the server address (prefilled with the deployed Worker) and the API token.

The token is stored in the iOS Keychain on the phone. It is never written to the repo or to a file in the project.

## Layout

```
Shared/DesignSystem/Theme.swift       Colors, type, spacing, radii. Restyling starts here.
Shared/DesignSystem/Components.swift  Card, Badge, Tile, Row, Banner, buttons, fields
Shared/WorkoutActivityAttributes.swift  Live Activity payload (app and widget extension)
Training/API/                         API client (Keychain, offline write queue, read cache) and wire models
Training/Features/                    Today, Calendar, Progress, Diet, Data, Settings
Training/LiveActivity/LiveWorkout.swift  Live Activity controller and the interval runner
TrainingWidgets/                      Lock screen and Dynamic Island views
Config/                               Info.plist fragments for both targets
```

Screens use tokens and components from `Shared/DesignSystem` and do not set colors, fonts or radii themselves, so a
design round is mostly edits to those two files. The Live Activity uses the same tokens.

## Live Activities

- Lift: starts with "Start workout". Shows the next set, sets done, a rest timer counting up from the last tick,
  and the countdown for timed sets.
- Intervals: "Start interval timer" on an interval day. Warm-up, each rep and recovery, cool-down, with a spoken
  cue and the heart rate target at every change. Other runs get a plain timer with the easy heart rate cap.

The warm-up (10 min) and cool-down (5 min) lengths are constants in `LiveWorkout.swift` because `program.js` only
has them as text. Rep count and lengths come from the template's `intervals`.

To keep cues and the lock screen on time while the phone is locked, the interval runner plays a silent audio loop
(background mode `audio`). That is fine for a personal build and would not pass App Store review. The replacement is
Live Activity push updates sent by the Worker.

## Local development against `wrangler dev`

Debug builds read two launch environment variables, so the simulator can use a local Worker with the example
credentials from `.dev.vars.example`:

```bash
npm run dev    # in the repo root
SIMCTL_CHILD_TRAINING_BASE_URL=http://localhost:8787 SIMCTL_CHILD_TRAINING_TOKEN=dev-token-change-me \
  xcrun simctl launch booted com.hlynurholm.training
```

`SIMCTL_CHILD_TRAINING_INTERVAL_SCALE=40` shortens interval phases so a whole session runs in under a minute.
A launch straight after `simctl install` sometimes starts without these variables; launch again if the app shows
the connection screen.
