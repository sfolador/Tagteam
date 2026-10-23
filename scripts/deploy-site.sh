#!/usr/bin/env bash
# Deploys the landing page (site/) to Cloudflare, refusing to ship it without a notarized zip.
#   scripts/deploy-site.sh
# The zip is not in git: copy the notarized release zip to site/public/download/Tagteam.zip and
# write latest.json next to it ({"version":"x.y.z","file":"Tagteam.zip","size":<bytes>}).
set -euo pipefail
cd "$(dirname "$0")/.."

DOWNLOADS="site/public/download"
for file in Tagteam.zip latest.json; do
  if [[ ! -f "$DOWNLOADS/$file" ]]; then
    echo "Missing $DOWNLOADS/$file: the site would go live with a broken Download button." >&2
    exit 1
  fi
done

# ditto, not unzip: unzip drops symlinks and breaks the code signature seal.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ditto -x -k "$DOWNLOADS/Tagteam.zip" "$TMP"
xcrun stapler validate -q "$TMP/Tagteam.app" \
  || { echo "$DOWNLOADS/Tagteam.zip does not hold a notarized Tagteam.app." >&2; exit 1; }

PUBLISHED="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$DOWNLOADS/latest.json")"
INSIDE="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$TMP/Tagteam.app/Contents/Info.plist")"
CURRENT="$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml | head -1)"
if [[ "$PUBLISHED" != "$INSIDE" ]]; then
  echo "latest.json says $PUBLISHED but the app in the zip is $INSIDE." >&2
  exit 1
fi
if [[ "$PUBLISHED" != "$CURRENT" ]]; then
  echo "Note: the site offers version $PUBLISHED, project.yml is at $CURRENT." >&2
fi

(cd site && npx --yes wrangler deploy)
echo "Live: https://tagteam.simonefolador.com (version $PUBLISHED)"
