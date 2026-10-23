#!/usr/bin/env bash
# Deploys the landing page (site/) to Cloudflare, refusing to ship it without a notarized zip.
#   scripts/deploy-site.sh
# The zip is not in git: copy the notarized release zip to site/public/download/Tagteam.zip and
# write latest.json next to it ({"version":"x.y.z","file":"Tagteam.zip","size":<bytes>}).
set -euo pipefail
cd "$(dirname "$0")/.."

DOWNLOADS="site/public/download"
# Downloads are paused until the upstream licensing is settled: the page
# ships without a download, and a stray zip must not be published with it.
if [[ -e "$DOWNLOADS" ]]; then
  echo "$DOWNLOADS exists, but downloads are paused. Move it out of site/public first." >&2
  exit 1
fi

(cd site && npx --yes wrangler deploy)
echo "Live: https://tagteam.simonefolador.com (no downloads)"
