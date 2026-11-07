-- The upstream catalog is private Admin data. Only explicitly imported
-- entries create channels; refreshing a source never publishes new channels.
create table public.channel_source_state (
 id text primary key check(id='darkbyte'), enabled boolean not null default true,
 revision text, last_checked_at timestamptz, last_success_at timestamptz,
 status text not null default 'pending', entry_count integer not null default 0,
 lease_id uuid, lease_until timestamptz
);
insert into public.channel_source_state(id) values('darkbyte');
create table public.channel_source_catalog (
 id text primary key check(length(id) between 1 and 180),
 provider integer not null check(provider between 1 and 6),
 kind text not null check(kind in ('channel','event','video','playlist')),
 name text not null check(length(name) between 1 and 120),
 category text not null check(length(category) between 1 and 80),
 image_url text, source_file text not null, playlist_url text,
 streams jsonb not null default '[]', unsupported_count integer not null default 0,
 stream_count integer not null default 0, revision text not null,
 is_present boolean not null default true, updated_at timestamptz not null default now()
);
create index channel_source_catalog_browse_idx on public.channel_source_catalog(provider,kind,name,id) where is_present;
create table public.channel_source_links (
 entry_id text primary key references public.channel_source_catalog(id),
 channel_id uuid not null references public.channels(id) on delete cascade,
 owns_channel boolean not null default true, follow_updates boolean not null default true,
 source_missing boolean not null default false, line_map jsonb not null default '{}',
 last_synced_at timestamptz, created_at timestamptz not null default now()
);
create index channel_source_links_channel_idx on public.channel_source_links(channel_id);
create table public.channel_source_sync_auth (
 id integer primary key check(id=1), secret_sha256 text not null
);
alter table public.channel_source_state enable row level security;
alter table public.channel_source_catalog enable row level security;
alter table public.channel_source_links enable row level security;
alter table public.channel_source_sync_auth enable row level security;
revoke all on public.channel_source_state,public.channel_source_catalog,
 public.channel_source_links,public.channel_source_sync_auth from public,anon,authenticated;
grant all on public.channel_source_state,public.channel_source_catalog,
 public.channel_source_links,public.channel_source_sync_auth to service_role;
grant select on public.channel_source_state,public.channel_source_catalog,public.channel_source_links to authenticated;
create policy "Admins read channel source state" on public.channel_source_state for select to authenticated using ((select public.is_admin()));
create policy "Admins read channel source catalog" on public.channel_source_catalog for select to authenticated using ((select public.is_admin()));
create policy "Admins read channel source links" on public.channel_source_links for select to authenticated using ((select public.is_admin()));

create function public.begin_channel_source_sync(p_force boolean default false)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare s public.channel_source_state;
begin
 select * into s from public.channel_source_state where id='darkbyte' for update;
 if not s.enabled and not p_force then return jsonb_build_object('skipped',true); end if;
 if s.lease_until>now() then return jsonb_build_object('busy',true); end if;
 update public.channel_source_state set lease_id=gen_random_uuid(),lease_until=now()+interval '2 minutes'
  where id='darkbyte' returning * into s;
 return jsonb_build_object('lease',s.lease_id,'revision',s.revision);
end $$;

create function public.link_channel_source_entry(p_entry_id text,p_target_channel_id uuid default null,p_refresh_only boolean default false)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare e public.channel_source_catalog; l public.channel_source_links;
 config jsonb; old_config jsonb; m jsonb; old_item record; line_id uuid;
 changed integer:=0; position integer; was_enabled boolean; rows_changed integer;
