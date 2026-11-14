begin;
do $$
declare
 entry text:='permanent-channel-delete-fixture'; channel uuid; line uuid;
 fixture uuid; copied uuid; manual uuid; config jsonb; result jsonb;
begin
 config:=jsonb_build_object('id','permanent-line','label','Test stream',
  'stream_type','dash','stream_url','https://example.org/permanent-delete.mpd',
  'key_id',repeat('a',32),'key_data',repeat('b',32));
 insert into public.channel_source_catalog(id,provider,kind,name,category,
  source_file,streams,stream_count,revision)
 values(entry,1,'channel','Permanent delete fixture','Sports','fixture',
  jsonb_build_array(config),1,'fixture');
 channel:=(public.link_channel_source_entry(entry)->>'channel_id')::uuid;
 select id into line from public.channel_lines where channel_id=channel;
 insert into public.matches(league,home_team,away_team,kickoff_at)
  values('Test','Home','Away',now()) returning id into fixture;
 insert into public.stream_links(match_id,label,stream_type,stream_url,
  channel_id,channel_line_id,key_id,key_data)
 values(fixture,'Copied channel line','dash',config->>'stream_url',
  channel,line,config->>'key_id',config->>'key_data') returning id into copied;
 insert into public.stream_links(match_id,label,stream_url)
  values(fixture,'Independent manual line','https://example.org/manual.m3u8') returning id into manual;
 insert into public.channel_repository_imports(fingerprint,line_id,repository,
  revision,source_file) values(repeat('f',64),line,'rohmanabdu/lian',repeat('a',40),'fixture');
 delete from public.channels where id=channel;
 if exists(select from public.channel_lines where channel_id=channel)
  or exists(select from public.channel_source_links where channel_id=channel)
  or exists(select from public.channel_repository_imports where line_id=line)
  or exists(select from public.stream_links where id=copied) then
  raise exception 'Deleted channel left a stream/key copy or follow-up link'; end if;
 if not exists(select from public.stream_links where id=manual) or
  not exists(select from public.matches where id=fixture) then
  raise exception 'Channel deletion removed an unrelated match/manual line'; end if;
 result:=public.link_channel_source_entry(entry,null,true);
 if exists(select from public.channels where id=channel) or
  exists(select from public.channel_source_links where entry_id=entry) or
  coalesce((result->>'updated_lines')::int,0)<>0 then
  raise exception 'Background refresh revived the deleted channel'; end if;
 -- Deleting one line has the same permanent-copy semantics and the existing
 -- source rejection prevents that line being re-added on the next refresh.
 channel:=(public.link_channel_source_entry(entry)->>'channel_id')::uuid;
 select id into line from public.channel_lines where channel_id=channel;
 insert into public.stream_links(match_id,label,stream_type,stream_url,channel_id,channel_line_id)
  values(fixture,'Copied line','dash',config->>'stream_url',channel,line) returning id into copied;
 delete from public.channel_lines where id=line;
 perform public.link_channel_source_entry(entry,null,true);
 if exists(select from public.stream_links where id=copied) or
  exists(select from public.channel_lines where channel_id=channel) then
  raise exception 'Deleted line kept a match copy or was resurrected'; end if;
end $$;
rollback;
