-- Run only in the disposable database created by test_database_security.sh.
begin;
do $$ begin
  if (select array_agg(column_name::text || ':' || udt_name::text order by ordinal_position)
      from information_schema.columns where table_schema='public' and table_name='match_stream_counts')
     is distinct from array['match_id:uuid','stream_count:int4']::text[] then
    raise exception 'Public count API columns changed';
  end if;
  if current_database() <> 'nca_security_test' then
    raise exception 'This test requires the disposable nca_security_test database';
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='stream_library'
      and column_name in ('key_id','key_data')
  ) then
    raise exception 'Private HLS Library must not store DRM keys';
  end if;
end $$;

insert into auth.users(id) values
  ('20000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000002');
insert into public.profiles(id,role) values
  ('20000000-0000-0000-0000-000000000001','admin'),
  ('20000000-0000-0000-0000-000000000002','viewer');
insert into public.matches(id,league,home_team,away_team,kickoff_at,is_active,is_featured,publish_state) values
  ('10000000-0000-0000-0000-000000000001','Test','A','B',now(),true,true,'published'),
  ('10000000-0000-0000-0000-000000000002','Test','C','D',now(),true,true,'published'),
  ('10000000-0000-0000-0000-000000000003','Test','E','F',now(),true,true,'draft'),
  ('10000000-0000-0000-0000-000000000004','Test','G','H',now(),false,true,'published'),
  ('10000000-0000-0000-0000-000000000005','Test','I','J',now(),true,false,'published');
insert into public.stream_links(match_id,label,stream_url,stream_type,key_id,key_data,is_active,use_webview,available_from,expires_at) values
  ('10000000-0000-0000-0000-000000000001','HLS','https://fixture.invalid/live.m3u8','hls',null,null,true,false,null,null),
  ('10000000-0000-0000-0000-000000000001','Keyed DASH','https://fixture.invalid/live.mpd','dash','fixture-id','fixture-key',true,false,null,null),
  ('10000000-0000-0000-0000-000000000001','Inactive','https://fixture.invalid/disabled','hls',null,null,false,false,null,null),
  ('10000000-0000-0000-0000-000000000001','Webview','https://fixture.invalid/embed','hls',null,null,true,true,null,null),
  ('10000000-0000-0000-0000-000000000001','Blank','','hls',null,null,true,false,null,null),
  ('10000000-0000-0000-0000-000000000001','Future','https://fixture.invalid/future','hls',null,null,true,false,now()+interval '1 hour',null),
  ('10000000-0000-0000-0000-000000000001','Expired','https://fixture.invalid/expired','hls',null,null,true,false,null,now()-interval '1 hour');
insert into public.stream_links(match_id,stream_url)
  select id,'https://fixture.invalid/private' from public.matches
  where id in ('10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000005');
insert into public.highlights(title,video_url,is_active) values
  ('Active','https://fixture.invalid/a',true),('Inactive','https://fixture.invalid/b',false);
insert into public.stream_library(label,stream_url,referer,origin) values
  ('Saved HLS','https://fixture.invalid/library.m3u8?private=1',
   'https://fixture.invalid/watch','https://fixture.invalid');
insert into private.gateway_secrets(name,secret_hash) values
  ('cloudflare_playback',encode(extensions.digest('local-test-gateway','sha256'),'hex'));

do $$ begin
  if private.visible_stream_count(null) <> 0 or
     private.visible_stream_count('10000000-0000-0000-0000-000000000003') <> 0 or
     private.visible_stream_count('10000000-0000-0000-0000-000000000004') <> 0 or
     private.visible_stream_count('10000000-0000-0000-0000-000000000005') <> 0 or
     private.visible_stream_count('10000000-0000-0000-0000-000000000099') <> 0 then
    raise exception 'Private count helper leaked unavailable match counts';
  end if;
end $$;

set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
  if (select count(*) from public.match_stream_counts) <> 2 or
     (select stream_count from public.match_stream_counts where match_id='10000000-0000-0000-0000-000000000001') <> 2 or
     (select stream_count from public.match_stream_counts where match_id='10000000-0000-0000-0000-000000000002') <> 0 then
    raise exception 'Anonymous counts changed or keyed DASH was excluded';
  end if;
  if (select count(*) from public.stream_links) <> 0 or
     (select count(*) from public.profiles) <> 0 or
     (select count(*) from public.highlights) <> 1 then
    raise exception 'Anonymous RLS read boundary failed';
  end if;
  if has_schema_privilege('anon','private','USAGE') or
     has_table_privilege('anon','public.stream_links','TRUNCATE') or
     has_table_privilege('authenticated','public.stream_links','TRUNCATE') or
     has_table_privilege('anon','public.stream_links','TRIGGER') or
     has_table_privilege('authenticated','public.stream_links','TRIGGER') or
     has_table_privilege('anon','public.stream_links','REFERENCES') or
     has_table_privilege('authenticated','public.stream_links','REFERENCES') or
     has_table_privilege('anon','public.stream_library','SELECT') or
     has_table_privilege('authenticated','public.stream_library','TRUNCATE') or
     has_table_privilege('authenticated','public.profiles','UPDATE') or
     has_function_privilege('anon','public.publish_featured_matches(jsonb)','EXECUTE') then
    raise exception 'Anonymous private-schema or publish privilege was granted';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(
      public.get_stream_metadata_for_gateway(
        '10000000-0000-0000-0000-000000000001','local-test-gateway')->'streams') s
    where s->>'stream_type'='dash' and s->>'key_data'='fixture-key'
  ) then
    raise exception 'Valid gateway failed to resolve keyed DASH';
  end if;
  begin
    perform public.get_stream_metadata_for_gateway('10000000-0000-0000-0000-000000000001','wrong-secret');
    raise exception 'Wrong gateway secret accepted';
  exception when insufficient_privilege then null;
  end;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000002',true);
