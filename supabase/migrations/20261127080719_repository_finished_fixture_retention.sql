-- Persist the first verified finish across syncs and partial source outages.
-- The marker is retained after deleting the transient catalogue row.
create table public.repository_fixture_retention (
 fixture_key text primary key,
 entry_id text not null,
 finished_at timestamptz not null,
 expired_at timestamptz
);
create index repository_fixture_retention_entry_idx on public.repository_fixture_retention(entry_id);
alter table public.repository_fixture_retention enable row level security;
revoke all on public.repository_fixture_retention from public,anon,authenticated;
grant select,insert,update,delete on public.repository_fixture_retention to service_role;

create function public.record_repository_fixture_finish() returns trigger
language plpgsql security invoker set search_path='' as $$
declare fixture text:=new.event_meta->>'fixture_key'; ended timestamptz;
begin
 if exists(select from public.repository_fixture_retention r where r.expired_at is not null
   and (r.fixture_key=fixture or r.entry_id=new.id)) then return null; end if;
 if fixture is not null and new.event_meta->>'source_finished'='true' and
    new.event_meta->>'kickoff_at' is not null then
  ended:=coalesce((new.event_meta->>'finished_at')::timestamptz,statement_timestamp());
  insert into public.repository_fixture_retention(fixture_key,entry_id,finished_at)
    values(fixture,new.id,ended)
    on conflict(fixture_key) do update set entry_id=excluded.entry_id
    where repository_fixture_retention.entry_id is distinct from excluded.entry_id;
 end if;
 return new;
end $$;
revoke all on function public.record_repository_fixture_finish() from public,anon,authenticated;
grant execute on function public.record_repository_fixture_finish() to service_role;
create trigger record_repository_fixture_finish before insert on public.channel_source_catalog
for each row when(new.source_id='repository' and new.kind='event')
execute function public.record_repository_fixture_finish();

create function public.prune_finished_repository_fixtures(p_preview boolean default true)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare ids text[];
begin
 if not p_preview then
  perform 1 from public.channel_source_state where id='repository' for update;
 end if;
 select coalesce(array_agg(distinct c.id),'{}') into ids
 from public.channel_source_catalog c
 join public.repository_fixture_retention r
  on r.entry_id=c.id or r.fixture_key=c.event_meta->>'fixture_key'
 where c.source_id='repository' and c.kind='event'
  and r.expired_at is null and r.finished_at<=statement_timestamp()-interval '6 hours'
  and not exists(select from public.repository_match_imports i where i.entry_id=c.id)
  and not exists(select from public.channel_source_match_links i where i.entry_id=c.id)
  and not exists(select from public.channel_source_links i where i.entry_id=c.id)
  and not exists(select from public.channel_source_line_suppressions i where i.entry_id=c.id);
 if not p_preview and cardinality(ids)>0 then
  perform 1 from public.channel_source_catalog c where c.id=any(ids) order by c.id for update;
  -- Repeat the ownership guards in the deleting statement and record only
  -- rows physically deleted. FK checks serialize with concurrent imports.
  with removed as (
   delete from public.channel_source_catalog c where c.source_id='repository' and c.id=any(ids)
    and not exists(select from public.repository_match_imports i where i.entry_id=c.id)
    and not exists(select from public.channel_source_match_links i where i.entry_id=c.id)
    and not exists(select from public.channel_source_links i where i.entry_id=c.id)
    and not exists(select from public.channel_source_line_suppressions i where i.entry_id=c.id)
   returning c.id,c.event_meta->>'fixture_key' as fixture_key
  ), marked as (
   update public.repository_fixture_retention r set expired_at=statement_timestamp()
    from removed d where r.entry_id=d.id or r.fixture_key=d.fixture_key returning r.entry_id
  )
  select coalesce(array_agg(distinct entry_id),'{}') into ids from marked;
  update public.channel_source_state set entry_count=(select count(*) from public.channel_source_catalog
   where source_id='repository' and is_present) where id='repository';
 end if;
 return jsonb_build_object('preview',p_preview,'count',cardinality(ids),'entry_ids',to_jsonb(ids));
end $$;
revoke all on function public.prune_finished_repository_fixtures(boolean) from public,anon,authenticated;
grant execute on function public.prune_finished_repository_fixtures(boolean) to service_role;
notify pgrst,'reload schema';
