-- Independent source snapshots prevent one upstream from removing another's entries.
alter table public.channel_source_state drop constraint channel_source_state_id_check;
alter table public.channel_source_state add constraint channel_source_state_id_check check(id in ('darkbyte','livetv'));
insert into public.channel_source_state(id) values('livetv');
alter table public.channel_source_catalog drop constraint channel_source_catalog_provider_check;
alter table public.channel_source_catalog add constraint channel_source_catalog_provider_check check(provider between 1 and 7);
alter table public.channel_source_catalog add column source_id text not null default 'darkbyte' references public.channel_source_state(id);
alter table public.channel_source_catalog add column epg_id text, add column epg_source text,
 add column epg_channel_id uuid references public.channels(id) on delete set null, add column region text;
create index channel_source_catalog_source_browse_idx on public.channel_source_catalog(source_id,name,id) where is_present;
-- Hosted channels already have these public metadata columns.
alter table public.channels add column if not exists epg_id text, add column if not exists epg_source text;

create function public.begin_connected_channel_source_sync(p_source text,p_force boolean default false)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare s public.channel_source_state;
begin
 if p_source not in ('darkbyte','livetv') then raise exception 'Invalid channel source'; end if;
 select * into s from public.channel_source_state where id=p_source for update;
 if not s.enabled and not p_force then return jsonb_build_object('skipped',true); end if;
 if s.lease_until>now() then return jsonb_build_object('busy',true); end if;
 update public.channel_source_state set lease_id=gen_random_uuid(),lease_until=now()+interval '2 minutes'
  where id=p_source returning * into s;
 return jsonb_build_object('lease',s.lease_id,'revision',s.revision);
end $$;

create function public.import_connected_channel_source_entry(p_entry_id text,p_target_channel_id uuid default null,p_refresh_only boolean default false)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare e public.channel_source_catalog; r jsonb; owned boolean;
begin
 select * into e from public.channel_source_catalog where id=p_entry_id for update;
 if not found then raise exception 'Source entry not found'; end if;
 if not p_refresh_only and p_target_channel_id is null and e.epg_channel_id is not null then
  p_target_channel_id:=e.epg_channel_id;
 end if;
 r:=public.link_channel_source_entry(p_entry_id,p_target_channel_id,p_refresh_only);
 select owns_channel into owned from public.channel_source_links where entry_id=p_entry_id;
 if e.epg_id is not null and e.epg_source is not null then
  update public.channels set epg_id=e.epg_id,epg_source=e.epg_source
   where id=(r->>'channel_id')::uuid and (owned or id=e.epg_channel_id)
    and epg_id is null and epg_source is null;
 end if;
 return r;
end $$;

create function public.commit_connected_channel_source_sync(p_source text,p_lease uuid,p_revision text,p_entries jsonb,p_complete boolean,p_unchanged boolean default false)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare s public.channel_source_state; linked record; changes integer:=0; result jsonb;
begin
 if p_source not in ('darkbyte','livetv') then raise exception 'Invalid channel source'; end if;
 select * into s from public.channel_source_state where id=p_source for update;
 if s.lease_id is distinct from p_lease then raise exception 'Source sync lease expired'; end if;
 if not p_unchanged then
  if jsonb_typeof(p_entries)<>'array' or jsonb_array_length(p_entries)>15000 then raise exception 'Invalid source snapshot'; end if;
  insert into public.channel_source_catalog(source_id,id,provider,kind,name,category,image_url,source_file,playlist_url,streams,unsupported_count,stream_count,revision,epg_id,epg_source,epg_channel_id,region)
   select p_source,x.id,x.provider,x.kind,x.name,x.category,x.image_url,x.source_file,x.playlist_url,x.streams,x.unsupported_count,jsonb_array_length(x.streams),p_revision,x.epg_id,x.epg_source,x.epg_channel_id,x.region
   from jsonb_to_recordset(p_entries) x(id text,provider integer,kind text,name text,category text,image_url text,source_file text,playlist_url text,streams jsonb,unsupported_count integer,epg_id text,epg_source text,epg_channel_id uuid,region text)
   on conflict(id) do update set provider=excluded.provider,kind=excluded.kind,name=excluded.name,category=excluded.category,
    image_url=excluded.image_url,source_file=excluded.source_file,playlist_url=excluded.playlist_url,streams=excluded.streams,
    unsupported_count=excluded.unsupported_count,stream_count=excluded.stream_count,revision=excluded.revision,is_present=true,updated_at=now(),epg_id=excluded.epg_id,epg_source=excluded.epg_source,epg_channel_id=excluded.epg_channel_id,region=excluded.region;
  if p_complete then update public.channel_source_catalog set is_present=false where source_id=p_source and revision<>p_revision; end if;
 end if;
 for linked in select l.entry_id from public.channel_source_links l join public.channel_source_catalog c on c.id=l.entry_id where c.source_id=p_source and l.follow_updates order by l.entry_id loop
  result:=public.import_connected_channel_source_entry(linked.entry_id,null,true);
  changes:=changes+coalesce((result->>'updated_lines')::integer,0);
 end loop;
 update public.channel_source_state set last_checked_at=now(),last_success_at=case when p_complete then now() else last_success_at end,
  revision=case when p_complete then p_revision else revision end,status=case when p_complete then 'ok' else 'partial' end,
  entry_count=(select count(*) from public.channel_source_catalog where source_id=p_source and is_present),lease_id=null,lease_until=null where id=p_source;
 return jsonb_build_object('ok',true,'updated_lines',changes,'entry_count',(select entry_count from public.channel_source_state where id=p_source));
end $$;

-- Retain compatibility for already deployed callers and database checks.
create or replace function public.begin_channel_source_sync(p_force boolean default false)
returns jsonb language sql security invoker set search_path='' as $$
 select public.begin_connected_channel_source_sync('darkbyte',p_force);
$$;
create or replace function public.commit_channel_source_sync(p_lease uuid,p_revision text,p_entries jsonb,p_complete boolean,p_unchanged boolean default false)
returns jsonb language sql security invoker set search_path='' as $$
 select public.commit_connected_channel_source_sync('darkbyte',p_lease,p_revision,p_entries,p_complete,p_unchanged);
$$;
revoke all on function public.begin_connected_channel_source_sync(text,boolean),
 public.commit_connected_channel_source_sync(text,uuid,text,jsonb,boolean,boolean),
 public.import_connected_channel_source_entry(text,uuid,boolean) from public,anon,authenticated;
grant execute on function public.begin_connected_channel_source_sync(text,boolean),
 public.commit_connected_channel_source_sync(text,uuid,text,jsonb,boolean,boolean),
 public.import_connected_channel_source_entry(text,uuid,boolean) to service_role;
do $schedule$
begin
 if to_regprocedure('cron.schedule(text,text,text)') is not null and
  to_regprocedure('vault.create_secret(text,text,text,uuid)') is not null then
  perform cron.schedule('nca-livetv-sports-source','2-59/5 * * * *',$job$
   select net.http_post(url:='https://woggzixprvyjnfjzsglz.supabase.co/functions/v1/channel-source-sync',
    headers:=jsonb_build_object('Content-Type','application/json','x-nca-channel-source-key',
     (select decrypted_secret from vault.decrypted_secrets where name='nca_darkbyte_channel_source_pulse' limit 1)),
    body:='{"action":"sync","source":"livetv"}'::jsonb,timeout_milliseconds:=50000);
  $job$);
 end if;
end $schedule$;
notify pgrst,'reload schema';

