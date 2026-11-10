import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const native = readFileSync('user_app/android_patch/NativePlayerActivity.kt','utf8');
const web = readFileSync('user_app/web/index.html','utf8');
const embedded = readFileSync('user_app/assets/embedded_player.html','utf8');

test('Android portrait player is top-aligned and landscape header overlays picture', () => {
  assert.match(native, /topMargin = if \(landscape\) 0 else headerHeight/);
  assert.match(native, /topMargin = 0/);
  assert.doesNotMatch(native, /\(root\.height - headerHeight - portraitHeight - railHeight\) \/ 2/);
  assert.match(native, /val portraitHeight = \(root\.width \* 9f \/ 16f\)/);
});

test('Native Android settings match the Web header, tab names, font sizes and close X', () => {
  assert.match(native, /text = "PLAYER SETTINGS"/);
  assert.match(native, /overlayButton\("✕"\)/);
  assert.match(native, /"video" to "VIDEO", "audio" to "AUDIO"/);
  assert.match(native, /"subtitles" to "SUBTITLES", "speed" to "SPEED"/);
  assert.match(native, /private fun addSettingsChoice/);
  assert.match(native, /textSize = 12f/);
  assert.match(native, /textSize = 10f/);
  assert.match(native, /Color\.rgb\(56, 185, 121\)/);
  assert.match(native, /text = "✓"/);
  assert.match(native, /private fun closeSettingsMenu/);
  assert.doesNotMatch(native, /PopupMenu\(this, settingsButton\)/);
});

test('Web controls remain on Android Media3 video and retain all four track menus', () => {
  for (const text of ['↶5','15↷','● LIVE','Resolution audio and playback speed',
    'Adaptive quality','Audio track','Subtitle track','Playback speed','Normal · 1×']) {
    assert.ok(native.includes(text), 'Missing: ' + text);
  }
  assert.match(native, /videoHost\.addView\(compactControls/);
  assert.match(native, /C\.TRACK_TYPE_VIDEO/);
  assert.match(native, /C\.TRACK_TYPE_AUDIO/);
  assert.match(native, /C\.TRACK_TYPE_TEXT/);
  assert.match(native, /ExoPlayer\.Builder\(this\)/);
  assert.match(native, /private fun recoverOrFallback/);
});

test('Web Fit Full Zoom button is compact, while iOS maintains its own sizing', () => {
  assert.match(web, /Compact Fit \/ Full \/ Zoom selector/);
  assert.match(web, /#football-player-overlay:not\(\.ios-native-mode\) #football-player-fit\{/);
  assert.match(web, /min-width:34px;max-width:34px;width:34px/);
  assert.match(web, /height:34px;min-height:34px;max-height:34px/);
  assert.match(web, /font-size:11px;font-weight:700/);
  assert.match(embedded, /Compact Fit \/ Full \/ Zoom selector/);
  assert.match(web, /#football-player-overlay\.ios-native-mode #football-player-fit,/);
});
