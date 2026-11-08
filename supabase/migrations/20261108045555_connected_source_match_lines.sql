-- A source line can follow its upstream directly on a match, without
-- publishing an extra My Channels entry or overwriting manual match lines.
create table public.channel_source_match_links (
 stream_link_id uuid primary key references public.stream_links(id) on delete cascade,
 match_id uuid not null references public.matches(id) on delete cascade,
 entry_id text not null references public.channel_source_catalog(id),
 source_line_id text not null,
 source_missing boolean not null default false,
 was_active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(match_id,entry_id,source_line_id)
);
create index channel_source_match_links_entry_idx on public.channel_source_match_links(entry_id);
alter table public.channel_source_match_links enable row level security;
revoke all on public.channel_source_match_links from public,anon,authenticated;
grant all on public.channel_source_match_links to service_role;
grant select on public.channel_source_match_links to authenticated;
create policy "admin read connected match lines" on public.channel_source_match_links
 for select to authenticated using((select public.is_admin()));

create function public.add_connected_source_line_to_match(p_entry_id text,p_source_line_id text,p_match_id uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare entry public.channel_source_catalog; config jsonb; link_id uuid; position integer;
begin
 select * into entry from public.channel_source_catalog where id=p_entry_id and is_present for update;
 if not found then raise exception 'Source entry unavailable'; end if;
 perform 1 from public.matches where id=p_match_id and is_active and deleted_at is null for update;
 if not found then raise exception 'Match unavailable'; end if;
 select value into config from jsonb_array_elements(entry.streams) where value->>'id'=p_source_line_id;
 if config is null or coalesce(config->>'stream_url','') !~ '^https?://' then raise exception 'Source line unavailable'; end if;
 select stream_link_id into link_id from public.channel_source_match_links
  where match_id=p_match_id and entry_id=p_entry_id and source_line_id=p_source_line_id;
 if link_id is not null then return jsonb_build_object('stream_link_id',link_id,'already_exists',true); end if;
 -- An identical manual or channel-linked line is kept as its own authority.
 select sl.id into link_id from public.stream_links sl left join public.channel_lines cl on cl.id=sl.channel_line_id
  where sl.match_id=p_match_id and not coalesce(sl.use_webview,false)
   and coalesce(cl.stream_url,sl.stream_url)=config->>'stream_url'
   and coalesce(cl.stream_type,sl.stream_type)=coalesce(config->>'stream_type','auto')
   and coalesce(coalesce(cl.key_id,sl.key_id),'')=coalesce(config->>'key_id','')
   and coalesce(coalesce(cl.key_data,sl.key_data),'')=coalesce(config->>'key_data','')
   and coalesce(coalesce(cl.referer,sl.referer),'')=coalesce(config->>'referer','')
   and coalesce(coalesce(cl.origin,sl.origin),'')=coalesce(config->>'origin','')
  order by sl.created_at limit 1;
 if link_id is not null then return jsonb_build_object('stream_link_id',link_id,'already_exists',true); end if;
 select coalesce(max(sort_order),-1)+1 into position from public.stream_links where match_id=p_match_id;
 insert into public.stream_links(match_id,label,resolution,stream_type,stream_url,referer,origin,key_id,key_data,
  use_webview,is_active,send_notification,sort_order)
 values(p_match_id,left(entry.name||' • '||coalesce(config->>'label','Line'),160),left(coalesce(config->>'label','Source'),90),
  coalesce(config->>'stream_type','auto'),config->>'stream_url',nullif(config->>'referer',''),nullif(config->>'origin',''),
  nullif(config->>'key_id',''),nullif(config->>'key_data',''),false,true,false,position) returning id into link_id;
 insert into public.channel_source_match_links(stream_link_id,match_id,entry_id,source_line_id)
  values(link_id,p_match_id,p_entry_id,p_source_line_id);
 return jsonb_build_object('stream_link_id',link_id,'already_exists',false);
end $$;

create function public.sync_connected_source_match_lines(p_source text)
returns integer language plpgsql security invoker set search_path='' as $$
declare item record; config jsonb; count_changed integer:=0;
begin
 for item in select r.*,e.streams,e.is_present from public.channel_source_match_links r
  join public.channel_source_catalog e on e.id=r.entry_id where e.source_id=p_source for update of r loop
  config:=null;
  if item.is_present then
   select value into config from jsonb_array_elements(item.streams) where value->>'id'=item.source_line_id;
  end if;
  if config is null then
   if not item.source_missing then
    update public.channel_source_match_links set source_missing=true,
     was_active=(select is_active from public.stream_links where id=item.stream_link_id) where stream_link_id=item.stream_link_id;
    update public.stream_links set is_active=false where id=item.stream_link_id;
   end if;
  else
   update public.stream_links sl set stream_url=config->>'stream_url',stream_type=coalesce(config->>'stream_type','auto'),
    referer=nullif(config->>'referer',''),origin=nullif(config->>'origin',''),
    key_id=nullif(config->>'key_id',''),key_data=nullif(config->>'key_data',''),
    is_active=case when item.source_missing then item.was_active else sl.is_active end,health_status='unknown'
    where sl.id=item.stream_link_id and (item.source_missing or
     row(sl.stream_url,sl.stream_type,sl.referer,sl.origin,sl.key_id,sl.key_data) is distinct from
     row(config->>'stream_url',coalesce(config->>'stream_type','auto'),nullif(config->>'referer',''),nullif(config->>'origin',''),nullif(config->>'key_id',''),nullif(config->>'key_data','')));
   if found then count_changed:=count_changed+1; end if;
   update public.channel_source_match_links set source_missing=false where stream_link_id=item.stream_link_id and source_missing;
  end if;
 end loop;
 return count_changed;
end $$;
revoke all on function public.add_connected_source_line_to_match(text,text,uuid),public.sync_connected_source_match_lines(text)
 from public,anon,authenticated;
grant execute on function public.add_connected_source_line_to_match(text,text,uuid),public.sync_connected_source_match_lines(text) to service_role;
do $$
declare definition text;
begin
 definition:=pg_get_functiondef('public.commit_connected_channel_source_sync(text,uuid,text,jsonb,boolean,boolean)'::regprocedure);
 if strpos(definition,'update public.channel_source_state set')=0 then raise exception 'Source sync hook unavailable'; end if;
 definition:=replace(definition,'update public.channel_source_state set',
  'perform public.sync_connected_source_match_lines(p_source); update public.channel_source_state set');
 execute definition;
end $$;
notify pgrst,'reload schema';