begin
 -- Lock the catalog entry first in both refresh/import paths, so concurrent
 -- imports cannot duplicate channels or deadlock against a source refresh.
 select * into e from public.channel_source_catalog where id=p_entry_id for update;
 if not found then raise exception 'Source entry not found'; end if;
 select * into l from public.channel_source_links where entry_id=p_entry_id for update;
 if not found then
  if p_refresh_only then return jsonb_build_object('updated_lines',0); end if;
  if not e.is_present or e.stream_count=0 then raise exception 'No native stream in source entry'; end if;
  if p_target_channel_id is null then
   insert into public.channels(name,category,image_url)
    values(e.name,e.category,e.image_url) returning id into p_target_channel_id;
   insert into public.channel_source_links(entry_id,channel_id,owns_channel)
    values(e.id,p_target_channel_id,true) returning * into l;
  else
   if not exists(select from public.channels where id=p_target_channel_id) then raise exception 'Channel not found'; end if;
   insert into public.channel_source_links(entry_id,channel_id,owns_channel)
    values(e.id,p_target_channel_id,false) returning * into l;
  end if;
 end if;
 if not l.follow_updates then return jsonb_build_object('channel_id',l.channel_id,'updated_lines',0); end if;
 if not e.is_present or e.stream_count=0 then
  -- A removed/broken upstream record must not delete the operator's saved
  -- channel. Keep the last good configuration and show its missing status.
  update public.channel_source_links set source_missing=true where entry_id=e.id;
  return jsonb_build_object('channel_id',l.channel_id,'updated_lines',0);
 end if;
 if l.owns_channel then
  update public.channels set name=e.name,category=e.category,image_url=e.image_url
   where id=l.channel_id and (name,category,image_url) is distinct from (e.name,e.category,e.image_url);
 end if;
 m:=l.line_map;
 for config in select value from jsonb_array_elements(e.streams) loop
  old_config:=m->(config->>'id');line_id:=nullif(old_config->>'line_id','')::uuid;
  if line_id is not null and not exists(select from public.channel_lines where id=line_id and channel_id=l.channel_id) then line_id:=null; end if;
  if line_id is null then
   select coalesce(max(sort_order),-1)+1 into position from public.channel_lines where channel_id=l.channel_id;
   insert into public.channel_lines(channel_id,label,stream_url,stream_type,referer,origin,key_id,key_data,sort_order)
    values(l.channel_id,config->>'label',config->>'stream_url',config->>'stream_type',
     config->>'referer',config->>'origin',config->>'key_id',config->>'key_data',position) returning id into line_id;
   changed:=changed+1;
  else
   update public.channel_lines set label=config->>'label',stream_url=config->>'stream_url',stream_type=config->>'stream_type',
    referer=config->>'referer',origin=config->>'origin',key_id=config->>'key_id',key_data=config->>'key_data',
    health_status='unknown',last_checked_at=null,health_latency_ms=null,health_http_status=null
    where id=line_id and (label,stream_url,stream_type,referer,origin,key_id,key_data) is distinct from
     (config->>'label',config->>'stream_url',config->>'stream_type',config->>'referer',config->>'origin',config->>'key_id',config->>'key_data');
   get diagnostics rows_changed=row_count;changed:=changed+rows_changed;
   if coalesce((old_config->>'source_missing')::boolean,false) then
    update public.channel_lines set is_active=coalesce((old_config->>'was_enabled')::boolean,true) where id=line_id;
   end if;
  end if;
  m:=jsonb_set(m,array[config->>'id'],jsonb_build_object('line_id',line_id,'source_missing',false));
 end loop;
 for old_item in select key,value from jsonb_each(m) loop
  if not exists(select from jsonb_array_elements(e.streams) item where item->>'id'=old_item.key)
    and not coalesce((old_item.value->>'source_missing')::boolean,false) then
   line_id:=(old_item.value->>'line_id')::uuid;
   select is_active into was_enabled from public.channel_lines where id=line_id and channel_id=l.channel_id;
   update public.channel_lines set is_active=false where id=line_id and channel_id=l.channel_id;
   m:=jsonb_set(m,array[old_item.key],old_item.value||jsonb_build_object('source_missing',true,'was_enabled',coalesce(was_enabled,false)));
  end if;
 end loop;
 update public.channel_source_links set line_map=m,source_missing=false,last_synced_at=now() where entry_id=e.id;
 return jsonb_build_object('channel_id',l.channel_id,'updated_lines',changed);
end $$;

create function public.commit_channel_source_sync(p_lease uuid,p_revision text,p_entries jsonb,p_complete boolean,p_unchanged boolean default false)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare s public.channel_source_state; linked record; changes integer:=0; result jsonb;
begin
 select * into s from public.channel_source_state where id='darkbyte' for update;
 if s.lease_id is distinct from p_lease then raise exception 'Source sync lease expired'; end if;
 if not p_unchanged then
  if jsonb_typeof(p_entries)<>'array' or jsonb_array_length(p_entries)>15000 then raise exception 'Invalid source snapshot'; end if;
  insert into public.channel_source_catalog(id,provider,kind,name,category,image_url,source_file,playlist_url,streams,unsupported_count,stream_count,revision)
   select x.id,x.provider,x.kind,x.name,x.category,x.image_url,x.source_file,x.playlist_url,x.streams,x.unsupported_count,jsonb_array_length(x.streams),p_revision
   from jsonb_to_recordset(p_entries) x(id text,provider integer,kind text,name text,category text,image_url text,source_file text,playlist_url text,streams jsonb,unsupported_count integer)
   on conflict(id) do update set provider=excluded.provider,kind=excluded.kind,name=excluded.name,category=excluded.category,
    image_url=excluded.image_url,source_file=excluded.source_file,playlist_url=excluded.playlist_url,streams=excluded.streams,
    unsupported_count=excluded.unsupported_count,stream_count=excluded.stream_count,revision=excluded.revision,is_present=true,updated_at=now();
  if p_complete then update public.channel_source_catalog set is_present=false where revision<>p_revision; end if;
 end if;
 for linked in select entry_id from public.channel_source_links where follow_updates order by entry_id loop
  result:=public.link_channel_source_entry(linked.entry_id,null,true);
  changes:=changes+coalesce((result->>'updated_lines')::integer,0);
 end loop;
 update public.channel_source_state set last_checked_at=now(),last_success_at=case when p_complete then now() else last_success_at end,
  revision=case when p_complete then p_revision else revision end,status=case when p_complete then 'ok' else 'partial' end,
  entry_count=(select count(*) from public.channel_source_catalog where is_present),lease_id=null,lease_until=null where id='darkbyte';
 return jsonb_build_object('ok',true,'updated_lines',changes,'entry_count',(select entry_count from public.channel_source_state where id='darkbyte'));
