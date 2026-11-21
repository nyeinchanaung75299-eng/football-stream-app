-- Disposable database only. No live channels are modified by this fixture.
begin;
do $$ begin
 if current_database()<>'nca_security_test' then raise exception 'Disposable database required';end if;
end $$;
set local role service_role;
select public.import_repository_mpds(jsonb_build_array(
 jsonb_build_object('repository','darkbyteprojects/iptv_png','revision',repeat('a',40),'source_file','provider_1/sports.json',
  'name','Partial update healthy','stream_url','https://partial.example.org/healthy.mpd?token=old','configuration_status','clear'),
 jsonb_build_object('repository','rohmanabdu/lian','revision',repeat('a',40),'source_file','finall',
  'name','Partial update unavailable','stream_url','https://partial.example.org/unavailable.mpd?token=old','configuration_status','clear'),
 jsonb_build_object('repository','darkbyteprojects/iptv_png','revision',repeat('a',40),'source_file','provider_1/sports.json',
  'name','Partial update removed','stream_url','https://partial.example.org/removed.mpd','configuration_status','clear')
));
do $$
declare result jsonb; original_metadata jsonb;
begin
 select metadata into original_metadata from public.channel_repository_imports where repository='rohmanabdu/lian';
 result:=public.refresh_available_repository_channel_imports(jsonb_build_array(
  jsonb_build_object('repository','darkbyteprojects/iptv_png','revision',repeat('b',40),'source_file','provider_1/sports.json',
   'name','Partial update healthy','stream_url','https://partial.example.org/healthy.mpd?token=new','configuration_status','clear')
 ),'["rohmanabdu/lian","rohmanabdu/deqiaa"]');
 if result->>'updated_lines'<>'1' or result->>'unavailable_imports'<>'1' or result->>'missing_or_ambiguous'<>'1' then
  raise exception 'Partial update counts incorrect: %',result;
 end if;
 if not exists(select from public.channel_lines where stream_url='https://partial.example.org/healthy.mpd?token=new' and health_status='unknown') then
  raise exception 'Observed healthy source did not rotate';
 end if;
 if not exists(select from public.channel_repository_imports r join public.channel_lines l on l.id=r.line_id
  where r.repository='rohmanabdu/lian' and r.metadata=original_metadata and l.stream_url='https://partial.example.org/unavailable.mpd?token=old') then
  raise exception 'Unavailable source configuration or verification metadata changed';
 end if;
 if not exists(select from public.channel_repository_imports r join public.channel_lines l on l.id=r.line_id
  where l.stream_url='https://partial.example.org/removed.mpd' and r.metadata->>'source_missing'='true') then
  raise exception 'Observed removal did not get flagged';
 end if;
 begin
  perform public.refresh_available_repository_channel_imports('[]','["untrusted/repo"]');
  raise exception 'Invalid missing origin accepted';
 exception when raise_exception then if sqlerrm<>'Invalid unavailable repository list' then raise;end if;end;
end $$;
reset role;
set local role authenticated;
do $$begin
 begin
  perform public.refresh_available_repository_channel_imports('[]','[]');
  raise exception 'Non-service update accepted';
 exception when insufficient_privilege then null;end;
end $$;
rollback;
