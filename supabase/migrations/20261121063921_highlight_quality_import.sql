-- A repeat ADD updates the same source line; highlights never enter Live.
alter table public.highlights
  add column if not exists stream_type text not null default 'auto' check(stream_type in ('auto','hls','dash','mp4')),
  add column if not exists referer text check(referer is null or (length(referer)<=2048 and referer ~ '^https?://[^[:space:]]+$')),
  add column if not exists origin text check(origin is null or (length(origin)<=2048 and origin ~ '^https?://[^[:space:]]+$')),
  add column if not exists user_agent text check(user_agent is null or (length(user_agent)<=1024 and user_agent !~ '[\r\n]')),
  add column if not exists source_provider text,
  add column if not exists source_entry_id text,
  add column if not exists source_line_id text;
create unique index if not exists highlights_source_line_key on public.highlights(source_provider,source_entry_id,source_line_id);
notify pgrst, 'reload schema';
