begin;
insert into auth.users(id) values('36000000-0000-0000-0000-000000000001'),('36000000-0000-0000-0000-000000000002');
insert into public.profiles(id,role) values('36000000-0000-0000-0000-000000000001','admin'),('36000000-0000-0000-0000-000000000002','viewer');
update public.channel_source_state set revision='snapshot-test' where id='repository';
insert into public.channel_source_catalog(id,provider,kind,name,category,source_file,streams,source_id,is_present,revision)
 values('repo:match:ffffffffffffffffffffffffffff',1,'event','Fixture only','Football','fixture.json','[]','repository',true,'snapshot-test');
set local role authenticated;
select set_config('request.jwt.claim.sub','36000000-0000-0000-0000-000000000001',true);
do $$begin
 if public.hide_confirmed_repository_removals('old-snapshot','["repo:match:ffffffffffffffffffffffffffff"]')<>0 then raise exception 'Stale snapshot mutated catalogue';end if;
 if public.hide_confirmed_repository_removals('snapshot-test','["repo:match:ffffffffffffffffffffffffffff"]')<>1 then raise exception 'Confirmed removal did not hide catalogue row';end if;
end $$;
select set_config('request.jwt.claim.sub','36000000-0000-0000-0000-000000000002',true);
do $$begin
 begin perform public.hide_confirmed_repository_removals('snapshot-test','[]');raise exception 'Viewer removal allowed';exception when insufficient_privilege then null;end;
end $$;
rollback;