do $$ begin
  if public.is_admin() or (select count(*) from public.profiles) <> 1 or
     (select count(*) from public.stream_links) <> 0 or
     (select count(*) from public.stream_library) <> 0 or
     (select count(*) from public.highlights) <> 1 or
     (select stream_count from public.match_stream_counts where match_id='10000000-0000-0000-0000-000000000001') <> 2 then
    raise exception 'Non-admin read privileges changed';
  end if;
  begin
    perform public.publish_featured_matches('[]'::jsonb);
    raise exception 'Non-admin publish accepted';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.stream_links(match_id,stream_url) values
      ('10000000-0000-0000-0000-000000000001','https://fixture.invalid/unauthorized');
    raise exception 'Non-admin insert accepted';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.stream_library(label,stream_url) values
      ('Unauthorized','https://fixture.invalid/unauthorized.m3u8');
    raise exception 'Non-admin Library insert accepted';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000001',true);
do $$ declare result jsonb; before_count int; begin
  if not public.is_admin() or (select count(*) from public.profiles) <> 2 or
     (select count(*) from public.matches) <> 5 or
     (select count(*) from public.stream_library) <> 1 or
     (select count(*) from public.highlights) <> 2 then
    raise exception 'Admin read privileges changed';
  end if;
  insert into public.stream_library(label,stream_url) values
    ('Added HLS','https://fixture.invalid/added.m3u8');
  update public.stream_library set label='Edited HLS',updated_at='2000-01-01'
    where label='Added HLS';
  if (select updated_at from public.stream_library where label='Edited HLS') <> now() then
    raise exception 'Library timestamp trigger failed';
  end if;
  delete from public.stream_library where label='Edited HLS';
  insert into public.stream_links(match_id,label,stream_url) values
    ('10000000-0000-0000-0000-000000000001','Added','https://fixture.invalid/added');
  if (select stream_count from public.match_stream_counts where match_id='10000000-0000-0000-0000-000000000001') <> 3 then
    raise exception 'Inserted stream count was stale';
  end if;
  update public.stream_links set is_active=false where label='Added';
  if (select stream_count from public.match_stream_counts where match_id='10000000-0000-0000-0000-000000000001') <> 2 then
    raise exception 'Updated stream count was stale';
  end if;
  delete from public.stream_links where match_id='10000000-0000-0000-0000-000000000001';
  if (select stream_count from public.match_stream_counts where match_id='10000000-0000-0000-0000-000000000001') <> 0 then
    raise exception 'Final deleted stream count was stale';
  end if;
  update public.matches set league='Edited',updated_at='2000-01-01' where id='10000000-0000-0000-0000-000000000001';
  if (select updated_at from public.matches where id='10000000-0000-0000-0000-000000000001') <> now() then
    raise exception 'Timestamp trigger failed with fixed search path';
  end if;
  insert into public.highlights(title,video_url) values ('Added','https://fixture.invalid/new');
  update public.highlights set is_active=false where title='Added';
  delete from public.highlights where title='Added';
  result := public.publish_featured_matches('[{"fixture_id":501,"league_name":"Test","home_name":"K","away_name":"L","kickoff_at":"2026-10-10T12:00:00Z"}]'::jsonb);
  if (result->>'published_count')::int <> 1 or
     not (select is_featured from public.matches where id='10000000-0000-0000-0000-000000000001') then
    raise exception 'Publish replaced existing featured matches';
  end if;
  select count(*) into before_count from public.matches;
  begin
    perform public.publish_featured_matches('[{"fixture_id":502,"league_name":"Test","home_name":"M","away_name":"N","kickoff_at":"2026-10-10T12:00:00Z"},{"fixture_id":503,"league_name":"Test","home_name":"O","away_name":"P","kickoff_at":"invalid-date"}]'::jsonb);
    raise exception 'Invalid fixture unexpectedly published';
  exception when invalid_datetime_format then null;
  end;
  if (select count(*) from public.matches) <> before_count then
    raise exception 'Failed publish was not atomic';
  end if;
end $$;
reset role;
do $$
begin
  if has_function_privilege('anon','public.claim_nca_bot_update(text,bigint,uuid)','execute')
     or has_function_privilege('authenticated','public.claim_nca_bot_update(text,bigint,uuid)','execute') then
    raise exception 'Bot claim RPC exposed to client roles';
  end if;
  if has_table_privilege('anon','public.nca_viewer_reminders','select')
     or has_table_privilege('authenticated','public.nca_viewer_reminders','insert')
     or has_table_privilege('anon','public.nca_viewer_reports','select') then
    raise exception 'Viewer bot private data exposed to clients';
  end if;
