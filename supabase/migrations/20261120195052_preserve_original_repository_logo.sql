-- Badge identity is the original URL. Admin/Viewer choose their image gateway
-- at render time, so stored data must not depend on a retired Vercel hostname.
create or replace function private.repository_import_logo(p_url text) returns text
language sql immutable set search_path='' as $$
 select case
  when btrim(p_url) ~ '^https://(nca-network-backup-test[.]vercel[.]app|nca25-live-relay[.]vercel[.]app|football-api[.]nyeinchanaung[.]us[.]ci|football-api[.]nyeinchanaung[.]ccwu[.]cc|football-public-api[.]nyeinchanaung75299-eng[.]workers[.]dev)/team-logos/[0-9]{1,12}([?][^[:space:]]*)?$'
   or btrim(p_url) ~ '^https://woggzixprvyjnfjzsglz[.]supabase[.]co/functions/v1/viewer-network-api/team-logos/[0-9]{1,12}([?][^[:space:]]*)?$'
   then 'https://img.sofascore.com/api/v1/team/' ||
    substring(btrim(p_url) from '/team-logos/([0-9]{1,12})') || '/image'
  when btrim(p_url) ~ '^https?://[^[:space:]]+$' then btrim(p_url)
  else null end;
$$;
revoke all on function private.repository_import_logo(text) from public,anon,authenticated;

-- Convert only recognized badge relays. Preserve all names, operator URLs,
-- line credentials and deletion flags; no deleted fixture is republished.
update public.matches
set home_logo_url = coalesce(private.repository_import_logo(home_logo_url),home_logo_url),
    away_logo_url = coalesce(private.repository_import_logo(away_logo_url),away_logo_url)
where (home_logo_url ~ '^https://(nca-network-backup-test[.]vercel[.]app|nca25-live-relay[.]vercel[.]app|football-api[.]nyeinchanaung[.]us[.]ci|football-api[.]nyeinchanaung[.]ccwu[.]cc|football-public-api[.]nyeinchanaung75299-eng[.]workers[.]dev)/team-logos/'
    or away_logo_url ~ '^https://(nca-network-backup-test[.]vercel[.]app|nca25-live-relay[.]vercel[.]app|football-api[.]nyeinchanaung[.]us[.]ci|football-api[.]nyeinchanaung[.]ccwu[.]cc|football-public-api[.]nyeinchanaung75299-eng[.]workers[.]dev)/team-logos/'
    or home_logo_url like 'https://woggzixprvyjnfjzsglz.supabase.co/functions/v1/viewer-network-api/team-logos/%'
    or away_logo_url like 'https://woggzixprvyjnfjzsglz.supabase.co/functions/v1/viewer-network-api/team-logos/%')
  and (home_logo_url is distinct from private.repository_import_logo(home_logo_url)
    or away_logo_url is distinct from private.repository_import_logo(away_logo_url));
