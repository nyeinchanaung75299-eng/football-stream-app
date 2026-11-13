-- Allow explicit re-publication of a match previously deleted in Controls.
-- This does NOT automatically restore all deleted matches; the Admin must select
-- the exact fixture in Pick Big Matches. Old stream links remain deleted.
-- Repository fixture lines are re-imported only after validation.

CREATE OR REPLACE FUNCTION public.publish_featured_matches(p_fixtures jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  item jsonb;
  fixture_id bigint;
  saved_id uuid;
  eligible_count integer := 0;
  restored_count integer := 0;
  saved_ids jsonb := '[]'::jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admin access required.' using errcode = '42501';
  end if;

  if p_fixtures is null
     or jsonb_typeof(p_fixtures) <> 'array'
     or jsonb_array_length(p_fixtures) = 0 then
    raise exception 'Select at least one match.';
  end if;

  for item in select value from jsonb_array_elements(p_fixtures)
  loop
    fixture_id := nullif(item->>'fixture_id', '')::bigint;
    if fixture_id is null then
      raise exception 'A selected fixture is missing fixture_id.';
    end if;
    if coalesce(btrim(item->>'league_name'), '') = ''
       or coalesce(btrim(item->>'home_name'), '') = ''
       or coalesce(btrim(item->>'away_name'), '') = ''
       or coalesce(btrim(item->>'kickoff_at'), '') = '' then
      raise exception 'A selected fixture is missing required match data.';
    end if;

    eligible_count := eligible_count + 1;
  end loop;

  update public.matches
  set is_featured = false
  where is_featured = true
    and (
      is_active = false
      or publish_state <> 'published'
      or deleted_at is not null
    );

  for item in select value from jsonb_array_elements(p_fixtures)
  loop
    fixture_id := nullif(item->>'fixture_id', '')::bigint;

    -- Restore only the explicitly selected soft-deleted fixture.
    if exists (
      select 1 from public.matches m
      where m.external_fixture_id = fixture_id and m.deleted_at is not null
    ) then
      restored_count := restored_count + 1;
    end if;

    insert into public.matches (
      external_fixture_id, source, league, home_team, away_team,
      home_logo_url, away_logo_url, kickoff_at, status_short, is_live,
      is_active, is_featured, publish_state, deleted_at
    )
    values (
      fixture_id,
      coalesce(nullif(item->>'provider', ''), 'api_football'),
      item->>'league_name',
      item->>'home_name',
      item->>'away_name',
      nullif(item->>'home_logo', ''),
      nullif(item->>'away_logo', ''),
      (item->>'kickoff_at')::timestamptz,
      coalesce(nullif(item->>'status_short', ''), 'NS'),
      coalesce((item->>'is_live')::boolean, false),
      true, true, 'published', null
    )
    on conflict (external_fixture_id)
    do update set
      source = excluded.source,
      league = excluded.league,
      home_team = excluded.home_team,
      away_team = excluded.away_team,
      home_logo_url = excluded.home_logo_url,
      away_logo_url = excluded.away_logo_url,
      kickoff_at = excluded.kickoff_at,
      status_short = excluded.status_short,
      is_live = excluded.is_live,
      is_active = true,
      is_featured = true,
      publish_state = 'published',
      deleted_at = null,
      is_finished = case when public.matches.deleted_at is not null
        then false else public.matches.is_finished end
    returning public.matches.id into saved_id;

    saved_ids := saved_ids || jsonb_build_array(saved_id::text);
  end loop;

  return jsonb_build_object(
    'saved_ids', saved_ids,
    'published_count', eligible_count,
    'skipped_deleted', 0,
    'restored_count', restored_count
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.publish_repository_match(p_entry_id text, p_kickoff_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 entry public.channel_source_catalog; meta jsonb; kickoff timestamptz;
 home text; away text; league text; home_key text; away_key text;
 saved public.matches; saved_id uuid; candidate_count integer; config jsonb; result jsonb;
 eligible jsonb:='[]'; added integer:=0; existing integer:=0; skipped integer:=0;
 created boolean:=false; changed boolean:=false; restored boolean:=false; duplicate_id uuid; women boolean;
begin
 if not public.is_admin() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_entry_id !~ '^repo:match:[a-f0-9]{28}$' then
  return jsonb_build_object('ok',false,'code','invalid_entry'); end if;
 select * into entry from public.channel_source_catalog
  where id=p_entry_id and source_id='repository' and kind='event' and is_present for update;
 if not found then return jsonb_build_object('ok',false,'code','source_missing'); end if;
 meta:=entry.event_meta;home:=btrim(meta->>'home_team');away:=btrim(meta->>'away_team');
 league:=coalesce(nullif(btrim(meta->>'league'),''),'Football');
 if coalesce(home,'')='' or coalesce(away,'')='' then
  return jsonb_build_object('ok',false,'code','metadata_pending'); end if;
 kickoff:=coalesce(nullif(meta->>'kickoff_at','')::timestamptz,p_kickoff_at);
 if kickoff is null then return jsonb_build_object('ok',false,'code','kickoff_required'); end if;
 if kickoff<'2000-01-01'::timestamptz or kickoff>='2100-01-01'::timestamptz then
  return jsonb_build_object('ok',false,'code','invalid_kickoff'); end if;
 home_key:=private.repository_team_key(home);away_key:=private.repository_team_key(away);
 if home_key='' or away_key='' or home_key=away_key then
  return jsonb_build_object('ok',false,'code','metadata_pending'); end if;
 women:=(league||' '||home||' '||away) ~* '(women|ladies|wsl|femenin|frauen|femminile)';
 -- Serialize repeat imports, including independent entries for the same fixture.
 perform pg_advisory_xact_lock(hashtextextended('nca-repository-publish:'||home_key||':'||away_key||':'||
  (kickoff at time zone 'UTC')::date::text,0));
 select m.* into saved from public.repository_match_imports r
  join public.matches m on m.id=r.match_id where r.entry_id=p_entry_id for update of m;
 if found then saved_id:=saved.id;
 else
  select count(*) into candidate_count from public.matches m
   where m.kickoff_at between kickoff-interval '30 minutes' and kickoff+interval '30 minutes'
    and private.repository_team_key(m.home_team)=home_key and private.repository_team_key(m.away_team)=away_key
    and ((m.league||' '||m.home_team||' '||m.away_team) ~* '(women|ladies|wsl|femenin|frauen|femminile)')=women;
  if candidate_count>1 then return jsonb_build_object('ok',false,'code','ambiguous_match'); end if;
  if candidate_count=1 then
   select * into saved from public.matches m
    where m.kickoff_at between kickoff-interval '30 minutes' and kickoff+interval '30 minutes'
     and private.repository_team_key(m.home_team)=home_key and private.repository_team_key(m.away_team)=away_key
     and ((m.league||' '||m.home_team||' '||m.away_team) ~* '(women|ladies|wsl|femenin|frauen|femminile)')=women
    for update;
   saved_id:=saved.id;
  end if;
 end if;
 -- Only the explicitly selected repository fixture can be restored.
 if saved_id is not null and saved.deleted_at is not null then
   restored:=true;
 end if;
 if saved_id is not null and saved.is_finished and not restored then
  return jsonb_build_object('ok',false,'code','previously_finished'); end if;
 -- Only publish native configurations that stream_links can represent. Never
 -- invent missing DRM keys or expose protected/malformed configurations.
 for config in select value from jsonb_array_elements(entry.streams) loop
  if coalesce(config->>'id','')='' or coalesce(config->>'stream_url','') !~ '^https?://[^[:space:]]+$'
   or coalesce(config->>'stream_type','') not in ('hls','dash','mp4','flv')
   or config->>'configuration_status'='requires_drm'
   or coalesce(config->>'drm_type','') not in ('','none','clearkey')
   or ((coalesce(config->>'key_id','')<>'' or coalesce(config->>'key_data','')<>'') and
    (coalesce(config->>'key_id','') !~ '^[a-fA-F0-9]{32}$' or coalesce(config->>'key_data','') !~ '^[a-fA-F0-9]{32}$'))
   or (config->>'drm_type'='clearkey' and coalesce(config->>'key_data','')='') then
   skipped:=skipped+1;
  else eligible:=eligible||jsonb_build_array(config);end if;
 end loop;
 if jsonb_array_length(eligible)=0 then
  return jsonb_build_object('ok',false,'code','no_importable_lines','skipped_lines',skipped); end if;
 if saved_id is null then
  insert into public.matches(league,home_team,away_team,home_logo_url,away_logo_url,kickoff_at,
   source,is_live,is_active,is_featured,publish_state,status_short)
  values(league,home,away,private.repository_import_logo(meta->>'home_logo_url'),
   private.repository_import_logo(meta->>'away_logo_url'),kickoff,'repository',false,true,true,'published','NS')
  returning id into saved_id;
  created:=true;changed:=true;
 else
  -- Keep existing fixture IDs, edited names, order, scores and nonempty badges.
  update public.matches m set is_active=true,is_featured=true,publish_state='published',
   deleted_at=null,
   is_finished=case when m.deleted_at is not null then false else m.is_finished end,
   is_live=case when m.deleted_at is not null then false else m.is_live end,
   status_short=case when m.deleted_at is not null then 'NS' else m.status_short end,
   home_logo_url=coalesce(nullif(m.home_logo_url,''),private.repository_import_logo(meta->>'home_logo_url')),
   away_logo_url=coalesce(nullif(m.away_logo_url,''),private.repository_import_logo(meta->>'away_logo_url'))
   where m.id=saved_id and (m.deleted_at is not null or not m.is_active or not m.is_featured or m.publish_state<>'published'
    or (coalesce(m.home_logo_url,'')='' and private.repository_import_logo(meta->>'home_logo_url') is not null)
    or (coalesce(m.away_logo_url,'')='' and private.repository_import_logo(meta->>'away_logo_url') is not null));
  changed:=found;
 end if;
 for config in select value from jsonb_array_elements(eligible) loop
  duplicate_id:=null;
  if config->>'stream_type'='dash' then
   -- User-defined identity: MPD + key ID + key data, regardless of label/header.
   select sl.id into duplicate_id from public.stream_links sl
    left join public.channel_lines cl on cl.id=sl.channel_line_id
    where sl.match_id=saved_id and not coalesce(sl.use_webview,false)
     and coalesce(cl.stream_type,sl.stream_type)='dash'
     and public.channel_mpd_identity(coalesce(cl.stream_url,sl.stream_url))=public.channel_mpd_identity(config->>'stream_url')
     and lower(coalesce(cl.key_id,sl.key_id,''))=lower(coalesce(config->>'key_id',''))
     and lower(coalesce(cl.key_data,sl.key_data,''))=lower(coalesce(config->>'key_data',''))
    order by sl.created_at limit 1;
  end if;
  if duplicate_id is not null then existing:=existing+1;
  else
   result:=public.add_connected_source_line_to_match(p_entry_id,config->>'id',saved_id);
   if (result->>'already_exists')::boolean then existing:=existing+1;else added:=added+1;end if;
  end if;
 end loop;
 insert into public.repository_match_imports(entry_id,match_id) values(p_entry_id,saved_id)
  on conflict(entry_id) do nothing;
 return jsonb_build_object('ok',true,'match_id',saved_id,'created',created,'restored',restored,
  'changed',changed or added>0,
  'added_lines',added,'existing_lines',existing,'skipped_lines',skipped);
end $function$
;

revoke all on function public.publish_featured_matches(jsonb) from public, anon, authenticated;
grant execute on function public.publish_featured_matches(jsonb) to authenticated;
revoke all on function public.publish_repository_match(text,timestamptz) from public, anon, authenticated;
grant execute on function public.publish_repository_match(text,timestamptz) to authenticated;
notify pgrst, 'reload schema';
