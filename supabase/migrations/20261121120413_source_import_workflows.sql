-- Public-schema metadata is Admin-only under RLS. No new anonymous source API.
create table public.imported_source_lines(
 link_id uuid primary key references public.stream_links(id) on delete cascade,
 match_id uuid not null references public.matches(id) on delete cascade,
 source text not null check(source in ('soco','yyzb','cola','fawa','arena','roxie','crichd','playz')),
 room jsonb not null check(jsonb_typeof(room)='object' and octet_length(room::text)<=8192),
 logical_key text not null,config_hash text not null,selector jsonb not null default '{}',refresh_lease uuid,
 last_resolved_at timestamptz not null default now(),last_attempt_at timestamptz,
 unique(match_id,source,logical_key)
);
create table public.source_import_requests(
 id uuid primary key,owner_id uuid not null references auth.users(id) on delete cascade,
 match_id uuid not null references public.matches(id) on delete cascade,
 payload_hash text not null,response jsonb not null,created_at timestamptz not null default now()
);
alter table public.imported_source_lines enable row level security;
alter table public.source_import_requests enable row level security;
revoke all on public.imported_source_lines,public.source_import_requests from public,anon,authenticated;
grant select,insert,update,delete on public.imported_source_lines,public.source_import_requests to authenticated;
grant all on public.imported_source_lines,public.source_import_requests to service_role;
create policy "admin source provenance" on public.imported_source_lines for all to authenticated
 using((select public.is_admin())) with check((select public.is_admin()));
create policy "admin import requests" on public.source_import_requests for all to authenticated
 using((select public.is_admin())) with check((select public.is_admin()));

create function public.stream_configuration_hash(p_config jsonb) returns text
 language sql immutable security invoker set search_path='' as $$
 select encode(sha256(convert_to(jsonb_build_array(
 btrim(coalesce(p_config->>'stream_url',p_config->>'url','')),coalesce(p_config->>'stream_type','auto'),
 btrim(coalesce(p_config->>'referer','')),btrim(coalesce(p_config->>'origin','')),
 lower(replace(btrim(coalesce(p_config->>'key_id','')),'-','')),lower(replace(btrim(coalesce(p_config->>'key_data','')),'-',''))
 )::text,'UTF8')),'hex');
$$;
revoke all on function public.stream_configuration_hash(jsonb) from public,anon;
grant execute on function public.stream_configuration_hash(jsonb) to authenticated,service_role;

create function public.import_match_source_lines(p_match_id uuid,p_lines jsonb,p_source text,p_room jsonb,p_request_id uuid)
 returns jsonb language plpgsql security invoker set search_path='' as $$
declare item jsonb; config jsonb; line public.stream_links%rowtype; existing public.source_import_requests%rowtype;
 room jsonb; logical text; fingerprint text; payload_hash text; saved uuid; ids jsonb:='[]'; changed boolean; result jsonb;
