-- Admin-managed channels: public metadata, private stream lines.
create table if not exists public.channels (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 120),
  category text not null check (length(btrim(category)) between 1 and 80),
  image_url text check (image_url is null or
    (length(image_url) <= 2048 and image_url ~ '^https://[^[:space:]]+$')),
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.channel_lines (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels(id) on delete cascade,
  label text not null default 'Server 1' check (length(btrim(label)) between 1 and 100),
  stream_type text not null default 'auto' check (stream_type in ('auto','hls','dash','mp4','flv')),
  stream_url text not null check (length(stream_url) <= 4096 and stream_url ~ '^https?://[^[:space:]]+$'),
  referer text check (referer is null or (length(referer) <= 2048 and referer ~ '^https?://[^[:space:]]+$')),
  origin text check (origin is null or (length(origin) <= 2048 and origin ~ '^https?://[^[:space:]]+$')),
  key_id text check (key_id is null or length(key_id) <= 512),
  key_data text check (key_data is null or length(key_data) <= 512),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint channel_complete_key_pair check
    ((nullif(btrim(coalesce(key_id,'')), '') is null) =
     (nullif(btrim(coalesce(key_data,'')), '') is null))
);
create index if not exists channels_public_order_idx on public.channels (category, sort_order, name) where is_active;
create index if not exists channel_lines_channel_order_idx on public.channel_lines (channel_id, sort_order) where is_active;
alter table public.channels enable row level security;
alter table public.channel_lines enable row level security;
revoke all on public.channels, public.channel_lines from public, anon, authenticated;
grant select on public.channels to anon, authenticated;
grant select, insert, update, delete on public.channels to authenticated;
grant select, insert, update, delete on public.channel_lines to authenticated;
create policy "public active channels or admin" on public.channels
  for select to anon, authenticated using (is_active or (select public.is_admin()));
create policy "admin insert channels" on public.channels
  for insert to authenticated with check ((select public.is_admin()));
create policy "admin update channels" on public.channels
  for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admin delete channels" on public.channels
  for delete to authenticated using ((select public.is_admin()));
create policy "admin read channel lines" on public.channel_lines
  for select to authenticated using ((select public.is_admin()));
create policy "admin insert channel lines" on public.channel_lines
  for insert to authenticated with check ((select public.is_admin()));
create policy "admin update channel lines" on public.channel_lines
  for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admin delete channel lines" on public.channel_lines
  for delete to authenticated using ((select public.is_admin()));
create trigger trg_channels_updated_at before update on public.channels
  for each row execute function public.touch_updated_at();
create trigger trg_channel_lines_updated_at before update on public.channel_lines
  for each row execute function public.touch_updated_at();
create or replace function public.get_channel_metadata_for_gateway(
  p_channel_id uuid, p_secret text
) returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare result jsonb;
begin
  if not exists (
    select 1 from private.gateway_secrets s
    where s.name = 'cloudflare_playback'
      and s.secret_hash = encode(extensions.digest(coalesce(p_secret,''), 'sha256'), 'hex')
  ) then
    raise exception 'unauthorized gateway' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'channel_valid', true,
    'streams', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', l.id, 'label', l.label, 'resolution', null,
        'stream_type', l.stream_type, 'stream_url', l.stream_url,
        'referer', l.referer, 'origin', l.origin,
        'key_id', l.key_id, 'key_data', l.key_data,
        'use_webview', false, 'is_active', l.is_active,
        'priority', l.sort_order, 'sort_order', l.sort_order,
        'health_status', 'unknown', 'available_from', null,
        'expires_at', null
      ) order by l.sort_order, l.created_at)
      from public.channel_lines l where l.channel_id = c.id and l.is_active
    ), '[]'::jsonb)
  ) into result
  from public.channels c where c.id = p_channel_id and c.is_active;
  return coalesce(result, '{"channel_valid":false,"streams":[]}'::jsonb);
end;
$$;
revoke all on function public.get_channel_metadata_for_gateway(uuid,text)
  from public, anon, authenticated;
grant execute on function public.get_channel_metadata_for_gateway(uuid,text)
  to anon, authenticated, service_role;
notify pgrst, 'reload schema';
