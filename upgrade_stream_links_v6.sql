-- Run ONCE in Supabase SQL Editor for an existing project.
-- Adds direct/FLV/MP4 support while keeping existing HLS/DASH rows valid.

alter table public.stream_links
  drop constraint if exists stream_links_stream_type_check;

alter table public.stream_links
  alter column stream_type set default 'auto';

alter table public.stream_links
  add constraint stream_links_stream_type_check
  check (stream_type in ('auto', 'hls', 'dash', 'flv', 'mp4'));
