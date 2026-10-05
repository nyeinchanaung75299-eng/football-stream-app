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

# Public GitHub fallback contains match metadata only. It intentionally never
# publishes stream_url, Referer, Origin, ClearKey data, or WebView URLs.
SELECT = """
id,league,home_team,away_team,home_logo_url,away_logo_url,
kickoff_at,is_live,sort_order,home_score,away_score,status_short,
status_elapsed,is_finished,is_featured,publish_state,
last_score_sync_at,updated_at,
stream_links(id,is_active,use_webview,available_from,expires_at)
""".replace("\n", "").replace(" ", "")

params = {
    "select": SELECT,
    "is_active": "eq.true",
    "publish_state": "eq.published",
    "is_featured": "eq.true",
    "order": "kickoff_at.asc,sort_order.asc",
}

url = (
    SUPABASE_URL.rstrip("/")
    + "/rest/v1/matches?"
    + urllib.parse.urlencode(params)
)

request = urllib.request.Request(
    url,
    headers={
        "apikey": PUBLISHABLE_KEY,
        "Accept": "application/json",
        "User-Agent": "football-stream-public-feed/4.0",
    },
)

with urllib.request.urlopen(request, timeout=20) as response:
    data = json.loads(response.read().decode("utf-8"))

if not isinstance(data, list):
    raise SystemExit("Supabase feed did not return a list")


def parse_time(value):
    text = str(value or "").strip()
    if not text:
        return None
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed
    except Exception:
        return None


now = datetime.now(timezone.utc)
safe_data = []

for row in data:
    if not isinstance(row, dict):
        continue

    clean = dict(row)
    links = clean.pop("stream_links", None) or []

    def advertised(link):
        if not isinstance(link, dict) or link.get("is_active") is not True:
            return False
        if link.get("use_webview") is True:
            return False

        available_from = parse_time(link.get("available_from"))
        if available_from is not None and now < available_from:
            return False

        expires_at = parse_time(link.get("expires_at"))
        if expires_at is not None and now >= expires_at:
            return False

        return True

    # Count only. No playback address or header is written to GitHub.
    clean["stream_count"] = sum(1 for link in links if advertised(link))
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
            "public_feed": "metadata-only",
        }
    )
)
