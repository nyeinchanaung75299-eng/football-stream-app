# NCA Admin history audit — 2026-10-05

စစ်ဆေးချိန် main HEAD: `7660b7fc1c3ab15f9b255aad85f544f1189a81f5`။ Full clone သည် shallow မဟုတ်ပါ။ Reachable commits 319 ခု၊ remote branches 5 ခု၊ tags မရှိ၊ main commits 289 ခုကို စစ်ခဲ့သည်။ Historical Admin text paths 31 ခုမှ unique blobs 84 ခုနှင့် deleted legacy snapshots ကိုပါ နှိုင်းခဲ့သည်။ GitHub မှ မရှိတော့သော unreachable/deleted history ကို ဤ audit က အတည်မပြုနိုင်ပါ။

## Link tools အလိုက် ရလဒ်

| Feature | အရင် implementation / commits | လက်ရှိ state / files / functions |
|---|---|---|
| Standalone link generator | Reachable history တွင် သီးသန့် generator page/function မတွေ့ | ခန့်မှန်းပြီး အသစ် မရေးရန် |
| Stream URL extractor / source picker | [74b732f](https://github.com/nyeinchanaung75299-eng/football-stream-app/commit/74b732f) Soco picker; [fbd4f26](https://github.com/nyeinchanaung75299-eng/football-stream-app/commit/fbd4f26) YYZB/Fawa tabs | ဆက်ရှိသည်။ `admin_app/lib/screens/soco_import_page.dart` → `SocoImportPage`, `_loadSoco`, `_addLine`; `supabase/functions/source-match-list/index.ts` + `supabase/functions/soco-links/index.ts`; authenticated `FunctionGateway.invoke` |
| Control Center source picker route | [5927471](https://github.com/nyeinchanaung75299-eng/football-stream-app/commit/5927471) dashboard entry; [003f028](https://github.com/nyeinchanaung75299-eng/football-stream-app/commit/003f028) Stream Source Picker rename | မပျောက်ပါ။ `dashboard_page.dart` → `/admin/stream-source-picker`; Stream Servers ကနေလည်း `SocoImportPage(initialMatchId: matchId)` ဝင်နိုင်သည် |
| URL converter / DASH↔HLS transcoder | Standalone converter သို့မဟုတ် media transcoding implementation မတွေ့ | `dart:convert` သည် gateway JSON encoding ဖြစ်သည်။ Stream type detection သည် URL conversion မဟုတ်ပါ |
| MPD / M3U8 controls | [3d31405](https://github.com/nyeinchanaung75299-eng/football-stream-app/commit/3d31405) link form; [c54cf28](https://github.com/nyeinchanaung75299-eng/football-stream-app/commit/c54cf28) V7.2 auto detection / DASH-only ClearKey visibility | `live_links_page.dart` → `detectStreamType`, add/edit forms; HLS/DASH/FLV/MP4 detection ဆက်ရှိသည် |
| Referer / Origin / ClearKey / WebView | [bc704e8](https://github.com/nyeinchanaung75299-eng/football-stream-app/commit/bc704e8) Advanced options ထဲ ပြောင်းထားသည် | Delete မလုပ်ထားပါ။ `LiveLinksPage` add/edit Advanced options မှ ဝင်နိုင်သည် |
| Stream testing / health | [fa450fe](https://github.com/nyeinchanaung75299-eng/football-stream-app/commit/fa450fe), [4bf9c29](https://github.com/nyeinchanaung75299-eng/football-stream-app/commit/4bf9c29) health controls; [3989a51](https://github.com/nyeinchanaung75299-eng/football-stream-app/commit/3989a51) gateway routing | `live_links_page.dart` → `testHealth`, `checkHealth`, `checkAllHealth`; `supabase/functions/stream-health/index.ts`။ TEST ALL / per-server check ဆက်ရှိသည် |
| Admin playback preview | Standalone Admin player/preview implementation မတွေ့ | Health check ကို playable preview ဟု မဆိုနိုင်ပါ |
| Proxy link generation | [c801e8f](https://github.com/nyeinchanaung75299-eng/football-stream-app/commit/c801e8f) protected Cloudflare playback sessions | Backend `cloudflare/public-api/src/index.js` `/matches/:id/streams` → temporary `/p/<token>`။ အရင် Admin generator card အဖြစ် ရှိခဲ့သည့် အထောက်အထား မတွေ့ |
| Copy / share link | [74b732f](https://github.com/nyeinchanaung75299-eng/football-stream-app/commit/74b732f) source sheet Copy link | `soco_import_page.dart` → `Clipboard.setData` ဆက်ရှိသည်။ OS share integration သီးသန့် မတွေ့ |
| Upload Live Links | [3d31405](https://github.com/nyeinchanaung75299-eng/football-stream-app/commit/3d31405) dashboard entry; [5c94fed](https://github.com/nyeinchanaung75299-eng/football-stream-app/commit/5c94fed) Control Center redesign | `LiveLinksPage` ကို Stream Servers အမည်ဖြင့် ပြောင်းထားသည်။ Feature မဖျက်ထားပါ |

## တကယ်ပျောက်သွားသော menu/control

**Upload Highlight menu**: [3d31405856bed6072c12c6fea2b0f16f968e1f3d](https://github.com/nyeinchanaung75299-eng/football-stream-app/commit/3d31405856bed6072c12c6fea2b0f16f968e1f3d) တွင် ရှိခဲ့ပြီး [7da84dfdb30e45377e0228cd0d6b554b99835ea7](https://github.com/nyeinchanaung75299-eng/football-stream-app/commit/7da84dfdb30e45377e0228cd0d6b554b99835ea7) (Admin `1.2.0+3`) သည် page implementation နောက်ဆုံးပြောင်းခဲ့သော commit ဖြစ်သည်။ Menu သည် removal မတိုင်မီ Admin `1.3.0+4` အထိ ဆက်ရှိခဲ့သည်။

[bc704e88f607fd5dedd72f93d7d5211c367635f5](https://github.com/nyeinchanaung75299-eng/football-stream-app/commit/bc704e88f607fd5dedd72f93d7d5211c367635f5) (Admin `1.5.0+9`) တွင် `dashboard_page.dart` မှ Highlights import/card/`open(context, const HighlightsPage())` route ဖယ်ခဲ့သည်။ `admin_app/lib/screens/highlights_page.dart` / `HighlightsPage` / `save()` သည် လက်ရှိ code ထဲ ဆက်ရှိပြီး အရင် `7da84df` implementation နှင့် တူသည်။ ဤ tool သည် title, thumbnail URL, video URL ကို `public.highlights` ထဲ သိမ်းသော tool ဖြစ်ပြီး stream generator/converter မဟုတ်ပါ။

Live Supabase metadata မှ `highlights` fields နှင့် current page insert payload ကိုက်ညီကြောင်း အတည်ပြုသည်။ RLS enabled; authenticated admins အတွက် `is_admin()` manage policy နှင့် active highlights အတွက် public read policy ရှိသည်။ Route ပြန်ချိတ်ရန် backend/schema change မလိုပါ။

**Player notification checkbox**: [64d4638](https://github.com/nyeinchanaung75299-eng/football-stream-app/commit/64d4638) တွင် `sendNotification` checkbox / `send_notification` field ရှိခဲ့ပြီး `bc704e8` တွင် UI ဖယ်၍ value ကို false ထားသည်။ Working notification sender implementation ကို မတွေ့သဖြင့် link tool အဖြစ် restore မလုပ်ရန်။

## Deployment နှင့် screenshot ကွာခြားမှု

စစ်ဆေးခဲ့သော HEAD `7660b7f` (restore မလုပ်မီ) မှာ Control Center cards 5 ခုရှိသည်: Pick Big Matches, Manual Match, Matches & Scores, Stream Servers, Stream Source Picker။ Screenshot မှာ 4 ခုသာမြင်ရခြင်းသည် older installed APK သို့မဟုတ် scroll position ကြောင့် ဖြစ်နိုင်သည်ဟုသာ ခန့်မှန်းနိုင်ပြီး source deletion အဖြစ် မအတည်ပြုနိုင်ပါ။ Workflow/artifact label သည် V9.8 ဖြစ်သော်လည်း Admin pubspec သည် `2.5.0+16` ဖြစ်သည်။

Live `stream-health` နှင့် `source-match-list` code သည် current source နှင့် ကိုက်ညီသည်။ Live `soco-links` v3 သည် [3bd75cc](https://github.com/nyeinchanaung75299-eng/football-stream-app/commit/3bd75cc) code ဖြစ်ပြီး current [93aa0b2](https://github.com/nyeinchanaung75299-eng/football-stream-app/commit/93aa0b2) ၏ friendly labels, Fawa parsing နှင့် source line health probes မပါသေးပါ။ ဤသည် deployed backend အဟောင်းဖြစ်နေခြင်း ဖြစ်သည်။ Existing implementation ကို compatible ဖြစ်အောင် deploy စစ်ရန် လိုသည်။

`aee8f3e` သည် duplicate V7.1 snapshots/docs နှင့် duplicate root SQL/function/workflow copies ကို ဖယ်ခဲ့သည်။ Active Admin tool files ကို cleanup မှာ မဖျက်ခဲ့ပါ။ `9075607` မှ deleted-file list သည် feed orphan branch reset ဖြစ်ပြီး main Admin features ပျောက်ခြင်း မဟုတ်ပါ။

## Restore အတွက် အခြေခံ

V9.8 UI ကို rollback မလုပ်ဘဲ အရင် working `HighlightsPage` route ကို လက်ရှိ card style ဖြင့် ပြန်ချိတ်နိုင်သည်။ ရှိပြီးသား source picker, extraction, copy, advanced fields, stream health controls ကို ဆက်သုံးရမည်။ Generator/converter/preview/share tool အသစ်ကို history အထောက်အထားမရှိဘဲ မထည့်ရ။ Viewer source ကို ပြင်ရန် မလိုပါ။

## ပြန်ချိတ်ထားသော implementation နှင့် စစ်ဆေးချက်

- `admin_app/lib/screens/dashboard_page.dart` တွင် retained `HighlightsPage` import နှင့် “Highlights Management” card ပြန်ထည့်၍ current `open()` မှ `/admin/highlights` route သို့ ချိတ်ထားသည်။ Card wording နှင့် page သည် အရင် `7da84df` implementation အပေါ် အခြေခံသည်။ Retained page ကို ပြန်မရေးထားပါ။ Existing cards 5 ခု မပြောင်းဘဲ စုစုပေါင်း 6 ခု ဖြစ်သည်။
- Repo history report ကို `docs/ADMIN_LINK_TOOL_HISTORY.md` တွင် ထည့်ထားသည်။ Viewer source နှင့် workflow configuration ကို မပြင်ထားပါ။
- Live `soco-links` ကို current repo implementation (နောက်ဆုံး function change `93aa0b2ddfb292386236ec2e64a3d5fb3a1064a7`) ဖြင့် Supabase plugin မှ deploy လုပ်ပြီး ACTIVE v4 ဖြစ်သည်။ Function ID `4462e3d4-ad7f-41a0-9b0e-4407f9632427`။ Exact source readback ကိုက်ညီသည်။ Existing `verify_jwt=false` setting နှင့် function ထဲ signed-user/admin role checks ကို ဆက်ထိန်းထားသည်။ Database/Worker/secret changes မရှိပါ။
- Mocked fixtures 10 ခုတွင် JSONP, friendly labels, HLS/DASH/FLV/MP4 classification, expiry parsing, source host validation, nested Fawa markup, link/header contracts, Soco quality variants, media health states နှင့် unsigned auth rejection pass ဖြစ်သည်။ Live direct Supabase နှင့် Cloudflare admin gateway နှစ်ခုစလုံး unsigned POST ကို HTTP 401 ပြန်ပေးပြီး raw lines မထုတ်ပါ။
- Dart 3.13.5 parser/formatter check နှင့် `git diff --check` pass ဖြစ်သည်။ Local Flutter dependency resolution သည် Windows Dart process error ကြောင့် မပြီးခဲ့သဖြင့် full analysis/build အတွက် existing GitHub Actions quality gates ကို သုံးသည်။
- Third-party live source availability, authenticated Admin publish/import နှင့် installed Android UI ကို automated test မလုပ်ထားပါ။ Production rows မရေးဘဲ schema/RLS, parser fixtures နှင့် auth denial ကို စစ်ထားသည်။ APK build results ကို final delivery တွင် သီးသန့် အတည်ပြုမည်။
