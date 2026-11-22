create table public.highlight_matches (
  id uuid primary key,
  league text not null,
  home_team text not null,
  away_team text not null,
  home_logo_url text,
  away_logo_url text,
  kickoff_at timestamptz,
  home_score integer check (home_score >= 0),
  away_score integer check (away_score >= 0),
  is_finished boolean not null default false,
  created_at timestamptz not null default now(),
  check ((home_score is null) = (away_score is null))
);

alter table public.highlight_matches enable row level security;
revoke all on public.highlight_matches from public, anon, authenticated;
grant select on public.highlight_matches to anon, authenticated;
grant insert, update, delete on public.highlight_matches to authenticated;
create policy "Viewer reads highlight matches" on public.highlight_matches
  for select to anon, authenticated using (true);
create policy "Admins manage highlight matches" on public.highlight_matches
  for all to authenticated using ((select public.is_admin()))
  with check ((select public.is_admin()));

alter table public.highlights add column match_id uuid
  references public.highlight_matches(id) on delete cascade;
create index highlights_match_id_idx on public.highlights(match_id);

create function public.move_live_match_to_highlights(p_match_id uuid)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  fixture public.matches;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  select * into fixture from public.matches where id = p_match_id for update;
  if found then
    insert into public.highlight_matches (
      id, league, home_team, away_team, home_logo_url, away_logo_url,
      kickoff_at, home_score, away_score, is_finished
    ) values (
      fixture.id, fixture.league, fixture.home_team, fixture.away_team,
      fixture.home_logo_url, fixture.away_logo_url, fixture.kickoff_at,
      case when fixture.away_score is not null then fixture.home_score end,
      case when fixture.home_score is not null then fixture.away_score end,
      coalesce(fixture.is_finished, false)
    ) on conflict (id) do nothing;
  elsif not exists (select 1 from public.highlight_matches where id = p_match_id) then
    raise exception 'Match unavailable';
  end if;
  return public.permanently_delete_match(p_match_id);
end
$$;
revoke all on function public.move_live_match_to_highlights(uuid) from public, anon;
grant execute on function public.move_live_match_to_highlights(uuid) to authenticated;

-- Embed only the playback fields the Viewer consumes. The legacy rows remain
-- visible until an Admin associates them with an archived match.
create function public.viewer_highlight_matches(p_offset integer default 0)
returns setof jsonb language sql stable security invoker set search_path = '' as $$
  select row_data from (
    select m.id, coalesce(m.kickoff_at, m.created_at) as match_time,
      to_jsonb(m) || jsonb_build_object(
        'title', m.home_team || ' vs ' || m.away_team,
        'lines', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', h.id, 'label', h.title, 'stream_url', h.video_url,
            'stream_type', h.stream_type, 'referer', h.referer,
            'origin', h.origin, 'user_agent', h.user_agent
          ) order by h.sort_order, h.id)
          from public.highlights h where h.match_id = m.id and h.is_active
        ), '[]'::jsonb)
      ) as row_data
    from public.highlight_matches m
    union all
    select h.id, h.created_at, jsonb_build_object(
      'id', h.id, 'title', h.title, 'thumbnail_url', h.thumbnail_url,
      'lines', jsonb_build_array(jsonb_build_object(
        'id', h.id, 'label', h.title, 'stream_url', h.video_url,
        'stream_type', h.stream_type, 'referer', h.referer,
        'origin', h.origin, 'user_agent', h.user_agent
      ))
    )
    from public.highlights h where h.match_id is null and h.is_active
  ) rows
  order by match_time desc, id
  offset greatest(coalesce(p_offset, 0), 0) limit 25
$$;
revoke all on function public.viewer_highlight_matches(integer) from public;
grant execute on function public.viewer_highlight_matches(integer) to anon, authenticated;

create table public.combat_match_imports (
  event_id text primary key,
  match_id uuid not null references public.matches(id) on delete cascade
);
alter table public.combat_match_imports enable row level security;
revoke all on public.combat_match_imports from public, anon, authenticated;

