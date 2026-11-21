-- Called only after a successfully committed partial repository snapshot.
-- Never deletes user matches or their uploaded lines.
create function public.hide_confirmed_repository_removals(p_revision text,p_ids jsonb) returns integer
 language plpgsql security definer set search_path='' as $$
declare changed integer;
begin
 if coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' and not coalesce(public.is_admin(),false) then raise exception 'Admin access required' using errcode='42501'; end if;
 if jsonb_typeof(p_ids) is distinct from 'array' or jsonb_array_length(p_ids)>15000 then raise exception 'Invalid removal list'; end if;
 perform 1 from public.channel_source_state where id='repository' and revision=p_revision for update;
 if not found then return 0; end if;
 update public.channel_source_catalog set is_present=false where source_id='repository' and is_present and id in(select jsonb_array_elements_text(p_ids));
 get diagnostics changed=row_count;
 update public.channel_source_state set entry_count=(select count(*) from public.channel_source_catalog where source_id='repository' and is_present) where id='repository';
 return changed;
end $$;
revoke all on function public.hide_confirmed_repository_removals(text,jsonb) from public,anon;
grant execute on function public.hide_confirmed_repository_removals(text,jsonb) to authenticated,service_role;
notify pgrst,'reload schema';
