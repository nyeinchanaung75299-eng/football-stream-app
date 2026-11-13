import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const native = readFileSync('user_app/android_patch/NativePlayerActivity.kt','utf8');
const web = readFileSync('user_app/web/index.html','utf8');
const embedded = readFileSync('user_app/assets/embedded_player.html','utf8');

test('Android portrait player is top-aligned and landscape header overlays picture', () => {
  assert.match(native, /height = if \(landscape\) root.height else portraitHeight/);
  assert.match(native, /videoHost\.addView\(\s*serverRailScroll/);
  assert.match(native, /bottomMargin = dp\(36\)/);
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

test('seven-second native UI auto-hide toggles all controls and respects settings', () => {
  assert.match(native, /controlsHideDelayMs = 7000L/);
  assert.match(native, /setControlsVisible\(!controlsVisible\)/);
  assert.match(native, /serverRailScroll\.visibility =\s*if \(visible && visibleServerIndices\(\)\.size > 1\)/);
  assert.match(native, /topBar\.visibility = if \(visible\)/);
  assert.match(native, /compactControls\.visibility = if \(visible\)/);
  assert.match(native, /settingsPanel\.visibility != View\.VISIBLE/);
  assert.match(native, /clearControlsHideTimer\(\)/);
});

test('native lines use no TV icon, separate 1080p/HLS/DASH/FLV tags and a slim progress track', () => {
  assert.match(native, /private fun safeLineFormat/);
  for(const type of ['HLS','DASH','FLV','MP4']) assert.ok(native.includes('"'+type+'"'));
  assert.match(native, /textSize = 10f/);

  assert.match(native, /setSingleChoiceItems\(labels/);
  assert.match(native, /Change line/);
  assert.match(native, /setLayerHeight\(layer, dp\(3\)\)/);
  assert.doesNotMatch(native, /📺/);
  assert.match(native, /LayerDrawable\(arrayOf/);
  assert.match(native, /ClipDrawable\(filledTrack/);
  assert.match(native, /setSize\(dp\(100\), dp\(3\)\)/);
  assert.doesNotMatch(native, /thumbTintList = ColorStateList\.valueOf\(Color\.rgb\(71, 229, 158\)\)/);
});

test('Web and embedded variants show overlay-only lines with no reserved rail strip', () => {
  for(const html of [web,embedded]) {
    assert.match(html, /<!-- Inside the picture: hiding lines must not reserve a black strip/);
    assert.match(html, /#football-player-video-wrap > #football-player-line-rail/);
    assert.match(html, /controlsTimer=setTimeout\(hideControls,7000\)/);
    assert.match(html, /football-line-chip-format/);
    assert.match(html, /function hideControls/);
    assert.match(html, /setTimeout\(hideControls,7000\)/);
  }
});

const workflow=readFileSync('.github/workflows/build-apks.yml','utf8');
test('Viewer and Admin release version codes are above older installed build 32748', () => {
  const matches=[...workflow.matchAll(/BUILD_NUMBER=\$\(\(40000 \+ GITHUB_RUN_NUMBER\)\)/g)];
  assert.equal(matches.length,2);
  assert.ok(40000+1>32748);
  assert.match(workflow,/verify_android_update_signing\.py/);
});
