alter table public.channels add column category_locked boolean not null default false;
create function public.channel_group_name(p_name text,p_category text) returns text
language sql immutable set search_path='' as $$
 select case
 when p_name ~* 'travel|voyage|pbs travel' then 'Travel'
 when p_name ~* 'be[il]?in|bein' then 'beIN Sports'
 when p_name ~* '\mufc\M|ultimate fighting' then 'UFC'
 when p_name ~* '\mtnt\M' then 'TNT Sports'
 when p_name ~* 'fubo' then 'Fubo'
 when p_name ~* 'fan\s*code|\mfc\s*[12]\M' then 'FanCode'
 when p_name ~* 'caz[eé]|cazÃ' then 'CazéTV'
 when p_name ~* 'arena' then 'Arena Sports'
 when p_name ~* '\mfox\M|\mfs[12]\M' then 'FOX Sports'
 when p_name ~* '\md\s*sports?\M|\mdsport' then 'D Sports'
 when p_name ~* '\mtsn' then 'TSN'
 when p_name ~* 'sportv|sport\s*v' then 'SporTV'
 when p_name ~* 'spotv|spo\s*tv' then 'SPOTV'
 when p_name ~* 'premiere|premire|premierer' then 'Premiere'
 when p_name ~* 'premier sports' then 'Premier Sports'
 when p_name ~* 'sky' then 'Sky Sports'
 when p_name ~* 'dazn' then 'DAZN'
 when p_name ~* 'espn' then 'ESPN'
 when p_name ~* 'eurosport|euro sports|euro\s*aq' then 'Eurosport'
 when p_name ~* '\mcbs\M|golazo' then 'CBS Sports'
 when p_name ~* '\mnbc\M|peacock|usa\s*(tv|network|sports|west|east)' then 'NBC / USA / Peacock'
 when p_name ~* 'willow|cricbuzz|criclife' then 'Willow / Cricket'
 when p_name ~* 'sony|ten\s*cricket' then 'Sony Sports'
 when p_name ~* 'star sports|sports18' then 'Star Sports'
 when p_name ~* 'ziggo' then 'Ziggo Sport'
 when p_name ~* 'eleven' then 'Eleven Sports'
 when p_name ~* 'setanta' then 'Setanta Sports'
 when p_name ~* '\mgo3\M|\mv\s*sport' then 'V Sport / Go3'
 when p_name ~* 'tudn|vix' then 'TUDN / ViX'
 when p_name ~* 'ssc|thmanyah|shahid|stc\s*tv' then 'Saudi Sports'
 when p_name ~* '\mad\s*(sports?|premium)' then 'Abu Dhabi Sports'
 when p_name ~* 'nova sport' then 'Nova Sport'
 when p_name ~* 'sportdigital|sport digital' then 'Sportdigital'
 when p_name ~* '\mjoj\M' then 'JOJ Sport'
 when p_name ~* '\m(ct|čt) sport' then 'ČT Sport'
 when p_name ~* 'rtvs' then 'RTVS Sport'
 when p_name ~* '\msport\s*[12]\M' then 'Sport 1 / 2'
 when p_name ~* 'canal\s*\+|canal\s*[1-9]' then 'Canal+'
 when p_name ~* '\mhbo\M|max hd|cinemax|miramax' then 'Movies & Entertainment'
 when p_name ~* 'disney|nick|cartoon|pogo' then 'Kids'
 when p_name ~* 'zee|sony\s*tv' then 'India Entertainment'
 when p_name ~* 'pbs|mythbusters|nature|dinos|disaster|military|history|marvels|space|sharks|genealogy|jack hanna' then 'Documentaries'
 when p_name ~* 'sport\s*tv' then 'Sport TV'
 when p_name ~* 'nba|basketball' then 'NBA / Basketball'
 when p_name ~* 'tennis|atp|wta' then 'Tennis'
 when p_name ~* 'nfl|redzone' then 'NFL'
 when p_name ~* 'motogp|formula|\mf1\M|motorsport' then 'Motorsports'
 when p_name ~* 'wwe|tna|fight|combat|boxing|bkfc' then 'Combat Sports'
 when p_name ~* 'golf|pga|dp tour' then 'Golf'
 when p_name ~* 'baseball|\mmlb\s*(network|tv)\M' then 'Baseball'
 when p_name ~* 'cricket|\mt10\M|\mnpl\M' then 'Cricket'
 when p_name ~* 'football|soccer|\svs\.?\s|paramount|laliga|milan tv|real madrid tv' then 'Football'
 when coalesce(p_category,'') !~* '^(sports?( 2)?|live events?|events / unverified|football|)$' then p_category
 else 'Uncategorized' end;
