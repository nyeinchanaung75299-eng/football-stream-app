-- Run ONCE in Supabase SQL Editor.
-- Lets manual matches and API-Football imported matches live together.

alter table public.matches
  add column if not exists source text not null default 'manual';

alter table public.matches
  add column if not exists external_fixture_id bigint;

create unique index if not exists matches_external_fixture_id_unique
  on public.matches (external_fixture_id)
  where external_fixture_id is not null;