begin
 if auth.uid() is null or not public.is_admin() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_request_id is null or jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) not between 1 and 50
 or p_source is null or p_source not in ('soco','yyzb','cola','fawa','arena','roxie','crichd','playz') then raise exception 'Invalid source selection'; end if;
 room:=coalesce(p_room,'{}'::jsonb);
 if jsonb_typeof(room)<>'object' or octet_length(room::text)>8192 then raise exception 'Invalid source identity'; end if;
 -- Keep only resolver identity metadata, never supplied cookies/auth headers.
 select coalesce(jsonb_object_agg(key,value),'{}') into room from jsonb_each(room)
 where key in ('room_num','schedule_id','page_url','watch_url','source_id');
 payload_hash:=encode(sha256(convert_to(jsonb_build_array(p_match_id,p_source,room,p_lines)::text,'UTF8')),'hex');
 perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,0));
 select * into existing from public.source_import_requests where id=p_request_id;
 if found then
  if existing.owner_id<>auth.uid() or existing.payload_hash<>payload_hash then raise exception 'Import request changed; review selection again'; end if;
  return existing.response;
 end if;
 perform 1 from public.matches m where m.id=p_match_id and m.is_active and m.deleted_at is null for update;
 if not found then raise exception 'Match was removed or hidden. Choose an active match'; end if;
 for item in select value from jsonb_array_elements(p_lines) loop
  config:=jsonb_build_object('stream_url',btrim(coalesce(item->>'stream_url',item->>'url','')),
   'stream_type',coalesce(item->>'stream_type','auto'),'referer',nullif(btrim(item->>'referer'),''),
   'origin',nullif(btrim(item->>'origin'),''),'key_id',nullif(lower(replace(btrim(item->>'key_id'),'-','')),''),
   'key_data',nullif(lower(replace(btrim(item->>'key_data'),'-','')),''));
  if config->>'stream_url' !~ '^https?://[^[:space:]/@]+([/?#][^[:space:]]*)?$'
   or octet_length(config->>'stream_url')>8192
   or config->>'stream_type' not in ('auto','hls','dash','flv','mp4') then raise exception 'Invalid direct stream URL'; end if;
  for fingerprint in select value from jsonb_each_text(config) where key in ('referer','origin') and value is not null loop
   if fingerprint !~ '^https?://[^[:space:]/@]+([/?#][^[:space:]]*)?$' or length(fingerprint)>2048 then raise exception 'Invalid Referer or Origin'; end if;
  end loop;
  if (config->>'key_id' is null)<>(config->>'key_data' is null) or
   (config->>'key_id' is not null and (config->>'stream_type'<>'dash' or config->>'key_id' !~ '^[a-f0-9]{32}$' or config->>'key_data' !~ '^[a-f0-9]{32}$')) then
   raise exception 'DASH requires a complete valid key pair'; end if;
  fingerprint:=public.stream_configuration_hash(config);
  logical:=encode(sha256(convert_to(jsonb_build_array(room,coalesce(item->>'source_line_id',item->>'label','Stream'),
   config->>'stream_type',coalesce(item->>'resolution','Auto'),config->>'referer',config->>'origin',config->>'key_id')::text,'UTF8')),'hex');
  saved:=null;
  select l.* into line from public.imported_source_lines r join public.stream_links l on l.id=r.link_id
   where r.match_id=p_match_id and r.source=p_source and r.logical_key=logical for update of l;
  if found then saved:=line.id; end if;
  if saved is null then
   select l.* into line from public.stream_links l where l.match_id=p_match_id and l.channel_line_id is null and not coalesce(l.use_webview,false)
    and not exists(select from public.channel_source_match_links c where c.stream_link_id=l.id)
    and public.stream_configuration_hash(to_jsonb(l))=fingerprint order by l.created_at,l.id limit 1 for update;
   if found then saved:=line.id; end if;
  end if;
  -- Migrate a unique legacy provider line without guessing by URL alone.
  if saved is null and (select count(*) from public.stream_links l where l.match_id=p_match_id and l.channel_line_id is null and l.label=item->>'label'
   and l.stream_type=config->>'stream_type' and coalesce(l.referer,'')=coalesce(config->>'referer','') and coalesce(l.origin,'')=coalesce(config->>'origin','')
   and coalesce(l.key_id,'')=coalesce(config->>'key_id','') and coalesce(l.key_data,'')=coalesce(config->>'key_data','')
   and not coalesce(l.use_webview,false) and not exists(select from public.imported_source_lines r where r.link_id=l.id)
   and not exists(select from public.channel_source_match_links c where c.stream_link_id=l.id))=1 then
   select l.* into line from public.stream_links l where l.match_id=p_match_id and l.channel_line_id is null and l.label=item->>'label'
    and l.stream_type=config->>'stream_type' and coalesce(l.referer,'')=coalesce(config->>'referer','') and coalesce(l.origin,'')=coalesce(config->>'origin','')
    and coalesce(l.key_id,'')=coalesce(config->>'key_id','') and coalesce(l.key_data,'')=coalesce(config->>'key_data','')
    and not coalesce(l.use_webview,false) and not exists(select from public.imported_source_lines r where r.link_id=l.id)
    and not exists(select from public.channel_source_match_links c where c.stream_link_id=l.id) for update;
   saved:=line.id;
  end if;
  if saved is null then
   insert into public.stream_links(match_id,label,resolution,stream_type,stream_url,referer,origin,key_id,key_data,is_active,expires_at)
   values(p_match_id,left(coalesce(nullif(item->>'label',''),'Stream'),180),left(coalesce(item->>'resolution','Auto'),80),
    config->>'stream_type',config->>'stream_url',config->>'referer',config->>'origin',config->>'key_id',config->>'key_data',true,
    nullif(item->>'expires_at','')::timestamptz) returning id into saved;
  else
   changed:=public.stream_configuration_hash(to_jsonb(line))<>fingerprint;
   update public.stream_links l set stream_url=config->>'stream_url',stream_type=config->>'stream_type',referer=config->>'referer',
    origin=config->>'origin',key_id=config->>'key_id',key_data=config->>'key_data',is_active=true,
    expires_at=nullif(item->>'expires_at','')::timestamptz,
    health_status=case when changed then 'unknown' else l.health_status end,
    last_checked_at=case when changed then null else l.last_checked_at end
   where id=saved;
  end if;
  -- Exact duplicates retain existing provenance. A distinct configuration can
  -- never overwrite a working row just because its URL happens to be equal.
  insert into public.imported_source_lines(link_id,match_id,source,room,logical_key,config_hash,selector)
   values(saved,p_match_id,p_source,room,logical,fingerprint,jsonb_build_object('id',item->>'source_line_id','label',item->>'source_label','resolution',item->>'resolution','stream_type',item->>'stream_type'))
   on conflict(link_id) do update set last_resolved_at=now(),config_hash=excluded.config_hash;
  ids:=ids||jsonb_build_array(jsonb_build_object('id',saved,'label',item->>'label'));
 end loop;
 result:=jsonb_build_object('ok',true,'match_id',p_match_id,'lines',ids,'saved_count',jsonb_array_length(ids));
 insert into public.source_import_requests(id,owner_id,match_id,payload_hash,response) values(p_request_id,auth.uid(),p_match_id,payload_hash,result);
 return result;
