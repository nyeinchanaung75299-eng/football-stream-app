-- Provider credentials are encrypted by the Edge Function before storage.
-- Even Admin JWTs cannot read these tables through the Data API.
create table public.system_monitor_connections (
  provider text primary key check (provider in ('posthog','cloudflare','vercel','google-drive')),
  config jsonb not null default '{}'::jsonb,
  encrypted_secret text not null,
  updated_at timestamptz not null default now()
);
create table public.system_monitor_cache (
  provider text primary key,
  summary jsonb not null,
  collected_at timestamptz not null default now()
);
alter table public.system_monitor_connections enable row level security;
alter table public.system_monitor_cache enable row level security;
revoke all on public.system_monitor_connections, public.system_monitor_cache from public, anon, authenticated;
grant select, insert, update, delete on public.system_monitor_connections, public.system_monitor_cache to service_role;

-- Keep verified credential replacement and its first summary in one transaction.
create function public.save_monitor_connection(p_provider text, p_config jsonb,
  p_encrypted_secret text, p_summary jsonb) returns void
language sql security invoker set search_path = '' as $$
  insert into public.system_monitor_connections(provider,config,encrypted_secret,updated_at)
  values (p_provider,p_config,p_encrypted_secret,now())
  on conflict (provider) do update set config=excluded.config,
    encrypted_secret=excluded.encrypted_secret,updated_at=excluded.updated_at;
  insert into public.system_monitor_cache(provider,summary,collected_at)
  values (p_provider,p_summary,now())
  on conflict (provider) do update set summary=excluded.summary,collected_at=excluded.collected_at;
$$;
revoke all on function public.save_monitor_connection(text,jsonb,text,jsonb) from public,anon,authenticated;
grant execute on function public.save_monitor_connection(text,jsonb,text,jsonb) to service_role;

alter table public.stream_links add column health_failure_streak integer not null default 0 check (health_failure_streak >= 0);
alter table public.stream_links add column health_total_failures bigint not null default 0 check (health_total_failures >= 0);
alter table public.stream_links add column health_last_failure_at timestamptz;

-- Use a trigger so both scheduled maintenance and manual checks update the
-- same streak atomically, without a read/modify/write race in either client.
create schema if not exists nca_monitor;
revoke all on schema nca_monitor from public, anon, authenticated;
create function nca_monitor.record_stream_check() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if new.last_checked_at is distinct from old.last_checked_at and new.last_checked_at is not null then
    if new.health_status = 'failed' then
      new.health_failure_streak := old.health_failure_streak + 1;
      new.health_total_failures := old.health_total_failures + 1;
      new.health_last_failure_at := new.last_checked_at;
    else
      new.health_failure_streak := 0;
      new.health_total_failures := old.health_total_failures;
      new.health_last_failure_at := old.health_last_failure_at;
    end if;
  else
    new.health_failure_streak := old.health_failure_streak;
    new.health_total_failures := old.health_total_failures;
    new.health_last_failure_at := old.health_last_failure_at;
  end if;
  return new;
end;
$$;
revoke all on function nca_monitor.record_stream_check() from public, anon, authenticated;
create trigger record_stream_health_check before update on public.stream_links
for each row execute function nca_monitor.record_stream_check();
