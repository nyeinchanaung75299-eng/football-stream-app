-- Use the verified finish when available. For an unconfirmed football
-- fixture, allow three hours from kickoff plus six hours in the list.
-- Keep these display estimates separate from the permanent-delete policy.
create or replace view public.repository_current_catalog
with (security_invoker = true) as
select c.*
from public.channel_source_catalog c
left join lateral (
  select min(r.finished_at) as finished_at
  from public.repository_fixture_retention r
  where r.entry_id=c.id or r.fixture_key=c.event_meta->>'fixture_key'
) recorded on c.event_meta->>'source_finished'='true'
cross join lateral (
  select case
    when c.event_meta->>'source_time' ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
      then regexp_replace(c.event_meta->>'source_time',
        '^([0-9]{2})/([0-9]{2})/([0-9]{4}) (.*)$', '\3-\2-\1T\4-12:00')
  end as latest_wall_clock_kickoff
) wall_clock
where c.source_id='repository' and c.kind='event' and c.is_present
  and case
    when c.event_meta->>'source_finished'='true' then
      coalesce(recorded.finished_at,
        case when pg_input_is_valid(c.event_meta->>'finished_at','timestamp with time zone')
          then (c.event_meta->>'finished_at')::timestamptz end,
        c.updated_at) > statement_timestamp()-interval '6 hours'
    when pg_input_is_valid(c.event_meta->>'kickoff_at','timestamp with time zone') then
      (c.event_meta->>'kickoff_at')::timestamptz > statement_timestamp()-interval '9 hours'
    -- An offsetless source clock can be as late as UTC-12. Only hide it
    -- after the window has elapsed even at that latest possible time.
    when pg_input_is_valid(wall_clock.latest_wall_clock_kickoff,'timestamp with time zone') then
      wall_clock.latest_wall_clock_kickoff::timestamptz > statement_timestamp()-interval '9 hours'
    when c.event_meta->>'source_civil_date' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      and pg_input_is_valid(c.event_meta->>'source_civil_date','date') then
      ((c.event_meta->>'source_civil_date')||'T00:00:00-12:00')::timestamptz
        + interval '1 day' > statement_timestamp()-interval '9 hours'
    else true -- No dated evidence. Keep available for manual review.
  end;
