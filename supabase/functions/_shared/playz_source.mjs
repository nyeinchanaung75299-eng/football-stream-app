import { playzSnapshot } from "./playz_snapshot.mjs";

const clean = (value) => String(value ?? "").trim();

function eventTime(row) {
  const match = clean(row.date).match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  const time = clean(row.time).match(/^(\d{2}):(\d{2})(?::(\d{2}))?$/);
  if (!match || !time) return null;
  // PlayZ publishes its schedule in UTC. Clients convert this ISO value to
  // their local timezone before rendering it.
  const value = Date.UTC(+match[3], +match[2] - 1, +match[1], +time[1], +time[2], +(time[3] ?? 0));
  return Number.isFinite(value) ? new Date(value).toISOString() : null;
}

function catalogKind(value) {
  return value === "matches" ? "matches" : "channels";
}

function safeLogo(value) {
  try {
    const url = new URL(clean(value));
    return url.protocol === "https:" || url.protocol === "http:" ? url.toString() : null;
  } catch {
    return null;
  }
}

function channelRows() {
  return playzSnapshot.channels.map((row) => ({
    source: "playz",
    source_id: row.id,
    schedule_id: row.id,
    kind: "channel",
    home_team: row.name,
    away_team: "",
    home_logo: safeLogo(row.logo),
    away_logo: null,
    league: "Sports channels",
    match_time: null,
    is_live: null,
    anchors: [{ uid: row.id, room_num: row.id, nick_name: row.name }],
  }));
}

function eventRows() {
  return playzSnapshot.events.map((row) => ({
    source: "playz",
    source_id: row.id,
    schedule_id: row.id,
    kind: "match",
    home_team: row.home,
    away_team: row.away,
    home_logo: safeLogo(row.home_logo),
    away_logo: safeLogo(row.away_logo),
    league: row.league,
    match_time: eventTime(row),
    is_live: null,
    anchors: [{ uid: row.id, room_num: row.id, nick_name: "PlayZ streams" }],
  }));
}

export function playzMatches(body = {}) {
  const kind = catalogKind(body.catalog);
  const matches = kind === "matches" ? eventRows() : channelRows();
  return {
    ok: true,
    source: "playz",
    catalog: kind,
    matches,
    results: matches.length,
    snapshot_version: playzSnapshot.version,
    message: matches.length
      ? "Select a PlayZ source to view its direct media lines."
      : "No PlayZ sources are available in this section.",
    generated_at: new Date().toISOString(),
  };
}

function sourceItem(id) {
  return [...playzSnapshot.channels, ...playzSnapshot.events].find((row) => row.id === id);
}

export function playzStreams(body = {}) {
  const id = clean(body.room_num ?? body.source_id ?? body.schedule_id);
  if (!/^(?:channel|event):[a-z0-9-]+$/i.test(id)) {
    throw new Error("Invalid PlayZ source ID.");
  }
  const item = sourceItem(id);
  if (!item) throw new Error("PlayZ source is no longer available.");
  const lines = item.lines.map((line) => ({
    label: clean(line.label) || "PlayZ stream",
    url: clean(line.url),
    stream_type: clean(line.stream_type) || "auto",
    resolution: clean(line.resolution) || "Auto",
    referer: clean(line.referer) || null,
    origin: clean(line.origin) || null,
    key_id: null,
    key_data: null,
    health_status: "unknown",
  })).filter((line) => line.url.startsWith("https://"));
  return {
    ok: true,
    source: "playz",
    catalog: id.startsWith("channel:") ? "channels" : "matches",
    kind: id.startsWith("channel:") ? "channel" : "match",
    room_num: id,
    title: item.name ?? `${item.home} vs ${item.away}`,
    line_count: lines.length,
    ready: lines.length > 0,
    live_status: null,
    lines,
    message: lines.length ? "Direct PlayZ media lines loaded." : "No direct line is available.",
    generated_at: new Date().toISOString(),
  };
}
