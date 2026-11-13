-- Disposable database only: no production fixture is imported by this test.
begin;
do $$ begin
 if current_database()<>'nca_security_test' then raise exception 'Disposable database required';end if;
end $$;
insert into auth.users(id) values('29000000-0000-0000-0000-000000000001'),('29000000-0000-0000-0000-000000000002');
insert into public.profiles(id,role) values('29000000-0000-0000-0000-000000000001','admin'),('29000000-0000-0000-0000-000000000002','viewer');
insert into public.matches(id,league,home_team,away_team,kickoff_at,home_logo_url,external_fixture_id,source)
 values('19000000-0000-0000-0000-000000000001','Premier League','Manchester United','Aston Villa','2026-11-20T17:00:00Z','https://operator.example.org/home.png',19001,'api_football');
insert into public.channel_source_catalog(id,provider,kind,name,category,source_file,source_id,revision,streams,event_meta,stream_count)
 values('repo:match:'||repeat('a',28),8,'event','Man Utd vs Aston Villa','Football','fixtures.json','repository','test',
 jsonb_build_array(
  jsonb_build_object('id','hls','label','HLS HD','stream_type','hls','stream_url','https://cdn.example.org/one.m3u8','referer','https://player.example.org/embed','origin','https://player.example.org'),
  jsonb_build_object('id','dash','label','DASH HD','stream_type','dash','stream_url','https://cdn.example.org/one.mpd?token=one','key_id',repeat('a',32),'key_data',repeat('b',32),'drm_type','clearkey','configuration_status','configured'),
  jsonb_build_object('id','duplicate','label','Different name','stream_type','dash','stream_url','https://cdn.example.org/one.mpd?token=two','key_id',repeat('a',32),'key_data',repeat('b',32),'referer','https://different.example.org/'),
  jsonb_build_object('id','needs-key','stream_type','dash','stream_url','https://cdn.example.org/protected.mpd','configuration_status','requires_drm')),
 jsonb_build_object('home_team','Man Utd','away_team','Aston Villa','league','Premier League','kickoff_at','2026-11-20T17:00:00Z',
 'home_logo_url','https://logos.example.org/home.png','away_logo_url','https://img.sofascore.com/api/v1/team/600/image'),4);
insert into public.channel_source_catalog(id,provider,kind,name,category,source_file,source_id,revision,streams,event_meta,stream_count)
 select 'repo:match:'||repeat('b',28),provider,kind,'Singapore vs Paraguay',category,source_file,source_id,revision,
 streams - 1 - 1,event_meta||'{"home_team":"Singapore","away_team":"Paraguay","league":"International Friendly Games"}',2
 from public.channel_source_catalog where id='repo:match:'||repeat('a',28);
insert into public.channel_source_catalog(id,provider,kind,name,category,source_file,source_id,revision,streams,event_meta,stream_count)
 select 'repo:match:'||repeat('c',28),provider,kind,'Unknown kickoff',category,source_file,source_id,revision,
 streams,(event_meta-'kickoff_at')||'{"home_team":"Comoros","away_team":"Congo Republic"}',2
 from public.channel_source_catalog where id='repo:match:'||repeat('b',28);
insert into public.channel_source_catalog(id,provider,kind,name,category,source_file,source_id,revision,streams,event_meta,stream_count)
 select 'repo:match:'||repeat('d',28),provider,kind,'No playable configuration',category,source_file,source_id,revision,
 jsonb_build_array(jsonb_build_object('id','protected','stream_type','dash','stream_url','https://cdn.example.org/private.mpd','configuration_status','requires_drm')),
 event_meta||'{"home_team":"Test D","away_team":"Test E"}',1
 from public.channel_source_catalog where id='repo:match:'||repeat('b',28);

set local role authenticated;
select set_config('request.jwt.claim.sub','29000000-0000-0000-0000-000000000002',true);
do $$ begin
 begin perform public.publish_repository_match('repo:match:'||repeat('a',28));raise exception 'Viewer published a match';
 exception when insufficient_privilege then null;end;
 if exists(select from public.repository_match_imports) then raise exception 'Viewer saw private import mapping';end if;
 if has_function_privilege('anon','public.publish_repository_match(text,timestamptz)','execute') then raise exception 'Anon publish allowed';end if;
