# API-Football fixture picker setup

The Admin app now has two ways to create matches:

1. **Pick Football Fixtures**
   - Load a date or currently live fixtures.
   - Tick only the matches you want.
   - Press **ADD SELECTED**.
   - Team names, league, kickoff time and API team logos are imported.
   - Nothing is shown to users until you select/import it.

2. **Create Match Manually**
   - Enter everything yourself.
   - Use your own logo URLs.

After importing an API match, **Edit Matches** can still change:
- team names
- league
- home/away logo URL
- date
- time
- LIVE status
- Active/Hidden status

So API logos are optional. You can replace either logo manually later.

## One-time Supabase setup

### A. Database
Run:

`supabase/upgrade_fixture_import_v6_3.sql`

in the Supabase SQL Editor.

### B. Create an API-Football key
Create an API-Football account and copy your API key.

### C. Keep the key out of the APK
Add the key to Supabase Edge Function secrets:

`API_FOOTBALL_KEY=YOUR_KEY`

Do not put this key in Flutter source code.

### D. Deploy the Edge Function
Deploy:

`supabase/functions/football-fixtures/index.ts`

as an Edge Function named:

`football-fixtures`

The function checks that the caller is an authenticated admin before it requests fixtures.
