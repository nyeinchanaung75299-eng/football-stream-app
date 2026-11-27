-- Versioned browse contract. Existing Viewer releases can keep the old RPC.
create function public.get_repository_catalog_page_for_gateway(
 p_date date,p_offset integer,p_limit integer,p_secret text
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not exists(select from private.gateway_secrets s where s.name='cloudflare_playback'
  and s.secret_hash=encode(extensions.digest(coalesce(p_secret,''),'sha256'),'hex')) then
  raise exception 'unauthorized gateway' using errcode='42501';
 end if;
 if p_offset is null or p_offset not between 0 and 15000 or p_limit is null or p_limit not between 1 and 200 then
  raise exception 'Invalid Live 2 page' using errcode='22023';
 end if;
 with page as (
  select c.id,c.event_meta,c.streams
  from public.channel_source_catalog c
  where c.source_id='repository' and c.kind='event' and c.is_present
    and (p_date is null or (nullif(c.event_meta->>'kickoff_at','')::timestamptz at time zone 'Asia/Yangon')::date=p_date)
  order by c.event_meta->>'kickoff_at',c.id
  offset p_offset limit p_limit+1
 ), visible as (
  select id,event_meta,(
   select count(*) from jsonb_array_elements(streams) s
   where coalesce(s->>'configuration_status','')<>'requires_drm'
    and s->>'stream_type' in ('hls','dash','mp4','flv')
  ) stream_count from page order by event_meta->>'kickoff_at',id limit p_limit
 )
 select jsonb_build_object(
  'matches',coalesce(jsonb_agg(jsonb_build_object(
   'source','repository','source_id',id,'schedule_id',id,
   'home_team',event_meta->>'home_team','away_team',event_meta->>'away_team',
   'home_logo',event_meta->>'home_logo_url','away_logo',event_meta->>'away_logo_url',
   'league',event_meta->>'league','match_time',event_meta->>'kickoff_at',
   'status',case when event_meta->>'source_finished'='true' then 'FINISHED' else 'SCHEDULED' end,
   'stream_count',stream_count,'anchors',case when stream_count>0 then
     jsonb_build_array(jsonb_build_object('room_num',id,'nick_name','Live 2')) else '[]'::jsonb end
   ) order by event_meta->>'kickoff_at',id),'[]'::jsonb),
  'next_offset',case when (select count(*) from page)>p_limit then p_offset+p_limit else null end)
 into result from visible;
 return result;
end $$;
revoke all on function public.get_repository_catalog_page_for_gateway(date,integer,integer,text) from public;
grant execute on function public.get_repository_catalog_page_for_gateway(date,integer,integer,text) to anon,authenticated,service_role;
notify pgrst,'reload schema';
