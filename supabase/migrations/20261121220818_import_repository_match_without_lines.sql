-- A reviewed fixture may be published before any native media is available.
-- Stream validation, Admin authorization, serialization and dedup stay intact.
do $$
declare definition text; gate text:=$gate$if jsonb_array_length(eligible)=0 then
  return jsonb_build_object('ok',false,'code','no_importable_lines','skipped_lines',skipped); end if;$gate$;
begin
 definition:=pg_get_functiondef('public.publish_repository_match(text,timestamptz)'::regprocedure);
 if strpos(definition,gate)=0 then raise exception 'Repository metadata-only import hook unavailable';end if;
 definition:=replace(definition,gate,'-- Zero eligible lines is a metadata-only fixture; Viewer remains NOT READY.');
 definition:=replace(definition,'insert into public.repository_match_imports(entry_id,match_id)',
  $restore$delete from private.deleted_match_fingerprints where fingerprint=encode(sha256(convert_to('repository:'||p_entry_id,'UTF8')),'hex');
 insert into public.repository_match_imports(entry_id,match_id)$restore$);
 execute definition;
end $$;
notify pgrst,'reload schema';
