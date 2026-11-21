begin;
insert into auth.users(id) values('33000000-0000-0000-0000-000000000001'),('33000000-0000-0000-0000-000000000002');
insert into public.profiles(id,role) values('33000000-0000-0000-0000-000000000001','admin'),('33000000-0000-0000-0000-000000000002','viewer');
insert into public.matches(id,league,home_team,away_team,kickoff_at,is_active,is_featured,publish_state,external_fixture_id)
 values('34000000-0000-0000-0000-000000000001','Fixture League','Home','Away',now(),true,true,'published',987654321);
set local role authenticated;
select set_config('request.jwt.claim.sub','33000000-0000-0000-0000-000000000001',true);
do $$
declare m uuid:='34000000-0000-0000-0000-000000000001';req uuid:='35000000-0000-0000-0000-000000000001'; result jsonb; id uuid;
 lines jsonb:='[{"label":"HD","source_line_id":"hd","stream_type":"hls","url":"https://cdn.example/a.m3u8","referer":"https://player.example/","resolution":"1080p"}]';
begin
 result:=public.import_match_source_lines(m,lines,'soco','{"room_num":"123","cookies":"must-not-retain"}',req);
 id:=(result->'lines'->0->>'id')::uuid;
 if result is distinct from public.import_match_source_lines(m,lines,'soco','{"room_num":"123","cookies":"must-not-retain"}',req) then raise exception 'Retry changed result'; end if;
 if (select count(*) from public.stream_links where match_id=m)<>1 then raise exception 'Retry duplicated'; end if;
 if exists(select from public.imported_source_lines where room?'cookies') then raise exception 'Cookie stored'; end if;
 perform public.import_match_source_lines(m,lines||'[{"label":"bad","url":"javascript:alert(1)"}]','soco','{}',gen_random_uuid());
 raise exception 'Invalid batch accepted';
exception when raise_exception then
 if sqlerrm<>'Invalid direct stream URL' then raise; end if;
end $$;
-- Previous DO is an exception subtransaction: repeat outside it, then verify rollback.
do $$
declare m uuid:='34000000-0000-0000-0000-000000000001';result jsonb;line uuid;before_count int;
 lines jsonb:='[{"label":"HD","source_line_id":"hd","stream_type":"hls","url":"https://cdn.example/a.m3u8","referer":"https://player.example/","resolution":"1080p"}]';
begin
 result:=public.import_match_source_lines(m,lines,'soco','{"room_num":"123"}',gen_random_uuid());line:=(result->'lines'->0->>'id')::uuid;
 perform public.import_match_source_lines(m,lines,'soco','{"room_num":"123"}',gen_random_uuid());
 if (select count(*) from public.stream_links where match_id=m)<>1 then raise exception 'Config duplicate'; end if;
 lines:=jsonb_set(lines,'{0,url}','"https://cdn.example/renewed.m3u8"');
 result:=public.import_match_source_lines(m,lines,'soco','{"room_num":"123"}',gen_random_uuid());
 if (result->'lines'->0->>'id')::uuid<>line then raise exception 'Renewal inserted row'; end if;
 lines:=jsonb_set(lines,'{0,referer}','"https://another.example/"');
 perform public.import_match_source_lines(m,lines,'soco','{"room_num":"123"}',gen_random_uuid());
 if (select count(*) from public.stream_links where match_id=m)<>2 then raise exception 'Different headers collapsed'; end if;
 before_count:=(select count(*) from public.stream_links where match_id=m);
 begin
  perform public.import_match_source_lines(m,'[{"label":"SD","url":"https://cdn.example/sd.m3u8","stream_type":"hls"},{"url":"bad"}]','soco','{}',gen_random_uuid());
  raise exception 'Bad batch saved';
 exception when raise_exception then if sqlerrm<>'Invalid direct stream URL' then raise; end if; end;
 if (select count(*) from public.stream_links where match_id=m)<>before_count then raise exception 'Batch partial commit'; end if;
 update public.stream_links set health_status='healthy',last_checked_at=now(),health_latency_ms=15 where id=line;
 update public.stream_links set label='Renamed only' where id=line;
 if not exists(select from public.stream_links where id=line and health_status='healthy' and last_checked_at is not null) then raise exception 'Label-only edit invalidated valid health'; end if;
 update public.stream_links set stream_url='https://manual.example/changed.m3u8' where id=line;
 if not exists(select from public.stream_links where id=line and health_status='unknown' and last_checked_at is null and health_latency_ms is null) then raise exception 'Changed playback kept stale health'; end if;
 if exists(select from public.imported_source_lines where link_id=line) then raise exception 'Manual edits retain renewal provenance'; end if;
