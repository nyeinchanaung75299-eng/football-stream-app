-- Some publishers give an explicit final result and a civil fixture day
-- without a timezone or end time. Start their six-hour clock at first sight.
create or replace function public.record_repository_fixture_finish() returns trigger
language plpgsql security invoker set search_path='' as $$
declare fixture text:=new.event_meta->>'fixture_key'; ended timestamptz;
begin
 if exists(select from public.repository_fixture_retention r where r.expired_at is not null
   and (r.fixture_key=fixture or r.entry_id=new.id)) then return null; end if;
 if fixture is not null and new.event_meta->>'source_finished'='true' and
    (new.event_meta->>'kickoff_at' is not null or
     new.event_meta->>'finished_source_date' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') then
  ended:=coalesce((new.event_meta->>'finished_at')::timestamptz,statement_timestamp());
  insert into public.repository_fixture_retention(fixture_key,entry_id,finished_at)
    values(fixture,new.id,ended)
    on conflict(fixture_key) do update set entry_id=excluded.entry_id
    where repository_fixture_retention.entry_id is distinct from excluded.entry_id;
 end if;
 return new;
end $$;
