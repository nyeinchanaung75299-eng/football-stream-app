import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { sendTelegramReleaseApk, ReleaseDeliveryError } from
  "../supabase/functions/_shared/telegram_apk_delivery.mjs";

const BASE = "https://raw.githubusercontent.com/nyeinchanaung75299-eng/football-stream-app/feed/public/releases/";
const bytes = new TextEncoder().encode("fixture-apk-not-a-real-binary");
const digest = createHash("sha256").update(bytes).digest("hex");

function fixture(kind = "viewer", overrides = {}) {
  const calls = [];
  const admin = kind === "admin";
  const apk = admin ? "NCA-admin-arm64-v8a-latest.apk" : "NCA-arm64-v8a-latest.apk";
  const manifest = {
    ...(admin ? { app: "nca_admin" } : {}),
    version_name: admin ? "2.5.3" : "9.8.0",
    build_number: 30739,
    apk_url: BASE + apk,
    abi: "arm64-v8a",
    sha256: digest,
    size_bytes: bytes.byteLength,
    ...overrides,
  };
  const fetcher = async (input, options = {}) => {
    const url = String(input);
    calls.push({ url, options });
    if (url === BASE + (admin ? "admin-latest.json" : "latest.json"))
      return Response.json(manifest);
    if (url === BASE + apk)
      return new Response(bytes, { status: 200, headers: { "content-length": String(bytes.byteLength) } });
    if (url === "https://api.telegram.org/botfake-token/sendDocument")
      return Response.json({ ok: true, result: { message_id: 10 } });
    throw Error("Unexpected outbound URL in test: " + url);
  };
  return { calls, fetcher, manifest };
}

test("Viewer APK sends actual multipart .apk bytes after strict SHA and size validation", async () => {
  const f = fixture();
  const result = await sendTelegramReleaseApk({
    kind: "viewer", chatId: 123, token: "fake-token", fetcher: f.fetcher,
  });
  assert.deepEqual(result, { version: "9.8.0", build: 30739 });
  const telegram = f.calls.find(c => c.url.endsWith("/sendDocument"));
  assert.ok(telegram);
  assert.ok(telegram.options.body instanceof FormData);
  assert.equal(telegram.options.body.get("chat_id"), "123");
  const document = telegram.options.body.get("document");
  assert.equal(document.name, "NCA-Viewer-arm64.apk");
  assert.equal(document.size, bytes.byteLength);
  assert.deepEqual(new Uint8Array(await document.arrayBuffer()), bytes);
  assert.match(telegram.options.body.get("caption"), /SHA-256/);
  assert.equal(f.calls.length, 3);
});

test("Admin downloads use separate release manifest and APK, with exact allowed URL", async () => {
  const f = fixture("admin");
  await sendTelegramReleaseApk({
    kind: "admin", chatId: 111, token: "fake-token", fetcher: f.fetcher,
  });
  const doc = f.calls.at(-1).options.body.get("document");
  assert.equal(doc.name, "NCA-Admin-arm64.apk");
  assert.ok(f.calls[0].url.endsWith("/admin-latest.json"));
  assert.ok(f.calls[1].url.endsWith("/NCA-admin-arm64-v8a-latest.apk"));
});

test("Rejects wrong hashes, sizes, APK URLs and oversized releases before Telegram upload", async () => {
  for (const overrides of [
    { sha256: "0".repeat(64) },
    { size_bytes: bytes.byteLength + 1 },
    { size_bytes: 51 * 1024 * 1024 },
    { apk_url: "https://evil.example/nca.apk" },
    { abi: "universal" },
    { build_number: -1 },
    { version_name: "not-a-version" },
  ]) {
    const f = fixture("viewer", overrides);
    await assert.rejects(() => sendTelegramReleaseApk({
      kind: "viewer", chatId: 123, token: "fake-token", fetcher: f.fetcher,
    }), ReleaseDeliveryError);
    assert.equal(f.calls.some(c => c.url.endsWith("/sendDocument")), false);
  }
});

test("Unexpected release kind and invalid chat never fetch or send anything", async () => {
  const f = fixture();
  await assert.rejects(() => sendTelegramReleaseApk({
    kind: "unknown", chatId: 123, token: "fake-token", fetcher: f.fetcher,
  }), ReleaseDeliveryError);
  await assert.rejects(() => sendTelegramReleaseApk({
    kind: "viewer", chatId: "forged", token: "fake-token", fetcher: f.fetcher,
  }), ReleaseDeliveryError);
  assert.equal(f.calls.length, 0);
});
