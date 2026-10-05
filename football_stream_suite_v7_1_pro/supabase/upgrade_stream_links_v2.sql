-- Run this ONCE in Supabase SQL Editor if you already ran the original schema.sql.
alter table public.stream_links add column if not exists resolution text;
alter table public.stream_links alter column stream_url set default '';
alter table public.stream_links add column if not exists referer text;
alter table public.stream_links add column if not exists origin text;
alter table public.stream_links add column if not exists key_id text;
alter table public.stream_links add column if not exists key_data text;
alter table public.stream_links add column if not exists use_webview boolean not null default false;
alter table public.stream_links add column if not exists webview_url text;
alter table public.stream_links add column if not exists send_notification boolean not null default false;
