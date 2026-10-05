#!/usr/bin/env python3
import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone

SUPABASE_URL = os.environ.get("SUPABASE_URL", "").strip()
PUBLISHABLE_KEY = os.environ.get("SUPABASE_PUBLISHABLE_KEY", "").strip()

if not SUPABASE_URL or not PUBLISHABLE_KEY:
    raise SystemExit("SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY are required")

MATCH_SELECT = """
id,league,home_team,away_team,home_logo_url,away_logo_url,
kickoff_at,is_live,sort_order,home_score,away_score,status_short,
status_elapsed,is_finished,is_featured,publish_state,
last_score_sync_at,updated_at
""".replace("\n", "").replace(" ", "")

headers = {
    "apikey": PUBLISHABLE_KEY,
    "Accept": "application/json",
    "User-Agent": "football-stream-public-feed/5.0",
}


def get_json(url):
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


match_params = {
    "select": MATCH_SELECT,
    "is_active": "eq.true",
    "publish_state": "eq.published",
    "is_featured": "eq.true",
    "order": "kickoff_at.asc,sort_order.asc",
}

match_url = (
    SUPABASE_URL.rstrip("/")
    + "/rest/v1/matches?"
    + urllib.parse.urlencode(match_params)
)

counts_url = (
    SUPABASE_URL.rstrip("/")
    + "/rest/v1/match_stream_counts?"
    + urllib.parse.urlencode(
        {
            "select": "match_id,stream_count",
        }
    )
)

data = get_json(match_url)
counts = get_json(counts_url)

if not isinstance(data, list):
    raise SystemExit("Supabase match feed did not return a list")
if not isinstance(counts, list):
    raise SystemExit("Supabase stream count view did not return a list")

count_by_match = {}
for row in counts:
    if not isinstance(row, dict):
        continue
    match_id = str(row.get("match_id") or "").strip()
    if not match_id:
        continue
    try:
        count_by_match[match_id] = max(0, int(row.get("stream_count") or 0))
    except (TypeError, ValueError):
        count_by_match[match_id] = 0

safe_data = []
for row in data:
    if not isinstance(row, dict):
        continue

    clean = dict(row)
    match_id = str(clean.get("id") or "").strip()
    clean["stream_count"] = count_by_match.get(match_id, 0)
    clean["public_stream_count"] = 0
    safe_data.append(clean)

out = sys.argv[1] if len(sys.argv) > 1 else "matches.json"

with open(out, "w", encoding="utf-8") as fh:
    json.dump(
        safe_data,
        fh,
        ensure_ascii=False,
        separators=(",", ":"),
    )

print(
    json.dumps(
        {
            "ok": True,
            "matches": len(safe_data),
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "output": out,
            "public_feed": "metadata-and-safe-counts-only",
        }
    )
)
