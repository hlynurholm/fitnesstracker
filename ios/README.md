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

## Look

Everything is set in `Shared/DesignSystem`:

- `Theme.swift`: the palette, the two typefaces (headings are the system face in its condensed heavy cut; all other
  text is Avenir Next, see `Typography.accessory`), radii and spacing.
- Colours come from the theme chosen in Settings, Appearance (`ThemeStore`, `ThemeKind`, `ThemeColors.make`): dark,
  light, colourful (built from one hue: analogous colours for charts, the complement and split complements for
  contrast), mono dark and mono light. `Theme.Palette` reads the store, so never copy a palette colour into a
  `static let`. Use `Theme.Palette.onAccent` or `on(_:)` for text on a colour, not `.white`.
- `Components.swift`: `Backdrop` (the waves behind every screen, with `Grain`), `cardSurface` (cards are Liquid
  Glass, or a grainy gradient when given a `fill`), `Badge`, `OpenGlyph`.
- A view on a card of colour reads `\.onColor` from the environment and draws in the text colour instead of its
  own tint. `CardKind.fill` in `HomeModel.swift` says which Home widgets are cards of colour.

## Tabs and titles

Home, Today, Progress, Diet, Settings. The calendar is a panel inside Today (`CalendarPanel`), opened from the
button under the week strip. No screen puts buttons in the top bar: Home's edit button is at the bottom of the page.

Titles are always drawn by the app, never by the system, so they are always in the heading typeface: the first
screen of a tab uses `Screen(title:)` (which hides the navigation bar), and a pushed screen or sheet uses
`.inlineTitle(_:)`. Do not use `navigationTitle` with a large title. Tappable cards and rows carry no arrow.
The main value of a widget or tile, a number or a name, is `Typography.numeral` or `timer` (through `BigValue`).

## Runs

`Features/Runs/RunScreen.swift` is the page for one run: the route on a map coloured by pace, with a marker at every kilometre and the totals along its top, then pace, heart rate
and elevation over distance, splits and heart rate zones. It opens from the Last run widget, the recent runs list in
Progress and "Open run" on the day it was recorded. On that day the run is shown in brief (`RunSummary`: a map and
four numbers), inside the session card on a running day, where it replaces the description of what was planned, and
as a card of its own on other days. Maps inside a scrolling page (`fixed`) zoom, turn and tilt with two fingers; one
finger scrolls the page. Today has a Sync button that calls `POST /api/garmin/sync` and reloads the day.

## Dashboard

Home is a grid of widgets (`Features/Home/Widgets.swift`): watch metrics from `GET /api/metrics`, plus training,
weight and nutrition from the data the other tabs use. `HomeModel.swift` holds the widget list (`CardKind`), what
each watch metric widget shows (`MetricSpec`, keyed by Garmin's field names) and the layout, saved on the phone.

- Five sizes (`WidgetSize`), as width × height in shares of the screen's width: ½ × ¼, ½ × ½, 1 × ¼, 1 × ½, 1 × 1.
  `WidgetGrid` places them in two columns of quarter-height rows. A widget shows more as it grows: name and number
  at quarter height, a chart from half height (`MetricWidget`), and at 1 × 1 the lowest, average and highest, the
  session's lifts (`SessionCard`) or the whole run map (`LastRunCard`).
- Editing works like the iOS home screen. Touch and hold any widget (or tap "Edit Home" at the bottom of the page)
  and the widgets wiggle: drag one to move it, drag the thick line round its bottom right corner to resize it (it
  snaps to the nearest of the five sizes), and tap the button in its top left corner for its settings: size, range of
  days (2 days to 6 months), resolution, chart type, "use this range and resolution for all widgets" (asks twice)
  and remove. "Add widget" and "Done" sit above the tab bar. A widget's own tap action checks `editing`, so the
  touch that started editing does not also open its page.
- The heading (`CardHeader`) is the same size and in the same place at every size. Quarter-height widgets are built
  with `CompactLines` and `StripLines`.
- Launch with `TRAINING_LAYOUT='[{"kind":"steps","wide":true,"size":"strip"}, ...]'` to look at an arrangement.
- Every chart widget is built the same way: the number, the chart (`ValueAndChart`), then one line under it
  (`ChartCaption`) with short wording such as "goal 9,000 · 6m avg 8,601". Keep new widgets to that.
- HRV is drawn as dots on a line over a shaded band (`BandSpark`). The band is the watch's own balanced range for
  each night (`hrv.baseline.balancedLow` and `balancedUpper`); without those it is the middle half of his last four
  weeks, and the caption says "usual" instead of "healthy".
- Fun facts change every day (`FunFacts.swift`): the date picks a theme (record days, last 7 days, best months,
  totals, best weekdays, off days, best weeks, streaks), which facts are shown, their order, the layout and the look.
  Launch with `TRAINING_FACTS_DAY=3` to see the widget as it will be in three days.
- A widget with no data stays out of the grid until there is some. To add a widget for another metric, add a
  `CardKind` case and a `MetricSpec` entry. "Everything from your watch" lists every stored value.

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
