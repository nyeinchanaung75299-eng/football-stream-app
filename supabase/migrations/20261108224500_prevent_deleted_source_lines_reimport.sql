-- Explicit deletions of provider-synced channel lines survive future syncs.
-- No raw stream URL, header, token or DRM field is persisted here.
create table if not exists public.channel_source_line_suppressions (
  entry_id text not null references public.channel_source_catalog(id) on delete cascade,
  channel_id uuid not null references public.channels(id) on delete cascade,
  source_line_id text not null,
  deleted_at timestamptz not null default now(),
  primary key (entry_id, channel_id, source_line_id)
);
alter table public.channel_source_line_suppressions enable row level security;
revoke all on public.channel_source_line_suppressions from anon, authenticated;

create or replace function nca_monitor.remember_deleted_source_channel_line()
returns trigger language plpgsql security definer set search_path='' as $fn$
begin
  insert into public.channel_source_line_suppressions (entry_id,channel_id,source_line_id)
  select links.entry_id, old.channel_id, mapped.key
  from public.channel_source_links links
  cross join lateral jsonb_each(links.line_map) mapped
  where links.channel_id=old.channel_id
    and mapped.value->>'line_id'=old.id::text
  on conflict(entry_id,channel_id,source_line_id) do nothing;
  return old;
end
$fn$;
-- A trigger needs elevated rights to write an operator's suppression record,
-- but the helper is not a callable public Data API function.
revoke all on function nca_monitor.remember_deleted_source_channel_line() from public, anon, authenticated;

drop trigger if exists remember_deleted_source_channel_line on public.channel_lines;
create trigger remember_deleted_source_channel_line
after delete on public.channel_lines for each row
execute function nca_monitor.remember_deleted_source_channel_line();

-- Recover previously deleted source lines that still appear in saved line_map.
insert into public.channel_source_line_suppressions(entry_id,channel_id,source_line_id)
select links.entry_id,links.channel_id,mapped.key
from public.channel_source_links links
cross join lateral jsonb_each(links.line_map) mapped
left join public.channel_lines existing
  on existing.id=nullif(mapped.value->>'line_id','')::uuid
where nullif(mapped.value->>'line_id','') is not null
  and existing.id is null
on conflict(entry_id,channel_id,source_line_id) do nothing;

-- Refresh the existing importer, preserving its behavior except for rejection.

CREATE OR REPLACE FUNCTION public.link_channel_source_entry(p_entry_id text, p_target_channel_id uuid DEFAULT NULL::uuid, p_refresh_only boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare e public.channel_source_catalog; l public.channel_source_links;
 config jsonb; old_config jsonb; m jsonb; old_item record; line_id uuid;
 changed integer:=0; position integer; was_enabled boolean; rows_changed integer; shared_line boolean;
begin
 -- Lock the catalog entry first in both refresh/import paths, so concurrent
 -- imports cannot duplicate channels or deadlock against a source refresh.
 select * into e from public.channel_source_catalog where id=p_entry_id for update;
 if not found then raise exception 'Source entry not found'; end if;
 select * into l from public.channel_source_links where entry_id=p_entry_id for update;
 if not found then
  if p_refresh_only then return jsonb_build_object('updated_lines',0); end if;
  if not e.is_present or e.stream_count=0 then raise exception 'No native stream in source entry'; end if;
  
  if p_target_channel_id is null and jsonb_array_length(e.streams)=1 then
   select cl.channel_id into p_target_channel_id from public.channel_lines cl
   join public.channels channel on channel.id=cl.channel_id
   where public.same_channel_mpd_configuration(cl.id,e.streams->0) or row(cl.stream_url,coalesce(cl.referer,''),coalesce(cl.origin,''),coalesce(cl.key_id,''),coalesce(cl.key_data,''))
    is not distinct from row(e.streams->0->>'stream_url',coalesce(e.streams->0->>'referer',''),coalesce(e.streams->0->>'origin',''),
     coalesce(e.streams->0->>'key_id',''),coalesce(e.streams->0->>'key_data',''))
    and (cl.stream_type=e.streams->0->>'stream_type' or cl.stream_type='auto' or e.streams->0->>'stream_type'='auto')
   order by channel.is_active desc,(channel.epg_id is not null and channel.epg_source is not null) desc,cl.created_at,cl.id limit 1;
  end if;
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
  -- Deleting an imported line is an explicit operator rejection. Its source
  -- entry/line ID must not be resurrected by a later catalog sync. Other
  -- entries and sibling lines continue refreshing normally.
  if exists (
    select 1 from public.channel_source_line_suppressions suppressed
    where suppressed.entry_id=e.id
      and suppressed.channel_id=l.channel_id
      and suppressed.source_line_id=config->>'id'
  ) then
    m:=m-(config->>'id');
    continue;
  end if;
  old_config:=m->(config->>'id');line_id:=nullif(old_config->>'line_id','')::uuid;
  if line_id is not null and not exists(select from public.channel_lines where id=line_id and channel_id=l.channel_id) then line_id:=null; end if;
  shared_line:=coalesce((old_config->>'shared')::boolean,false);
  if shared_line and line_id is not null and exists(
   select from public.channel_lines where id=line_id and
    (label,stream_url,stream_type,referer,origin,key_id,key_data) is distinct from
    (config->>'label',config->>'stream_url',config->>'stream_type',config->>'referer',config->>'origin',config->>'key_id',config->>'key_data')) then
   line_id:=null;shared_line:=false;
  end if;
  if line_id is null then
   select id into line_id from public.channel_lines
    where public.same_channel_mpd_configuration(id,config) or (channel_id=l.channel_id and
     (stream_url,referer,origin,key_id,key_data) is not distinct from
     (config->>'stream_url',config->>'referer',config->>'origin',config->>'key_id',config->>'key_data')
     and (stream_type=config->>'stream_type' or stream_type='auto' or config->>'stream_type'='auto'))
    order by sort_order,created_at limit 1;
   shared_line:=line_id is not null;
   if line_id is null then
   select coalesce(max(sort_order),-1)+1 into position from public.channel_lines where channel_id=l.channel_id;
   insert into public.channel_lines(channel_id,label,stream_url,stream_type,referer,origin,key_id,key_data,sort_order)
    values(l.channel_id,config->>'label',config->>'stream_url',config->>'stream_type',
     config->>'referer',config->>'origin',config->>'key_id',config->>'key_data',position) returning id into line_id;
   changed:=changed+1;shared_line:=false;
   end if;
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
  m:=jsonb_set(m,array[config->>'id'],jsonb_build_object('line_id',line_id,'source_missing',false,'shared',shared_line));
 end loop;
 for old_item in select key,value from jsonb_each(m) loop
  if not exists(select from jsonb_array_elements(e.streams) item where item->>'id'=old_item.key)
    and not coalesce((old_item.value->>'source_missing')::boolean,false) then
   if coalesce((old_item.value->>'shared')::boolean,false) then
    m:=m-old_item.key;continue;
   end if;
   line_id:=(old_item.value->>'line_id')::uuid;
   select is_active into was_enabled from public.channel_lines where id=line_id and channel_id=l.channel_id;
   update public.channel_lines set is_active=false where id=line_id and channel_id=l.channel_id;
   m:=jsonb_set(m,array[old_item.key],old_item.value||jsonb_build_object('source_missing',true,'was_enabled',coalesce(was_enabled,false)));
  end if;
 end loop;
 update public.channel_source_links set line_map=m,source_missing=false,last_synced_at=now() where entry_id=e.id;
 return jsonb_build_object('channel_id',l.channel_id,'updated_lines',changed);
end $function$

