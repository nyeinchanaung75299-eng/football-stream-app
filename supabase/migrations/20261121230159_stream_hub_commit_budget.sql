-- PostgREST hoists this setting before the RPC starts. Full catalog upgrades
-- need more than the default API statement budget; this remains service-only.
alter function public.commit_stream_hub_snapshot(uuid,text,jsonb,jsonb) set statement_timeout='45s';

-- Do not rewrite every large stream JSON whenever an unrelated origin rotates.
-- Presence comes from the authoritative incoming IDs, not a per-row revision.
do $$
declare definition text;
 old_tail text:='event_meta=excluded.event_meta;';
 old_removal text:='if p_complete then update public.channel_source_catalog set is_present=false where source_id=p_source and revision<>p_revision; end if;';
begin
 definition:=pg_get_functiondef('public.commit_connected_channel_source_sync(text,uuid,text,jsonb,boolean,boolean)'::regprocedure);
 if strpos(definition,old_tail)=0 or strpos(definition,old_removal)=0 then raise exception 'Catalog upsert hook unavailable';end if;
 definition:=replace(definition,old_tail,$patch$event_meta=excluded.event_meta
  where row(channel_source_catalog.provider,channel_source_catalog.kind,channel_source_catalog.name,channel_source_catalog.category,
   channel_source_catalog.image_url,channel_source_catalog.source_file,channel_source_catalog.playlist_url,channel_source_catalog.streams,
   channel_source_catalog.unsupported_count,channel_source_catalog.stream_count,channel_source_catalog.is_present,
   channel_source_catalog.epg_id,channel_source_catalog.epg_source,channel_source_catalog.epg_channel_id,channel_source_catalog.region,channel_source_catalog.event_meta)
  is distinct from row(excluded.provider,excluded.kind,excluded.name,excluded.category,excluded.image_url,excluded.source_file,
   excluded.playlist_url,excluded.streams,excluded.unsupported_count,excluded.stream_count,true,excluded.epg_id,excluded.epg_source,
   excluded.epg_channel_id,excluded.region,excluded.event_meta);$patch$);
 definition:=replace(definition,old_removal,$patch$if p_complete then update public.channel_source_catalog set is_present=false
  where source_id=p_source and is_present and id not in(select item->>'id' from jsonb_array_elements(p_entries) item); end if;$patch$);
 execute definition;
end $$;
notify pgrst,'reload schema';