end $$;

set role service_role;
do $$
declare claim_id uuid := gen_random_uuid();
begin
  if public.claim_nca_bot_update('viewer',999999999,claim_id) <> 'claimed' then
    raise exception 'First claim must succeed';
  end if;
  if public.claim_nca_bot_update('viewer',999999999,gen_random_uuid()) <> 'busy' then
    raise exception 'Concurrent duplicate must wait for the lease';
  end if;
  update public.nca_bot_updates set completed=true where bot='viewer' and update_id=999999999;
  if public.claim_nca_bot_update('viewer',999999999,gen_random_uuid()) <> 'completed' then
    raise exception 'Completed update must not execute again';
  end if;
  delete from public.nca_bot_updates where bot='viewer' and update_id=999999999;
end $$;
reset role;

-- Connected sources are never a public playlist/credential endpoint.
do $$ begin
 if has_table_privilege('anon','public.channel_source_catalog','select') or
    has_function_privilege('authenticated','public.link_channel_source_entry(text,uuid,boolean)','execute') or
    has_function_privilege('anon','public.commit_channel_source_sync(uuid,text,jsonb,boolean,boolean)','execute') then
  raise exception 'Source catalog or mutation RPC exposed to client roles';
 end if;
end $$;
set local role service_role;
do $$
declare lease jsonb; entry jsonb; result jsonb; cid uuid; lid uuid; before_channels integer; configured text; gateway jsonb;
begin
 select count(*) into before_channels from public.channels;
 entry:=jsonb_build_object('id','db:p1:channel:0000000000000000000000000001','provider',1,'kind','channel',
  'name','Followed source','category','Sports','source_file','provider_1/channels.json','streams',jsonb_build_array(
   jsonb_build_object('id','primary','label','Primary','stream_url','https://fixture.invalid/first.m3u8','stream_type','hls')),'unsupported_count',0);
 lease:=public.begin_channel_source_sync(true);
 if not (public.begin_channel_source_sync(true)->>'busy')::boolean then raise exception 'Concurrent source refresh acquired the same lease'; end if;
 perform public.commit_channel_source_sync((lease->>'lease')::uuid,'revision-1',jsonb_build_array(entry),true,false);
 if (select count(*) from public.channels)<>before_channels then raise exception 'Refreshing source must never import unselected channels'; end if;
 result:=public.link_channel_source_entry(entry->>'id');cid:=(result->>'channel_id')::uuid;
 select (line_map->'primary'->>'line_id')::uuid into lid from public.channel_source_links where entry_id=entry->>'id';
 perform public.link_channel_source_entry(entry->>'id');
 if (select count(*) from public.channels)<>before_channels+1 or
    (select count(*) from public.channel_lines where channel_id=cid)<>1 then raise exception 'Repeated import duplicated a channel or line'; end if;
 insert into public.channel_lines(channel_id,label,stream_url) values(cid,'Manual backup','https://fixture.invalid/manual.m3u8');
 insert into public.stream_links(match_id,channel_id,channel_line_id,label,stream_url)
  values('10000000-0000-0000-0000-000000000001',cid,lid,'Bound source','https://fixture.invalid/stale-copy.m3u8');
 entry:=jsonb_set(entry,'{streams,0,stream_url}','"https://fixture.invalid/rotated.m3u8"');
 entry:=jsonb_set(entry,'{streams}',entry->'streams'||jsonb_build_array(jsonb_build_object('id','backup','label','New backup',
  'stream_url','https://fixture.invalid/new.m3u8','stream_type','hls')));
 lease:=public.begin_channel_source_sync(true);
 perform public.commit_channel_source_sync((lease->>'lease')::uuid,'revision-2',jsonb_build_array(entry),true,false);
 select stream_url into configured from public.channel_lines where id=lid;
 if configured<>'https://fixture.invalid/rotated.m3u8' or
    (select count(*) from public.channel_lines where channel_id=cid)<>3 then raise exception 'Source rotation or newly added backup did not follow the selection'; end if;
 set local role authenticated;
 gateway:=public.get_stream_metadata_for_gateway('10000000-0000-0000-0000-000000000001','local-test-gateway');
 set local role service_role;
 if not exists(select from jsonb_array_elements(gateway->'streams') row where row->>'label'='Bound source'
  and row->>'stream_url'='https://fixture.invalid/rotated.m3u8') then raise exception 'Bound match did not resolve the current channel source'; end if;
 if not exists(select from public.stream_links where channel_line_id=lid and stream_url='https://fixture.invalid/stale-copy.m3u8') then raise exception 'Resolving a binding must not rewrite operator data'; end if;
 update public.channel_source_links set follow_updates=false where entry_id=entry->>'id';
 entry:=jsonb_set(entry,'{streams,0,stream_url}','"https://fixture.invalid/paused-change.m3u8"');
 lease:=public.begin_channel_source_sync(true);
 perform public.commit_channel_source_sync((lease->>'lease')::uuid,'revision-3',jsonb_build_array(entry),true,false);
 if (select stream_url from public.channel_lines where id=lid)<>configured then raise exception 'Paused source still overwrote local configuration'; end if;
 update public.channel_source_links set follow_updates=true where entry_id=entry->>'id';
 perform public.link_channel_source_entry(entry->>'id',null,true);
 if (select stream_url from public.channel_lines where id=lid)<>'https://fixture.invalid/paused-change.m3u8' then raise exception 'Resuming did not use the latest saved source'; end if;
 lease:=public.begin_channel_source_sync(true);
 perform public.commit_channel_source_sync((lease->>'lease')::uuid,'partial','[]',false,false);
 if not (select is_present from public.channel_source_catalog where id=entry->>'id') then raise exception 'Partial source failure removed last-good entries'; end if;
 lease:=public.begin_channel_source_sync(true);
 perform public.commit_channel_source_sync((lease->>'lease')::uuid,'revision-4','[]',true,false);
 if not (select source_missing from public.channel_source_links where entry_id=entry->>'id') or
  not exists(select from public.channel_lines where id=lid) then raise exception 'Missing upstream must be marked without deleting a saved channel'; end if;
 delete from public.channel_source_links where entry_id=entry->>'id';
 lease:=public.begin_channel_source_sync(true);
 perform public.commit_channel_source_sync((lease->>'lease')::uuid,'revision-5',jsonb_build_array(entry),true,false);
 if exists(select from public.channel_source_links where entry_id=entry->>'id') then raise exception 'A removed connection was automatically reimported'; end if;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000002',true);
