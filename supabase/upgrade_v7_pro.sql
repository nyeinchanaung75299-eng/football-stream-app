-- V7 Pro upgrade
-- Run once AFTER the older V6/V6.3 upgrades.

alter table public.matches add column if not exists publish_state text not null default 'published';
alter table public.matches add column if not exists is_featured boolean not null default true;
alter table public.matches add column if not exists home_score integer;
alter table public.matches add column if not exists away_score integer;
alter table public.matches add column if not exists status_short text not null default 'NS';
alter table public.matches add column if not exists status_elapsed integer;
alter table public.matches add column if not exists is_finished boolean not null default false;
alter table public.matches add column if not exists last_score_sync_at timestamptz;

alter table public.matches drop constraint if exists matches_publish_state_check;
alter table public.matches add constraint matches_publish_state_check check (publish_state in ('draft','published'));

drop index if exists public.matches_external_fixture_id_unique;
create unique index if not exists matches_external_fixture_id_unique on public.matches (external_fixture_id);

alter table public.stream_links add column if not exists priority integer not null default 100;
alter table public.stream_links add column if not exists available_from timestamptz;
alter table public.stream_links add column if not exists expires_at timestamptz;
alter table public.stream_links add column if not exists health_status text not null default 'unknown';
alter table public.stream_links add column if not exists health_latency_ms integer;
alter table public.stream_links add column if not exists last_checked_at timestamptz;

alter table public.stream_links drop constraint if exists stream_links_health_status_check;
alter table public.stream_links add constraint stream_links_health_status_check check (health_status in ('unknown','healthy','slow','failed'));

drop policy if exists "public read active matches" on public.matches;
drop policy if exists "public read published matches" on public.matches;
create policy "public read published matches"
on public.matches for select
to anon, authenticated
using (((is_active = true) and (publish_state = 'published')) or public.is_admin());

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='matches'
  ) then
    alter publication supabase_realtime add table public.matches;
  end if;
end $$;
