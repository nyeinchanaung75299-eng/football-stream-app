// Providers repeat featured schedules in a `hot` group. Keep that membership
// when the main schedule list appears first, without changing match metadata.
export function isFootballSourceRow(row, { allowUnclassified = false } = {}) {
  const id = value => value == null || value === '' ? NaN : Number(value);
  const sport = id(row?.sportId ?? row?.sport_id ?? row?.sport?.id);
  const category = id(row?.categoryId ?? row?.category_id);
  if ([sport, category].some(value => Number.isFinite(value) && value > 0 && value !== 1)) return false;
  const names = [row?.categoryName, row?.subCateName, row?.leagueName,
    row?.sportName, row?.sport?.name, row?.sport?.slug,
    row?.tournament?.name_en, row?.tournament?.name]
    .filter(value => typeof value === 'string').join(' ').toLowerCase();
  if (/basketball|volleyball|tennis|esport|cricket|baseball|hockey|rugby|american\s*football|\bnfl\b|\bnba\b|\bncaa\b|\bncaaf\b|\bnhl\b|boxing|\bufc\b|\bmma\b|motogp|formula|篮球|籃球|排球|网球|網球|电竞|電競|كرة\s*السلة|تنس|كريكت/.test(names)) return false;
  if (sport === 1 || category === 1) return true;
  if (/football|soccer|足球|كرة\s*القدم/.test(names)) return true;
  // Soco's legacy feed sometimes omits its sport field. YYZB must supply
  // positive football metadata; a pair of team names is not sport evidence.
  return allowUnclassified && !Number.isFinite(category) &&
    (row?.hostName != null || row?.homeName != null || row?.homeTeam != null || row?.teams?.home != null) &&
    (row?.guestName != null || row?.awayName != null || row?.awayTeam != null || row?.teams?.away != null);
}

export function hasPublishedSourceRoom(row) {
  return Array.isArray(row?.anchors) && row.anchors.some(anchor => {
    const room = String(anchor?.room_num ?? '').trim();
    return /^[A-Za-z0-9_-]{1,64}$/.test(room) && !['0', 'null', 'undefined'].includes(room);
  });
}

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
    value.away_team != null || value.homeTeamName != null ||
    value.awayTeamName != null || value.hostTeamName != null ||
    value.guestTeamName != null ||
    (value.homeTeam != null && value.awayTeam != null) ||
    (value.hostTeam != null && value.guestTeam != null) ||
    (value.teams?.home != null && value.teams?.away != null);
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
      // YYZB featured and ordinary lists may contain the same match ID
      // with different completeness: one has room data, the other team names
      // and logos. Preserve non-empty identity metadata from both records.
      for (const key of teamMetadataFields) {
        const value = existing[key];
        const replacement = row[key];
        const missing = value == null ||
          (typeof value === "string" && !value.trim()) ||
          (typeof value === "object" && !Array.isArray(value) &&
           Object.keys(value).length === 0);
        if (missing && replacement != null &&
            (typeof replacement !== "string" || replacement.trim())) {
          existing[key] = replacement;
        }
      }
    } else {
      matches.set(id, { ...row });
    }
  }
  return [...matches.values()];
}

// Only presentation metadata is filled in here: never overwrite stable
// schedule IDs, stream room IDs, signed playback URLs or match status.
const teamMetadataFields = [
  "hostName", "guestName", "homeName", "awayName", "hostNameEn",
  "guestNameEn", "homeNameEn", "awayNameEn", "hostTeamName",
  "guestTeamName", "hostTeamNameEn", "guestTeamNameEn",
  "homeTeamName", "awayTeamName", "homeTeamNameEn", "awayTeamNameEn",
  "home_team", "away_team", "homeTeam", "awayTeam", "hostTeam",
  "guestTeam", "host", "guest", "home", "away", "teams",
  "team1Name", "team2Name", "team1", "team2",
  "hostIcon", "guestIcon", "hostLogo", "guestLogo", "hostPic",
  "guestPic", "homeIcon", "awayIcon", "homeLogo", "awayLogo",
  "homeTeamLogo", "awayTeamLogo", "team1Logo", "team2Logo",
  "subCateName", "subCateNameEn", "leagueName", "leagueNameEn",
  "competitionName", "competitionNameEn", "categoryName",
];

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
