-- Repository fixtures are an Admin source catalog, not automatic publications.
alter table public.channel_source_state drop constraint channel_source_state_id_check;
alter table public.channel_source_state add constraint channel_source_state_id_check check(id in ('darkbyte','livetv','repository','repository-imports'));
insert into public.channel_source_state(id) values('repository'),('repository-imports');
alter table public.channel_source_catalog drop constraint channel_source_catalog_provider_check;
alter table public.channel_source_catalog add constraint channel_source_catalog_provider_check check(provider between 1 and 8);
alter table public.channel_source_catalog add column event_meta jsonb not null default '{}';

create function public.reconcile_repository_match_links() returns integer
language plpgsql security invoker set search_path='' as $$
declare item record; candidates jsonb; replacement jsonb; removed integer:=0;
begin
 for item in select r.*,e.streams,e.is_present,sl.stream_url,sl.referer,sl.origin,sl.stream_type
  from public.channel_source_match_links r join public.channel_source_catalog e on e.id=r.entry_id
  join public.stream_links sl on sl.id=r.stream_link_id where e.source_id='repository' for update of r loop
  if item.is_present and exists(select from jsonb_array_elements(item.streams) c where c->>'id'=item.source_line_id) then continue; end if;
  -- A key/token rotation of one unambiguous manifest follows the same
  -- selected line. Distinct key configurations never inherit one another.
  select jsonb_agg(c) into candidates from jsonb_array_elements(item.streams) c
   where item.is_present and public.channel_mpd_identity(c->>'stream_url')=public.channel_mpd_identity(item.stream_url)
    and coalesce(c->>'referer','')=coalesce(item.referer,'') and coalesce(c->>'origin','')=coalesce(item.origin,'')
    and c->>'stream_type'=item.stream_type;
  if jsonb_array_length(candidates)=1 then
   replacement:=candidates->0;
   if not exists(select from public.channel_source_match_links where match_id=item.match_id and entry_id=item.entry_id and source_line_id=replacement->>'id') then
    update public.channel_source_match_links set source_line_id=replacement->>'id' where stream_link_id=item.stream_link_id;
    continue;
   end if;
  end if;
  delete from public.stream_links where id=item.stream_link_id;
  removed:=removed+1;
 end loop;
 return removed;
end $$;
revoke all on function public.reconcile_repository_match_links() from public,anon,authenticated;
grant execute on function public.reconcile_repository_match_links() to service_role;

do $$
declare definition text;
begin
 definition:=pg_get_functiondef('public.begin_connected_channel_source_sync(text,boolean)'::regprocedure);
 definition:=replace(definition,'''darkbyte'',''livetv''','''darkbyte'',''livetv'',''repository'',''repository-imports''');
 execute definition;
 definition:=pg_get_functiondef('public.commit_connected_channel_source_sync(text,uuid,text,jsonb,boolean,boolean)'::regprocedure);
 if strpos(definition,'x.epg_channel_id,x.region')=0 then raise exception 'Source metadata hook unavailable'; end if;
 definition:=replace(definition,'''darkbyte'',''livetv''','''darkbyte'',''livetv'',''repository'',''repository-imports''');
 definition:=replace(definition,'epg_channel_id,region)','epg_channel_id,region,event_meta)');
 definition:=replace(definition,'x.epg_channel_id,x.region','x.epg_channel_id,x.region,coalesce(x.event_meta,''{}''::jsonb)');
 definition:=replace(definition,'region text)','region text,event_meta jsonb)');
 definition:=replace(definition,'region=excluded.region;','region=excluded.region,event_meta=excluded.event_meta;');
 definition:=replace(definition,'perform public.sync_connected_source_match_lines(p_source);',
  'if p_source=''repository'' and p_complete then perform public.reconcile_repository_match_links(); end if; perform public.sync_connected_source_match_lines(p_source);');
 execute definition;
end $$;

