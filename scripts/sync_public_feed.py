#!/usr/bin/env python3
import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone

SUPABASE_URL = os.environ.get(
    "SUPABASE_URL",
    "https://woggzixprvyjnfjzsglz.supabase.co",
)
PUBLISHABLE_KEY = os.environ.get(
    "SUPABASE_PUBLISHABLE_KEY",
    "sb_publishable_ka-rZxHdJUMYng6WJDDQUg_ZcWZJl3O",
)

SELECT = """
id,league,home_team,away_team,home_logo_url,away_logo_url,
kickoff_at,is_live,sort_order,home_score,away_score,status_short,
status_elapsed,is_finished,is_featured,publish_state,
stream_links(
id,label,resolution,stream_type,stream_url,referer,origin,
key_id,key_data,use_webview,webview_url,is_active,priority,
available_from,expires_at,health_status
)
""".replace("\n", "").replace(" ", "")

params = {
    "select": SELECT,
    "is_active": "eq.true",
    "publish_state": "eq.published",
    "is_featured": "eq.true",
    "order": "kickoff_at.asc,sort_order.asc",
}
url = SUPABASE_URL.rstrip("/") + "/rest/v1/matches?" + urllib.parse.urlencode(params)

request = urllib.request.Request(
    url,
    headers={
        "apikey": PUBLISHABLE_KEY,
        "Accept": "application/json",
        "User-Agent": "football-stream-public-feed/1.0",
    },
)

with urllib.request.urlopen(request, timeout=20) as response:
    raw = response.read().decode("utf-8")
    data = json.loads(raw)

if not isinstance(data, list):
    raise SystemExit("Supabase feed did not return a list")

out = sys.argv[1] if len(sys.argv) > 1 else "matches.json"
with open(out, "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, separators=(",", ":"))

print(
    json.dumps(
        {
            "ok": True,
            "matches": len(data),
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "output": out,
        }
    )
)
