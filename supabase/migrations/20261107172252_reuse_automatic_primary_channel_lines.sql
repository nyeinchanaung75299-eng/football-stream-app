-- Auto and an explicit native format are compatible for an identical URL
-- and headers. Reuse the primary without changing its operator settings.
create or replace function public.link_channel_source_entry(p_entry_id text,p_target_channel_id uuid default null,p_refresh_only boolean default false)
returns jsonb language plpgsql security invoker set search_path='' as $$
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
  shared_line:=coalesce((old_config->>'shared')::boolean,false);
  if shared_line and line_id is not null and exists(
   select from public.channel_lines where id=line_id and
    (label,stream_url,stream_type,referer,origin,key_id,key_data) is distinct from
    (config->>'label',config->>'stream_url',config->>'stream_type',config->>'referer',config->>'origin',config->>'key_id',config->>'key_data')) then
   line_id:=null;shared_line:=false;
  end if;
  if line_id is null then
   select id into line_id from public.channel_lines
    where channel_id=l.channel_id and
     (stream_url,referer,origin,key_id,key_data) is not distinct from
     (config->>'stream_url',config->>'referer',config->>'origin',config->>'key_id',config->>'key_data')
     and (stream_type=config->>'stream_type' or stream_type='auto' or config->>'stream_type'='auto')
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
end $$;
notify pgrst,'reload schema';