-- Each source has its own lease, snapshot and selected links. A verified
-- Sports EPG match appends a backup to the existing channel without duplicates.
reset role;
set local role service_role;
do $$
declare cid uuid; entry jsonb; shared_entry jsonb; lease jsonb; result jsonb; before_channels integer;
begin
 select count(*) into before_channels from public.channels;
 insert into public.channels(name,category,epg_id,epg_source) values('TNT Sports 1','Sports','TNT.Sports.1.uk','UK1') returning id into cid;
 insert into public.channel_lines(channel_id,label,stream_url) values(cid,'Existing','https://fixture.invalid/existing.m3u8');
 entry:=jsonb_build_object('id','ltv:channel:0000000000000000000000000001','provider',7,'kind','channel',
  'name','TNT Sports 1 HD','category','Sports • UK','source_file','LiveTV/UK/LiveTV.json',
  'epg_id','TNT.Sports.1.uk','epg_source','UK1','epg_channel_id',cid,'region','UK','unsupported_count',0,
  'streams',jsonb_build_array(jsonb_build_object('id','sports-primary','label','LiveTVCollector 1',
   'stream_type','hls','stream_url','https://fixture.invalid/sports.m3u8')));
 lease:=public.begin_connected_channel_source_sync('livetv',true);
 perform public.commit_connected_channel_source_sync('livetv',(lease->>'lease')::uuid,'sports-1',jsonb_build_array(entry),true,false);
 if (select count(*) from public.channels)<>before_channels+1 then raise exception 'Sports catalog published channels without a selection'; end if;
 result:=public.import_connected_channel_source_entry(entry->>'id');
 if (result->>'channel_id')::uuid<>cid then raise exception 'EPG-linked import duplicated an existing channel'; end if;
 perform public.import_connected_channel_source_entry(entry->>'id');
 if (select count(*) from public.channel_lines where channel_id=cid)<>2 then raise exception 'Sports backup missing or duplicated'; end if;
 shared_entry:=jsonb_set(entry,'{id}','"ltv:channel:0000000000000000000000000002"');
 shared_entry:=jsonb_set(shared_entry,'{streams,0,stream_url}','"https://fixture.invalid/existing.m3u8"');
 lease:=public.begin_connected_channel_source_sync('livetv',true);
 perform public.commit_connected_channel_source_sync('livetv',(lease->>'lease')::uuid,'sports-2',jsonb_build_array(entry,shared_entry),true,false);
 perform public.import_connected_channel_source_entry(shared_entry->>'id');
 if (select count(*) from public.channel_lines where channel_id=cid)<>2 then raise exception 'Identical primary configuration duplicated'; end if;
 shared_entry:=jsonb_set(shared_entry,'{streams,0,stream_url}','"https://fixture.invalid/shared-rotation.m3u8"');
 lease:=public.begin_connected_channel_source_sync('livetv',true);
 perform public.commit_connected_channel_source_sync('livetv',(lease->>'lease')::uuid,'sports-3',jsonb_build_array(entry,shared_entry),true,false);
 if (select count(*) from public.channel_lines where channel_id=cid)<>3 or not exists(
  select from public.channel_lines where channel_id=cid and label='Existing' and stream_url='https://fixture.invalid/existing.m3u8') then
  raise exception 'Following a shared source overwrote the existing primary';
 end if;
 lease:=public.begin_channel_source_sync(true);
 perform public.commit_channel_source_sync((lease->>'lease')::uuid,'darkbyte-independent','[]',true,false);
 if not (select is_present from public.channel_source_catalog where id=entry->>'id') then raise exception 'DarkByte refresh removed Sports source'; end if;
 if not exists(select from public.channels where id=cid and name='TNT Sports 1' and epg_source='UK1') then raise exception 'Source overwrote existing channel metadata'; end if;
 if has_function_privilege('authenticated','public.import_connected_channel_source_entry(text,uuid,boolean)','execute') then raise exception 'Sports mutation bypasses Admin auth'; end if;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000002',true);
