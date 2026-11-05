import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { requireSofaScoreOnlyResult, requireSofaScoreEvents } from "./sofascore_only.mjs";

const realMatch = {
  source: "sofascore",
  provider: "sofascore",
  source_id: "123",
  home_team: "Ajax",
  away_team: "PSV",
};
const realResult = {
  ok: true, source: "sofascore", served_by: "sofascore", matches: [realMatch],
};

test("accepts only a genuine SofaScore response", () => {
  assert.equal(requireSofaScoreOnlyResult(realResult), realResult);
  assert.deepEqual(requireSofaScoreOnlyResult({ ...realResult, matches: [] }).matches, []);
});

test("rejects disguised API-Football / Soco / YYZB fallback", () => {
  for (const provider of ["fixture-fallback", "api_football", "soco", "yyzb"]) {
    assert.throws(
      () => requireSofaScoreOnlyResult({ ...realResult, matches: [{ ...realMatch, provider }] }),
      /rejected non-SofaScore/,
    );
  }
});

test("rejects inconsistent source metadata and malformed fixture payloads", () => {
  for (const result of [
    { ...realResult, served_by: "football-fixtures" },
    { ...realResult, source: "soco" },
    { ...realResult, matches: null },
    { ...realResult, matches: [{ ...realMatch, source: "yyzb" }] },
  ]) assert.throws(() => requireSofaScoreOnlyResult(result), /rejected non-SofaScore/);
});

test("only a real SofaScore events array can become matches", () => {
  assert.deepEqual(requireSofaScoreEvents({ events: [] }), []);
  assert.deepEqual(requireSofaScoreEvents({ events: [{ id: 123 }] }), [{ id: 123 }]);
  for (const payload of [{ error: "403 Forbidden" }, "<html>Challenge</html>", null, { events: null }]) {
    assert.throws(() => requireSofaScoreEvents(payload), /valid events array/);
  }
});

test("Backend and Admin routes never silently replace SofaScore with fallback", () => {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
  const server = readFileSync(resolve(root, "supabase/functions/source-match-list/index.ts"), "utf8");
  const client = readFileSync(resolve(root, "admin_app/lib/screens/fixture_import_page.dart"), "utf8");
  assert.match(server, /requireSofaScoreOnlyResult\(await sofascoreMatches\(body\.date\)\)/);
  assert.doesNotMatch(server, /fallbackFootballMatches\(/);
  assert.match(server, /code: "SOFASCORE_UNAVAILABLE"/);
  assert.match(client, /if \(provider == 'sofascore'\) rethrow;/);
  assert.match(client, /if \(rows\.isEmpty && provider == 'cola'\)/);
  assert.doesNotMatch(client, /provider == 'cola' \|\| provider == 'sofascore'/);
  assert.match(client, /data\['served_by'\]\?\.toString\(\) == 'sofascore'/);
});
