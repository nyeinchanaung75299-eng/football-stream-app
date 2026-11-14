-- Exercise the real importer, including its line refresh path.
begin;
do $$
declare
 entry text:='verified-logo-fixture'; channel uuid; line uuid;
 config jsonb:=jsonb_build_object('id','fixture-line','label','Source line',
   'stream_type','hls','stream_url','https://example.org/fixture.m3u8');
begin
 insert into public.channel_source_catalog(id,provider,kind,name,category,
  image_url,source_file,playlist_url,streams,unsupported_count,stream_count,revision)
 values(entry,1,'channel','Source station','Sports','https://example.org/wrong.png',
  'fixture','https://example.org/playlist',jsonb_build_array(config),0,1,'fixture');
 channel:=(public.link_channel_source_entry(entry)->>'channel_id')::uuid;
 select id into line from public.channel_lines where channel_id=channel;
 update public.channels set image_url='https://example.org/verified.png',image_locked=true where id=channel;
 update public.channel_source_catalog set name='Updated source station',
  streams=jsonb_build_array(config||jsonb_build_object('stream_url','https://example.org/new.m3u8')) where id=entry;
 perform public.link_channel_source_entry(entry,null,true);
 if not exists(select from public.channels where id=channel
   and image_url='https://example.org/verified.png' and name='Updated source station') then
  raise exception 'Verified logo lost or normal metadata refresh stopped'; end if;
 if not exists(select from public.channel_lines where id=line and stream_url='https://example.org/new.m3u8') then
  raise exception 'Logo protection stopped source line refresh'; end if;
 update public.channels set image_url='https://example.org/operator.png' where id=channel;
 perform public.link_channel_source_entry(entry,null,true);
 if not exists(select from public.channels where id=channel and image_url='https://example.org/operator.png') then
  raise exception 'Manual logo edit was lost'; end if;
 update public.channels set image_locked=false where id=channel;
 perform public.link_channel_source_entry(entry,null,true);
 if not exists(select from public.channels where id=channel and image_url='https://example.org/wrong.png') then
  raise exception 'Unlocked source logo did not refresh'; end if;
end $$;
rollback;