do $$ begin
 if exists(select from public.channel_source_catalog) or exists(select from public.channel_source_links) then
  raise exception 'Viewer role can read private source URLs';
 end if;
end $$;
reset role;

-- Bulk repository imports retain private credentials, skip existing and
-- cross-repository token rotations, and never publish missing-key MPDs.
set local role service_role;
do $$
declare payload jsonb; result jsonb; cid uuid; before_channels integer;
begin
 select count(*) into before_channels from public.channels;
 payload:=jsonb_build_array(jsonb_build_object('repository','rohmanabdu/lian','revision',repeat('a',40),
  'source_file','hasill','name','Repository MPD fixture','category','Sports',
  'stream_url','https://cdn.example.org/new.mpd?id=one&token=first','configuration_status','requires_drm'));
 result:=public.import_repository_mpds(payload);
 if (result->>'added_channels')::integer<>1 or (result->>'added_lines')::integer<>1 then raise exception 'New MPD missing'; end if;
 payload:=jsonb_set(payload,'{0,stream_url}','"https://cdn.example.org/new.mpd?token=second&id=one"');
 payload:=jsonb_set(payload,'{0,repository}','"Roshavarma/cfy"');
 result:=public.import_repository_mpds(payload);
 if (result->>'added_lines')::integer<>0 or (result->>'skipped_existing')::integer<>1 then raise exception 'Rotated MPD duplicated'; end if;
 if not exists(select from public.channel_lines where stream_url='https://cdn.example.org/new.mpd?id=one&token=first' and configuration_status='requires_drm') then raise exception 'Repeated import overwrote saved configuration'; end if;
 if (select count(*) from public.channels)<>before_channels+1 then raise exception 'Duplicate channel created'; end if;
 if not exists(select from public.channel_lines where stream_url like 'https://cdn.example.org/new.mpd%' and configuration_status='requires_drm') then raise exception 'Missing DRM not labelled'; end if;
 select c.id into cid from public.channels c where c.name='Repository MPD fixture';
 if jsonb_array_length(public.get_channel_metadata_for_gateway(cid,'local-test-gateway')->'streams')<>0 then raise exception 'Missing DRM became playable'; end if;
 if has_function_privilege('authenticated','public.import_repository_mpds(jsonb)','execute') or has_function_privilege('anon','public.import_repository_mpds(jsonb)','execute') then raise exception 'Unprivileged MPD mutation'; end if;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000002',true);
do $$ begin
 if exists(select from public.channel_repository_imports) then raise exception 'Viewer sees private MPD provenance'; end if;
end $$;
reset role;

set local role service_role;
do $$
declare entry text:='db:p1:channel:8888888888888888888888888888'; result jsonb; link uuid; before_channels integer;
begin
 select count(*) into before_channels from public.channels;
 insert into public.channel_source_catalog(id,provider,kind,name,category,source_file,streams,stream_count,revision)
 values(entry,1,'channel','Connected test channel','Sports','provider_1/channels.json',jsonb_build_array(jsonb_build_object(
  'id','match-source-line','label','HD','stream_type','dash','stream_url','https://cdn.example.org/source.mpd',
  'key_id',repeat('a',32),'key_data',repeat('b',32))),1,'match-source-1');
 result:=public.add_connected_source_line_to_match(entry,'match-source-line','10000000-0000-0000-0000-000000000001');
 link:=(result->>'stream_link_id')::uuid;
 if not exists(select from public.stream_links where id=link and key_id=repeat('a',32) and key_data=repeat('b',32) and channel_id is null) then raise exception 'Match attachment lost configuration'; end if;
 if (select count(*) from public.channels)<>before_channels then raise exception 'Add to Match published another channel'; end if;
 result:=public.add_connected_source_line_to_match(entry,'match-source-line','10000000-0000-0000-0000-000000000001');
 if result->>'already_exists'<>'true' or (result->>'stream_link_id')::uuid<>link then raise exception 'Repeated match attachment duplicated'; end if;
 update public.stream_links set label='Operator label' where id=link;
 update public.channel_source_catalog set streams=jsonb_set(streams,'{0,stream_url}','"https://cdn.example.org/rotated.mpd"') where id=entry;
 perform public.sync_connected_source_match_lines('darkbyte');
 if not exists(select from public.stream_links where id=link and stream_url='https://cdn.example.org/rotated.mpd' and label='Operator label') then raise exception 'Source rotation lost manual metadata'; end if;
 update public.channel_source_catalog set is_present=false where id=entry;
 perform public.sync_connected_source_match_lines('darkbyte');
 if (select is_active from public.stream_links where id=link) then raise exception 'Missing source stayed active'; end if;
 update public.channel_source_catalog set is_present=true where id=entry;
 perform public.sync_connected_source_match_lines('darkbyte');
 if not (select is_active from public.stream_links where id=link) then raise exception 'Source recovery did not restore owned line'; end if;
 if has_function_privilege('anon','public.add_connected_source_line_to_match(text,text,uuid)','execute') or has_function_privilege('authenticated','public.add_connected_source_line_to_match(text,text,uuid)','execute') then raise exception 'Unverified source match mutation'; end if;
