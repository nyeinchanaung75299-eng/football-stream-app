-- This read filter does not change the source snapshot, import mappings,
-- or retention clock. A missing final result cannot authorize deletion.
create view public.repository_current_catalog
with (security_invoker = true) as
select c.*
from public.channel_source_catalog c
left join lateral (
  select min(r.finished_at) as finished_at
  from public.repository_fixture_retention r
  where r.entry_id=c.id or r.fixture_key=c.event_meta->>'fixture_key'
) recorded on c.event_meta->>'source_finished'='true'
where c.source_id='repository' and c.kind='event' and c.is_present
  and case
    when c.event_meta->>'source_finished'='true' then
      coalesce(recorded.finished_at,
        case when pg_input_is_valid(c.event_meta->>'finished_at','timestamp with time zone')
          then (c.event_meta->>'finished_at')::timestamptz end,
        c.updated_at) > statement_timestamp()-interval '6 hours'
    when pg_input_is_valid(c.event_meta->>'kickoff_at','timestamp with time zone') then
      (c.event_meta->>'kickoff_at')::timestamptz >= statement_timestamp()-interval '24 hours'
    else true -- Missing UTC kickoff remains eligible for manual review.
  end;

revoke all on public.repository_current_catalog from public,anon,authenticated,service_role;
grant select on public.repository_current_catalog to service_role;

-- Apply the same catalog filter before limiting either Viewer list response.
-- The legacy function's separate playback lookup continues to read the
-- saved record directly so existing references keep working.
do $migration$
declare
  routine regprocedure;
  definition text;
  browse_from text := 'from public\.channel_source_catalog c[[:space:]]+where c\.source_id=''repository'' and c\.kind=''event'' and c\.is_present';
  filtered_from text := 'from public.repository_current_catalog c where c.is_present';
begin
  foreach routine in array array[
    'public.get_repository_metadata_for_gateway(text,text)'::regprocedure,
    'public.get_repository_catalog_page_for_gateway(date,integer,integer,text)'::regprocedure
  ] loop
    definition:=pg_get_functiondef(routine);
    if regexp_count(definition,browse_from)<>1 then
      raise exception 'Repository list query changed: %',routine;
    end if;
    execute regexp_replace(definition,browse_from,filtered_from);
  end loop;
end
$migration$;

notify pgrst,'reload schema';
