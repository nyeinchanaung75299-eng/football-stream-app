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
        "User-Agent": "football-stream-public-feed/2.0",
    },
)

with urllib.request.urlopen(request, timeout=20) as response:
    raw = response.read().decode("utf-8")
    data = json.loads(raw)

if not isinstance(data, list):
    raise SystemExit("Supabase feed did not return a list")

SENSITIVE_QUERY_PARTS = {
    "token",
    "auth",
    "signature",
    "sig",
    "key",
    "expires",
    "expire",
    "policy",
    "jwt",
    "hdnts",
    "hdnea",
}

def looks_signed(value):
    try:
        parsed = urllib.parse.urlparse(str(value or ""))
        keys = {str(k).lower() for k in urllib.parse.parse_qs(parsed.query)}
        return any(
            any(part in key for part in SENSITIVE_QUERY_PARTS)
            for key in keys
        )
    except Exception:
        return True

def sanitize_link(link):
    if not isinstance(link, dict):
        return None
    if link.get("is_active") is not True:
        return None
    if link.get("use_webview") is True:
        return None

    protected = (
        link.get("referer"),
        link.get("origin"),
        link.get("key_id"),
        link.get("key_data"),
    )
    if any(str(value or "").strip() for value in protected):
        return None

    stream_url = str(link.get("stream_url") or "").strip()
    if not stream_url or looks_signed(stream_url):
        return None

    return {
        "id": link.get("id"),
        "label": link.get("label"),
        "resolution": link.get("resolution"),
        "stream_type": link.get("stream_type"),
        "stream_url": stream_url,
        "use_webview": False,
        "webview_url": None,
        "is_active": True,
        "priority": link.get("priority"),
        "available_from": link.get("available_from"),
        "expires_at": link.get("expires_at"),
        "health_status": link.get("health_status"),
    }

safe_data = []
for row in data:
    if not isinstance(row, dict):
        continue
    clean = dict(row)
    links = clean.get("stream_links") or []
    clean["stream_links"] = [
        safe
        for safe in (sanitize_link(item) for item in links)
        if safe is not None
    ]
    safe_data.append(clean)

out = sys.argv[1] if len(sys.argv) > 1 else "matches.json"
with open(out, "w", encoding="utf-8") as fh:
    json.dump(safe_data, fh, ensure_ascii=False, separators=(",", ":"))

print(
    json.dumps(
        {
            "ok": True,
            "matches": len(safe_data),
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "output": out,
        }
    )
)
