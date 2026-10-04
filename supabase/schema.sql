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
  sort_order int not null default 0,
  is_live boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.stream_links (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  label text not null default 'Main',
  resolution text,
  stream_type text not null check (stream_type in ('hls', 'dash')),
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
