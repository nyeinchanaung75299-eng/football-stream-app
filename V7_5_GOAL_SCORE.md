# V7.5 Goal Score

Goal score is now explicit in both Viewer and Admin.

Viewer:
- Live and finished matches show a score board in the center.
- A live match displays 0-0 until the first API score arrives, instead of VS.
- Supabase Realtime refreshes the card when a score/status row changes.

Admin:
- Edit Match has a Goal Score panel.
- Home/Away score can be corrected manually.
- + GOAL and minus buttons make quick live corrections easier.
- Sync Scores requests an immediate API refresh for signed-in admins.

Backend:
- football-score-sync accepts either the Cron secret or a signed-in admin session.
- Admin force sync bypasses the normal score-sync interval.
- Only published, featured matches with external fixture IDs are auto-synced.
