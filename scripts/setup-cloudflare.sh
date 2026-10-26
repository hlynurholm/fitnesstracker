#!/usr/bin/env bash
# One-time Cloudflare setup: creates the D1 database, writes its id into wrangler.jsonc,
# applies migrations, sets the secrets and deploys. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."

DB_NAME="fitness-tracker-db"
command -v npx >/dev/null || { echo "Install Node.js 20+ first (https://nodejs.org)"; exit 1; }
[ -d node_modules ] || npm install

echo "==> Checking Cloudflare login"
npx wrangler whoami >/dev/null 2>&1 || npx wrangler login

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
if ! npx wrangler secret list 2>/dev/null | grep -q '"APP_PASSWORD"'; then npx wrangler secret put APP_PASSWORD; else echo "    APP_PASSWORD already set (use: npx wrangler secret put APP_PASSWORD to change)"; fi
if ! npx wrangler secret list 2>/dev/null | grep -q '"API_TOKEN"'; then
  if command -v openssl >/dev/null; then TOKEN=$(openssl rand -hex 24); echo "$TOKEN" | npx wrangler secret put API_TOKEN; echo "    Generated API_TOKEN (save this, it is shown once): $TOKEN";
  else npx wrangler secret put API_TOKEN; fi
else echo "    API_TOKEN already set"; fi

echo "==> Deploying"
npx wrangler deploy
echo
echo "Done. Open the URL printed above on your phone, log in with APP_PASSWORD, and add it to the home screen."
