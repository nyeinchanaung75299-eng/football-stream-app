-- Non-DRM DASH manifests are now rewritten by the Cloudflare protected
-- playback gateway. Count them as playable lines again. Keyed/ClearKey
-- streams stay excluded from the anonymous Viewer count.

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
