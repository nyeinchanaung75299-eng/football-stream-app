-- Preserve the public count API used by existing APKs without granting access
-- to protected stream URLs or DRM keys. The private helper has one deliberately
-- public output: the count of currently available lines for a public match.
set local lock_timeout = '5s';

create index if not exists stream_links_match_id_idx
  on public.stream_links (match_id);

create or replace function private.visible_stream_count(p_match_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(sl.id)::integer
  from public.stream_links sl
  join public.matches m on m.id = sl.match_id
  where m.id = p_match_id
    and m.is_active = true
    and m.is_featured = true
    and m.publish_state = 'published'
    and sl.is_active = true
    and coalesce(sl.use_webview, false) = false
    and coalesce(sl.stream_url, '') <> ''
    and (sl.available_from is null or sl.available_from <= now())
    and (sl.expires_at is null or sl.expires_at > now());
$$;

revoke all on function private.visible_stream_count(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.visible_stream_count(uuid)
  to anon, authenticated, service_role;
-- Do not grant USAGE on private. Stored view references can execute this
-- helper, but it is neither an exposed RPC nor a grant to private tables.

create or replace view public.match_stream_counts
with (security_invoker = true)
as
select m.id as match_id,
       private.visible_stream_count(m.id) as stream_count
from public.matches m
where m.is_active = true
  and m.is_featured = true
  and m.publish_state = 'published';

revoke all on public.match_stream_counts from public, anon, authenticated;
grant select on public.match_stream_counts to anon, authenticated;

alter function public.touch_updated_at() set search_path = '';
alter function public.is_admin() set search_path = '';
alter function public.get_stream_links_for_gateway(uuid, text)
  set search_path = '';
alter function public.publish_featured_matches(jsonb) set search_path = '';
-- The function retains its own admin-role check for authenticated callers.
revoke all on function public.publish_featured_matches(jsonb)
  from public, anon;
grant execute on function public.publish_featured_matches(jsonb)
  to authenticated;

-- RLS governs row-level DML, but does not restrict privileges such as TRUNCATE.
-- Clients need SELECT and Admin DML, never table-wide DDL-like privileges.
revoke all on public.profiles, public.matches, public.stream_links,
  public.highlights from public, anon, authenticated;
grant select on public.profiles, public.matches, public.stream_links,
  public.highlights to anon, authenticated;
grant insert, update, delete on public.matches, public.stream_links,
  public.highlights to authenticated;

-- Cache caller-level checks once per statement and avoid overlapping SELECT
-- policies. Write access still requires the database-backed admin role.
drop policy if exists "read own profile" on public.profiles;
drop policy if exists "admins read all profiles" on public.profiles;
create policy "read own or admin profiles" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists "admins manage matches" on public.matches;
drop policy if exists "public read active matches" on public.matches;
drop policy if exists "public read published matches" on public.matches;
create policy "public read published matches" on public.matches
  for select to anon, authenticated
  using ((is_active = true and publish_state = 'published')
         or (select public.is_admin()));
create policy "admins insert matches" on public.matches
  for insert to authenticated with check ((select public.is_admin()));
create policy "admins update matches" on public.matches
  for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admins delete matches" on public.matches
  for delete to authenticated using ((select public.is_admin()));

alter policy "admins manage stream links" on public.stream_links
  using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists "admins manage highlights" on public.highlights;
drop policy if exists "public read active highlights" on public.highlights;
create policy "public read active highlights" on public.highlights
  for select to anon using (is_active = true);
create policy "authenticated read highlights" on public.highlights
  for select to authenticated
  using (is_active = true or (select public.is_admin()));
create policy "admins insert highlights" on public.highlights
  for insert to authenticated with check ((select public.is_admin()));
create policy "admins update highlights" on public.highlights
  for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admins delete highlights" on public.highlights
  for delete to authenticated using ((select public.is_admin()));

notify pgrst, 'reload schema';
