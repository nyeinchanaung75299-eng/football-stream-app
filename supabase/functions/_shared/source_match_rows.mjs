// Providers repeat featured schedules in a `hot` group. Keep that membership
// when the main schedule list appears first, without changing match metadata.
function featuredRow(row) {
  return row.hot === true ||
    String(row.hot ?? row.isHot ?? "0") === "1";
}

function collectRows(value, output, depth = 0, featured = false) {
  if (depth > 6 || value == null) return;

  if (Array.isArray(value)) {
    for (const item of value) collectRows(item, output, depth + 1, featured);
    return;
  }
  if (typeof value !== "object") return;

  const looksLikeMatch = value.hostName != null ||
    value.guestName != null || value.homeName != null ||
    value.awayName != null || value.home_team != null ||
    value.away_team != null;
  if (looksLikeMatch) {
    output.push({ ...value, hot: featured || featuredRow(value) });
  }

  for (const [group, child] of Object.entries(value)) {
    if (child && typeof child === "object") {
      collectRows(child, output, depth + 1, featured || group === "hot");
    }
  }
}

/**
 * @param {any} payload Provider data, either grouped schedules or a flat list.
 * @param {(row: any) => boolean} acceptRow Keep the caller's sport filtering.
 * @returns {any[]}
 */
export function sourceMatchRows(payload, acceptRow) {
  const rows = [];
  collectRows(payload, rows);
  const matches = new Map();
  for (const row of rows) {
    if (!acceptRow(row)) continue;
    // Some feeds use matchId/gameId instead of scheduleId for ordinary
    // fixtures; dropping those rows made the catalogue look incomplete.
    const id = String(
      row.scheduleId ?? row.schedule_id ?? row.fixtureId ??
      row.matchId ?? row.match_id ?? row.gameId ?? row.eventId ?? row.id ?? "",
    ).trim();
    if (!id) continue;
    const existing = matches.get(id);
    if (existing) {
      existing.hot ||= row.hot;
      // A fixture may appear in both the normal list and the featured list.
      // The first occurrence often has no streamer rooms. Merge the room
      // catalogue instead of discarding the second occurrence.
      existing.anchors = mergeStreamerRooms(
        existing.anchors ?? existing.anchorList,
        row.anchors ?? row.anchorList,
      );
      if (!existing.matchTime && row.matchTime) existing.matchTime = row.matchTime;
      if (!existing.match_time && row.match_time) existing.match_time = row.match_time;
    } else {
      matches.set(id, { ...row });
    }
  }
  return [...matches.values()];
}

function roomIdentity(room) {
  if (!room || typeof room !== "object") return "";
  const raw = room.anchor?.roomNum ?? room.anchor?.room_num ??
    room.room?.roomNum ?? room.roomNum ?? room.room_num ??
    room.roomId ?? room.uid ?? room.id;
  const id = String(raw ?? "").trim();
  return id ? "room:" + id : "";
}

function mergeStreamerRooms(first, second) {
  const result = [];
  const known = new Set();
  for (const source of [first, second]) {
    if (!Array.isArray(source)) continue;
    for (const room of source) {
      if (!room || typeof room !== "object") continue;
      const key = roomIdentity(room);
      if (key && known.has(key)) continue;
      if (key) known.add(key);
      result.push(room);
    }
  }
  return result;
}
