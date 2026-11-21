alter table public.channel_source_state add column unavailable_repositories jsonb not null default '[]'::jsonb;
alter table public.channel_source_state add column catalog_schema_version integer not null default 1;
alter table public.channel_source_catalog drop constraint channel_source_catalog_provider_check;
alter table public.channel_source_catalog add constraint channel_source_catalog_provider_check check(provider between 1 and 15);

-- Freeze unavailable origins in the input union, reconcile observed origins,
-- and publish truthful partial status atomically with the Hub snapshot.
create function public.commit_stream_hub_snapshot(p_lease uuid,p_revision text,p_entries jsonb,p_unavailable_repositories jsonb)
 returns jsonb language plpgsql security invoker set search_path='' as $$
declare previous public.channel_source_state; result jsonb; partial boolean; unchanged boolean;
begin
 if jsonb_typeof(p_unavailable_repositories) is distinct from 'array' or jsonb_array_length(p_unavailable_repositories)>8 then raise exception 'Invalid unavailable repository list';end if;
 select * into previous from public.channel_source_state where id='darkbyte' for update;
 if p_lease is null or previous.lease_id is distinct from p_lease then raise exception 'Source sync lease expired';end if;
 partial:=jsonb_array_length(p_unavailable_repositories)>0;
 unchanged:=previous.revision=p_revision and previous.unavailable_repositories=p_unavailable_repositories and previous.catalog_schema_version=3;
 result:=public.commit_connected_channel_source_sync('darkbyte',p_lease,p_revision,p_entries,true,coalesce(unchanged,false));
 update public.channel_source_state set status=case when partial then 'partial' else 'ok' end,
  last_success_at=case when partial then previous.last_success_at else last_success_at end,
  unavailable_repositories=p_unavailable_repositories,catalog_schema_version=3 where id='darkbyte';
 return result||jsonb_build_object('partial',partial,'unavailable_repositories',p_unavailable_repositories);
end $$;
revoke all on function public.commit_stream_hub_snapshot(uuid,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.commit_stream_hub_snapshot(uuid,text,jsonb,jsonb) to service_role;

-- Live 2 uses exactly the same is_present catalogue as Admin. The source
-- synchronizer owns expiry; a second, different expiry window caused drift.
do $$
declare definition text; gate text:=$gate$and (nullif(c.event_meta->>'kickoff_at','') is null or (c.event_meta->>'kickoff_at')::timestamptz>now()-interval '6 hours')$gate$;
begin
 definition:=pg_get_functiondef('public.get_repository_metadata_for_gateway(text,text)'::regprocedure);
 if strpos(definition,gate)=0 then raise exception 'Live 2 catalogue parity hook unavailable';end if;
 definition:=replace(definition,gate,'');execute definition;
end $$;
notify pgrst,'reload schema';
