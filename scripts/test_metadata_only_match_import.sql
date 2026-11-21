begin;
do $$begin if current_database()<>'nca_security_test' then raise exception 'Disposable database required';end if;end $$;
insert into auth.users(id) values('48000000-0000-0000-0000-000000000001');
insert into public.profiles(id,role) values('48000000-0000-0000-0000-000000000001','admin');
insert into public.channel_source_catalog(id,provider,kind,name,category,source_file,source_id,revision,streams,event_meta)
 values('repo:match:'||repeat('e',28),8,'event','Metadata Home vs Metadata Away','Football','fixture.json','repository','test','[]',
 '{"home_team":"Metadata Home","away_team":"Metadata Away","league":"Football","kickoff_at":"2026-11-22T17:00:00Z"}');
set local role authenticated;
select set_config('request.jwt.claim.sub','48000000-0000-0000-0000-000000000001',true);
do $$declare first jsonb;again jsonb;begin
 first:=public.publish_repository_match('repo:match:'||repeat('e',28));
 again:=public.publish_repository_match('repo:match:'||repeat('e',28));
 if first->>'ok'<>'true' or again->>'created'<>'false' or first->>'match_id'<>again->>'match_id' then raise exception 'Empty fixture import not idempotent';end if;
 if exists(select from public.stream_links where match_id=(first->>'match_id')::uuid) then raise exception 'Empty fixture has fabricated lines';end if;
end $$;
reset role;
update public.channel_source_catalog set streams='[{"id":"later-line","label":"Later HLS","stream_type":"hls","stream_url":"https://metadata.example.org/later.m3u8"}]'
 where id='repo:match:'||repeat('e',28);
set local role authenticated;
do $$declare r jsonb;mid uuid;begin
 r:=public.publish_repository_match('repo:match:'||repeat('e',28));mid:=(r->>'match_id')::uuid;
 if r->>'added_lines'<>'1' or r->>'created'<>'false' then raise exception 'Later line was not added to original match';end if;
 r:=public.publish_repository_match('repo:match:'||repeat('e',28));
 if r->>'added_lines'<>'0' or (select count(*) from public.stream_links where match_id=mid)<>1 then raise exception 'Later line duplicated';end if;
 perform public.permanently_delete_match(mid);
 r:=public.publish_repository_match('repo:match:'||repeat('e',28));
 if r->>'created'<>'true' or (r->>'match_id')::uuid=mid then raise exception 'Permanently deleted fixture cannot be reimported';end if;
 if (select count(*) from public.matches where home_team='Metadata Home')<>1 then raise exception 'Reimport duplicated fixture';end if;
end $$;
rollback;