end $$;
select set_config('request.jwt.claim.sub','29000000-0000-0000-0000-000000000001',true);
do $$
declare r jsonb; mid uuid; before_count integer;
begin
 select count(*) into before_count from public.matches;
 r:=public.publish_repository_match('repo:match:'||repeat('a',28));
 if r->>'ok'<>'true' or r->>'created'<>'false' or r->>'added_lines'<>'2' or r->>'existing_lines'<>'1' or r->>'skipped_lines'<>'1' then raise exception 'Full existing import failed: %',r;end if;
 if (r->>'match_id')::uuid<>'19000000-0000-0000-0000-000000000001'::uuid or (select count(*) from public.matches)<>before_count then raise exception 'Existing Pick Big Match duplicated';end if;
 if not exists(select from public.matches where id=(r->>'match_id')::uuid and home_team='Manchester United' and source='api_football' and external_fixture_id=19001 and home_logo_url='https://operator.example.org/home.png' and away_logo_url='https://nca-network-backup-test.vercel.app/team-logos/600') then raise exception 'Operator edits/fixture identity/badge lost';end if;
 if not exists(select from public.stream_links where match_id=(r->>'match_id')::uuid and referer='https://player.example.org/embed' and origin='https://player.example.org') or not exists(select from public.stream_links where match_id=(r->>'match_id')::uuid and key_id=repeat('a',32) and key_data=repeat('b',32) and health_status='unknown') then raise exception 'Full line configuration lost';end if;
 r:=public.publish_repository_match('repo:match:'||repeat('b',28));mid:=(r->>'match_id')::uuid;
 if r->>'created'<>'true' or r->>'added_lines'<>'1' or r->>'skipped_lines'<>'1' then raise exception 'New fixture import failed: %',r;end if;
 if not exists(select from public.matches where id=mid and home_team='Singapore' and away_team='Paraguay' and home_logo_url='https://logos.example.org/home.png' and source='repository' and is_active and is_featured and publish_state='published' and kickoff_at='2026-11-20T17:00:00Z'::timestamptz) then raise exception 'Live metadata/publication missing';end if;
 r:=public.publish_repository_match('repo:match:'||repeat('b',28));
 if (r->>'match_id')::uuid<>mid or r->>'added_lines'<>'0' or r->>'changed'<>'false' then raise exception 'Repeated publish duplicated or changed match: %',r;end if;
 r:=public.publish_repository_match('repo:match:'||repeat('c',28));
 if r->>'code'<>'kickoff_required' or exists(select from public.matches where home_team='Comoros') then raise exception 'Invented kickoff';end if;
 r:=public.publish_repository_match('repo:match:'||repeat('c',28),'2026-11-21T19:00:00+06:30');
 if r->>'created'<>'true' or not exists(select from public.matches where id=(r->>'match_id')::uuid and kickoff_at='2026-11-21T12:30:00Z'::timestamptz) then raise exception 'Explicit MMT kickoff lost';end if;
 r:=public.publish_repository_match('repo:match:'||repeat('d',28));
 if r->>'code'<>'no_importable_lines' or exists(select from public.matches where home_team='Test D') then raise exception 'Missing DRM published an empty match';end if;
 -- Simulate the existing Controls soft-delete operation.
 update public.matches set deleted_at=now(),is_active=false,is_featured=false,publish_state='draft' where id=mid;
 r:=public.publish_repository_match('repo:match:'||repeat('b',28));
 if r->>'code'<>'previously_deleted' or exists(select from public.matches where id=mid and is_active) then raise exception 'Deleted match revived';end if;
end $$;
reset role;
-- A failure on a later line must roll back the entire fixture and provenance.
create function public.test_fail_repository_line() returns trigger language plpgsql as $$
begin if new.label like '%explode%' then raise check_violation using message='test line failure';end if;return new;end $$;
create trigger test_repository_rollback before insert on public.stream_links for each row execute function public.test_fail_repository_line();
insert into public.channel_source_catalog(id,provider,kind,name,category,source_file,source_id,revision,streams,event_meta,stream_count)
 select 'repo:match:'||repeat('e',28),provider,kind,'Atomic fixture',category,source_file,source_id,revision,
 jsonb_build_array(jsonb_build_object('id','first','label','first','stream_type','hls','stream_url','https://cdn.example.org/first.m3u8'),
 jsonb_build_object('id','second','label','explode','stream_type','hls','stream_url','https://cdn.example.org/second.m3u8')),
 event_meta||'{"home_team":"Atomic Home","away_team":"Atomic Away"}',2
 from public.channel_source_catalog where id='repo:match:'||repeat('b',28);
set local role authenticated;
select set_config('request.jwt.claim.sub','29000000-0000-0000-0000-000000000001',true);
do $$ begin
 begin perform public.publish_repository_match('repo:match:'||repeat('e',28));raise exception 'Rollback test did not fail';
 exception when check_violation then null;end;
 if exists(select from public.matches where home_team='Atomic Home') or exists(select from public.repository_match_imports where entry_id='repo:match:'||repeat('e',28)) then raise exception 'Partial fixture saved';end if;
end $$;
reset role;
select 'Repository full-match publish checks passed' as result;
rollback;