end $$;
revoke all on function public.import_match_source_lines(uuid,jsonb,text,jsonb,uuid) from public,anon;
grant execute on function public.import_match_source_lines(uuid,jsonb,text,jsonb,uuid) to authenticated;

-- Opaque suppression fingerprints contain no names, URLs, line settings or
-- recoverable match records. They prevent background synchronizers re-adding a
-- record whose match and dependent links the Admin permanently deleted.
create table private.deleted_match_fingerprints(fingerprint text primary key,created_at timestamptz not null default now());
alter table private.deleted_match_fingerprints enable row level security;
revoke all on private.deleted_match_fingerprints from public,anon,authenticated;
create function private.prevent_deleted_match_resurrection() returns trigger
 language plpgsql security definer set search_path='' as $$
declare v_fingerprint text;
begin
 if new.external_fixture_id is null then return new; end if;
 v_fingerprint:=encode(sha256(convert_to('fixture:'||new.external_fixture_id::text,'UTF8')),'hex');
 if exists(select from private.deleted_match_fingerprints d where d.fingerprint=v_fingerprint) then
  raise exception 'This fixture was permanently deleted'; end if;
 return new;
end $$;
create trigger prevent_deleted_match_resurrection before insert or update of external_fixture_id on public.matches
 for each row execute function private.prevent_deleted_match_resurrection();
create function private.remember_permanent_match_deletion() returns trigger
 language plpgsql security definer set search_path='' as $$
begin
 if old.external_fixture_id is not null then
  insert into private.deleted_match_fingerprints(fingerprint)
  values(encode(sha256(convert_to('fixture:'||old.external_fixture_id::text,'UTF8')),'hex')) on conflict do nothing;
 end if;
 insert into private.deleted_match_fingerprints(fingerprint)
 select encode(sha256(convert_to('repository:'||r.entry_id,'UTF8')),'hex') from public.repository_match_imports r where r.match_id=old.id on conflict do nothing;
 return old;
