-- Record only notification outcomes; never Telegram credentials, stream URLs,
-- request headers, DRM data or private playback identifiers.
create table if not exists public.nca_bot_delivery_attempts (
  id bigint generated always as identity primary key,
  chat_id bigint not null,
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

-- The live Telegram preference table was provisioned independently of
-- earlier repo migrations. Make the FK when available, without breaking
-- clean-room migration replay in CI. On production, unsubscribe cascades
-- removal of the associated delivery audit.
do $fk$
begin
  if to_regclass('public.nca_bot_preferences') is not null
     and not exists (
       select 1 from pg_constraint
       where conrelid='public.nca_bot_delivery_attempts'::regclass
         and conname='nca_bot_delivery_attempts_chat_id_fkey'
     ) then
    alter table public.nca_bot_delivery_attempts
      add constraint nca_bot_delivery_attempts_chat_id_fkey
      foreign key (chat_id) references public.nca_bot_preferences(chat_id)
      on delete cascade;
  end if;
end
$fk$;

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
  if to_regclass('cron.job') is null then
    -- Standalone Postgres CI does not install pg_cron.
    raise notice 'pg_cron not present; Admin schedule is unchanged here';
  else
    execute 'select jobid from cron.job where jobname=$1 and active order by jobid limit 1'
      into current_job using 'nca-private-admin-pulse';
    if current_job is null then
      -- Deploying code to a fresh project must not create a fake bot.
      raise notice 'Admin Telegram cron job not installed; no schedule changed';
    else
      execute 'select cron.alter_job(job_id=>$1, schedule=>$2)'
        using current_job, '*/2 * * * *';
    end if;
    -- Prune only metadata-only delivery outcomes after 30 days.
    if to_regprocedure('cron.schedule(text,text,text)') is not null then
      execute 'select cron.schedule($1,$2,$3)' using
        'nca-telegram-delivery-log-prune', '28 3 * * *',
        'delete from public.nca_bot_delivery_attempts where created_at < now() - interval ''30 days''';
    end if;
  end if;
end
$job$;
