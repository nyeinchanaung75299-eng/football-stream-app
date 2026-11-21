begin;
insert into auth.users(id) values('30000000-0000-0000-0000-000000000001'),('30000000-0000-0000-0000-000000000002');
insert into public.profiles(id,role) values('30000000-0000-0000-0000-000000000001','admin'),('30000000-0000-0000-0000-000000000002','viewer');
insert into public.channels(id,name,category) values('31000000-0000-0000-0000-000000000001','Before','Sports');
insert into public.channel_lines(id,channel_id,label,stream_url,referer,origin,is_active,health_status,health_http_status)
 values('32000000-0000-0000-0000-000000000001','31000000-0000-0000-0000-000000000001','Existing','https://example.org/old.m3u8','https://embed.example/watch','https://origin.example',false,'failed',403);
set local role authenticated;
select set_config('request.jwt.claim.sub','30000000-0000-0000-0000-000000000001',true);
do $$
declare channel uuid:='31000000-0000-0000-0000-000000000001'; line uuid:='32000000-0000-0000-0000-000000000001';
 fields jsonb:='{"name":"After","category":"Sports","image_url":"https://example.org/logo.png","is_active":true}';
begin
 perform public.save_channel_editor(channel,fields,jsonb_build_array(jsonb_build_object('id',line)));
 if not exists(select from public.channel_lines where id=line and not is_active and health_status='failed' and health_http_status=403 and origin='https://origin.example') then
  raise exception 'Metadata-only save changed disabled state, health or Origin'; end if;
 begin
  perform public.save_channel_editor(channel,fields||'{"name":"Must roll back"}',jsonb_build_array(
   jsonb_build_object('id',line,'label','Must roll back'),jsonb_build_object('label','Invalid','stream_url','bad-url')));
  raise exception 'Invalid line unexpectedly saved';
 exception when check_violation then null; end;
 if not exists(select from public.channels where id=channel and name='After') or
    not exists(select from public.channel_lines where id=line and label='Existing') then
  raise exception 'Failed second line left partial updates'; end if;
 -- A deleted line must reject the edit, never be recreated.
 begin
  perform public.save_channel_editor(channel,fields||'{"name":"Stale edit"}',
   jsonb_build_array(jsonb_build_object('id','32000000-0000-0000-0000-000000000099')));
  raise exception 'Missing line unexpectedly recreated';
 exception when raise_exception then
  if sqlerrm='Missing line unexpectedly recreated' then raise; end if; end;
 if not exists(select from public.channels where id=channel and name='After') then raise exception 'Missing line left metadata updates'; end if;
 perform public.save_channel_editor(channel,fields,jsonb_build_array(jsonb_build_object('id',line,'stream_url','https://example.org/new.m3u8')));
 if not exists(select from public.channel_lines where id=line and not is_active and health_status='unknown' and health_http_status is null and origin='https://origin.example') then raise exception 'Playback edit failed to invalidate health or preserve disabled state'; end if;
end $$;
select set_config('request.jwt.claim.sub','30000000-0000-0000-0000-000000000002',true);
do $$ begin
 begin
  perform public.save_channel_editor(null,'{"name":"Denied","category":"Sports"}','[{"label":"Line","stream_url":"https://example.org/a.m3u8"}]');
  raise exception 'Non-admin write accepted';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
 if has_function_privilege('anon','public.save_channel_editor(uuid,jsonb,jsonb,uuid[])','EXECUTE') then raise exception 'Anon can save'; end if;
end $$;
rollback;
