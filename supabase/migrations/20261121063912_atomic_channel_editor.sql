-- A channel edit is one RLS-protected transaction. Metadata-only edits do not
-- reactivate lines, replace independent Origin headers, or clear probe results.
create or replace function public.save_channel_editor(
  p_channel_id uuid, p_fields jsonb, p_lines jsonb,
  p_removed_ids uuid[] default '{}'::uuid[]
) returns uuid
language plpgsql security invoker set search_path = ''
as $$
declare
  v_channel_id uuid := p_channel_id;
  item jsonb;
  previous public.channel_lines%rowtype;
  edited public.channel_lines%rowtype;
  line_id uuid;
  seen uuid[] := '{}'::uuid[];
  playback_changed boolean;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_fields) is distinct from 'object'
    or jsonb_typeof(p_lines) is distinct from 'array'
    or jsonb_array_length(p_lines) not between 1 and 100 then
    raise exception 'Invalid channel edit';
  end if;
  if v_channel_id is null then
    insert into public.channels(name, category, image_url, sort_order, is_active, category_locked, image_locked)
    values (btrim(p_fields->>'name'), btrim(p_fields->>'category'), nullif(p_fields->>'image_url',''),
      coalesce((p_fields->>'sort_order')::integer,0), coalesce((p_fields->>'is_active')::boolean,false),
      true, coalesce((p_fields->>'image_locked')::boolean,false)) returning id into v_channel_id;
  else
    perform 1 from public.channels c where c.id = v_channel_id for update;
    if not found then raise exception 'Channel no longer exists or access was denied'; end if;
    update public.channels c set
      name = btrim(p_fields->>'name'), category = btrim(p_fields->>'category'),
      category_locked = true, image_url = nullif(p_fields->>'image_url',''),
      image_locked = case when p_fields ? 'image_locked' then (p_fields->>'image_locked')::boolean else c.image_locked end,
      sort_order = coalesce((p_fields->>'sort_order')::integer,0),
      is_active = coalesce((p_fields->>'is_active')::boolean,c.is_active)
    where c.id = v_channel_id;
  end if;
  for item in select value from jsonb_array_elements(p_lines) loop
    line_id := nullif(item->>'id','')::uuid;
    if line_id is not null then
      if line_id = any(seen) or line_id = any(p_removed_ids) then raise exception 'Duplicate channel line'; end if;
      select * into previous from public.channel_lines l where l.id = line_id and l.channel_id = v_channel_id for update;
      if not found then raise exception 'A channel line changed or was deleted. Reload before saving'; end if;
      seen := array_append(seen,line_id);
      -- An untouched line is represented by its ID only. Preserve every field.
      if item - 'id' = '{}'::jsonb then continue; end if;
      edited := jsonb_populate_record(previous, item - array['id','channel_id','is_active','health_status','last_checked_at','health_http_status','health_latency_ms']);
      playback_changed := row(previous.stream_url,previous.referer,previous.origin,previous.key_id,previous.key_data,previous.stream_type)
        is distinct from row(edited.stream_url,edited.referer,edited.origin,edited.key_id,edited.key_data,edited.stream_type);
      update public.channel_lines l set label=edited.label, stream_url=edited.stream_url,
        stream_type=edited.stream_type, referer=edited.referer, origin=edited.origin,
        key_id=edited.key_id,key_data=edited.key_data,sort_order=edited.sort_order,
        configuration_status=case when playback_changed then edited.configuration_status else l.configuration_status end,
        health_status=case when playback_changed then 'unknown' else l.health_status end,
        health_latency_ms=case when playback_changed then null else l.health_latency_ms end,
        health_http_status=case when playback_changed then null else l.health_http_status end,
        last_checked_at=case when playback_changed then null else l.last_checked_at end
      where l.id=line_id;
    else
      insert into public.channel_lines(channel_id,label,stream_url,stream_type,referer,origin,key_id,key_data,sort_order,configuration_status)
      values (v_channel_id,item->>'label',item->>'stream_url',coalesce(item->>'stream_type','auto'),nullif(item->>'referer',''),
        nullif(item->>'origin',''),nullif(item->>'key_id',''),nullif(item->>'key_data',''),coalesce((item->>'sort_order')::integer,0),
        coalesce(item->>'configuration_status','unverified'));
    end if;
  end loop;
  -- Only IDs explicitly removed by this edit may be deleted. Concurrently
  -- added lines and remotely deleted lines must never be recreated.
  delete from public.channel_lines l where l.channel_id=v_channel_id and l.id=any(p_removed_ids);
  return v_channel_id;
end;
$$;
revoke all on function public.save_channel_editor(uuid,jsonb,jsonb,uuid[]) from public,anon;
grant execute on function public.save_channel_editor(uuid,jsonb,jsonb,uuid[]) to authenticated;
notify pgrst, 'reload schema';
