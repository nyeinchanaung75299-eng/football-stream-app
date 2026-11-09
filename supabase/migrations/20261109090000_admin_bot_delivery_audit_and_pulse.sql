-- Record only notification outcomes; never Telegram credentials, stream URLs,
-- request headers, DRM data or private playback identifiers.
create table if not exists public.nca_bot_delivery_attempts (
  id bigint generated always as identity primary key,
  chat_id bigint not null references public.nca_bot_preferences(chat_id)
    on delete cascade,
  event_key text not null check (char_length(event_key) between 1 and 240),
  kind text not null check (kind in ('health', 'readiness', 'football')),
  outcome text not null check (outcome in ('sent', 'failed')),
  error_code text check (
    error_code is null or error_code ~ '^[a-z0-9_]{1,48}$'
  ),
  created_at timestamptz not null default now()
);
create index if not exists nca_bot_delivery_attempts_chat_recent_idx
  on public.nca_bot_delivery_attempts(chat_id, created_at desc);

alter table public.nca_bot_delivery_attempts enable row level security;
revoke all on public.nca_bot_delivery_attempts from anon, authenticated;
grant select, insert on public.nca_bot_delivery_attempts to service_role;
grant usage, select on sequence public.nca_bot_delivery_attempts_id_seq to service_role;

-- More frequent but still bounded and non-overlapping monitoring.
-- The Edge Function probes 12 oldest-checked lines per invocation (at most
-- three concurrent groups of four with a 4.5 s probe timeout per line).
do $job$
declare current_job bigint;
begin
  select jobid into current_job from cron.job
    where jobname = 'nca-private-admin-pulse' and active
    order by jobid limit 1;
  if current_job is null then
    raise exception 'nca-private-admin-pulse cron job missing; no scheduler modified';
  end if;
  perform cron.alter_job(job_id => current_job, schedule => '*/2 * * * *');
end
$job$;

-- Retain at most 30 days of metadata-only delivery outcomes.
select cron.schedule(
  'nca-telegram-delivery-log-prune', '28 3 * * *',
  $$delete from public.nca_bot_delivery_attempts
    where created_at < now() - interval '30 days'$$
);
