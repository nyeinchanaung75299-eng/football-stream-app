-- Keep the strict importer API intact. The scheduled updater can reconcile
-- observed repositories while leaving unavailable repositories untouched.
do $$
declare definition text;
begin
 definition:=pg_get_functiondef('public.refresh_repository_channel_imports(jsonb)'::regprocedure);
 if strpos(definition,'for update of r,l loop')=0 or strpos(definition,'missing integer:=0;')=0 then
  raise exception 'Repository update hooks unavailable';
 end if;
 definition:=replace(definition,'public.refresh_repository_channel_imports(p_entries jsonb)',
  'public.refresh_available_repository_channel_imports(p_entries jsonb, p_unavailable_repositories jsonb)');
 definition:=replace(definition,'missing integer:=0;','missing integer:=0; unavailable integer:=0;');
 definition:=replace(definition,'begin', $guard$begin
 if jsonb_typeof(p_unavailable_repositories) is distinct from 'array'
  or jsonb_array_length(p_unavailable_repositories)>4
  or exists(select from jsonb_array_elements_text(p_unavailable_repositories) r
    where r is null or r not in ('rohmanabdu/lian','rohmanabdu/deqiaa','darkbyteprojects/iptv_png','Roshavarma/cfy')) then
  raise exception 'Invalid unavailable repository list';
 end if;
 if jsonb_typeof(p_entries) is distinct from 'array' then raise exception 'Invalid repository snapshot'; end if;
 if exists(select from jsonb_array_elements(p_entries) e
   where e->>'repository' in (select jsonb_array_elements_text(p_unavailable_repositories))) then
  raise exception 'Unavailable repository contains snapshot entries';
 end if;
$guard$);
 definition:=replace(definition,'for update of r,l loop', $guard$for update of r,l loop
  if imported.repository in (select jsonb_array_elements_text(p_unavailable_repositories)) then
   unavailable:=unavailable+1;
   continue;
  end if;
$guard$);
 definition:=replace(definition,'''missing_or_ambiguous'',missing)',
  '''missing_or_ambiguous'',missing,''unavailable_imports'',unavailable)');
 execute definition;
end $$;
revoke all on function public.refresh_available_repository_channel_imports(jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.refresh_available_repository_channel_imports(jsonb,jsonb) to service_role;
notify pgrst,'reload schema';
