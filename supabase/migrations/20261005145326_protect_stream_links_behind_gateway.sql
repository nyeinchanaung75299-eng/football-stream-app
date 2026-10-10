-- Protect raw playback configuration from anonymous PostgREST reads.
-- The Cloudflare gateway secret hash is seeded operationally in
-- private.gateway_secrets and is intentionally not committed to GitHub.

create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon, authenticated;

create table if not exists private.gateway_secrets (
  name text primary key,
  secret_hash text not null,
  updated_at timestamptz not null default now()
);

revoke all on table private.gateway_secrets from public;
revoke all on table private.gateway_secrets from anon, authenticated;

drop policy if exists "public read active stream links"
on public.stream_links;

create or replace function public.get_stream_links_for_gateway(
  p_match_id uuid,
  p_secret text
)
returns table (
  id uuid,
  label text,
  resolution text,
  stream_type text,
  stream_url text,
  referer text,
  origin text,
  key_id text,
  key_data text,
  use_webview boolean,
  webview_url text,
  is_active boolean,
  priority integer,
  available_from timestamptz,
  expires_at timestamptz,
  health_status text,
  sort_order integer
)
language plpgsql
security definer
set search_path = public, private, extensions
as $$
begin
  if not exists (
    select 1
    from private.gateway_secrets s
    where s.name = 'cloudflare_playback'
      and s.secret_hash =
          encode(extensions.digest(coalesce(p_secret, ''), 'sha256'), 'hex')
  ) then
    raise exception 'unauthorized gateway'
      using errcode = '42501';
  end if;

  return query
  select
    sl.id,
    sl.label,
    sl.resolution,
    sl.stream_type,
    sl.stream_url,
    sl.referer,
    sl.origin,
    sl.key_id,
    sl.key_data,
    sl.use_webview,
    sl.webview_url,
    sl.is_active,
    sl.priority,
    sl.available_from,
    sl.expires_at,
    sl.health_status,
    sl.sort_order
  from public.stream_links sl
  join public.matches m on m.id = sl.match_id
  where sl.match_id = p_match_id
    and sl.is_active = true
    and m.is_active = true
    and m.is_featured = true
    and m.publish_state = 'published'
  order by sl.priority asc nulls last,
           sl.sort_order asc,
           sl.created_at asc;
end;
$$;

revoke all on function public.get_stream_links_for_gateway(uuid, text)
from public;
grant execute on function public.get_stream_links_for_gateway(uuid, text)
to anon, authenticated;

create or replace view public.match_stream_counts
with (security_invoker = false)
as
select
  m.id as match_id,
  count(sl.id) filter (
    where sl.is_active = true
      and coalesce(sl.use_webview, false) = false
      and coalesce(sl.stream_url, '') <> ''
      and coalesce(sl.key_id, '') = ''
      and coalesce(sl.key_data, '') = ''
      and (sl.available_from is null or sl.available_from <= now())
      and (sl.expires_at is null or sl.expires_at > now())
  )::integer as stream_count
from public.matches m
left join public.stream_links sl on sl.match_id = m.id
where m.is_active = true
  and m.is_featured = true
  and m.publish_state = 'published'
group by m.id;

revoke all on table public.match_stream_counts from public;
grant select on table public.match_stream_counts to anon, authenticated;