$$;
revoke all on function public.channel_group_name(text,text) from public,anon,authenticated;
grant execute on function public.channel_group_name(text,text) to authenticated,service_role;
create function public.apply_channel_group() returns trigger language plpgsql set search_path='' as $$
begin
 if not new.category_locked then new.category:=public.channel_group_name(new.name,new.category);
 elsif tg_op='UPDATE' and old.category_locked and current_user='service_role' then new.category:=old.category;
 end if;
 return new;
end $$;
revoke all on function public.apply_channel_group() from public,anon,authenticated;
create trigger classify_channel_group before insert or update of name,category,category_locked on public.channels
for each row execute function public.apply_channel_group();
-- Existing records were explicitly requested for regrouping by the operator.
update public.channels set category=public.channel_group_name(name,category);

alter table public.channel_lines add column manifest_status text not null default 'not_tested',
 add column segment_status text not null default 'not_tested',add column drm_status text not null default 'unknown',
 add column playback_status text not null default 'not_tested' check(playback_status in ('not_tested','verified','failed','unsupported')),
 add column last_playback_checked_at timestamptz,add column playback_device text,add column health_detail text;

create function public.channel_line_config_hash(p_id uuid) returns text language sql stable set search_path='' as $$
 select encode(sha256(convert_to(jsonb_build_array(stream_url,stream_type,referer,origin,key_id,key_data)::text,'UTF8')),'hex')
 from public.channel_lines where id=p_id;
$$;
revoke all on function public.channel_line_config_hash(uuid) from public,anon,authenticated;
grant execute on function public.channel_line_config_hash(uuid) to service_role;
create function public.invalidate_channel_playback() returns trigger language plpgsql set search_path='' as $$
begin
 if row(new.stream_url,new.stream_type,new.referer,new.origin,new.key_id,new.key_data) is distinct from
  row(old.stream_url,old.stream_type,old.referer,old.origin,old.key_id,old.key_data) then
  new.playback_status:='not_tested';new.last_playback_checked_at:=null;
 end if;
 return new;
end $$;
revoke all on function public.invalidate_channel_playback() from public,anon,authenticated;
create trigger invalidate_channel_playback before update of stream_url,stream_type,referer,origin,key_id,key_data
 on public.channel_lines for each row execute function public.invalidate_channel_playback();

