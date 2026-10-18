-- Covers auth.users cleanup and administrator ownership queries without
-- changing the Library's RLS boundary.
create index if not exists stream_library_created_by_idx
  on public.stream_library (created_by)
  where created_by is not null;