end $$;
reset role;

-- Legacy runtime-created guide/bot tables are represented in this disposable
-- database as well, so their reference-remapping branches are exercised.
create table if not exists public.nca_epg_auto_stream_links (
 stream_link_id uuid primary key references public.stream_links(id) on delete cascade,
 match_id uuid not null references public.matches(id),
 channel_line_id uuid not null references public.channel_lines(id) on delete cascade,
 created_at timestamptz not null default now(), unique(match_id,channel_line_id)
);
create table if not exists public.nca_epg_auto_match_channels (
 match_id uuid not null references public.matches(id),channel_id uuid not null references public.channels(id) on delete cascade,
 programme_title text,programme_start timestamptz,guide_updated_at timestamptz,last_verified_at timestamptz,
 primary key(match_id,channel_id)
);
create table if not exists public.nca_bot_match_channels (
 match_id uuid not null references public.matches(id),channel_id uuid not null references public.channels(id) on delete cascade,
 source text not null,created_at timestamptz not null default now(),primary key(match_id,channel_id)
);
set local role service_role;
do $$
declare keeper uuid; alias_channel uuid; primary_line uuid; duplicate_line uuid; different_key uuid; different_header uuid;
 entry text:='db:p1:channel:7777777777777777777777777777'; config jsonb; result jsonb; attached uuid;
begin
 insert into public.channels(name,category,epg_id,epg_source) values('Verified station','Sports','Verified.us','US2') returning id into keeper;
 insert into public.channels(name,category) values('Alias station','Sports') returning id into alias_channel;
 insert into public.channel_lines(channel_id,label,stream_type,stream_url,key_id,key_data)
  values(keeper,'Original primary','dash','https://cdn.example.org/exact-full-set.mpd',repeat('c',32),repeat('d',32)) returning id into primary_line;
 insert into public.channel_lines(channel_id,label,stream_type,stream_url,key_id,key_data)
  values(alias_channel,'Duplicate','dash','https://cdn.example.org/exact-full-set.mpd',repeat('c',32),repeat('d',32)) returning id into duplicate_line;
 insert into public.channel_lines(channel_id,label,stream_type,stream_url,key_id,key_data)
  values(keeper,'Different key','dash','https://cdn.example.org/exact-full-set.mpd',repeat('c',32),repeat('f',32)) returning id into different_key;
 insert into public.channel_lines(channel_id,label,stream_type,stream_url,referer,key_id,key_data)
  values(keeper,'Different header','dash','https://cdn.example.org/exact-full-set.mpd','https://another.example/player',repeat('c',32),repeat('d',32)) returning id into different_header;
 update public.channel_lines set sort_order=1 where id=different_header;
 config:=jsonb_build_object('id','full-set-line','label','Source label','stream_type','dash','stream_url','https://cdn.example.org/exact-full-set.mpd','key_id',repeat('c',32),'key_data',repeat('d',32));
 insert into public.channel_source_catalog(id,provider,kind,name,category,source_file,streams,stream_count,revision)
  values(entry,1,'channel','Alias station','Sports','provider_1/channels.json',jsonb_build_array(config),1,'dedup-source');
 insert into public.channel_source_links(entry_id,channel_id,line_map)
  values(entry,alias_channel,jsonb_build_object('full-set-line',jsonb_build_object('line_id',duplicate_line,'shared',false)));
 insert into public.stream_links(match_id,channel_id,channel_line_id,stream_url)
  values('10000000-0000-0000-0000-000000000001',alias_channel,duplicate_line,'https://cdn.example.org/exact-full-set.mpd') returning id into attached;
 insert into public.nca_epg_auto_stream_links(stream_link_id,match_id,channel_line_id)
  values(attached,'10000000-0000-0000-0000-000000000001',duplicate_line);
 insert into public.nca_epg_auto_match_channels(match_id,channel_id,programme_title,programme_start,guide_updated_at,last_verified_at)
  values('10000000-0000-0000-0000-000000000001',alias_channel,'Verified fixture',now(),now(),now());
 insert into public.nca_bot_match_channels(match_id,channel_id,source)
  values('10000000-0000-0000-0000-000000000001',alias_channel,'manual');
 perform public.deduplicate_exact_channel_lines();
 if exists(select from public.channel_lines where id=duplicate_line) or exists(select from public.channels where id=alias_channel) then raise exception 'Exact duplicate remained'; end if;
 if not exists(select from public.channel_lines where id=different_key) then raise exception 'Different key configuration was removed'; end if;
 if exists(select from public.channel_lines where id=different_header) then raise exception 'A request header incorrectly prevented three-field MPD merging'; end if;
 if not exists(select from public.stream_links where id=attached and channel_line_id=primary_line and channel_id=keeper) then raise exception 'Match reference broke during deduplication'; end if;
 if not exists(select from public.nca_epg_auto_stream_links where stream_link_id=attached and channel_line_id=primary_line) or
  not exists(select from public.nca_epg_auto_match_channels where channel_id=keeper and programme_title='Verified fixture') or
  not exists(select from public.nca_bot_match_channels where channel_id=keeper and source='manual') then raise exception 'Guide or bot reference broke during deduplication'; end if;
 if not exists(select from public.channel_source_links where entry_id=entry and channel_id=keeper and not owns_channel and (line_map->'full-set-line'->>'shared')::boolean) then raise exception 'Following source reference lost'; end if;
 perform public.link_channel_source_entry(entry,null,true);
 if (select count(*) from public.channel_lines where channel_id=keeper)<>2 then raise exception 'Source refresh recreated the duplicate'; end if;
 update public.channel_source_catalog set streams=jsonb_build_array(config||jsonb_build_object('referer','https://rotated-header.example.org/')) where id=entry;
 perform public.link_channel_source_entry(entry,null,true);
 if (select count(*) from public.channel_lines where channel_id=keeper)<>2 then raise exception 'Header-only source refresh recreated a three-field duplicate'; end if;
 -- A new source selection with the same complete configuration reuses the
 -- saved channel and keeps its EPG/name instead of publishing another card.
 delete from public.channel_source_links where entry_id=entry;
 result:=public.link_channel_source_entry(entry);
 if (result->>'channel_id')::uuid<>keeper or not exists(select from public.channels where id=keeper and name='Verified station' and epg_id='Verified.us') then raise exception 'Source import duplicated or overwrote the saved channel'; end if;
