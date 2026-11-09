-- Telegram's server-side first-chunk probe is not a media playback test.
-- Keep its diagnostics entirely separate from the authoritative manifest,
-- segment and on-device playback fields.
alter table public.channel_lines
  add column if not exists telegram_probe_status text not null default 'unknown',
  add column if not exists telegram_probe_http_status integer,
  add column if not exists telegram_probe_latency_ms integer,
  add column if not exists telegram_probe_checked_at timestamptz,
  add column if not exists telegram_probe_failure_streak integer not null default 0;

alter table public.channel_lines
  drop constraint if exists channel_lines_telegram_probe_status_check;
alter table public.channel_lines
  add constraint channel_lines_telegram_probe_status_check
    check (telegram_probe_status in ('healthy','slow','failed','unknown'));

alter table public.channel_lines
  drop constraint if exists channel_lines_telegram_probe_failure_streak_check;
alter table public.channel_lines
  add constraint channel_lines_telegram_probe_failure_streak_check
    check (telegram_probe_failure_streak between 0 and 3);

create index if not exists channel_lines_telegram_probe_rotation_idx
  on public.channel_lines (telegram_probe_checked_at asc nulls first)
  where is_active;
