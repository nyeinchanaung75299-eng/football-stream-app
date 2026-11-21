-- Retrying an already-committed deletion is success, after Admin verification.
-- A row that remains visible but cannot be deleted must still fail closed.
create or replace function public.permanently_delete_match(p_match_id uuid) returns jsonb
 language plpgsql security invoker set search_path='' as $$
declare saved uuid;
begin
 if auth.uid() is null or not public.is_admin() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_match_id is null then raise exception 'Match id is required'; end if;
 perform 1 from public.matches where id=p_match_id for update;
 if not found then return jsonb_build_object('deleted',true,'already_deleted',true,'match_id',p_match_id); end if;
 delete from public.matches where id=p_match_id returning id into saved;
 if saved is null then raise exception 'Match could not be deleted; refresh and check access'; end if;
 return jsonb_build_object('deleted',true,'already_deleted',false,'match_id',saved);
end $$;
revoke all on function public.permanently_delete_match(uuid) from public,anon;
grant execute on function public.permanently_delete_match(uuid) to authenticated;
notify pgrst,'reload schema';
