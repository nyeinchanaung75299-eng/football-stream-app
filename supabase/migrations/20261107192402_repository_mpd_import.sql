-- Repository MPD import is private, idempotent and append-only. Metadata can
-- be reachable while an encrypted manifest still needs operator credentials.
alter table public.channel_lines add column configuration_status text not null default 'unverified'
 check(configuration_status in ('unverified','configured','clear','requires_drm'));
create table public.channel_repository_imports (
 fingerprint text primary key check(fingerprint ~ '^[a-f0-9]{64}$'),
 line_id uuid not null references public.channel_lines(id) on delete cascade,
 repository text not null check(repository in ('rohmanabdu/lian','rohmanabdu/deqiaa','darkbyteprojects/iptv_png','Roshavarma/cfy')),
 revision text not null check(revision ~ '^[a-f0-9]{40}$'),
 source_file text not null, imported_at timestamptz not null default now(),
 metadata jsonb not null default '{}'::jsonb
);
create index channel_repository_imports_line_idx on public.channel_repository_imports(line_id);
alter table public.channel_repository_imports enable row level security;
revoke all on public.channel_repository_imports from public,anon,authenticated;
grant select on public.channel_repository_imports to authenticated;
grant all on public.channel_repository_imports to service_role;
create policy "admin repository import provenance" on public.channel_repository_imports
 for select to authenticated using((select public.is_admin()));

create function public.channel_mpd_identity(p_url text) returns text
 language sql immutable strict set search_path='' as $$
 with address as (select split_part(split_part(p_url,'|',1),'#',1) value),
 parts as (select split_part(value,'?',1) base,case when strpos(value,'?')>0 then split_part(value,'?',2) else '' end query from address),
 retained as (select string_agg(item,'&' order by split_part(item,'=',1),item) query from parts,
  lateral unnest(string_to_array(query,'&')) item
  where item<>'' and lower(split_part(item,'=',1)) !~ '^(token|access_token|auth|authorization|sig|signature|expires?|exp|e|hdnts|hdnea|aws_sessionid|x-amz-.+)$')
 select lower(substring(base from '^https?://[^/]+'))||regexp_replace(base,'^https?://[^/]+','')||
  case when retained.query is null then '' else '?'||retained.query end from parts cross join retained;
$$;
revoke all on function public.channel_mpd_identity(text) from public,anon,authenticated;
grant execute on function public.channel_mpd_identity(text) to service_role;

create function public.import_repository_mpds(p_entries jsonb) returns jsonb
 language plpgsql security invoker set search_path='' as $$
declare item jsonb; target uuid; line uuid; identity text; digest text;
 added_channels integer:=0; added_lines integer:=0; skipped integer:=0;
 status text; entry_category text; entry_name text;
begin
 if jsonb_typeof(p_entries)<>'array' or jsonb_array_length(p_entries)>1000 then raise exception 'Invalid import batch'; end if;
 -- Serialize imports so two clicks cannot insert the same manifest twice.
 perform pg_advisory_xact_lock(hashtextextended('nca-repository-mpd-import',0));
 for item in select value from jsonb_array_elements(p_entries) loop
  if item->>'repository' not in ('rohmanabdu/lian','rohmanabdu/deqiaa','darkbyteprojects/iptv_png','Roshavarma/cfy')
    or coalesce(item->>'revision','') !~ '^[a-f0-9]{40}$'
    or coalesce(item->>'stream_url','') !~* '^https?://[^[:space:]]+\.mpd([/?][^[:space:]]*)?$'
    or coalesce(item->>'name','')='' then raise exception 'Invalid MPD entry'; end if;
  identity:=public.channel_mpd_identity(item->>'stream_url');
  digest:=encode(sha256(convert_to(identity,'UTF8')),'hex');
  select cl.id into line from public.channel_lines cl
   where public.channel_mpd_identity(cl.stream_url)=identity order by cl.created_at,cl.id limit 1;
  if line is not null then skipped:=skipped+1; continue; end if;
  entry_name:=left(btrim(item->>'name'),120);entry_category:=left(coalesce(nullif(item->>'category',''),'Sports'),80);
  select c.id into target from public.channels c
   where lower(btrim(c.name))=lower(entry_name) and lower(btrim(c.category))=lower(entry_category)
   order by c.created_at,c.id limit 1;
  if target is null then
   insert into public.channels(name,category,image_url)
    values(entry_name,entry_category,nullif(item->>'image_url','')) returning id into target;
   added_channels:=added_channels+1;
  end if;
  status:=coalesce(item->>'configuration_status','unverified');
  if status not in ('unverified','configured','clear','requires_drm') then raise exception 'Invalid configuration state'; end if;
  insert into public.channel_lines(channel_id,label,stream_type,stream_url,referer,origin,key_id,key_data,sort_order,configuration_status)
   values(target,left(entry_name,100),'dash',item->>'stream_url',nullif(item->>'referer',''),nullif(item->>'origin',''),
    nullif(item->>'key_id',''),nullif(item->>'key_data',''),
    coalesce((select max(sort_order)+1 from public.channel_lines where channel_id=target),0),status) returning id into line;
  insert into public.channel_repository_imports(fingerprint,line_id,repository,revision,source_file,metadata)
   values(digest,line,item->>'repository',item->>'revision',coalesce(item->>'source_file',''),
    jsonb_build_object('drm_type',item->>'drm_type','license_url',item->>'license_url','manifest_status',item->>'manifest_status'));
  added_lines:=added_lines+1;
 end loop;
 return jsonb_build_object('added_channels',added_channels,'added_lines',added_lines,'skipped_existing',skipped);
end $$;
revoke all on function public.import_repository_mpds(jsonb) from public,anon,authenticated;
grant execute on function public.import_repository_mpds(jsonb) to service_role;

-- An HTTP-successful encrypted MPD without credentials must not become READY
-- through the channel endpoint or through a match linked to that channel.
do $$
declare definition text;
begin
 definition:=pg_get_functiondef('public.get_channel_metadata_for_gateway(uuid,text)'::regprocedure);
 definition:=replace(definition,'l.channel_id = c.id and l.is_active',
  'l.channel_id = c.id and l.is_active and l.configuration_status <> ''requires_drm''');
 execute definition;
 definition:=pg_get_functiondef('public.get_stream_metadata_for_gateway(uuid,text)'::regprocedure);
 definition:=replace(definition,'cl.is_active and c.is_active','cl.is_active and c.is_active and cl.configuration_status <> ''requires_drm''');
 execute definition;
end $$;
comment on column public.channel_lines.configuration_status is 'Manifest/configuration audit; HTTP reachability is separate from decoded video playback.';
notify pgrst,'reload schema';
