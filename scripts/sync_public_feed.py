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

# GitHub Pages is the last-resort transport for networks that block both
# Supabase and Cloudflare Worker hostnames. Match metadata stays in matches.json
# and active client playback lines are mirrored separately in streams.json.
# This makes WATCH usable without a VPN on those networks.
SELECT = """
id,league,home_team,away_team,home_logo_url,away_logo_url,
kickoff_at,is_live,sort_order,home_score,away_score,status_short,
status_elapsed,is_finished,is_featured,publish_state,
last_score_sync_at,updated_at,
stream_links(
id,stream_type,stream_url,referer,origin,key_id,key_data,
use_webview,webview_url,is_active,health_status,available_from,expires_at
)
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
        "User-Agent": "football-stream-public-feed/3.0",
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


def is_safe_public_link(link):
    if not isinstance(link, dict):
        return False
    if link.get("is_active") is not True:
        return False
    if link.get("use_webview") is True:
        return False

    if any(
        str(link.get(field) or "").strip()
        for field in ("referer", "origin", "key_id", "key_data")
    ):
        return False

    stream_url = str(link.get("stream_url") or "").strip()
    return bool(stream_url) and not looks_signed(stream_url)


safe_data = []
stream_data = {}
for row in data:
    if not isinstance(row, dict):
        continue

    clean = dict(row)
    links = clean.pop("stream_links", None) or []
    now = datetime.now(timezone.utc)

    def advertised(link):
        if not isinstance(link, dict) or link.get("is_active") is not True:
            return False

        for field, relation in (
            ("available_from", "from"),
            ("expires_at", "until"),
        ):
            value = str(link.get(field) or "").strip()
            if not value:
                continue
            try:
                moment = datetime.fromisoformat(value.replace("Z", "+00:00"))
                if moment.tzinfo is None:
                    moment = moment.replace(tzinfo=timezone.utc)
                if relation == "from" and now < moment:
                    return False
                if relation == "until" and now >= moment:
                    return False
            except Exception:
                pass

        if link.get("use_webview") is True:
            return False
        return bool(str(link.get("stream_url") or "").strip())

    clean["stream_count"] = sum(1 for link in links if advertised(link))
    clean["public_stream_count"] = sum(
        1 for link in links if is_safe_public_link(link)
    )

    active_lines = []
    for link in links:
        if not advertised(link):
            continue
        # These fields are already required by the anonymous viewer to play a
        # selected line. Keep the fallback payload minimal and client-focused.
        active_lines.append({
            "id": link.get("id"),
            "label": link.get("label"),
            "resolution": link.get("resolution"),
            "stream_type": link.get("stream_type"),
            "stream_url": link.get("stream_url"),
            "referer": link.get("referer"),
            "origin": link.get("origin"),
            "key_id": link.get("key_id"),
            "key_data": link.get("key_data"),
            "use_webview": link.get("use_webview") is True,
            "webview_url": link.get("webview_url"),
            "is_active": True,
            "priority": link.get("priority", 100),
            "available_from": link.get("available_from"),
            "expires_at": link.get("expires_at"),
            "health_status": link.get("health_status", "unknown"),
        })

    match_id = str(clean.get("id") or "").strip()
    if match_id and active_lines:
        stream_data[match_id] = active_lines

    safe_data.append(clean)

out = sys.argv[1] if len(sys.argv) > 1 else "matches.json"
streams_out = sys.argv[2] if len(sys.argv) > 2 else "streams.json"

with open(out, "w", encoding="utf-8") as fh:
    json.dump(
        safe_data,
        fh,
        ensure_ascii=False,
        separators=(",", ":"),
    )

with open(streams_out, "w", encoding="utf-8") as fh:
    json.dump(
        stream_data,
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
            "streams_output": streams_out,
            "mirrored_stream_matches": len(stream_data),
            "public_feed": "vpn-free-fallback",
        }
    )
)
