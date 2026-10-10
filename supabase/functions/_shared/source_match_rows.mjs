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
    const id = String(
      row.scheduleId ?? row.schedule_id ?? row.fixtureId ?? row.id ?? "",
    ).trim();
    if (!id) continue;
    const existing = matches.get(id);
    if (existing) {
      existing.hot ||= row.hot;
    } else {
      matches.set(id, row);
    }
  }
  return [...matches.values()];
}
