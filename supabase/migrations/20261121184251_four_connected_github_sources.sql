alter table public.channel_source_catalog drop constraint channel_source_catalog_provider_check;
alter table public.channel_source_catalog add constraint channel_source_catalog_provider_check check(provider between 1 and 12);
alter table public.channel_repository_imports drop constraint channel_repository_imports_repository_check;
alter table public.channel_repository_imports add constraint channel_repository_imports_repository_check check(repository in (
 'rohmanabdu/lian','rohmanabdu/deqiaa','darkbyteprojects/iptv_png','Roshavarma/cfy',
 'nehalmahamuddev/SM-IPTV-Category-Playlists-Auto-Sync','dilzyking/allrounderlive',
 'sm-monirulislam/Upcoming-and-Live-Sports-Data','mdjamsad9/dudetvapi'));
do $$
declare definition text; signature text;
 old_list text:='''rohmanabdu/lian'',''rohmanabdu/deqiaa'',''darkbyteprojects/iptv_png'',''Roshavarma/cfy''';
 new_list text:='''rohmanabdu/lian'',''rohmanabdu/deqiaa'',''darkbyteprojects/iptv_png'',''Roshavarma/cfy'',''nehalmahamuddev/SM-IPTV-Category-Playlists-Auto-Sync'',''dilzyking/allrounderlive'',''sm-monirulislam/Upcoming-and-Live-Sports-Data'',''mdjamsad9/dudetvapi''';
begin
 foreach signature in array array['public.import_repository_mpds(jsonb)',
  'public.refresh_available_repository_channel_imports(jsonb,jsonb)'] loop
  definition:=pg_get_functiondef(signature::regprocedure);
  if strpos(definition,old_list)=0 then raise exception 'Repository allowlist hook unavailable';end if;
  definition:=replace(definition,old_list,new_list);
  definition:=replace(definition,'jsonb_array_length(p_unavailable_repositories)>4','jsonb_array_length(p_unavailable_repositories)>8');
  execute definition;
 end loop;
end $$;
notify pgrst,'reload schema';