end $$;
reset role;

set local role service_role;
do $$
declare entry text:='repo:match:9999999999999999999999999999'; target uuid; owned uuid; manual uuid;
 job uuid; same_job uuid; item record; current_item record; valid jsonb;
begin
 if public.channel_group_name('beIN SPORTS 2','Sports')<>'beIN Sports' or
  public.channel_group_name('UFC TV - AQ','Sports')<>'UFC' or
  public.channel_group_name('PBS Travel','Documentaries')<>'Travel' then raise exception 'Channel grouping wrong'; end if;
 if public.channel_group_name('FS 1 - AQ','Sports')<>'FOX Sports' or
  public.channel_group_name('ICC TV','Sports')<>'Cricket' or public.channel_group_name('Server 1','Sports')<>'Extra Servers' then raise exception 'Known brands or anonymous slots were grouped incorrectly'; end if;
 insert into public.channels(name,category) values('beIN Sports 99','Sports') returning id into target;
 if (select category from public.channels where id=target)<>'beIN Sports' then raise exception 'New channel was not grouped'; end if;
 update public.channels set category='My custom group',category_locked=true where id=target;
 update public.channels set name='beIN Sports 99 Updated',category='Sports' where id=target;
 if (select category from public.channels where id=target)<>'My custom group' then raise exception 'Source overwrote the operator group'; end if;
 insert into public.channel_source_catalog(id,source_id,provider,kind,name,category,source_file,streams,stream_count,revision,event_meta)
 values(entry,'repository',8,'event','Napoli vs Inter','Football','fixtures.json',
  '[{"id":"old-line","stream_url":"https://cdn.example.org/repo-test.mpd","stream_type":"dash","key_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","key_data":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]',1,'fixture',
  '{"home_team":"Napoli","away_team":"Inter"}');
 owned:=(public.add_connected_source_line_to_match(entry,'old-line','10000000-0000-0000-0000-000000000001')->>'stream_link_id')::uuid;
 insert into public.stream_links(match_id,stream_url) values('10000000-0000-0000-0000-000000000001','https://cdn.example.org/manual-safe.m3u8') returning id into manual;
 update public.channel_source_catalog set streams='[{"id":"rotated-line","stream_url":"https://cdn.example.org/repo-test.mpd","stream_type":"dash","key_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","key_data":"cccccccccccccccccccccccccccccccc"}]' where id=entry;
 perform public.reconcile_repository_match_links();perform public.sync_connected_source_match_lines('repository');
 if not exists(select from public.stream_links where id=owned and key_data=repeat('c',32)) then raise exception 'Repository key rotation lost the selected match line'; end if;
 update public.channel_source_catalog set is_present=false where id=entry;
 perform public.reconcile_repository_match_links();
 if exists(select from public.stream_links where id=owned) or not exists(select from public.stream_links where id=manual) then raise exception 'Source removal deleted a manual line or left its owned line'; end if;
 insert into public.channel_lines(channel_id,label,stream_url) values(target,'Health fixture','https://cdn.example.org/health-original.m3u8');
 job:=public.start_channel_health_job('all');same_job:=public.start_channel_health_job('all');
 if job<>same_job then raise exception 'Repeated Check All created concurrent jobs'; end if;
 update public.channel_health_jobs set status='paused' where id=job;
 if exists(select from public.claim_channel_health_items(32)) then raise exception 'Paused health job still claimed work'; end if;
 update public.channel_health_jobs set status='running' where id=job;
 valid:='{"health_status":"healthy","http_status":200,"latency_ms":20,"manifest_status":"valid","segment_status":"reachable","drm_status":"not_required","detail":"Test media bytes"}';
 for item in select * from public.claim_channel_health_items(32) loop
  if item.configuration->>'stream_url'='https://cdn.example.org/health-original.m3u8' then
   update public.channel_lines set stream_url='https://cdn.example.org/health-rotated.m3u8' where id=item.line_id;
   if public.finish_channel_health_item(item.item_id,item.config_hash,valid) then raise exception 'Stale health result applied to a changed source'; end if;
  else perform public.finish_channel_health_item(item.item_id,item.config_hash,valid); end if;
 end loop;
 for current_item in select * from public.claim_channel_health_items(32) loop
  perform public.finish_channel_health_item(current_item.item_id,current_item.config_hash,valid);
 end loop;
 if (select status from public.channel_health_jobs where id=job)<>'completed' then raise exception 'Health queue did not finish'; end if;
 if has_function_privilege('anon','public.start_channel_health_job(text)','execute') or
  has_function_privilege('authenticated','public.claim_channel_health_items(integer)','execute') then raise exception 'Unverified health mutation exposed'; end if;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000002',true);
