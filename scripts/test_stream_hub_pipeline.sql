begin;
do $$begin if current_database()<>'nca_security_test' then raise exception 'Disposable database required';end if;end $$;
update public.channel_source_state set lease_id='59000000-0000-0000-0000-000000000001',revision='before',last_success_at='2026-11-20T00:00:00Z' where id='darkbyte';
insert into public.channel_source_catalog(id,source_id,provider,kind,name,category,source_file,streams,revision,event_meta)
 values('hub-frozen','darkbyte',14,'channel','Frozen source','Sports','finall','[]','before','{"source_repository":"rohmanabdu/lian"}'),
 ('hub-removed','darkbyte',9,'channel','Observed removal','Sports','output/channels.json','[]','before','{"source_repository":"nehalmahamuddev/SM-IPTV-Category-Playlists-Auto-Sync"}');
insert into public.matches(id,league,home_team,away_team,kickoff_at) values('59000000-0000-0000-0000-000000000002','Manual','Manual A','Manual B',now());
insert into public.stream_links(match_id,label,stream_url) values('59000000-0000-0000-0000-000000000002','Operator line','https://manual.example.org/keep.m3u8');
set local role service_role;
do $$declare result jsonb;begin
 result:=public.commit_stream_hub_snapshot('59000000-0000-0000-0000-000000000001','after',
  '[{"id":"hub-frozen","provider":14,"kind":"channel","name":"Frozen source","category":"Sports","source_file":"finall","streams":[],"unsupported_count":0,"event_meta":{"source_repository":"rohmanabdu/lian"}},
    {"id":"hub-new","provider":9,"kind":"channel","name":"New source","category":"Sports","source_file":"output/channels.json","streams":[],"unsupported_count":0,"event_meta":{"source_repository":"nehalmahamuddev/SM-IPTV-Category-Playlists-Auto-Sync"}}]',
  '["rohmanabdu/lian"]');
 if result->>'partial'<>'true' then raise exception 'Unavailable origin was marked fully successful';end if;
 if not exists(select from public.channel_source_catalog where id='hub-frozen' and is_present) or
  exists(select from public.channel_source_catalog where id='hub-removed' and is_present) then raise exception 'Frozen/observed source reconciliation failed';end if;
 if not exists(select from public.channel_source_state where id='darkbyte' and status='partial' and catalog_schema_version=3 and last_success_at='2026-11-20T00:00:00Z'::timestamptz) then raise exception 'Partial snapshot changed last full success';end if;
 if not exists(select from public.stream_links where stream_url='https://manual.example.org/keep.m3u8') then raise exception 'Manual line changed during source sync';end if;
end $$;
reset role;
insert into private.gateway_secrets(name,secret_hash) values('cloudflare_playback',encode(extensions.digest('hub-parity-fixture','sha256'),'hex'))
 on conflict(name) do update set secret_hash=excluded.secret_hash;
insert into public.channel_source_catalog(id,source_id,provider,kind,name,category,source_file,streams,revision,event_meta)
 values('repo:match:'||repeat('f',28),'repository',8,'event','Present metadata only','Football','Hub projection','[]','test',
 jsonb_build_object('home_team','Present Home','away_team','Present Away','kickoff_at',now()-interval '8 hours'));
set local role anon;
do $$declare data jsonb;begin
 data:=public.get_repository_metadata_for_gateway(null,'hub-parity-fixture');
 if not exists(select from jsonb_array_elements(data->'matches') m where m->>'source_id'='repo:match:'||repeat('f',28) and m->>'stream_count'='0' and m->'anchors'='[]'::jsonb) then raise exception 'Live 2 differed from present Admin catalogue or advertised empty match playable';end if;
 if data::text like '%key_data%' or data::text like '%stream_url%' then raise exception 'Metadata leaked line configuration';end if;
end $$;
reset role;
insert into public.channel_source_catalog(id,source_id,provider,kind,name,category,source_file,streams,revision,event_meta)
select id,'repository',8,'event',id,'Football','Hub projection','[]','test',
 jsonb_build_object('fixture_key',fixture,'home_team','Test Home','away_team','Test Away',
 'kickoff_at','2026-11-19T19:00:00Z','source_finished',finished,'finished_at',end_at)
