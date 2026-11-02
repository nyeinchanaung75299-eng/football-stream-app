// Shared provider team-logo extraction for Admin and Viewer. Preserve
// team metadata; never mistake streamer avatar icons for football badges.

export function sourceLogo(
  row: any,
  side: "home" | "away",
  source: "soco" | "yyzb",
) {
  const home = side === "home";
  const directCandidates = home
    ? [
        row?.hostLogo, row?.hostLogoUrl, row?.host_logo, row?.host_logo_url,
        row?.hostIcon, row?.hostIconUrl, row?.hostPic, row?.hostImage,
        row?.homeLogo, row?.homeLogoUrl, row?.home_logo, row?.home_logo_url,
        row?.homeIcon, row?.homeIconUrl, row?.homePic, row?.homeImage,
        row?.homeCrest, row?.homeCrestUrl, row?.homeTeamLogo, row?.home_team_logo,
        row?.team1Logo, row?.team1_logo,
      ]
    : [
        row?.guestLogo, row?.guestLogoUrl, row?.guest_logo, row?.guest_logo_url,
        row?.guestIcon, row?.guestIconUrl, row?.guestPic, row?.guestImage,
        row?.awayLogo, row?.awayLogoUrl, row?.away_logo, row?.away_logo_url,
        row?.awayIcon, row?.awayIconUrl, row?.awayPic, row?.awayImage,
        row?.awayCrest, row?.awayCrestUrl, row?.awayTeamLogo, row?.away_team_logo,
        row?.team2Logo, row?.team2_logo,
      ];

  const nested = home
    ? [
        row?.host, row?.home, row?.homeTeam, row?.teams?.home, row?.team1,
      ]
    : [
        row?.guest, row?.away, row?.awayTeam, row?.teams?.away, row?.team2,
      ];

  for (const value of directCandidates) {
    const normalized = normalizeLogoUrl(value, source);
    if (normalized) return normalized;
  }

  for (const obj of nested) {
    if (!obj || typeof obj !== "object") continue;
    for (const key of [
      "logo", "logoUrl", "logo_url", "crest", "crestUrl", "crest_url",
      "icon", "iconUrl", "icon_url", "image", "imageUrl", "image_url",
      "avatar", "avatarUrl", "avatar_url", "pic", "photo",
    ]) {
      const normalized = normalizeLogoUrl(obj?.[key], source);
      if (normalized) return normalized;
    }
  }

  // Last-resort schema-tolerant scan. Some source revisions rename team
  // image fields without notice, so accept side-specific image-ish keys.
  const sideWords = home
    ? ["home", "host", "team1", "team_1"]
    : ["away", "guest", "team2", "team_2"];
  const imageWords = ["logo", "crest", "icon", "image", "avatar", "pic", "photo"];

  for (const [key, value] of Object.entries(row ?? {})) {
    const lower = key.toLowerCase();
    if (!sideWords.some((word) => lower.includes(word.toLowerCase()))) continue;
    if (!imageWords.some((word) => lower.includes(word))) continue;
    const normalized = normalizeLogoUrl(value, source);
    if (normalized) return normalized;
  }

  return null;
}

function normalizeLogoUrl(value: unknown, source: "soco" | "yyzb") {
  if (value == null) return null;
  const raw = String(value).trim();
  if (!raw || raw === "null" || raw === "undefined") return null;

  if (raw.startsWith("//")) return "https:" + raw;

  try {
    const url = new URL(raw);
    if (url.protocol === "http:" || url.protocol === "https:") {
      return url.toString();
    }
  } catch (_) {}

  // YYZB team assets are often hosted separately from its JSON feed.
  // Keep both absolute paths and relative file/imgs paths, not merely URLs
  // with an explicit HTTP scheme.
  if (/^(\\/)?file\\/(?:imgs?|images?)\\//i.test(raw) && source === "yyzb") {
    return new URL(raw.replace(/^\\//, ""), "https://sta.ncctrials.com/").toString();
  }
  if (raw.startsWith("/") || /^[\\w.-]+\\/(?:[\\w.-]+\\/)*[\\w.-]+$/.test(raw)) {
    const base = source === "yyzb"
      ? "https://json.ncctrials.com/"
      : "https://json.vnres.co/";
    try {
      return new URL(raw, base).toString();
    } catch (_) {}
  }

  return null;
}

