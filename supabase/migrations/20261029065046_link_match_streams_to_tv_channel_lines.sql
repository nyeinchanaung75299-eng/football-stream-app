-- Preserve where an Admin match line came from without exposing channel
-- stream settings to the Viewer. Existing manually added match lines remain
-- valid because both references are optional.
alter table public.stream_links
  add column if not exists channel_id uuid,
  add column if not exists channel_line_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'stream_links_channel_id_fkey'
      and conrelid = 'public.stream_links'::regclass
  ) then
    alter table public.stream_links
      add constraint stream_links_channel_id_fkey
      foreign key (channel_id) references public.channels(id)
      on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'stream_links_channel_line_id_fkey'
      and conrelid = 'public.stream_links'::regclass
  ) then
    alter table public.stream_links
      add constraint stream_links_channel_line_id_fkey
      foreign key (channel_line_id) references public.channel_lines(id)
      on delete set null;
  end if;
end
$$;

create index if not exists stream_links_match_channel_line_idx
  on public.stream_links (match_id, channel_line_id)
  where channel_line_id is not null;

create unique index if not exists stream_links_one_channel_line_per_match_idx
  on public.stream_links (match_id, channel_line_id)
  where channel_line_id is not null;

comment on column public.stream_links.channel_id is
  'The optional published TV channel that supplied this match stream line.';
comment on column public.stream_links.channel_line_id is
  'The optional published TV channel line that supplied this match stream line.';

notify pgrst, 'reload schema';
