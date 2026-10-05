-- Show the real number of active Viewer lines in match metadata.
-- Keyed/ClearKey DASH remains protected: only its safe metadata is shown,
-- while keys and upstream URLs are never exposed by the public gateway.

create or replace view public.match_stream_counts
with (security_invoker = false)
as
select
  m.id as match_id,
  count(sl.id) filter (
    where sl.is_active = true
      and coalesce(sl.use_webview, false) = false
      and coalesce(sl.stream_url, '') <> ''
      and (sl.available_from is null or sl.available_from <= now())
      and (sl.expires_at is null or sl.expires_at > now())
  )::integer as stream_count
from public.matches m
left join public.stream_links sl on sl.match_id = m.id
where m.is_active = true
  and m.is_featured = true
  and m.publish_state = 'published'
group by m.id;

revoke all on table public.match_stream_counts from public;
grant select on table public.match_stream_counts to anon, authenticated;
