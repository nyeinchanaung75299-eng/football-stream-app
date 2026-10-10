# Football Stream Suite

Starter project for:
- `admin_app/` — Flutter admin dashboard inspired by the supplied reference UI
- `user_app/` — Flutter viewer app for active football matches
- `supabase/schema.sql` — Supabase tables + Row Level Security policies

## What is included

### Admin App
- Email/password admin login
- Dashboard
  - Upload Live
  - Upload Live Links
  - Edit & Delete Live
  - Highlights Management
- Match metadata upload
- Multiple HLS (`.m3u8`) / DASH (`.mpd`) links per match
- Activate/deactivate and delete matches
- Supabase-backed data

### User App
- Reads active matches
- Shows league / teams / kickoff
- Lets the user choose an active stream link
- Opens the stream in a player screen

> Use only streams you own or are authorized to distribute.

## 1. Create Supabase project

For a new project, open Supabase SQL Editor and run the base schema:

`supabase/schema.sql`

Then apply **all files in `supabase/migrations/` in filename order** before
publishing the apps or adding stream credentials. The base schema alone is not
the current production setup. Follow [Database migrations](docs/DATABASE_MIGRATIONS.md)
for fresh setup and existing-project history repair; do not replay historical
migrations on an existing production database.

Then create an Auth user with email/password.

After the user exists, promote it to admin:

```sql
insert into public.profiles (id, role)
select id, 'admin'
from auth.users
where email = 'YOUR_ADMIN_EMAIL'
on conflict (id) do update set role = excluded.role;
```

## 2. Run Admin App

Supabase URL and publishable key are already configured in `admin_app/lib/main.dart`.

```bash
cd admin_app
flutter pub get
flutter run
```

## 3. Run User App

Supabase URL and publishable key are already configured in `user_app/lib/main.dart`.

```bash
cd user_app
flutter pub get
flutter run
```bash
cd user_app
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

## Notes

- Do NOT put the Supabase service-role key in either app.
- RLS allows only users with `profiles.role = 'admin'` to create/update/delete content.
- Anonymous users can read published match metadata and safe stream counts.
  Raw playback URLs and keys remain behind the protected gateway.
- This starter targets the common Android use case. Test your exact HLS/DASH streams on the target devices.
- DRM-protected streams require the proper licensed DRM integration and cannot be handled by merely pasting a URL.

## V2: Own ClearKey / headers / WebView

`Upload Live Links` now supports:
- Resolution / server label
- HLS or MPD/DASH URL
- Referer header
- Origin header
- ClearKey `keyID` + `keyData` in HEX (Android)
- Optional WebView URL
- Player/WebView switch
- Player notification switch

If this Supabase project already used the original schema, run:
`supabase/upgrade_stream_links_v2.sql`

ClearKey is client-side DRM and is not strong key secrecy. For stronger protection use a licensed DRM system and license server.
