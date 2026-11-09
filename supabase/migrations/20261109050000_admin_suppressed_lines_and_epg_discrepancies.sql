-- Admin operators can explicitly allow a previously suppressed source line.
-- Regular catalog sync still skips every entry in this table until an admin
-- explicitly removes that specific (entry_id, channel_id, source_line_id) row.
grant select, delete on public.channel_source_line_suppressions to authenticated;

drop policy if exists "Admin read suppressed channel source lines"
  on public.channel_source_line_suppressions;
create policy "Admin read suppressed channel source lines"
  on public.channel_source_line_suppressions
  for select to authenticated
  using ((select public.is_admin()));

drop policy if exists "Admin allow suppressed channel source lines"
  on public.channel_source_line_suppressions;
create policy "Admin allow suppressed channel source lines"
  on public.channel_source_line_suppressions
  for delete to authenticated
  using ((select public.is_admin()));

-- Audit what was actually shown instead of changing the saved EPG mapping
-- based only on a guessed broadcast region.
create table if not exists public.channel_epg_discrepancies (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels(id) on delete cascade,
  observed_programme text not null
    check (char_length(btrim(observed_programme)) between 1 and 240),
  observed_at timestamptz not null,
  reported_epg_id text,
  reported_epg_source text,
  notes text not null default ''
    check (char_length(notes) <= 500),
  status text not null default 'open'
    check (status in ('open', 'resolved')),
  guide_checked_at timestamptz,
  guide_programme_at_check text,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index if not exists channel_epg_discrepancies_channel_time_idx
  on public.channel_epg_discrepancies(channel_id, observed_at desc);
create index if not exists channel_epg_discrepancies_open_idx
  on public.channel_epg_discrepancies(created_at desc)
  where status = 'open';

alter table public.channel_epg_discrepancies enable row level security;
revoke all on public.channel_epg_discrepancies from anon;
grant select, insert, update on public.channel_epg_discrepancies
  to authenticated;

drop policy if exists "Admin read EPG discrepancies"
  on public.channel_epg_discrepancies;
create policy "Admin read EPG discrepancies"
  on public.channel_epg_discrepancies for select to authenticated
  using ((select public.is_admin()));

drop policy if exists "Admin report EPG discrepancies"
  on public.channel_epg_discrepancies;
create policy "Admin report EPG discrepancies"
  on public.channel_epg_discrepancies for insert to authenticated
  with check ((select public.is_admin())
    and created_by = (select auth.uid()));

drop policy if exists "Admin update EPG discrepancy review"
  on public.channel_epg_discrepancies;
create policy "Admin update EPG discrepancy review"
  on public.channel_epg_discrepancies for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));
