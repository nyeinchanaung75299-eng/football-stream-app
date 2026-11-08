-- Reuse a saved channel when an identical source configuration is selected
-- again. Full URL, format, headers and the complete key pair must agree.
-- Different keys or playback headers remain independent lines.
do $$
declare definition text;
begin
 definition:=pg_get_functiondef('public.link_channel_source_entry(text,uuid,boolean)'::regprocedure);
 if strpos(definition,'if p_target_channel_id is null then')=0 then raise exception 'Channel import hook unavailable'; end if;
 definition:=replace(definition,'if p_target_channel_id is null then', $hook$
  if p_target_channel_id is null and jsonb_array_length(e.streams)=1 then
   select cl.channel_id into p_target_channel_id from public.channel_lines cl
   join public.channels channel on channel.id=cl.channel_id
   where row(cl.stream_url,coalesce(cl.referer,''),coalesce(cl.origin,''),coalesce(cl.key_id,''),coalesce(cl.key_data,''))
    is not distinct from row(e.streams->0->>'stream_url',coalesce(e.streams->0->>'referer',''),coalesce(e.streams->0->>'origin',''),
     coalesce(e.streams->0->>'key_id',''),coalesce(e.streams->0->>'key_data',''))
    and (cl.stream_type=e.streams->0->>'stream_type' or cl.stream_type='auto' or e.streams->0->>'stream_type'='auto')
   order by channel.is_active desc,(channel.epg_id is not null and channel.epg_source is not null) desc,cl.created_at,cl.id limit 1;
  end if;
  if p_target_channel_id is null then
 $hook$);
 execute definition;
end $$;

create function public.deduplicate_exact_channel_lines()
returns jsonb language plpgsql security invoker set search_path='' as $$
declare item record; source record; pair record; has_other boolean;
 removed_lines integer:=0; removed_channels integer:=0;
begin
 -- Serialize with source refreshes and lock configurations before deciding
 -- whether a row is still an exact duplicate. Existing matches keep working
 -- by following the surviving line and channel IDs.
 perform 1 from public.channel_source_catalog order by id for update;
 perform 1 from public.channels order by id for update;
 perform 1 from public.channel_lines order by id for update;
 for item in
  with ranked as (
   select l.id,l.channel_id,first_value(l.id) over same_config keep_id,
    first_value(l.channel_id) over same_config keep_channel,
    row_number() over same_config rank
   from public.channel_lines l join public.channels c on c.id=l.channel_id
   window same_config as (partition by l.stream_url,l.stream_type,coalesce(l.referer,''),coalesce(l.origin,''),
     coalesce(l.key_id,''),coalesce(l.key_data,''),
     case when nullif(l.key_id,'') is not null and nullif(l.key_data,'') is not null then 'clearkey'
      else coalesce((select r.metadata->>'drm_type' from public.channel_repository_imports r where r.line_id=l.id order by r.imported_at limit 1),'unspecified') end,
     coalesce((select r.metadata->>'license_url' from public.channel_repository_imports r where r.line_id=l.id order by r.imported_at limit 1),'')
    order by c.is_active desc,(c.epg_id is not null and c.epg_source is not null) desc,l.is_active desc,l.created_at,l.id)
  ) select * from ranked where rank>1 order by channel_id,id
 loop
  select exists(select from public.channel_lines where channel_id=item.channel_id and id<>item.id) into has_other;
  -- A multi-line alias may have different channels mixed in it. Keep that
  -- case for explicit review instead of moving unrelated configurations.
  if item.channel_id<>item.keep_channel and has_other then continue; end if;
  for source in select entry_id,line_map,channel_id from public.channel_source_links
   where channel_id=item.channel_id or line_map::text like '%'||item.id::text||'%' for update loop
   for pair in select key,value from jsonb_each(source.line_map) loop
    if pair.value->>'line_id'=item.id::text then
     source.line_map:=jsonb_set(source.line_map,array[pair.key],pair.value||
      jsonb_build_object('line_id',item.keep_id,'shared',true));
    end if;
   end loop;
   update public.channel_source_links set line_map=source.line_map,
    channel_id=case when channel_id=item.channel_id and not has_other then item.keep_channel else channel_id end,
    owns_channel=case when channel_id=item.channel_id and item.channel_id<>item.keep_channel and not has_other then false else owns_channel end
    where entry_id=source.entry_id;
  end loop;
  update public.stream_links set channel_line_id=item.keep_id,channel_id=item.keep_channel where channel_line_id=item.id;
  if to_regclass('public.nca_epg_auto_stream_links') is not null then
   update public.nca_epg_auto_stream_links set channel_line_id=item.keep_id where channel_line_id=item.id;
  end if;
  update public.nca_viewer_reports set line_id=item.keep_id,channel_id=item.keep_channel where line_id=item.id;
  update public.channel_repository_imports set line_id=item.keep_id where line_id=item.id;
  delete from public.channel_lines where id=item.id;
  removed_lines:=removed_lines+1;
  if item.channel_id<>item.keep_channel and not has_other then
   update public.stream_links set channel_id=item.keep_channel where channel_id=item.channel_id;
   update public.nca_viewer_reports set channel_id=item.keep_channel where channel_id=item.channel_id;
   update public.channel_source_catalog set epg_channel_id=item.keep_channel where epg_channel_id=item.channel_id;
   if to_regclass('public.nca_epg_auto_match_channels') is not null then
    insert into public.nca_epg_auto_match_channels(match_id,channel_id,programme_title,programme_start,guide_updated_at,last_verified_at)
     select match_id,item.keep_channel,programme_title,programme_start,guide_updated_at,last_verified_at
     from public.nca_epg_auto_match_channels where channel_id=item.channel_id
     on conflict(match_id,channel_id) do nothing;
   end if;
   if to_regclass('public.nca_bot_match_channels') is not null then
    insert into public.nca_bot_match_channels(match_id,channel_id,source,created_at)
     select match_id,item.keep_channel,source,created_at from public.nca_bot_match_channels where channel_id=item.channel_id
     on conflict(match_id,channel_id) do nothing;
   end if;
   delete from public.channels where id=item.channel_id;
   removed_channels:=removed_channels+1;
  end if;
 end loop;
 return jsonb_build_object('removed_lines',removed_lines,'merged_channels',removed_channels);
end $$;
revoke all on function public.deduplicate_exact_channel_lines() from public,anon,authenticated;
grant execute on function public.deduplicate_exact_channel_lines() to service_role;
notify pgrst,'reload schema';
