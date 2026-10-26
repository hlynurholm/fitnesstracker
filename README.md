# Training tracker

A personal workout tracker and fitness dashboard for the "Plan to 85 kg" program. Runs on Cloudflare Workers with a D1 (SQLite) database. Phone for logging, desktop for the dashboard. Single user, password protected.

What it does:

- Shows the session for any day: Lift A, B or C with warm-up, jump drills for the current phase and every lift with sets and reps, or the run with its distance and structure, or a rest day. Deload weeks and test weeks are marked.
- Calendar: a month view of every planned session. Tap a day to open it, swap it with another day, or change which session happens that day. Moved days are marked and "Back to the plan" undoes it. The same options sit under "Move or change this session" in the day view.
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

## Security notes

- One password, compared in constant time, 8 failed attempts per 15 minutes per IP, signed HttpOnly cookie valid 180 days. Changing the password logs out every device.
- The API token is as powerful as the password. Keep it in the project memory for Claude only if you accept that.
- Uploaded files are stored gzipped inside D1 (2 MB row limit, so files over about 1.8 MB compressed keep only their parsed data).
- Reports are rendered from Markdown with HTML allowed, which is fine for a single user posting their own content.
