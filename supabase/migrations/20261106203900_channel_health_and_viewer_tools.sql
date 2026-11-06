alter table public.channel_lines add column if not exists health_http_status integer;

create table public.nca_bot_updates (
  bot text not null check (bot in ('viewer','admin')),
  update_id bigint not null check (update_id >= 0),
  claim uuid not null,
  locked_until timestamptz not null default now() + interval '2 minutes',
  completed boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (bot, update_id)
);
alter table public.nca_bot_updates enable row level security;
revoke all on public.nca_bot_updates from anon, authenticated;
grant all on public.nca_bot_updates to service_role;

create function public.claim_nca_bot_update(p_bot text, p_update_id bigint, p_claim uuid)
returns text language sql security invoker set search_path = public as $$
  with claimed as (
    insert into public.nca_bot_updates(bot,update_id,claim) values(p_bot,p_update_id,p_claim)
    on conflict(bot,update_id) do update set claim=excluded.claim,
      locked_until=now()+interval '2 minutes'
      where not nca_bot_updates.completed and nca_bot_updates.locked_until < now()
    returning 1
  ) select case when exists(select from claimed) then 'claimed'
      when exists(select from public.nca_bot_updates where bot=p_bot and update_id=p_update_id and completed)
      then 'completed' else 'busy' end;
$$;
revoke all on function public.claim_nca_bot_update(text,bigint,uuid) from public,anon,authenticated;
grant execute on function public.claim_nca_bot_update(text,bigint,uuid) to service_role;

create table public.nca_viewer_reminders (
  chat_id bigint not null,
  match_id uuid not null references public.matches(id) on delete cascade,
  due_at timestamptz not null,
  delivered_at timestamptz,
  retry_after timestamptz,
  created_at timestamptz not null default now(),
  primary key(chat_id,match_id)
);
create index on public.nca_viewer_reminders(due_at) where delivered_at is null;
create table public.nca_viewer_reports (
  id bigint generated always as identity primary key,
  chat_id bigint not null,
  channel_id uuid not null references public.channels(id) on delete cascade,
  line_id uuid not null references public.channel_lines(id) on delete cascade,
  report_day date not null default (now() at time zone 'UTC')::date,
  created_at timestamptz not null default now(),
  unique(chat_id,line_id,report_day)
);
alter table public.nca_viewer_reminders enable row level security;
alter table public.nca_viewer_reports enable row level security;
revoke all on public.nca_viewer_reminders,public.nca_viewer_reports from anon,authenticated;
grant all on public.nca_viewer_reminders,public.nca_viewer_reports to service_role;
grant usage,select on sequence public.nca_viewer_reports_id_seq to service_role;
grant select on public.nca_viewer_reports to authenticated;
create policy "Admins read viewer reports" on public.nca_viewer_reports for select to authenticated
  using ((select public.is_admin()));

-- Claims and delivered reminders contain private identifiers, so retain only
-- the short window needed for retries. Unsent reminders expire with the match.
create table public.nca_viewer_scheduler(id integer primary key check(id=1),secret_sha256 text not null);
alter table public.nca_viewer_scheduler enable row level security;
revoke all on public.nca_viewer_scheduler from anon,authenticated;
grant select on public.nca_viewer_scheduler to service_role;
do $setup$
declare pulse_key text;
begin
  if to_regprocedure('cron.schedule(text,text,text)') is not null then
    perform cron.schedule('nca-viewer-tools-retention','17 3 * * *', $job$
      delete from public.nca_bot_updates where created_at < now()-interval '7 days';
      delete from public.nca_viewer_reminders where due_at < now()-interval '7 days';
      delete from public.nca_viewer_reports where created_at < now()-interval '30 days';
    $job$);
    if to_regprocedure('vault.create_secret(text,text,text,uuid)') is not null then
      pulse_key := replace(gen_random_uuid()::text || gen_random_uuid()::text,'-','');
      perform vault.create_secret(pulse_key,'nca_viewer_pulse','Private viewer reminder scheduler');
      insert into public.nca_viewer_scheduler values(1,encode(sha256(convert_to(pulse_key,'UTF8')),'hex'));
      perform cron.schedule('nca-viewer-reminders','* * * * *', $job$
        select net.http_post(
          url := 'https://woggzixprvyjnfjzsglz.supabase.co/functions/v1/telegram-viewer',
          headers := jsonb_build_object('Content-Type','application/json','x-nca-viewer-pulse-key',
            (select decrypted_secret from vault.decrypted_secrets where name='nca_viewer_pulse' limit 1)),
          body := '{}'::jsonb, timeout_milliseconds := 50000);
      $job$);
    end if;
  end if;
end $setup$;