from (values ('old-finished','finished-key',true,'2026-11-19T21:00:00Z'),
 ('protected-finished','protected-key',true,'2026-11-19T21:00:00Z'),
 ('unknown-result','unknown-key',false,null),
 ('just-finished','just-finished-key',true,null)) v(id,fixture,finished,end_at);
insert into public.repository_match_imports(entry_id,match_id)
 values('protected-finished','59000000-0000-0000-0000-000000000002');
insert into public.channel_source_catalog(id,source_id,provider,kind,name,category,source_file,streams,revision,event_meta)
 values('finished-civil-only','repository',8,'event','Finished civil only','Football','Hub projection','[]','test',
 '{"fixture_key":"finished-civil-only","source_finished":true,"finished_source_date":"2026-08-28"}');
do $$ begin
 if not exists(select from public.repository_fixture_retention where entry_id='finished-civil-only'
  and finished_at>now()-interval '1 minute' and expired_at is null) then
  raise exception 'First observation must start the clock without a confirmed UTC end';
 end if;
end $$;
set local role anon;
do $$declare data jsonb;begin
 data:=public.get_repository_catalog_page_for_gateway('2026-11-20',0,1,'hub-parity-fixture');
 if jsonb_array_length(data->'matches')<>1 or data->>'next_offset'<>'1' or
    data->'matches'->0->>'source_id'<>'just-finished' then raise exception 'Live 2 Yangon page order/cursor: %', data; end if;
 if data::text like '%key_data%' or data::text like '%stream_url%' then raise exception 'Page leaked metadata';end if;
 data:=public.get_repository_metadata_for_gateway(null,'hub-parity-fixture');
 if exists(select from jsonb_array_elements(data->'matches') m
   where m->>'source_id' in ('unknown-result','old-finished','protected-finished')) then
   raise exception 'Stale fixtures remained in the legacy Viewer list';
 end if;
 if not exists(select from jsonb_array_elements(data->'matches') m
   where m->>'source_id'='finished-civil-only') then raise exception 'Newly confirmed finish disappeared';end if;
 if has_table_privilege('public.repository_current_catalog','select') then
   raise exception 'Viewer can query the raw browse view';
 end if;
 begin
  perform public.prune_finished_repository_fixtures(false);
  raise exception 'Viewer could execute prune';
 exception when insufficient_privilege then null;
 end;
end $$;
reset role;
set local role service_role;
do $$declare preview jsonb; removed jsonb;begin
 if exists(select from public.repository_current_catalog
   where id in ('unknown-result','old-finished','protected-finished'))
   or not exists(select from public.channel_source_catalog where id='unknown-result' and is_present)
   or not exists(select from public.repository_current_catalog where id='finished-civil-only') then
  raise exception 'Admin browse filtering mutated a source row or showed a stale fixture';
 end if;
 preview:=public.prune_finished_repository_fixtures();
 if preview->'entry_ids' <> '["old-finished"]'::jsonb
    or not exists(select from public.channel_source_catalog where id='old-finished') then
  raise exception 'Unexpected dry run: %', preview;
 end if;
 removed:=public.prune_finished_repository_fixtures(false);
 if removed->>'count'<>'1' or exists(select from public.channel_source_catalog where id='old-finished')
    or (select count(*) from public.channel_source_catalog where id in ('just-finished','protected-finished','unknown-result'))<>3
    or not exists(select from public.stream_links where stream_url='https://manual.example.org/keep.m3u8') then
  raise exception 'Cleanup did not preserve unrelated or imported records: %',removed;
 end if;
 insert into public.channel_source_catalog(id,source_id,provider,kind,name,category,source_file,streams,revision,event_meta)
  values('reissued-id','repository',8,'event','Reissued','Football','Hub projection','[]','test','{"fixture_key":"finished-key"}');
 if exists(select from public.channel_source_catalog where id='reissued-id') then
  raise exception 'Expired fixture reappeared with a new ID';
 end if;
end $$;
rollback;