-- Reconcile only rows created by the private repository importer. Manual
-- channels and operator names/order/EPG mappings are not source-owned here.
create function public.refresh_repository_channel_imports(p_entries jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare imported record; candidates jsonb; item jsonb; changes integer:=0; missing integer:=0;
begin
 if jsonb_typeof(p_entries)<>'array' or jsonb_array_length(p_entries)>15000 then raise exception 'Invalid repository snapshot'; end if;
 perform pg_advisory_xact_lock(hashtextextended('nca-repository-mpd-import',0));
 for imported in select r.*,l.stream_url,c.name from public.channel_repository_imports r
  join public.channel_lines l on l.id=r.line_id join public.channels c on c.id=l.channel_id for update of r,l loop
  select jsonb_agg(e) into candidates from jsonb_array_elements(p_entries) e where
   e->>'repository'=imported.repository and e->>'source_file'=imported.source_file and
   public.channel_mpd_identity(e->>'stream_url')=public.channel_mpd_identity(imported.stream_url);
  if candidates is null then
   select jsonb_agg(e) into candidates from jsonb_array_elements(p_entries) e
    where e->>'repository'=imported.repository and e->>'source_file'=imported.source_file and lower(e->>'name')=lower(imported.name);
  end if;
  -- Ambiguous alternatives need an operator choice; never guess a key.
  if jsonb_array_length(candidates)<>1 or candidates is null then
   update public.channel_repository_imports set metadata=metadata||jsonb_build_object('source_missing',true,'last_source_check',now()) where fingerprint=imported.fingerprint;
   missing:=missing+1; continue;
  end if;
  item:=candidates->0;
  if coalesce(item->>'configuration_status','') not in ('configured','clear') then
   update public.channel_repository_imports set metadata=metadata||jsonb_build_object('configuration_pending',true,'last_source_check',now()) where fingerprint=imported.fingerprint;
   continue;
  end if;
  update public.channel_lines set stream_url=item->>'stream_url',referer=nullif(item->>'referer',''),origin=nullif(item->>'origin',''),
   key_id=nullif(item->>'key_id',''),key_data=nullif(item->>'key_data',''),configuration_status=item->>'configuration_status',
   health_status='unknown',last_checked_at=null
   where id=imported.line_id and (stream_url,referer,origin,key_id,key_data,configuration_status) is distinct from
    (item->>'stream_url',nullif(item->>'referer',''),nullif(item->>'origin',''),nullif(item->>'key_id',''),nullif(item->>'key_data',''),item->>'configuration_status');
  if found then changes:=changes+1; end if;
  update public.channel_repository_imports set revision=item->>'revision',metadata=metadata||jsonb_build_object(
   'source_missing',false,'configuration_pending',false,'last_source_check',now()) where fingerprint=imported.fingerprint;
 end loop;
 return jsonb_build_object('updated_lines',changes,'missing_or_ambiguous',missing);
end $$;
revoke all on function public.refresh_repository_channel_imports(jsonb) from public,anon,authenticated;
grant execute on function public.refresh_repository_channel_imports(jsonb) to service_role;

do $schedule$
begin
 if to_regprocedure('cron.schedule(text,text,text)') is not null and to_regprocedure('vault.create_secret(text,text,text,uuid)') is not null then
  perform cron.schedule('nca-repository-matches','1-59/5 * * * *',$job$
   select net.http_post(url:='https://woggzixprvyjnfjzsglz.supabase.co/functions/v1/channel-source-sync',
    headers:=jsonb_build_object('Content-Type','application/json','x-nca-channel-source-key',
     (select decrypted_secret from vault.decrypted_secrets where name='nca_darkbyte_channel_source_pulse' limit 1)),
    body:='{"action":"sync","source":"repository"}'::jsonb,timeout_milliseconds:=55000);
  $job$);
  perform cron.schedule('nca-repository-channel-updates','41 * * * *',$job$
   select net.http_post(url:='https://woggzixprvyjnfjzsglz.supabase.co/functions/v1/channel-source-sync',
    headers:=jsonb_build_object('Content-Type','application/json','x-nca-channel-source-key',
     (select decrypted_secret from vault.decrypted_secrets where name='nca_darkbyte_channel_source_pulse' limit 1)),
    body:='{"action":"sync","source":"repository-imports"}'::jsonb,timeout_milliseconds:=55000);
  $job$);
 end if;
end $schedule$;
notify pgrst,'reload schema';
