-- Private, reusable HLS catalog for administrators. A saved row is never a
-- public playback line by itself; the Admin app copies it to stream_links only
-- after an administrator explicitly chooses a match.
set local lock_timeout = '5s';

create table if not exists public.stream_library (
  id uuid primary key default gen_random_uuid(),
  label text not null,
  stream_type text not null default 'hls',
  stream_url text not null,
  referer text,
  origin text,
  fingerprint text generated always as (
    encode(
      extensions.digest(
        stream_url || chr(31) || coalesce(referer, '') || chr(31) ||
        coalesce(origin, ''),
        'sha256'
      ),
      'hex'
    )
  ) stored,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  last_used_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stream_library_label_length
    check (char_length(btrim(label)) between 1 and 120),
  constraint stream_library_hls_only
    check (stream_type = 'hls'),
  constraint stream_library_http_url
    check (
      stream_url ~ '^https?://[^[:space:]]+$'
      and char_length(stream_url) <= 8192
    ),
  constraint stream_library_referer_length
    check (
      referer is null
      or (referer !~ '[\r\n]' and char_length(referer) <= 2048)
    ),
  constraint stream_library_origin_length
    check (
      origin is null
      or (origin !~ '[\r\n]' and char_length(origin) <= 2048)
    ),
  constraint stream_library_fingerprint_unique unique (fingerprint)
);

create index if not exists stream_library_recent_idx
  on public.stream_library (coalesce(last_used_at, updated_at) desc);

alter table public.stream_library enable row level security;

revoke all on public.stream_library from public, anon, authenticated;
grant select, insert, update, delete on public.stream_library to authenticated;

drop policy if exists "admins manage stream library" on public.stream_library;
create policy "admins manage stream library"
on public.stream_library
for all
to authenticated
using ((select public.is_admin()))
with check ((select public.is_admin()));

drop trigger if exists trg_stream_library_updated_at on public.stream_library;
create trigger trg_stream_library_updated_at
before update on public.stream_library
for each row execute function public.touch_updated_at();

comment on table public.stream_library is
  'Admin-only reusable HLS entries. Rows are not exposed by the public playback gateway.';
comment on column public.stream_library.stream_url is
  'Authorized direct HLS URL. Never include this column in public feeds or telemetry.';

notify pgrst, 'reload schema';
