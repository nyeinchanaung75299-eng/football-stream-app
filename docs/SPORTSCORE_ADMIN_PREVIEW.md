# SportScore read-only preview (NCA Admin)

This is an **opt-in test feature**, not a source replacement.

## Files

- `admin_app/lib/screens/sportscore_test_page.dart`: Admin-only display, no importing.
- `admin_app/lib/screens/dashboard_page.dart`: "SportScore Test Schedule" entry in Controls.
- `supabase/functions/sportscore-test/index.ts`: Authenticated, admin-role-checked, read-only fixture fetch.

## Setup (test environment / after review)

1. Deploy only the new function to the **intended test Supabase project**:

   ```bash
   supabase functions deploy sportscore-test --project-ref YOUR_TEST_PROJECT_REF
   ```

2. Build / run the Admin App pointing at the same project and sign in as an
   account with `profiles.role = 'admin'`.
3. Open **Controls → SportScore Test Schedule**.
4. Select Saudi Pro League, MLS, Premier League, or Champions League and
   a Myanmar calendar date. Press **Load Test Fixtures**.
5. Check kickoff times, status and match counts against official fixtures.

There is no automatic polling; each button press reads only the provider.
No database migrations or tables are required. The existing
`football-fixtures` provider chain, ColaTV selection, User App, and scheduled
score synchronization are not changed.

## Time handling

The screen selects a calendar day in Myanmar Standard Time (UTC+06:30).
The function requests both the preceding and selected **UTC** calendar day,
then returns only matches whose kickoff is on the requested Myanmar day.
Times are displayed as MMT. A failure on either UTC request fails the whole
preview instead of showing an incomplete list.

Provider requests use a maximum of 200 per UTC day. If either day returns
200 records, the UI warns that results may be truncated. This is a **test
preview**, not verified complete historical data.

## Safety / access

- The Edge Function checks the Supabase Auth user and the
  `profiles.role = 'admin'` authorization before calling SportScore.
- The competition slug is limited to the four above, and date is validated.
- Only read requests to SportScore and an admin-role lookup are performed.
- This feature must **not** be wired to fixture import, matches writes,
  User App or public feeds without additional review.
- The preview includes a visible **Powered by SportScore** hyperlink.
  Review the provider's current attribution, HTML backlink, and commercial
  licensing rules before any public or production release. A native-app link
  does not necessarily satisfy an HTML dofollow backlink requirement.

## Validation checklist

- [ ] Build and test Admin Flutter project
- [ ] Signed-out request is denied
- [ ] Signed-in non-admin request is denied
- [ ] Admin request returns JSON for all four supported leagues
- [ ] UTC-midnight boundary matches display on the correct MMT day
- [ ] Provider failure shows an error, not a fallback to ColaTV
- [ ] No new rows appear in `matches` or other app tables
- [ ] Current production fixtures and User App are unchanged