create table public.channel_health_jobs (
 id uuid primary key default gen_random_uuid(),mode text not null check(mode in ('all','failed','unverified')),
 status text not null default 'running' check(status in ('running','paused','completed','cancelled')),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table public.channel_health_job_items (
 id bigint generated always as identity primary key,job_id uuid not null references public.channel_health_jobs(id) on delete cascade,
 line_id uuid references public.channel_lines(id) on delete set null,config_hash text,
 status text not null default 'pending' check(status in ('pending','checking','done')),
 lease_until timestamptz,attempts integer not null default 0,result jsonb,
 unique(job_id,line_id)
);
create index channel_health_items_pending_idx on public.channel_health_job_items(job_id,status,lease_until);
create index channel_health_items_line_idx on public.channel_health_job_items(line_id);
alter table public.channel_health_jobs enable row level security;
alter table public.channel_health_job_items enable row level security;
revoke all on public.channel_health_jobs,public.channel_health_job_items from public,anon,authenticated;
grant select on public.channel_health_jobs,public.channel_health_job_items to authenticated;
grant all on public.channel_health_jobs,public.channel_health_job_items to service_role;
grant usage,select on sequence public.channel_health_job_items_id_seq to service_role;
create policy "Admin health jobs" on public.channel_health_jobs for select to authenticated using((select public.is_admin()));
create policy "Admin health progress" on public.channel_health_job_items for select to authenticated using((select public.is_admin()));

create function public.request_channel_health_worker() returns void language plpgsql security invoker set search_path='' as $$
begin
 if to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is not null and to_regclass('vault.decrypted_secrets') is not null then
  -- Cron runs as its database owner. A service-role enqueue does not need
  -- permission to read Vault; the recovery tick starts it within a minute.
  if not has_table_privilege(current_user,'vault.decrypted_secrets','select') then return; end if;
  perform net.http_post(url:='https://woggzixprvyjnfjzsglz.supabase.co/functions/v1/stream-health',
   headers:=jsonb_build_object('Content-Type','application/json','x-nca-channel-source-key',
    (select decrypted_secret from vault.decrypted_secrets where name='nca_darkbyte_channel_source_pulse' limit 1)),
   body:='{"action":"work"}'::jsonb,timeout_milliseconds:=50000);
 end if;
end $$;
create function public.start_channel_health_job(p_mode text default 'all') returns uuid
language plpgsql security invoker set search_path='' as $$
declare job uuid;
begin
 if p_mode not in ('all','failed','unverified') then raise exception 'Invalid scan mode'; end if;
 perform pg_advisory_xact_lock(hashtextextended('nca-channel-health-job',0));
 select id into job from public.channel_health_jobs where status in ('running','paused') order by created_at desc limit 1;
 if job is not null then return job; end if;
 insert into public.channel_health_jobs(mode) values(p_mode) returning id into job;
 insert into public.channel_health_job_items(job_id,line_id,config_hash)
  select job,l.id,public.channel_line_config_hash(l.id) from public.channel_lines l join public.channels c on c.id=l.channel_id
  where l.is_active and c.is_active and (p_mode='all' or p_mode='failed' and
   (l.health_status='failed' or l.playback_status='failed' or l.segment_status='failed' or l.manifest_status='invalid')
   or p_mode='unverified' and (l.last_checked_at is null or l.health_status='unknown'));
 if not found then update public.channel_health_jobs set status='completed' where id=job;
 else perform public.request_channel_health_worker(); end if;
 return job;
end $$;
create function public.claim_channel_health_items(p_limit integer default 24)
returns table(item_id bigint,line_id uuid,config_hash text,configuration jsonb)
language plpgsql security invoker set search_path='' as $$
begin
 return query with claimed as (
  select i.id from public.channel_health_job_items i join public.channel_health_jobs j on j.id=i.job_id
  where j.status='running' and (i.status='pending' or i.status='checking' and i.lease_until<now())
  order by i.id for update of i skip locked limit least(greatest(p_limit,1),32)
 ), changed as (
  update public.channel_health_job_items i set status='checking',lease_until=now()+interval '2 minutes',attempts=attempts+1
  from claimed c where i.id=c.id returning i.*
 ) select i.id,i.line_id,i.config_hash,case when l.id is null then null else jsonb_build_object(
  'stream_url',l.stream_url,'stream_type',l.stream_type,'referer',l.referer,'origin',l.origin,'key_id',l.key_id,'key_data',l.key_data) end
 from changed i left join public.channel_lines l on l.id=i.line_id;
end $$;
create function public.finish_channel_health_item(p_item bigint,p_hash text,p_result jsonb) returns boolean
language plpgsql security invoker set search_path='' as $$
declare item public.channel_health_job_items;
begin
 select * into item from public.channel_health_job_items where id=p_item for update;
 if not found or item.status<>'checking' or item.config_hash is distinct from p_hash then return false; end if;
 if item.line_id is not null and public.channel_line_config_hash(item.line_id) is distinct from p_hash then
  update public.channel_health_job_items set status='pending',config_hash=public.channel_line_config_hash(item.line_id),lease_until=null where id=p_item;
  return false;
 end if;
 update public.channel_lines set health_status=p_result->>'health_status',health_http_status=(p_result->>'http_status')::integer,
  health_latency_ms=(p_result->>'latency_ms')::integer,last_checked_at=now(),
  manifest_status=p_result->>'manifest_status',segment_status=p_result->>'segment_status',drm_status=p_result->>'drm_status',
  health_detail=left(p_result->>'detail',180),configuration_status=case
   when p_result->>'drm_status'='missing_configuration' then 'requires_drm'
   when p_result->>'drm_status'='configured' then 'configured'
   when p_result->>'drm_status'='not_required' then 'clear' else configuration_status end
  where id=item.line_id;
 update public.channel_health_job_items set status='done',lease_until=null,result=p_result where id=p_item;
 update public.channel_health_jobs set updated_at=now(),status=case when not exists(
  select from public.channel_health_job_items where job_id=item.job_id and status<>'done') then 'completed' else status end where id=item.job_id;
 return true;
end $$;
create function public.channel_health_job_status() returns jsonb language sql stable security invoker set search_path='' as $$
 select coalesce((select to_jsonb(j)||jsonb_build_object('total',count(i.id),'checked',count(i.id) filter(where i.status='done'),
  'failed',count(i.id) filter(where i.result->>'health_status'='failed'))
 from public.channel_health_jobs j left join public.channel_health_job_items i on i.job_id=j.id
 group by j.id order by j.created_at desc limit 1),'{}'::jsonb);
$$;
revoke all on function public.request_channel_health_worker(),public.start_channel_health_job(text),public.claim_channel_health_items(integer),
 public.finish_channel_health_item(bigint,text,jsonb),public.channel_health_job_status() from public,anon,authenticated;
grant execute on function public.request_channel_health_worker(),public.start_channel_health_job(text),public.claim_channel_health_items(integer),
 public.finish_channel_health_item(bigint,text,jsonb),public.channel_health_job_status() to service_role;
do $schedule$
begin
 if to_regprocedure('cron.schedule(text,text,text)') is not null then
  perform cron.schedule('nca-channel-health-recovery','* * * * *',$job$
   select public.request_channel_health_worker() where exists(select from public.channel_health_jobs where status='running');
  $job$);
 end if;
end $schedule$;
notify pgrst,'reload schema';
