begin;
do $$begin
 if current_database()<>'nca_security_test' then raise exception 'Disposable database required';end if;
end $$;
set local role service_role;
do $$
declare entries jsonb; lease jsonb; result jsonb; original_ctid text; after_ctid text;
begin
 select jsonb_agg(jsonb_build_object('id','gh:smsports:'||left(md5(i::text),28),'provider',11,'kind','channel',
  'name','Bulk fixture '||i,'category','Fixture','source_file','fixture.json','streams',jsonb_build_array(jsonb_build_object(
   'id','line','label','HD','stream_url','https://fixture.example.org/'||i||'.m3u8','stream_type','hls')),
  'unsupported_count',0,'event_meta',jsonb_build_object('source_repository','fixture-origin'))) into entries from generate_series(1,5000) i;
 lease:=public.begin_connected_channel_source_sync('darkbyte',true);
 result:=public.commit_stream_hub_snapshot((lease->>'lease')::uuid,'bulk-first',entries,'[]');
 select ctid::text into original_ctid from public.channel_source_catalog where id='gh:smsports:'||left(md5('1'),28);
 lease:=public.begin_connected_channel_source_sync('darkbyte',true);
 result:=public.commit_stream_hub_snapshot((lease->>'lease')::uuid,'bulk-next',entries,'[]');
 select ctid::text into after_ctid from public.channel_source_catalog where id='gh:smsports:'||left(md5('1'),28);
 if after_ctid is distinct from original_ctid then raise exception 'Unchanged stream JSON was rewritten for an unrelated revision';end if;
 if (result->>'entry_count')::int<>5000 then raise exception 'Fresh revision incorrectly removed unchanged entries';end if;
 lease:=public.begin_connected_channel_source_sync('darkbyte',true);
 result:=public.commit_stream_hub_snapshot((lease->>'lease')::uuid,'bulk-remove',entries-0,'[]');
 -- Removing one published ID must still reconcile the authoritative snapshot.
 if (result->>'entry_count')::int<>4999 then raise exception 'Confirmed removal was not reconciled';end if;
end $$;
rollback;
