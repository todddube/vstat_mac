#!/usr/bin/env bash
# Re-capture live vendor payloads so schema drift shows up as a reviewable diff
# instead of a field report. Run: make fixtures
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/VibeStatsTests/Fixtures"
mkdir -p "$DIR"

# Statuspage incident feeds run to hundreds of KB of history we never read
# (we prune to 10 within 14 days). Trim to the 25 most recent so the fixtures
# stay reviewable.
fetch() { # url, outfile
  echo "  → $2"
  curl -sSfL --max-time 20 -H 'Accept: application/json' "$1" \
    | python3 -c '
import json, sys
data = json.load(sys.stdin)
if isinstance(data, dict) and "incidents" in data:
    data["incidents"] = data["incidents"][:25]
json.dump(data, sys.stdout, indent=2)
' > "$DIR/$2"
}

echo "Capturing Statuspage fixtures…"
for pair in \
  "claude|https://status.claude.com/api/v2" \
  "github|https://www.githubstatus.com/api/v2" \
  "openai|https://status.openai.com/api/v2"
do
  id="${pair%%|*}"; base="${pair#*|}"
  fetch "$base/status.json"     "$id-status.json"
  fetch "$base/components.json" "$id-components.json"
  fetch "$base/incidents.json"  "$id-incidents.json"
done

echo "Capturing Google Cloud fixture…"
fetch "https://status.cloud.google.com/incidents.json" "gemini-incidents.json"

echo "Done. Review the diff before committing."
