-- An operator deleting a channel/line also rejects its copied match lines.
-- Keeping the URL/key fields with NULL channel references was an unintended
-- fallback. No backup or recoverable stream configuration is created.
alter table public.stream_links drop constraint stream_links_channel_id_fkey;
alter table public.stream_links add constraint stream_links_channel_id_fkey
 foreign key(channel_id) references public.channels(id) on delete cascade;
alter table public.stream_links drop constraint stream_links_channel_line_id_fkey;
alter table public.stream_links add constraint stream_links_channel_line_id_fkey
 foreign key(channel_line_id) references public.channel_lines(id) on delete cascade;
notify pgrst,'reload schema';
