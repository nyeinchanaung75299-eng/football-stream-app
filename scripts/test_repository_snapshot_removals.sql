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
reset role;
update public.channel_source_state set lease_id='37000000-0000-0000-0000-000000000001' where id='repository';
update public.channel_source_catalog set is_present=true where id='repo:match:ffffffffffffffffffffffffffff';
set local role authenticated;
do $$declare result jsonb;begin
 result:=public.commit_repository_partial_snapshot('37000000-0000-0000-0000-000000000001','new-partial-revision','[]','["repo:match:ffffffffffffffffffffffffffff"]');
 if result->>'removed_count'<>'1' then raise exception 'Atomic partial snapshot failed';end if;
 begin
 perform public.commit_repository_partial_snapshot('37000000-0000-0000-0000-000000000001','replay','[]','[]');raise exception 'Old lease replay allowed';
 exception when raise_exception then if sqlerrm<>'Source sync lease expired' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','36000000-0000-0000-0000-000000000002',true);
do $$begin
 begin perform public.hide_confirmed_repository_removals('snapshot-test','[]');raise exception 'Viewer removal allowed';exception when insufficient_privilege then null;end;
end $$;
rollback;