end $$;
revoke all on function public.begin_channel_source_sync(boolean),public.link_channel_source_entry(text,uuid,boolean),
 public.commit_channel_source_sync(uuid,text,jsonb,boolean,boolean) from public,anon,authenticated;
grant execute on function public.begin_channel_source_sync(boolean),public.link_channel_source_entry(text,uuid,boolean),
 public.commit_channel_source_sync(uuid,text,jsonb,boolean,boolean) to service_role;

-- Match lines imported from a channel retain their reference. Resolve that
-- reference at playback time so source URL/header/key rotations take effect
-- without rewriting the operator's match title, visibility or ordering.
create or replace function public.get_stream_metadata_for_gateway(p_match_id uuid,p_secret text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare match_valid boolean; streams jsonb;
begin
 if not exists(select from private.gateway_secrets s where s.name='cloudflare_playback'
  and s.secret_hash=encode(extensions.digest(coalesce(p_secret,''),'sha256'),'hex')) then
  raise exception 'unauthorized gateway' using errcode='42501';
 end if;
 select exists(select from public.matches m where m.id=p_match_id and m.is_active and m.is_featured and m.publish_state='published') into match_valid;
 if not match_valid then return jsonb_build_object('match_valid',false,'streams','[]'::jsonb); end if;
 select coalesce(jsonb_agg((to_jsonb(g)-'ordinality')||case when cl.id is null then '{}'::jsonb else
  jsonb_build_object('stream_url',cl.stream_url,'stream_type',cl.stream_type,'referer',cl.referer,'origin',cl.origin,
   'key_id',cl.key_id,'key_data',cl.key_data,'health_status',cl.health_status) end order by g.ordinality),'[]'::jsonb) into streams
 from public.get_stream_links_for_gateway(p_match_id,p_secret) with ordinality g
 join public.stream_links sl on sl.id=g.id
 left join public.channel_lines cl on cl.id=sl.channel_line_id
 left join public.channels c on c.id=cl.channel_id
 where sl.channel_line_id is null or (cl.id is not null and cl.is_active and c.is_active);
 return jsonb_build_object('match_valid',true,'streams',streams);
end $$;
revoke all on function public.get_stream_metadata_for_gateway(uuid,text) from public,anon,authenticated;
grant execute on function public.get_stream_metadata_for_gateway(uuid,text) to anon,authenticated;

do $schedule$
declare pulse text;
begin
 if to_regprocedure('cron.schedule(text,text,text)') is not null and
  to_regprocedure('vault.create_secret(text,text,text,uuid)') is not null then
  if not exists(select from public.channel_source_sync_auth where id=1) then
   pulse:=replace(gen_random_uuid()::text||gen_random_uuid()::text,'-','');
   perform vault.create_secret(pulse,'nca_darkbyte_channel_source_pulse','Private channel source sync');
   insert into public.channel_source_sync_auth values(1,encode(extensions.digest(pulse,'sha256'),'hex'));
  end if;
  perform cron.schedule('nca-darkbyte-channel-source','*/5 * * * *',$job$
   select net.http_post(url:='https://woggzixprvyjnfjzsglz.supabase.co/functions/v1/channel-source-sync',
    headers:=jsonb_build_object('Content-Type','application/json','x-nca-channel-source-key',
     (select decrypted_secret from vault.decrypted_secrets where name='nca_darkbyte_channel_source_pulse' limit 1)),
    body:='{"action":"sync"}'::jsonb,timeout_milliseconds:=45000);
  $job$);
 end if;
end $schedule$;
notify pgrst,'reload schema';
