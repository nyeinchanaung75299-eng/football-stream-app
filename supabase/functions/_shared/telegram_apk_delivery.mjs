// Deliver only the published, signed ARM64 NCA release from our fixed GitHub feed.
// This never accepts arbitrary URLs from a Telegram message or callback.
const RELEASE_BASE =
  "https://raw.githubusercontent.com/nyeinchanaung75299-eng/football-stream-app/feed/public/releases/";
const MAX_APK_BYTES = 45 * 1024 * 1024; // Below Telegram's 50 MB Bot API upload limit.

const RELEASES = Object.freeze({
  viewer: {
    label: "NCA Viewer",
    manifest: "latest.json",
    apk: "NCA-arm64-v8a-latest.apk",
    filename: "NCA-Viewer-arm64.apk",
  },
  admin: {
    label: "NCA Admin",
    manifest: "admin-latest.json",
    apk: "NCA-admin-arm64-v8a-latest.apk",
    filename: "NCA-Admin-arm64.apk",
  },
});

const hex = bytes => Array.from(new Uint8Array(bytes), value =>
  value.toString(16).padStart(2, "0")).join("");

export class ReleaseDeliveryError extends Error {
  constructor(code) {
    super(code);
    this.name = "ReleaseDeliveryError";
    this.code = code;
  }
}

export async function sendTelegramReleaseApk({ kind, chatId, token, fetcher = fetch }) {
  const release = RELEASES[kind];
  if (!release || !Number.isSafeInteger(chatId) || !token)
    throw new ReleaseDeliveryError("invalid_request");

  const manifestResponse = await fetcher(RELEASE_BASE + release.manifest, {
    headers: { Accept: "application/json" },
    cache: "no-store",
    signal: AbortSignal.timeout(15000),
  });
  if (!manifestResponse.ok) throw new ReleaseDeliveryError("manifest_unavailable");
  const manifest = await manifestResponse.json().catch(() => null);
  const apkUrl = RELEASE_BASE + release.apk;
  const size = manifest?.size_bytes;
  if (!manifest || manifest.apk_url !== apkUrl ||
      manifest.abi !== "arm64-v8a" ||
      !/^[a-f0-9]{64}$/i.test(manifest.sha256 || "") ||
      !Number.isSafeInteger(size) || size <= 0 || size > MAX_APK_BYTES ||
      !Number.isSafeInteger(manifest.build_number) || manifest.build_number <= 0 ||
      !/^\d+\.\d+\.\d+$/.test(manifest.version_name || "") ||
      (kind === "admin" && manifest.app !== "nca_admin")) {
    throw new ReleaseDeliveryError("invalid_release");
  }

  // Never post an unverified/mismatched binary to Telegram.
  const apkResponse = await fetcher(apkUrl, {
    headers: { Accept: "application/octet-stream" },
    cache: "no-store",
    signal: AbortSignal.timeout(60000),
  });
  if (!apkResponse.ok) throw new ReleaseDeliveryError("apk_unavailable");
  const reportedSize = Number(apkResponse.headers.get("content-length"));
  if (reportedSize > MAX_APK_BYTES || (reportedSize > 0 && reportedSize !== size))
    throw new ReleaseDeliveryError("size_mismatch");
  const bytes = await apkResponse.arrayBuffer();
  if (bytes.byteLength !== size) throw new ReleaseDeliveryError("size_mismatch");
  const sha = hex(await crypto.subtle.digest("SHA-256", bytes));
  if (sha !== manifest.sha256.toLowerCase())
    throw new ReleaseDeliveryError("sha_mismatch");

  const form = new FormData();
  form.set("chat_id", String(chatId));
  form.set("caption", "📦 " + release.label + " v" + manifest.version_name +
    "\nARM64 • Build " + manifest.build_number +
    "\nVerified SHA-256 from NCA release feed.\n" +
    "Install over an existing app only when its signing certificate matches.");
  form.set("document", new Blob([bytes], {
    type: "application/vnd.android.package-archive",
  }), release.filename);

  // Sending APK by URL is not supported reliably by Telegram Bot API.
  // Upload multipart bytes instead. Telegram stores the resulting document.
  const sent = await fetcher("https://api.telegram.org/bot" + token + "/sendDocument", {
    method: "POST",
    body: form,
    signal: AbortSignal.timeout(75000),
  });
  if (!sent.ok || (await sent.json().catch(() => null))?.ok !== true)
    throw new ReleaseDeliveryError("telegram_upload_failed");
  return { version: manifest.version_name, build: manifest.build_number };
}