end $$;
create trigger remember_permanent_match_deletion before delete on public.matches
 for each row execute function private.remember_permanent_match_deletion();
revoke all on function private.prevent_deleted_match_resurrection(),private.remember_permanent_match_deletion() from public,anon,authenticated;
create function public.permanently_delete_match(p_match_id uuid) returns jsonb
 language plpgsql security invoker set search_path='' as $$
declare saved uuid;
begin
 if auth.uid() is null or not public.is_admin() then raise exception 'Admin access required' using errcode='42501'; end if;
 delete from public.matches where id=p_match_id returning id into saved;
 if saved is null then raise exception 'Match was already removed or access was denied'; end if;
 return jsonb_build_object('deleted',true,'match_id',saved);
end $$;
revoke all on function public.permanently_delete_match(uuid) from public,anon;
grant execute on function public.permanently_delete_match(uuid) to authenticated;
notify pgrst,'reload schema';

create function private.prevent_deleted_repository_relink() returns trigger
 language plpgsql security definer set search_path='' as $$
begin
 if exists(select from private.deleted_match_fingerprints d where d.fingerprint=encode(sha256(convert_to('repository:'||new.entry_id,'UTF8')),'hex')) then
  raise exception 'This repository match was permanently deleted'; end if;
 return new;
end $$;
create trigger prevent_deleted_repository_relink before insert or update on public.repository_match_imports
 for each row execute function private.prevent_deleted_repository_relink();
revoke all on function private.prevent_deleted_repository_relink() from public,anon,authenticated;

-- Only the existing backend-secret holder may lease/refresh an imported line.
-- A refresh updates an existing active row; it can never insert or resurrect it.
create function public.claim_imported_source_refresh(p_link_id uuid,p_expected_hash text,p_secret text)
 returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if not exists(select from private.gateway_secrets s where s.name='cloudflare_playback' and s.secret_hash=encode(extensions.digest(coalesce(p_secret,''),'sha256'),'hex')) then raise exception 'unauthorized gateway' using errcode='42501'; end if;
 update public.imported_source_lines r set last_attempt_at=now(),refresh_lease=gen_random_uuid()
 from public.stream_links l,public.matches m
 where r.link_id=p_link_id and l.id=r.link_id and m.id=r.match_id and l.is_active and m.is_active and m.is_featured and m.publish_state='published' and m.deleted_at is null
  and r.source<>'playz' and r.config_hash=p_expected_hash and public.stream_configuration_hash(to_jsonb(l))=p_expected_hash
  and (r.last_attempt_at is null or r.last_attempt_at<now()-interval '2 minutes')
 returning to_jsonb(r) into result;
 return result;
end $$;
create function public.apply_imported_source_refresh(p_link_id uuid,p_expected_hash text,p_lease uuid,p_config jsonb,p_secret text)
 returns boolean language plpgsql security definer set search_path='' as $$
