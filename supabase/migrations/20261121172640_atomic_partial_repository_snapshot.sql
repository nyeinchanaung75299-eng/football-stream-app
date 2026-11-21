-- A partial commit intentionally retains the last complete revision. Guard on
-- the active sync lease and reconcile observed removals in the SAME transaction.
create function public.commit_repository_partial_snapshot(p_lease uuid,p_revision text,p_entries jsonb,p_removed_ids jsonb)
 returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; changed integer;
begin
 if coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' and not coalesce(public.is_admin(),false) then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_lease is null or p_revision is null or jsonb_typeof(p_removed_ids) is distinct from 'array' or jsonb_array_length(p_removed_ids)>15000 then raise exception 'Invalid partial snapshot'; end if;
 perform 1 from public.channel_source_state where id='repository' and lease_id=p_lease for update;
 if not found then raise exception 'Source sync lease expired'; end if;
 result:=public.commit_connected_channel_source_sync('repository',p_lease,p_revision,p_entries,false,false);
 update public.channel_source_catalog c set is_present=false where c.source_id='repository' and c.is_present
  and c.id in(select jsonb_array_elements_text(p_removed_ids))
  and not exists(select from jsonb_array_elements(p_entries) e where e->>'id'=c.id);
 get diagnostics changed=row_count;
 update public.channel_source_state set entry_count=(select count(*) from public.channel_source_catalog where source_id='repository' and is_present) where id='repository';
 return result||jsonb_build_object('removed_count',changed,'entry_count',(select entry_count from public.channel_source_state where id='repository'));
end $$;
revoke all on function public.commit_repository_partial_snapshot(uuid,text,jsonb,jsonb) from public,anon;
grant execute on function public.commit_repository_partial_snapshot(uuid,text,jsonb,jsonb) to authenticated,service_role;
notify pgrst,'reload schema';
