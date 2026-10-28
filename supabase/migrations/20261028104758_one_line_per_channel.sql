-- A channel opens its only stream directly; prevent another Admin client from
-- accidentally adding a second line after the single-stream UI is deployed.
create unique index if not exists channel_lines_one_per_channel_idx
  on public.channel_lines (channel_id);
