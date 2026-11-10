# Training tracker

A personal workout tracker and fitness dashboard for the "Plan to 85 kg" program. Runs on Cloudflare Workers with a D1 (SQLite) database. Phone for logging, desktop for the dashboard. Single user, password protected.

What it does:

- Shows the session for any day: Lift A, B or C with warm-up, jump drills for the current phase and every lift with sets and reps, or the run with its distance and structure, or a rest day. Deload weeks and test weeks are marked.
- Calendar: a month view of every planned session. Tap a day to open it, swap it with another day, or change which session happens that day. Moved days are marked and "Back to the plan" undoes it. The same options sit under "Move or change this session" in the day view.
- Notes on every exercise and on the warm-up, jumps and finisher blocks, shown again next time that exercise comes up (`workout_notes` table, `PUT /api/day/:date/notes`).
- While logging, the workout time and the rest since the last tick sit in a bar above the tabs. Timed sets (planks, marches) have a countdown button that buzzes and beeps at zero and logs the set.
- Logs kg and reps (or seconds, metres) per set. Last time's numbers are pre-filled as placeholders; the tick button accepts them with one tap. Works offline and syncs later.
- Charts progression per lift (estimated 1RM, top set, volume), several lifts overlaid, body weight with 7-day average against the 85 kg goal, running pace and 5 km times, nutrition against targets, and a session heatmap.
- Takes Garmin exports (FIT, TCX, GPX, CSV) attached to a run and MyFitnessPal CSV exports. Parses what it can (splits, heart rate zones, best 5 km, daily calories and protein) and keeps the original file.
- Exports everything as JSON and as a Markdown summary for pasting into Claude. Claude can also read and post reports through the API with a token.

## Local development

```bash
npm install
cp .dev.vars.example .dev.vars          # local password and API token
npm run migrate:local                   # creates the local SQLite database
npm run dev                             # http://localhost:8787, password: changeme
```

Tests: `npm test` runs the parser and schedule tests. With `npm run dev` running, `bash test/api-smoke.sh` exercises the whole API and `node test/ui-screens.mjs` drives the UI in a headless browser (needs Playwright).

## Deploy to Cloudflare (about 10 minutes)

You need a free Cloudflare account and Node.js 20 or newer on your computer.

1. Get the code: clone the GitHub repo, or unzip the project folder.
2. In the project folder run:
   ```bash
   npm install
   npm run setup
   ```
   Non-interactive (for scripts or when Claude runs it for you): `APP_PASSWORD='...' API_TOKEN='...' npm run setup`.

   The script logs you in to Cloudflare in the browser, creates the D1 database, writes its id into `wrangler.jsonc`, applies the schema, asks for the app password, generates an API token and deploys. It prints the URL, something like `https://fitness-tracker.<your-subdomain>.workers.dev`.
3. Open that URL on your phone, log in, and add it to the home screen (Safari: Share, Add to Home Screen). It then opens like an app.
4. Commit the `wrangler.jsonc` change (it now holds the database id) and push.

Manual equivalent of the script:

```bash
npx wrangler login
npx wrangler d1 create fitness-tracker-db        # paste the printed database_id into wrangler.jsonc
npx wrangler d1 migrations apply fitness-tracker-db --remote
npx wrangler secret put APP_PASSWORD
npx wrangler secret put API_TOKEN
npx wrangler deploy
```

### Automatic deploys from GitHub (optional)

`.github/workflows/deploy.yml` deploys on every push to `main`. Add two repository secrets under Settings, Secrets and variables, Actions:

- `CLOUDFLARE_API_TOKEN`: create at dash.cloudflare.com, My Profile, API Tokens, with the "Edit Cloudflare Workers" template plus D1 Edit.
- `CLOUDFLARE_ACCOUNT_ID`: shown on the Workers overview page.

Alternatively, connect the repo in the Cloudflare dashboard under Workers and Pages, Create, Import a repository. Build command: none. Deploy command: `npx wrangler deploy`.

### Custom domain

Workers and Pages, fitness-tracker, Settings, Domains and Routes, Add. Any domain already on Cloudflare works.

## Automatic Garmin import (optional)

The Worker can pull new runs from Garmin Connect by itself, using Garmin's Personal API (your own data, your own key).