declare r public.imported_source_lines; l public.stream_links; u text; typ text; kid text; kdata text; changed boolean;
begin
 if not exists(select from private.gateway_secrets s where s.name='cloudflare_playback' and s.secret_hash=encode(extensions.digest(coalesce(p_secret,''),'sha256'),'hex')) then raise exception 'unauthorized gateway' using errcode='42501'; end if;
 select sl.* into l from public.stream_links sl join public.matches m on m.id=sl.match_id
 where sl.id=p_link_id and sl.is_active and m.is_active and m.is_featured and m.publish_state='published' and m.deleted_at is null for update of sl;
 if not found then return false; end if;
 select * into r from public.imported_source_lines where link_id=p_link_id and refresh_lease=p_lease and config_hash=p_expected_hash and last_attempt_at>now()-interval '2 minutes' for update;
 if not found or public.stream_configuration_hash(to_jsonb(l))<>p_expected_hash then return false; end if;
 u:=coalesce(p_config->>'url',p_config->>'stream_url');typ:=p_config->>'stream_type';
 if u is null or typ is null or u !~ '^https?://[^[:space:]/@]+([/?#][^[:space:]]*)?$' or length(u)>8192 or typ<>l.stream_type then raise exception 'Invalid renewed configuration'; end if;
 if exists(select from jsonb_each_text(p_config) where key in ('referer','origin') and nullif(value,'') is not null and (value !~ '^https?://[^[:space:]/@]+([/?#][^[:space:]]*)?$' or length(value)>2048)) then raise exception 'Invalid renewed headers'; end if;
 kid:=case when typ='dash' then case when p_config?'key_id' then nullif(lower(replace(btrim(p_config->>'key_id'),'-','')),'') else l.key_id end else null end;
 kdata:=case when typ='dash' then case when p_config?'key_data' then nullif(lower(replace(btrim(p_config->>'key_data'),'-','')),'') else l.key_data end else null end;
 if (kid is null)<>(kdata is null) or (kid is not null and (kid !~ '^[a-f0-9]{32}$' or kdata !~ '^[a-f0-9]{32}$')) then raise exception 'Invalid renewed key pair'; end if;
 changed:=public.stream_configuration_hash(jsonb_build_object('url',u,'stream_type',typ,'referer',p_config->>'referer','origin',p_config->>'origin','key_id',kid,'key_data',kdata))<>p_expected_hash;
 update public.stream_links set stream_url=u,referer=nullif(p_config->>'referer',''),origin=nullif(p_config->>'origin',''),
 key_id=kid,key_data=kdata,
 expires_at=nullif(p_config->>'expires_at','')::timestamptz,health_status=case when changed then 'unknown' else l.health_status end,last_checked_at=case when changed then null else l.last_checked_at end
 where id=p_link_id returning * into l;
 update public.imported_source_lines set config_hash=public.stream_configuration_hash(to_jsonb(l)),last_resolved_at=now(),refresh_lease=null where link_id=p_link_id;
 return true;
end $$;
revoke all on function public.claim_imported_source_refresh(uuid,text,text),public.apply_imported_source_refresh(uuid,text,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.claim_imported_source_refresh(uuid,text,text),public.apply_imported_source_refresh(uuid,text,uuid,jsonb,text) to anon,authenticated;

-- Preserve the existing channel-line overlay and public eligibility rules.
-- Provenance is returned solely within the existing secret-gated metadata RPC.
do $attach$
declare definition text;
begin
 definition:=pg_get_functiondef('public.get_stream_metadata_for_gateway(uuid,text)'::regprocedure);
 if strpos(definition,'return jsonb_build_object(''match_valid'',true,''streams'',streams);')=0 then raise exception 'Gateway metadata definition changed; review before applying'; end if;
 definition:=replace(definition,'return jsonb_build_object(''match_valid'',true,''streams'',streams);',
 $replacement$return jsonb_build_object('match_valid',true,'streams',streams,'imported_sources',coalesce((
  select jsonb_agg(to_jsonb(r)||jsonb_build_object('expires_at',l.expires_at)) from public.imported_source_lines r
   join public.stream_links l on l.id=r.link_id where r.match_id=p_match_id and l.is_active
 ),'[]'::jsonb));$replacement$);
 execute definition;
end $attach$;
notify pgrst,'reload schema';

-- Manual playback changes detach automatic provenance. Provider batch imports
-- reattach their selected identity in the same transaction after this trigger.
create function private.detach_manually_edited_source() returns trigger
 language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is not null and public.stream_configuration_hash(to_jsonb(old))<>public.stream_configuration_hash(to_jsonb(new)) then
  delete from public.imported_source_lines where link_id=new.id;
 end if;
 return new;
end $$;
create trigger detach_manually_edited_source after update on public.stream_links
 for each row execute function private.detach_manually_edited_source();
revoke all on function private.detach_manually_edited_source() from public,anon,authenticated;
