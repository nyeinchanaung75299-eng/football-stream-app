import assert from "node:assert/strict";
import { test } from "node:test";
import { playzMatches, playzStreams } from "../supabase/functions/_shared/playz_source.mjs";

test("PlayZ Admin catalog includes sports channels and match sections", () => {
  const channels = playzMatches({ catalog: "channels" });
  const matches = playzMatches({ catalog: "matches" });
  assert.equal(channels.source, "playz");
  assert.equal(channels.catalog, "channels");
  assert.ok(channels.matches.length >= 20);
  assert.ok(channels.matches.every((row) => row.kind === "channel" && row.anchors.length === 1));
  assert.equal(matches.catalog, "matches");
  assert.ok(matches.matches.every((row) => row.kind === "match"));
});

test("PlayZ returns only keyless HTTPS direct media lines", () => {
  const channel = playzMatches({ catalog: "channels" }).matches[0];
  const result = playzStreams({ room_num: channel.source_id });
  assert.ok(result.lines.length > 0);
  for (const line of result.lines) {
    assert.match(line.url, /^https:\/\//);
    assert.equal(line.key_id, null);
    assert.equal(line.key_data, null);
    assert.ok(["hls", "dash", "flv", "mp4", "auto"].includes(line.stream_type));
  }
});

test("PlayZ rejects arbitrary source IDs", () => {
  assert.throws(() => playzStreams({ room_num: "https://attacker.test/live.m3u8" }), /Invalid PlayZ/);
  assert.throws(() => playzStreams({ room_num: "channel:99999" }), /no longer available/);
});
