-- Admin-only operational metadata for existing private channel lines.
-- Stream URLs, referers and keys stay under the existing channel_lines RLS
-- policies; this adds no public grant or playback field.
alter table public.channel_lines
  add column if not exists health_status text not null default 'unknown',
  add column if not exists health_latency_ms integer,
  add column if not exists last_checked_at timestamptz;

alter table public.channel_lines
  drop constraint if exists channel_lines_health_status_check;

alter table public.channel_lines
  add constraint channel_lines_health_status_check
  check (health_status in ('unknown', 'healthy', 'slow', 'failed'));

create index if not exists channel_lines_health_recent_idx
  on public.channel_lines (last_checked_at desc nulls last)
  where is_active;

comment on column public.channel_lines.health_status is
  'Admin-only reachability status from the first response chunk.';
comment on column public.channel_lines.health_latency_ms is
  'Admin-only reachability probe latency in milliseconds.';
comment on column public.channel_lines.last_checked_at is
  'When the Admin reachability probe last ran.';

notify pgrst, 'reload schema';
