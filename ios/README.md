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
Shared/DesignSystem/Charts.swift      TrendChart, BarsChart, StatLine and the chart style tokens
Shared/WorkoutActivityAttributes.swift  Live Activity payload (app and widget extension)
Training/API/                         API client (Keychain, offline write queue, read cache) and wire models
Training/Features/                    Home (dashboard), Today, Calendar, Progress, Diet, Data, Settings
Training/LiveActivity/LiveWorkout.swift  Live Activity controller and the interval runner
TrainingWidgets/                      Lock screen and Dynamic Island views
Config/                               Info.plist fragments for both targets
```

Screens use tokens and components from `Shared/DesignSystem` and do not set colors, fonts or radii themselves, so a
design round is mostly edits to those files. The Live Activity uses the same tokens.

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

## Dashboard

Home is a grid of cards: watch metrics from `GET /api/metrics`, plus training, weight and nutrition from the data the
other tabs use. `HomeModel.swift` holds the card list (`CardKind`), what each watch metric card shows (`MetricSpec`,
keyed by Garmin's field names) and the layout. Customize (top right) reorders cards, sets each to half or full width
and hides them; the layout is saved on the phone. A card with no data stays out of the grid until there is some.
To add a card for another metric, add a `CardKind` case and a `MetricSpec` entry. "Everything from your watch" lists
every stored value, including those without a card.

## Automatic data

- Apple Health (Data tab, "Connect Apple Health"): reads daily nutrition totals and the first weigh-in of each day from
  Health and sends them through `PUT /api/nutrition` and `PUT /api/body` whenever the app comes to the front.
  MyFitnessPal writes both to Health once HealthKit Sharing is on in its settings. A day imported from a MyFitnessPal
  CSV keeps its meal breakdown, and a weight typed in by hand is never replaced. The rules are in `HealthSync.plan`.
- Garmin: done by the Worker (root README, "Automatic Garmin import"). The Data tab shows its last run and has a
  "Check Garmin now" button.

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
