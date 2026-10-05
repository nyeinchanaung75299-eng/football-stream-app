# V8.2 chronological fixture ordering

Fix:
- Main Live now sorts matches by kickoff_at ascending.
- Date comes first, then time within the same date.
- sort_order is now only a tie-breaker when two fixtures have the same kickoff time.
- The GitHub mirror feed uses the same ordering.
- Client-side sorting is applied after both Supabase and mirror loads, so the UI stays correct even if the backend response order changes.

Example:
05 Oct 15:30
05 Oct 19:30
06 Oct 01:15
06 Oct 01:15
... rather than using admin sort_order as the primary order.