end $$;
select set_config('request.jwt.claim.sub','33000000-0000-0000-0000-000000000002',true);
do $$ begin
 begin
 perform public.import_match_source_lines('34000000-0000-0000-0000-000000000001','[]','soco','{}',gen_random_uuid());raise exception 'Viewer import allowed';
 exception when insufficient_privilege then null;end;
 if exists(select from public.imported_source_lines) then raise exception 'Viewer can read provenance'; end if;
end $$;
reset role;
-- Secret-gated refresh leases cannot be replayed and never recreate deleted rows.
insert into private.gateway_secrets(name,secret_hash) values('cloudflare_playback',encode(extensions.digest('fixture-refresh-secret','sha256'),'hex'))
 on conflict(name) do update set secret_hash=excluded.secret_hash;
do $$
declare r public.imported_source_lines;lease jsonb;ok boolean;
begin
 select * into strict r from public.imported_source_lines where match_id='34000000-0000-0000-0000-000000000001';
 begin perform public.claim_imported_source_refresh(r.link_id,r.config_hash,'wrong');raise exception 'Bad secret accepted';exception when insufficient_privilege then null;end;
 lease:=public.claim_imported_source_refresh(r.link_id,r.config_hash,'fixture-refresh-secret');
 if lease->>'refresh_lease' is null then raise exception 'Lease not granted';end if;
 if public.claim_imported_source_refresh(r.link_id,r.config_hash,'fixture-refresh-secret') is not null then raise exception 'Duplicate lease granted';end if;
 ok:=public.apply_imported_source_refresh(r.link_id,r.config_hash,(lease->>'refresh_lease')::uuid,'{"url":"https://cdn.example/fresh.m3u8","stream_type":"hls"}','fixture-refresh-secret');
 if not ok then raise exception 'Lease apply failed';end if;
 if public.apply_imported_source_refresh(r.link_id,r.config_hash,(lease->>'refresh_lease')::uuid,'{"url":"https://cdn.example/replayed.m3u8","stream_type":"hls"}','fixture-refresh-secret') then raise exception 'Lease replay applied';end if;
 delete from public.stream_links where id=r.link_id;
 if public.apply_imported_source_refresh(r.link_id,r.config_hash,(lease->>'refresh_lease')::uuid,'{"url":"https://cdn.example/resurrect.m3u8","stream_type":"hls"}','fixture-refresh-secret') then raise exception 'Deleted line refreshed';end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','33000000-0000-0000-0000-000000000001',true);
select public.permanently_delete_match('34000000-0000-0000-0000-000000000001');
reset role;
do $$ begin
 if exists(select from public.matches where id='34000000-0000-0000-0000-000000000001') or exists(select from public.stream_links where match_id='34000000-0000-0000-0000-000000000001') or exists(select from public.imported_source_lines where match_id='34000000-0000-0000-0000-000000000001') then raise exception 'Delete left content';end if;
 begin
 insert into public.matches(league,home_team,away_team,kickoff_at,external_fixture_id) values('Again','Home','Away',now(),987654321);raise exception 'Deleted fixture resurrected';
 exception when raise_exception then if sqlerrm<>'This fixture was permanently deleted' then raise;end if;end;
end $$;
select 'Source import, renewal and permanent deletion checks passed' as result;
rollback;
