#!/usr/bin/env bash
# One-time Cloudflare setup: creates the D1 database, writes its id into wrangler.jsonc,
# applies migrations, sets the secrets and deploys. Safe to re-run.
#
# Interactive:      npm run setup
# Non-interactive:  APP_PASSWORD='...' API_TOKEN='...' npm run setup
#   (an env var that is set overwrites the secret; a missing one is prompted for or generated)
set -euo pipefail
cd "$(dirname "$0")/.."

DB_NAME="fitness-tracker-db"
export WRANGLER_SEND_METRICS=false
command -v npx >/dev/null || { echo "Install Node.js 20+ first (https://nodejs.org)"; exit 1; }
[ -d node_modules ] || npm install

echo "==> Checking Cloudflare login"
npx wrangler whoami >/dev/null 2>&1 || npx wrangler login

# A login that can see several accounts has to be told which one to use.
if [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
  ACCOUNTS=$(npx wrangler whoami 2>/dev/null | grep -Eo '\b[0-9a-f]{32}\b' | sort -u || true)
  COUNT=$(printf '%s\n' "$ACCOUNTS" | grep -c . || true)
  if [ "$COUNT" -eq 1 ]; then
    export CLOUDFLARE_ACCOUNT_ID="$ACCOUNTS"
  elif [ "$COUNT" -gt 1 ]; then
    echo "Several Cloudflare accounts are visible. Re-run with CLOUDFLARE_ACCOUNT_ID set to one of:"
    printf '    %s\n' $ACCOUNTS
    exit 1
  fi
fi

echo "==> Creating D1 database $DB_NAME (skipped if it exists)"
npx wrangler d1 create "$DB_NAME" >/dev/null 2>&1 || true
DB_ID=$(npx wrangler d1 list --json | node -e '
  let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{ const list=JSON.parse(s); const db=list.find(x=>x.name===process.argv[1]); if(!db){console.error("database not found"); process.exit(1);} console.log(db.uuid); });' "$DB_NAME")
echo "    database id: $DB_ID"

echo "==> Writing database id into wrangler.jsonc"
node -e '
  const fs=require("fs"); const p="wrangler.jsonc"; let s=fs.readFileSync(p,"utf8");
  s=s.replace(/"database_id":\s*"[^"]*"/, `"database_id": "${process.argv[1]}"`); fs.writeFileSync(p,s);' "$DB_ID"

echo "==> Applying migrations to the remote database"
npx wrangler d1 migrations apply "$DB_NAME" --remote

echo "==> Secrets"
echo "    APP_PASSWORD is the password you type on the phone. API_TOKEN is for Claude and scripts."
have_secret() { npx wrangler secret list 2>/dev/null | grep -q "\"$1\""; }
put_secret() { printf '%s' "$2" | npx wrangler secret put "$1" >/dev/null; }

if [ -n "${APP_PASSWORD:-}" ]; then
  put_secret APP_PASSWORD "$APP_PASSWORD"; echo "    APP_PASSWORD set from the environment"
elif ! have_secret APP_PASSWORD; then
  npx wrangler secret put APP_PASSWORD
else
  echo "    APP_PASSWORD already set (to change it: npx wrangler secret put APP_PASSWORD)"
fi

if [ -n "${API_TOKEN:-}" ]; then
  put_secret API_TOKEN "$API_TOKEN"; echo "    API_TOKEN set from the environment"
elif ! have_secret API_TOKEN; then
  if command -v openssl >/dev/null; then
    TOKEN=$(openssl rand -hex 24); put_secret API_TOKEN "$TOKEN"
    echo "    Generated API_TOKEN (save this, it is shown once): $TOKEN"
  else
    npx wrangler secret put API_TOKEN
  fi
else
  echo "    API_TOKEN already set"
fi

echo "==> Deploying"
npx wrangler deploy
echo
echo "Done. Open the URL printed above on your phone, log in with APP_PASSWORD, and add it to the home screen."
echo "Commit the wrangler.jsonc change so later deploys (and GitHub Actions) use the same database."
