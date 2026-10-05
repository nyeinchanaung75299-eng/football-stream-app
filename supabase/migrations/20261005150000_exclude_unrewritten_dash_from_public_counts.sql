-- DASH MPD manifests are not yet rewritten by the protected playback
-- gateway. Do not advertise them as protected-playable lines.

create or replace view public.match_stream_counts
with (security_invoker = false)
as
select
  m.id as match_id,
  count(sl.id) filter (
    where sl.is_active = true
      and coalesce(sl.use_webview, false) = false
      and coalesce(sl.stream_url, '') <> ''
      and coalesce(sl.key_id, '') = ''
      and coalesce(sl.key_data, '') = ''
      and lower(coalesce(sl.stream_type, 'auto')) not in ('dash', 'mpd')
      and lower(coalesce(sl.stream_url, '')) not like '%.mpd%'
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
