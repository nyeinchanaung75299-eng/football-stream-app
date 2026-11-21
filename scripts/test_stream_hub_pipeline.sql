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
rollback;