do $$ begin
 if exists(select from public.channel_health_jobs) or exists(select from public.channel_health_job_items) then raise exception 'Viewer can read Admin health jobs'; end if;
end $$;
reset role;
-- URL + key ID + key data identity ignores headers, names and multi-line aliases.
set local role service_role;
do $$
declare verified uuid; alias uuid; keep_line uuid; duplicate uuid; other_line uuid; payload jsonb;
 entry text:='repo:match:'||repeat('d',28);
begin
 insert into public.channels(name,category,epg_id,epg_source) values('Verified EPG station','Football','verified.us','US2') returning id into verified;
 insert into public.channels(name,category) values('Completely different name','Football') returning id into alias;
 insert into public.channel_lines(channel_id,label,stream_url,stream_type,key_id,key_data,referer)
  values(verified,'Verified','https://cdn.example.org/three-fields.mpd','dash',repeat('a',32),repeat('b',32),'https://one.example.org/') returning id into keep_line;
 insert into public.channel_lines(channel_id,label,stream_url,stream_type,key_id,key_data,referer)
  values(alias,'Other header','https://cdn.example.org/three-fields.mpd','dash',repeat('a',32),repeat('b',32),'https://two.example.org/') returning id into duplicate;
 insert into public.channel_lines(channel_id,label,stream_url,stream_type,key_id,key_data)
  values(alias,'Independent line','https://cdn.example.org/independent.mpd','dash',repeat('c',32),repeat('d',32)) returning id into other_line;
 perform public.deduplicate_exact_channel_lines();
 if exists(select from public.channel_lines where id=duplicate) or not exists(select from public.channel_lines where id=keep_line)
  or not exists(select from public.channel_lines where id=other_line) then raise exception 'Three-field merging lost the verified EPG or an independent alias line'; end if;
 insert into public.channel_source_catalog(id,provider,kind,name,category,source_file,streams,stream_count,revision,source_id,event_meta)
 values(entry,8,'event','Independent repository fixture','Football','fixture.json',jsonb_build_array(jsonb_build_object(
  'id','private-line','label','HD','stream_url','https://private-repository.example.org/stream.mpd','stream_type','dash',
  'key_id',repeat('a',32),'key_data',repeat('b',32),'referer','https://private-origin.example.org/','configuration_status','configured')),1,'fixture','repository',
  jsonb_build_object('home_team','Napoli','away_team','Lazio','league','Serie A','kickoff_at',now()));
 -- The repository fixture is not published to the main Live match table.
 payload:=public.get_repository_metadata_for_gateway(null,'local-test-gateway');
 if payload->'matches' is null or not exists(select from jsonb_array_elements(payload->'matches') m where m->>'source_id'=entry) then raise exception 'Live 2 depended on an NCA Live match'; end if;
 if payload::text like '%private-repository%' or payload::text like '%key_data%' or payload::text like '%private-origin%' then raise exception 'Repository listing leaked a native configuration'; end if;
 payload:=public.get_repository_metadata_for_gateway(entry,'local-test-gateway');
 if payload->>'match_valid'<>'true' or payload->'streams'->0->>'key_id'<>repeat('a',32) then raise exception 'Trusted gateway lost the configured key pair'; end if;
 update public.channel_source_catalog set is_present=false where id=entry;
 if public.get_repository_metadata_for_gateway(entry,'local-test-gateway')->>'match_valid'<>'false' then raise exception 'Live 2 revived a removed repository fixture'; end if;
end $$;
reset role;
set local role anon;
do $$ begin
 begin perform public.get_repository_metadata_for_gateway(null,'wrong-secret');raise exception 'Public repository metadata bypassed gateway authentication';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'Database security and compatibility checks passed' as result;
rollback;
