-- MPD duplicate identity is exactly URL + Key ID + Key Data. Names,
-- request headers and license metadata are not additional identity fields.
do $$
declare definition text; old_partition text;
begin
 definition:=pg_get_functiondef('public.deduplicate_exact_channel_lines()'::regprocedure);
 old_partition:=$partition$partition by l.stream_url,l.stream_type,coalesce(l.referer,''),coalesce(l.origin,''),
     coalesce(l.key_id,''),coalesce(l.key_data,''),
     case when nullif(l.key_id,'') is not null and nullif(l.key_data,'') is not null then 'clearkey'
      else coalesce((select r.metadata->>'drm_type' from public.channel_repository_imports r where r.line_id=l.id order by r.imported_at limit 1),'unspecified') end,
     coalesce((select r.metadata->>'license_url' from public.channel_repository_imports r where r.line_id=l.id order by r.imported_at limit 1),'')$partition$;
 if strpos(definition,old_partition)=0 then raise exception 'Duplicate identity hook unavailable'; end if;
 definition:=replace(definition,old_partition,$replacement$partition by case
    when l.stream_type='dash' or l.stream_url ~* '\.mpd([?#]|$)' then
     jsonb_build_array(btrim(l.stream_url),lower(btrim(coalesce(l.key_id,''))),lower(btrim(coalesce(l.key_data,''))))
    else jsonb_build_array(l.stream_url,l.stream_type,coalesce(l.referer,''),coalesce(l.origin,''),
     coalesce(l.key_id,''),coalesce(l.key_data,''),
     coalesce((select r.metadata->>'drm_type' from public.channel_repository_imports r where r.line_id=l.id order by r.imported_at limit 1),'unspecified'),
     coalesce((select r.metadata->>'license_url' from public.channel_repository_imports r where r.line_id=l.id order by r.imported_at limit 1),'')) end$replacement$);
 definition:=replace(definition,
  'order by c.is_active desc,(c.epg_id is not null and c.epg_source is not null) desc,l.is_active desc,l.created_at,l.id',
  $priority$order by (nullif(btrim(c.epg_id),'') is not null and nullif(btrim(c.epg_source),'') is not null) desc,
    (nullif(c.epg_source,'') is not null and c.epg_source not like 'GH:%') desc,
    c.is_active desc,l.is_active desc,(l.health_status in ('healthy','slow')) desc,l.sort_order,l.created_at,l.id$priority$);
 definition:=replace(definition,'if item.channel_id<>item.keep_channel and has_other then continue; end if;','');
 definition:=replace(definition,'delete from public.channel_lines where id=item.id;', $merge$
  update public.channel_lines k set is_active=k.is_active or d.is_active
   from public.channel_lines d where k.id=item.keep_id and d.id=item.id;
  update public.channels k set is_active=k.is_active or d.is_active
   from public.channels d where k.id=item.keep_channel and d.id=item.channel_id;
  delete from public.channel_lines where id=item.id;
 $merge$);
 execute definition;
end $$;

create function public.same_channel_mpd_configuration(p_id uuid,p_config jsonb)
returns boolean language sql stable security invoker set search_path='' as $$
 select exists(select from public.channel_lines l where l.id=p_id
  and (l.stream_type='dash' or l.stream_url ~* '\.mpd([?#]|$)')
  and (p_config->>'stream_type'='dash' or p_config->>'stream_url' ~* '\.mpd([?#]|$)')
  and row(btrim(l.stream_url),lower(btrim(coalesce(l.key_id,''))),lower(btrim(coalesce(l.key_data,''))))=
   row(btrim(p_config->>'stream_url'),lower(btrim(coalesce(p_config->>'key_id',''))),lower(btrim(coalesce(p_config->>'key_data','')))));