create function public.publish_combat_match(
  p_event_id text, p_entries text[], p_kickoff_at timestamptz
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  fixture public.channel_source_catalog;
  saved_id uuid;
  source_line record;
  home text;
  away text;
  kickoff timestamptz;
  line_count integer := 0;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  if p_event_id is null or p_event_id !~ '^combat:[a-f0-9]{28}$'
     or coalesce(cardinality(p_entries), 0) not between 1 and 50 then
    return jsonb_build_object('ok', false, 'code', 'source_missing');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_event_id, 0));
  select * into fixture from public.channel_source_catalog
  where source_id = 'darkbyte' and kind = 'event' and is_present
    and id = p_entries[1] for update;
  if not found or concat_ws(' ', fixture.name, fixture.event_meta->>'league',
       fixture.event_meta->>'source_category') !~* '(ufc|mma|boxing|mixed martial arts|one championship|one friday fights|one fight night)' then
    return jsonb_build_object('ok', false, 'code', 'source_missing');
  end if;
  home := nullif(btrim(fixture.event_meta->>'home_team'), '');
  away := nullif(btrim(fixture.event_meta->>'away_team'), '');
  if home is null or away is null then
    return jsonb_build_object('ok', false, 'code', 'metadata_pending');
  end if;
  kickoff := coalesce(nullif(fixture.event_meta->>'kickoff_at', '')::timestamptz, p_kickoff_at);
  if kickoff is null or kickoff < '2000-01-01' or kickoff >= '2100-01-01' then
    return jsonb_build_object('ok', false, 'code', 'kickoff_required');
  end if;
  select match_id into saved_id from public.combat_match_imports where event_id = p_event_id;
  if saved_id is null then
    insert into public.matches (
      league, home_team, away_team, home_logo_url, away_logo_url,
      kickoff_at, source, is_live, is_active, is_featured, publish_state, status_short
    ) values (
      coalesce(nullif(fixture.event_meta->>'league', ''), 'Combat Sports'), home, away,
      private.repository_import_logo(fixture.event_meta->>'home_logo_url'),
      private.repository_import_logo(fixture.event_meta->>'away_logo_url'),
      kickoff, 'combat', false, true, true, 'published', 'NS'
    ) returning id into saved_id;
    insert into public.combat_match_imports values (p_event_id, saved_id);
  elsif not exists (
    select 1 from public.matches where id = saved_id and is_active and not is_finished and deleted_at is null
  ) then
    return jsonb_build_object('ok', false, 'code', 'previously_finished');
  end if;

  for source_line in
    select c.id as entry_id, line->>'id' as line_id
    from public.channel_source_catalog c cross join lateral jsonb_array_elements(c.streams) line
    where c.source_id = 'darkbyte' and c.kind = 'event' and c.is_present
      and c.id = any(p_entries)
      and lower(btrim(c.event_meta->>'home_team')) = lower(home)
      and lower(btrim(c.event_meta->>'away_team')) = lower(away)
      and c.event_meta->>'kickoff_at' is not distinct from fixture.event_meta->>'kickoff_at'
      and line->>'id' is not null
      and line->>'stream_type' in ('hls', 'dash', 'mp4', 'flv')
      and line->>'stream_url' ~ '^https?://[^[:space:]]+$'
      and coalesce(line->>'configuration_status', '') <> 'requires_drm'
      and (
        (coalesce(line->>'key_id', '') = '' and coalesce(line->>'key_data', '') = '')
        or (line->>'key_id' ~* '^[a-f0-9]{32}$' and line->>'key_data' ~* '^[a-f0-9]{32}$')
      )
    order by c.id, line->>'id'
  loop
    perform public.add_connected_source_line_to_match(source_line.entry_id, source_line.line_id, saved_id);
    line_count := line_count + 1;
  end loop;
  return jsonb_build_object('ok', true, 'match_id', saved_id, 'line_count', line_count);
end
$$;
revoke all on function public.publish_combat_match(text, text[], timestamptz) from public, anon;
grant execute on function public.publish_combat_match(text, text[], timestamptz) to authenticated;
notify pgrst, 'reload schema';

-- The projection can consolidate two source spellings without changing an
-- already-published match UUID. Match aliases only when both badge IDs,
-- competition, home/away order and exact UTC kickoff also agree.
create function private.repository_same_badge(p_left text, p_right text)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(
    substring(p_left from '^https://img[.]sofascore[.]com/api/v1/team/([0-9]+)/image(?:[?].*)?$') =
    substring(p_right from '^https://img[.]sofascore[.]com/api/v1/team/([0-9]+)/image(?:[?].*)?$'),
    false
  )
$$;
revoke all on function private.repository_same_badge(text,text) from public, anon, authenticated;

do $migration$
declare
  definition text := pg_get_functiondef('public.publish_repository_match(text,timestamptz)'::regprocedure);
  old_filter text := 'and private.repository_team_key(m.home_team)=home_key and private.repository_team_key(m.away_team)=away_key';
  new_filter text := $filter$and (
    (private.repository_team_key(m.home_team)=home_key and private.repository_team_key(m.away_team)=away_key)
    or (m.kickoff_at=kickoff
      and regexp_replace(lower(m.league),'[^a-z0-9]','','g')=regexp_replace(lower(meta->>'league'),'[^a-z0-9]','','g')
      and private.repository_same_badge(m.home_logo_url,meta->>'home_logo_url')
      and private.repository_same_badge(m.away_logo_url,meta->>'away_logo_url'))
  )$filter$;
begin
  if strpos(definition,old_filter)=0 then
    raise exception 'Repository publish identity filter not found';
  end if;
  execute replace(definition,old_filter,new_filter);
end
$migration$;
