-- V9 production hardening.
-- Run in Supabase SQL Editor after reviewing.

alter table public.stream_links enable row level security;

drop policy if exists "public read active stream links"
on public.stream_links;

create policy "public read active stream links"
on public.stream_links for select
to anon, authenticated
using (
  is_active = true
  and exists (
    select 1
    from public.matches m
    where m.id = stream_links.match_id
      and m.is_active = true
      and m.publish_state = 'published'
  )
);

-- Admin write policy remains based on public.is_admin().
-- Never store service-role keys, API-Football keys, CRON_SECRET,
-- or other backend credentials in stream_links.
-- Playback material required by a public client is inherently visible
-- to that client when the direct public table path is used.