$$;
revoke all on function public.same_channel_mpd_configuration(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.same_channel_mpd_configuration(uuid,jsonb) to service_role;
do $$
declare definition text; old_lookup text;
begin
 definition:=pg_get_functiondef('public.link_channel_source_entry(text,uuid,boolean)'::regprocedure);
 if strpos(definition,'where row(cl.stream_url,coalesce(cl.referer')=0 then raise exception 'MPD import identity hook unavailable'; end if;
 definition:=replace(definition,'where row(cl.stream_url,coalesce(cl.referer',
  'where public.same_channel_mpd_configuration(cl.id,e.streams->0) or row(cl.stream_url,coalesce(cl.referer');
 old_lookup:=$old$where channel_id=l.channel_id and
     (stream_url,referer,origin,key_id,key_data) is not distinct from
     (config->>'stream_url',config->>'referer',config->>'origin',config->>'key_id',config->>'key_data')
     and (stream_type=config->>'stream_type' or stream_type='auto' or config->>'stream_type='auto')$old$;
 if strpos(definition,old_lookup)=0 then raise exception 'Shared MPD refresh identity hook unavailable'; end if;
 definition:=replace(definition,old_lookup,
  'where public.same_channel_mpd_configuration(id,config) or ('||substr(old_lookup,7)||')');
 execute definition;
end $$;

-- Viewer receives public fixture fields through its trusted gateway. Native
-- source URLs/headers remain private and are encrypted by that gateway.
create function public.get_repository_metadata_for_gateway(p_entry_id text,p_secret text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not exists(select from private.gateway_secrets s where s.name='cloudflare_playback'
  and s.secret_hash=encode(extensions.digest(coalesce(p_secret,''),'sha256'),'hex')) then
  raise exception 'unauthorized gateway' using errcode='42501';
 end if;
 if p_entry_id is null then
  select jsonb_build_object('matches',coalesce(jsonb_agg(m order by m->>'match_time',m->>'source_id'),'[]'::jsonb)) into result
  from (
   select jsonb_build_object('source','repository','source_id',c.id,'schedule_id',c.id,
    'home_team',c.event_meta->>'home_team','away_team',c.event_meta->>'away_team',
    'home_logo',c.event_meta->>'home_logo_url','away_logo',c.event_meta->>'away_logo_url',
    'league',c.event_meta->>'league','match_time',c.event_meta->>'kickoff_at',
    'status','SCHEDULED','stream_count',(
     select count(*) from jsonb_array_elements(c.streams) s where coalesce(s->>'configuration_status','')<>'requires_drm'),
    'anchors',case when exists(select from jsonb_array_elements(c.streams) s where coalesce(s->>'configuration_status','')<>'requires_drm')
     then jsonb_build_array(jsonb_build_object('room_num',c.id,'nick_name','Live 2')) else '[]'::jsonb end) m
   from public.channel_source_catalog c
   where c.source_id='repository' and c.kind='event' and c.is_present
    and (nullif(c.event_meta->>'kickoff_at','') is null or (c.event_meta->>'kickoff_at')::timestamptz>now()-interval '6 hours')
   order by c.event_meta->>'kickoff_at',c.id limit 500
  ) entries;
  return result;
 end if;
 if p_entry_id !~ '^repo:match:[a-f0-9]{28}$' then raise exception 'Invalid repository fixture'; end if;
 select jsonb_build_object('match_valid',true,'streams',coalesce((
  select jsonb_agg(jsonb_build_object('id',c.id||':'||(s->>'id'),
   'label',coalesce(s->>'label','Line'),'stream_url',s->>'stream_url','stream_type',s->>'stream_type',
   'referer',s->>'referer','origin',s->>'origin','key_id',s->>'key_id','key_data',s->>'key_data',
   'is_active',true,'use_webview',false,'health_status','unknown','priority',100))
  from jsonb_array_elements(c.streams) s where coalesce(s->>'configuration_status','')<>'requires_drm'
   and s->>'stream_type' in ('hls','dash','mp4','flv')
 ),'[]'::jsonb)) into result from public.channel_source_catalog c
 where c.id=p_entry_id and c.source_id='repository' and c.is_present and c.kind='event'
  and (nullif(c.event_meta->>'kickoff_at','') is null or (c.event_meta->>'kickoff_at')::timestamptz>now()-interval '6 hours');
 return coalesce(result,jsonb_build_object('match_valid',false,'streams','[]'::jsonb));
end $$;
revoke all on function public.get_repository_metadata_for_gateway(text,text) from public;
grant execute on function public.get_repository_metadata_for_gateway(text,text) to anon,authenticated,service_role;
notify pgrst,'reload schema';
