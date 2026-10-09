-- One gateway request distinguishes an unpublished/missing match from a
-- published match with no lines. The existing encrypted-playback secret is
-- required before either match eligibility or private stream data is read.
create or replace function public.get_stream_metadata_for_gateway(
  p_match_id uuid,
  p_secret text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  match_valid boolean;
  streams jsonb;
begin
  if not exists (
    select 1
    from private.gateway_secrets s
    where s.name = 'cloudflare_playback'
      and s.secret_hash =
        encode(extensions.digest(coalesce(p_secret, ''), 'sha256'), 'hex')
  ) then
    raise exception 'unauthorized gateway' using errcode = '42501';
  end if;

  select exists (
    select 1 from public.matches m
    where m.id = p_match_id
      and m.is_active = true
      and m.is_featured = true
      and m.publish_state = 'published'
  ) into match_valid;

  if not match_valid then
    return jsonb_build_object('match_valid', false, 'streams', '[]'::jsonb);
  end if;

  -- Reuse the existing gate, filtering, field projection, and ordering.
  select coalesce(
    jsonb_agg(to_jsonb(g) - 'ordinality' order by g.ordinality), '[]'::jsonb
  ) into streams
  from public.get_stream_links_for_gateway(p_match_id, p_secret)
    with ordinality as g;

  return jsonb_build_object('match_valid', true, 'streams', streams);
end;
$$;

revoke all on function public.get_stream_metadata_for_gateway(uuid, text)
from public, anon, authenticated;
-- Same gateway-secret-gated roles as get_stream_links_for_gateway. A Viewer
-- publishable key alone cannot fetch either eligibility or protected rows.
grant execute on function public.get_stream_metadata_for_gateway(uuid, text)
to anon, authenticated;
