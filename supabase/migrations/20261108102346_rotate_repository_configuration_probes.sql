-- Only a configuration actually probed advances its repair cursor. Otherwise
-- the first failing twelve entries would starve the remaining pending lines.
do $$
declare definition text;
begin
 definition:=pg_get_functiondef('public.refresh_repository_channel_imports(jsonb)'::regprocedure);
 definition:=replace(definition,
  'jsonb_build_object(''configuration_pending'',true,''last_source_check'',now())',
  'jsonb_build_object(''configuration_pending'',true,''last_source_check'',now()) || case when item->>''probe_checked''=''true'' then jsonb_build_object(''last_config_probe'',now()) else ''{}''::jsonb end');
 definition:=replace(definition,
  '''configuration_pending'',false,''last_source_check'',now())',
  '''configuration_pending'',false,''last_source_check'',now()) || case when item->>''probe_checked''=''true'' then jsonb_build_object(''last_config_probe'',now()) else ''{}''::jsonb end');
 execute definition;
end $$;
notify pgrst,'reload schema';
