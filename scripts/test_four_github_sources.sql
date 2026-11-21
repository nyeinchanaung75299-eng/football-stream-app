begin;
do $$begin
 if current_database()<>'nca_security_test' then raise exception 'Disposable database required';end if;
end $$;
set local role service_role;
do $$
declare repositories text[]:=array['nehalmahamuddev/SM-IPTV-Category-Playlists-Auto-Sync','dilzyking/allrounderlive',
 'sm-monirulislam/Upcoming-and-Live-Sports-Data','mdjamsad9/dudetvapi']; entries jsonb:='[]'; result jsonb; i integer;
begin
 for i in 1..4 loop
  entries:=entries||jsonb_build_array(jsonb_build_object('repository',repositories[i],'revision',repeat('c',40),
   'name','New GitHub fixture '||i,'stream_url','https://new-source.example.org/fixture-'||i||'.mpd','source_file','export.json','configuration_status','clear'));
  insert into public.channel_source_catalog(id,provider,kind,name,category,source_file,source_id,revision,streams)
   values('new-source-fixture-'||i,i+8,'channel','New source fixture','Sports','export.json','darkbyte','test','[]');
 end loop;
 result:=public.import_repository_mpds(entries);
 if result->>'added_lines'<>'4' then raise exception 'New repositories were not accepted: %',result;end if;
 result:=public.refresh_available_repository_channel_imports(entries-3,jsonb_build_array(repositories[4]));
 if result->>'unavailable_imports'<>'1' then raise exception 'Unavailable new source was not preserved';end if;
 if (select count(*) from public.channel_lines where stream_url like 'https://new-source.example.org/%')<>4 then
  raise exception 'Partial source refresh deleted a saved line';
 end if;
end $$;
rollback;
