begin;
do $$begin if current_database()<>'nca_security_test' then raise exception 'Disposable database required';end if;end $$;
insert into auth.users(id) values('65000000-0000-0000-0000-000000000001');
insert into public.profiles(id,role) values('65000000-0000-0000-0000-000000000001','admin');
insert into public.channel_source_catalog(id,provider,kind,name,category,source_file,source_id,revision,streams,event_meta)
 values('hl-test-combat',13,'event','Test One vs Test Two','UFC','test.json','darkbyte','test',
 '[{"id":"combat-hls","stream_url":"https://example.org/video.m3u8","stream_type":"hls"}]',
 '{"home_team":"Test One","away_team":"Test Two","league":"UFC","home_logo_url":"https://example.org/home.png","kickoff_at":"2026-11-22T17:00:00Z"}');
set local role authenticated;
select set_config('request.jwt.claim.sub','65000000-0000-0000-0000-000000000001',true);
do $$
declare
  first jsonb;
  retry jsonb;
  fixture_id uuid;
begin
  first := public.publish_combat_match('combat:'||repeat('c',28), array['hl-test-combat'], null);
  retry := public.publish_combat_match('combat:'||repeat('c',28), array['hl-test-combat'], null);
  fixture_id := (first->>'match_id')::uuid;
  if fixture_id is null or first->>'line_count'<>'1' or first->>'match_id'<>retry->>'match_id'
     or (select count(*) from public.stream_links where match_id=fixture_id)<>1 then
    raise exception 'Combat fixture, lines or retry failed';
  end if;
  update public.matches set home_score=3,away_score=1,is_finished=true where id=fixture_id;
  perform public.move_live_match_to_highlights(fixture_id);
  perform public.move_live_match_to_highlights(fixture_id);
  if exists(select from public.matches where id=fixture_id)
     or exists(select from public.stream_links where match_id=fixture_id)
     or not exists(select from public.highlight_matches where id=fixture_id and home_score=3
          and away_score=1 and is_finished and home_logo_url='https://example.org/home.png') then
    raise exception 'Archive did not preserve metadata or remove Live lines';
  end if;
  insert into public.highlights(match_id,title,video_url) values(fixture_id,'Saved highlight','https://example.org/hl.mp4');
end $$;
reset role;
set local role anon;
do $$begin
 if not exists(select from public.viewer_highlight_matches(0) m
   where m->>'home_team'='Test One' and m->>'home_score'='3'
     and m->'lines'->0->>'stream_url'='https://example.org/hl.mp4') then
   raise exception 'Viewer did not receive archived metadata and saved highlight';
 end if;
 if has_function_privilege(current_user,'public.move_live_match_to_highlights(uuid)','execute')
    or has_function_privilege(current_user,'public.publish_combat_match(text,text[],timestamptz)','execute') then
   raise exception 'Anonymous write RPC';
 end if;
end $$;
rollback;
