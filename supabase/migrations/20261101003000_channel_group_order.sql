-- Persist Admin-managed TV channel-group order without changing channel count or playback.
create table if not exists public.channel_group_order (
  category text primary key check (length(btrim(category)) between 1 and 80),
  position integer not null check (position >= 0),
  updated_at timestamptz not null default now()
);

alter table public.channel_group_order enable row level security;
revoke all on public.channel_group_order from public, anon, authenticated;
grant select on public.channel_group_order to anon, authenticated;
grant insert, update, delete on public.channel_group_order to authenticated;

create policy "read channel group positions"
on public.channel_group_order for select to anon, authenticated using (true);
create policy "admin insert channel group positions"
on public.channel_group_order for insert to authenticated
with check ((select public.is_admin()));
create policy "admin update channel group positions"
on public.channel_group_order for update to authenticated
using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admin delete channel group positions"
on public.channel_group_order for delete to authenticated
using ((select public.is_admin()));

-- Preserve the familiar beIN/TNT/Fubo-first ordering on first creation.
with preferred(category, position) as (
 values
 ('beIN Sports', 0), ('TNT Sports', 1), ('Fubo', 2), ('FanCode', 3),
 ('CazéTV', 4), ('Arena Sports', 5), ('FOX Sports', 6), ('D Sports', 7),
 ('TSN', 8), ('SporTV', 9), ('SPOTV', 10), ('Premiere', 11),
 ('Premier Sports', 12), ('CBS Sports', 13)
), groups as (
 select distinct c.category from public.channels c
), ranked as (
 select g.category,
 row_number() over(order by coalesce(p.position, 1000), g.category)::integer - 1 as position
 from groups g left join preferred p on p.category = g.category
)
insert into public.channel_group_order(category, position)
select category, position from ranked
on conflict (category) do nothing;

notify pgrst, 'reload schema';