1. Log in to Garmin Connect on the web, open the [Personal API Key page](https://connect.garmin.com/app/settings/personalApiToken), create a key and copy it. Garmin shows it once. Keys expire after 30 days to one year, your choice, and Garmin emails a reminder a week before.
2. Store it as a Worker secret: `npx wrangler secret put GARMIN_API_KEY`
3. Deploy. Every 30 minutes the Worker lists your recent running activities, downloads the original file of each one it has not seen, and runs it through the same parser as a manual upload. `POST /api/garmin/sync` does the same on demand (`{"days": 60}` looks further back, default 14) and `GET /api/garmin` shows how the last run went. The iOS app has a button for it on the Data tab.

The same run also pulls the daily health data the watch records: steps, floors, calories, heart rate, intensity minutes, stress, Body Battery, breathing rate, blood oxygen, sleep, HRV and weight. It goes into the `daily_metrics` table, one row per day, as a flat object keyed by Garmin's own field names (`movement.steps.value`, `heartRate.restingValue`, `sleep.sleepTimeSeconds`, ...), so a metric Garmin adds later needs no schema change. The first run fetches about four months, later runs the last three days. `GET /api/metrics?days=120` returns it, and it is part of `export.json`.

Without the secret nothing happens. A file you already uploaded by hand under Garmin's own name (`<activity id>_ACTIVITY.fit`) is not imported twice. `GARMIN_ACTIVITY_TYPE` in `wrangler.jsonc` picks the activity type (`running`; empty for everything).

The code follows Garmin's published reference but has only been run against the stand-in server in `test/garmin-stub.mjs`, not yet against Garmin itself. `bash test/garmin-sync.sh` (see its header) runs that check.

## Changing the plan

The whole program lives in `public/js/program.js`: weekly schedule, phases, warm-up, jump drills per phase, the three lifting days with sets and reps, interval structure by week, deload and test weeks, targets. Edit and deploy. Logged sets are keyed by exercise key, so renaming an exercise keeps its history. The start date, jump phase, goal weight, calorie and protein targets, max heart rate and 5 km target can be changed in Settings inside the app without a deploy.

## How Claude gets the data

- Data page, "Copy summary for Claude": a Markdown summary of weight, sessions, lifts, runs, tests and nutrition. Paste it into the project chat.
- Data page, "Download JSON": the full export. Upload it in the project chat for a deeper analysis.
- Direct API access with the `API_TOKEN` secret, for example from a Claude session:
  ```bash
  curl -H "Authorization: Bearer $API_TOKEN" https://<your-url>/api/export.json
  curl -H "Authorization: Bearer $API_TOKEN" https://<your-url>/api/summary.md
  curl -X POST -H "Authorization: Bearer $API_TOKEN" -H "Content-Type: application/json" \
       -d '{"title":"Week 4 review","body_md":"# Week 4\n..."}' https://<your-url>/api/reports
  ```
  Reports posted this way appear on the Data page, rendered from Markdown.

## API

All routes need the session cookie or `Authorization: Bearer <API_TOKEN>`.

| Route | Purpose |
| --- | --- |
| `GET /api/schedule?from=&to=` | Planned session per day in a range (max 120 days), with overrides and logged workouts |
| `PUT /api/schedule/:date` | `{template_key}` sets what happens that day; `null` returns to the plan |
| `POST /api/schedule/swap` | `{a, b}` swaps the sessions of two dates |
| `GET /api/day/:date` | Everything for one day: schedule, plan, logged sets, last values per exercise, week strip |
| `PUT /api/day/:date/workout` | Create or update the day's session (status, notes, run distance and time, checklist, plan) |
| `PUT /api/sets/:client_id`, `DELETE` | Upsert or delete one set (client-generated id, so offline saves replay safely) |
| `GET /api/workouts`, `GET/PATCH/DELETE /api/workouts/:id` | History |
| `GET/PUT /api/body` | Morning weight |
| `GET/PUT /api/tests` | Performance tests (5 km, jumps, shuttle, 3RMs) |
| `POST /api/uploads` (multipart `file`, optional `workout_id`, `date`, `source`, `tz_offset_min`) | Garmin or MyFitnessPal files |
| `GET /api/uploads`, `GET /api/uploads/:id/raw`, `PATCH`, `DELETE` | Manage uploads |
| `GET /api/activities`, `GET /api/activities/:id` | Parsed Garmin activities, with splits, laps, HR zones and a downsampled track |
| `GET /api/nutrition` | Daily nutrition totals |
| `GET /api/dashboard` | Everything the Progress page needs |
| `GET /api/export.json[?include=raw]` | Full export, optionally with the original files as base64 |
| `GET /api/summary.md` | Markdown summary for Claude |
| `GET/POST /api/reports`, `GET/DELETE /api/reports/:id` | Reports shown in the app |
| `GET/PUT /api/settings` | Start date, phase override, targets |
| `GET /api/garmin`, `POST /api/garmin/sync` | Automatic Garmin import: status of the last run, and run it now |
| `GET /api/metrics?days=` | Daily health metrics from the watch, one flat object per day |

## Project layout

```
wrangler.jsonc          Worker, static assets and D1 config
migrations/0001_init.sql  Schema
src/index.js            Entry: auth gate, API dispatch, static assets
src/auth.js             Password login, signed cookie, bearer token, login throttling
src/api.js              All API routes
src/parsers/            fit.js (Garmin FIT SDK), xml.js (TCX, GPX), csv.js, garmin-csv.js, mfp.js, activity.js (summary maths)
src/summary.js          Markdown summary generator
public/js/program.js    The program (shared by server and browser)
public/js/views/        today.js (logging), progress.js (charts), history.js, data.js, settings.js
public/css/app.css      Styles, light and dark
test/                   Unit tests, API smoke test, headless UI check, fixture generators
```

## Diet tab

The Diet tab shows the targets (calories, protein, weekly fun budget, expected weight loss), the MyFitnessPal intake per day against the targets, weekly averages next to the weekly weight change, an implied maintenance estimate once there are about three weeks of both, the day template from the plan, the latest diet note from Claude, and the MyFitnessPal upload.

### For a future analysis task

The data model is ready for a scheduled Claude task that reads the data and writes suggestions back into the app:

| Call | Purpose |
| --- | --- |
| `GET /api/diet?days=120` | Targets, nutrition days with meals, weigh-ins, weekly averages and the latest diet report in one JSON document. |
| `GET /api/export.json` | Everything, including sets, runs and parsed Garmin activities. |
| `GET /api/summary.md` | The same as compact Markdown. |
| `POST /api/reports` with `{"title","body_md","section":"diet"}` | Posts a note. `section` is `general`, `diet` or `training`. The latest `diet` note shows on the Diet tab. |
| `GET /api/reports?section=diet&limit=1&full=1` | Reads the latest note back. |

All calls take `Authorization: Bearer <API_TOKEN>`.

## Sample data

## Fetching the data from a Claude thread

Nothing needs copying out of the app. Every read endpoint accepts the API token as a bearer header, so a script can pull the whole dataset:

```bash
FITNESS_API_TOKEN=<the API_TOKEN Worker secret> scripts/fetch-data.sh fitness-data
```

That writes `summary.md` (the same text as "Copy summary for Claude"), `export.json` (every table), `diet.json`, `uploads.json` and the original Garmin and MyFitnessPal files under `garmin/`. The raw files are kept gzip-compressed in D1 at upload time, so nothing is lost. `FITNESS_APP_URL` overrides the base URL (local dev: `http://127.0.0.1:8787`), `FITNESS_RAW=0` skips the raw files. Exit codes: 2 no token, 3 network, 4 token rejected.

The calls behind it, all `GET` with `Authorization: Bearer <token>`:

| Call | Returns |
| --- | --- |
| `/api/summary.md` | Markdown summary |
| `/api/export.json` | Every table as JSON; `?include=raw` adds the files base64 encoded |
| `/api/diet?days=120` | Diet feed |
| `/api/uploads` | Uploaded files with workout date and template |
| `/api/uploads/<id>/raw` | The original file (404 when none was kept) |

For a Claude cloud thread to run this, the cloud environment needs the app host allowed in its network settings and the token stored as the `FITNESS_API_TOKEN` environment variable. The token also allows writes (it is the same token the reports API uses), so treat it like a password.

To restart the program from another Monday, run the "Program start" workflow from the Actions tab with the date (YYYY-MM-DD). It only changes the `program_start_date` setting in the live database; logged history stays and shows under "Before the plan". Leave the date empty to clear the setting so the default in `public/js/program.js` applies. Tick "reset_run_target" to also clear a saved 5 km target. The same date can be set on the Settings page in the app.

To see the app populated, run the "Sample data" workflow from the Actions tab with `add`. It loads six weeks of made-up history (lifts with sets, runs with Garmin-style activities, morning weights, nutrition days, week 1 tests, a report) dated before the real program start and moves the program start date back six weeks so they show as weeks 1 to 6. Run the same workflow with `remove` to delete every sample row and restore the start date. Locally: `node scripts/sample-data.mjs add > sample.sql && npx wrangler d1 execute fitness-tracker-db --local --file sample.sql`.

## Security notes

- One password, compared in constant time, 8 failed attempts per 15 minutes per IP, signed HttpOnly cookie valid 180 days. Changing the password logs out every device.
- The API token is as powerful as the password. Keep it in the project memory for Claude only if you accept that.
- Uploaded files are stored gzipped inside D1 (2 MB row limit, so files over about 1.8 MB compressed keep only their parsed data).
- Reports are rendered from Markdown with HTML allowed, which is fine for a single user posting their own content.
