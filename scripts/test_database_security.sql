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
end $$;

select set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000001',true);
do $$ declare result jsonb; before_count int; begin
  if not public.is_admin() or (select count(*) from public.profiles) <> 2 or
     (select count(*) from public.matches) <> 5 or
     (select count(*) from public.highlights) <> 2 then
    raise exception 'Admin read privileges changed';
  end if;
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
select 'Database security and compatibility checks passed' as result;
rollback;
