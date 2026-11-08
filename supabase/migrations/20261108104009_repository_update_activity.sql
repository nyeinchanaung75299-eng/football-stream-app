-- Keep an Admin-readable change summary, never old/new URLs or DRM secrets.
do $$
declare definition text;
begin
 definition:=pg_get_functiondef('public.refresh_repository_channel_imports(jsonb)'::regprocedure);
 definition:=replace(definition,'r.*,l.stream_url,c.name','r.*,l.stream_url,l.referer,l.origin,l.key_id,l.key_data,l.configuration_status,c.name');
 definition:=replace(definition,'if found then changes:=changes+1; end if;', $activity$
  if found then
   changes:=changes+1;
   update public.channel_repository_imports set metadata=metadata||jsonb_build_object('last_updated_at',now(),
    'changed_fields',to_jsonb(array_remove(array[
     case when imported.stream_url is distinct from item->>'stream_url' then 'URL' end,
     case when row(imported.referer,imported.origin) is distinct from row(nullif(item->>'referer',''),nullif(item->>'origin','')) then 'Headers' end,
     case when imported.key_id is distinct from nullif(item->>'key_id','') then 'Key ID' end,
     case when imported.key_data is distinct from nullif(item->>'key_data','') then 'Key' end,
     case when imported.configuration_status is distinct from item->>'configuration_status' then 'Configuration' end
    ]::text[],null))) where fingerprint=imported.fingerprint;
  end if;
 $activity$);
 execute definition;
end $$;
notify pgrst,'reload schema';
