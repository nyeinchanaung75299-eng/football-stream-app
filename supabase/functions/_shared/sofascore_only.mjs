/** Guard the Admin's SofaScore-only feed against accidental provider fallback. */
export function requireSofaScoreOnlyResult(payload) {
  if (payload?.source !== "sofascore" ||
      payload?.served_by !== "sofascore" ||
      !Array.isArray(payload?.matches) ||
      payload.matches.some((row) => row?.source !== "sofascore" || row?.provider !== "sofascore")) {
    throw new Error("SofaScore-only mode rejected non-SofaScore fixtures.");
  }
  return payload;
}

/** An error or challenge page must not look like a legitimate empty fixture day. */
export function requireSofaScoreEvents(payload) {
  if (!payload || !Array.isArray(payload.events)) {
    throw new Error("SofaScore response did not contain a valid events array.");
  }
  return payload.events;
}
