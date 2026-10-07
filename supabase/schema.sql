create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'viewer' check (role in ('viewer', 'admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.matches (
  id uuid primary key default gen_random_uuid(),
  league text not null,
  home_team text not null,
  away_team text not null,
  home_logo_url text,
  away_logo_url text,
  kickoff_at timestamptz not null,
  source text not null default 'manual',
  external_fixture_id bigint,
  sort_order int not null default 0,
  is_live boolean not null default false,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.stream_links (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  label text not null default 'Main',
  resolution text,
  stream_type text not null default 'auto' check (stream_type in ('auto', 'hls', 'dash', 'flv', 'mp4')),
  stream_url text not null default '',
  referer text,
  origin text,
  key_id text,
  key_data text,
  use_webview boolean not null default false,
  webview_url text,
  send_notification boolean not null default false,
  is_active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.highlights (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  thumbnail_url text,
  video_url text not null,
  is_active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

alter table public.profiles enable row level security;
alter table public.matches enable row level security;
alter table public.stream_links enable row level security;
alter table public.highlights enable row level security;

drop policy if exists "read own profile" on public.profiles;
create policy "read own profile"
on public.profiles for select
to authenticated
using (id = auth.uid());

drop policy if exists "admins read all profiles" on public.profiles;
create policy "admins read all profiles"
on public.profiles for select
to authenticated
using (public.is_admin());

drop policy if exists "admins manage matches" on public.matches;
create policy "admins manage matches"
on public.matches for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "public read active matches" on public.matches;
create policy "public read active matches"
on public.matches for select
to anon, authenticated
using (is_active = true or public.is_admin());

drop policy if exists "admins manage stream links" on public.stream_links;
create policy "admins manage stream links"
on public.stream_links for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "public read active stream links" on public.stream_links;
create policy "public read active stream links"
on public.stream_links for select
to anon, authenticated
using (
  is_active = true
  and exists (
    select 1 from public.matches m
    where m.id = stream_links.match_id
      and m.is_active = true
  )
);

drop policy if exists "admins manage highlights" on public.highlights;
create policy "admins manage highlights"
on public.highlights for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "public read active highlights" on public.highlights;
create policy "public read active highlights"
on public.highlights for select
to anon, authenticated
using (is_active = true);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_matches_updated_at on public.matches;
create trigger trg_matches_updated_at
before update on public.matches
for each row execute function public.touch_updated_at();

create unique index if not exists matches_external_fixture_id_unique
  on public.matches (external_fixture_id)
  where external_fixture_id is not null;

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
alter table public.matches add column if not exists deleted_at timestamptz;

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


-- Publish a complete replacement Big Match set atomically.
-- See supabase/migrations/20261007_atomic_featured_publish.sql for the full
-- implementation used in production.
