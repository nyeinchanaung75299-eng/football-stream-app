alter table public.matches
  add column if not exists deleted_at timestamptz;

create or replace function public.publish_featured_matches(p_fixtures jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  fixture_id bigint;
  saved_id uuid;
  eligible_count integer := 0;
  skipped_deleted integer := 0;
  saved_ids jsonb := '[]'::jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admin access required.' using errcode = '42501';
  end if;

  if p_fixtures is null
     or jsonb_typeof(p_fixtures) <> 'array'
     or jsonb_array_length(p_fixtures) = 0 then
    raise exception 'Select at least one match.';
  end if;

  for item in select value from jsonb_array_elements(p_fixtures)
  loop
    fixture_id := nullif(item->>'fixture_id', '')::bigint;
    if fixture_id is null then
      raise exception 'A selected fixture is missing fixture_id.';
    end if;
    if coalesce(btrim(item->>'league_name'), '') = ''
       or coalesce(btrim(item->>'home_name'), '') = ''
       or coalesce(btrim(item->>'away_name'), '') = ''
       or coalesce(btrim(item->>'kickoff_at'), '') = '' then
      raise exception 'A selected fixture is missing required match data.';
    end if;

    if exists (
      select 1 from public.matches m
      where m.external_fixture_id = fixture_id
        and m.deleted_at is not null
    ) then
      skipped_deleted := skipped_deleted + 1;
    else
      eligible_count := eligible_count + 1;
    end if;
  end loop;

  if eligible_count = 0 then
    raise exception 'All selected matches were previously deleted; current Viewer matches were kept.';
  end if;

  update public.matches
  set is_featured = false
  where is_featured = true;

  for item in select value from jsonb_array_elements(p_fixtures)
  loop
    fixture_id := nullif(item->>'fixture_id', '')::bigint;
    if exists (
      select 1 from public.matches m
      where m.external_fixture_id = fixture_id
        and m.deleted_at is not null
    ) then
      continue;
    end if;

    insert into public.matches (
      external_fixture_id, source, league, home_team, away_team,
      home_logo_url, away_logo_url, kickoff_at, status_short, is_live,
      is_active, is_featured, publish_state, deleted_at
    )
    values (
      fixture_id,
      coalesce(nullif(item->>'provider', ''), 'api_football'),
      item->>'league_name',
      item->>'home_name',
      item->>'away_name',
      nullif(item->>'home_logo', ''),
      nullif(item->>'away_logo', ''),
      (item->>'kickoff_at')::timestamptz,
      coalesce(nullif(item->>'status_short', ''), 'NS'),
      coalesce((item->>'is_live')::boolean, false),
      true, true, 'published', null
    )
    on conflict (external_fixture_id)
    do update set
      source = excluded.source,
      league = excluded.league,
      home_team = excluded.home_team,
      away_team = excluded.away_team,
      home_logo_url = excluded.home_logo_url,
      away_logo_url = excluded.away_logo_url,
      kickoff_at = excluded.kickoff_at,
      status_short = excluded.status_short,
      is_live = excluded.is_live,
      is_active = true,
      is_featured = true,
      publish_state = 'published'
    returning public.matches.id into saved_id;

    saved_ids := saved_ids || jsonb_build_array(saved_id::text);
  end loop;

  return jsonb_build_object(
    'saved_ids', saved_ids,
    'published_count', eligible_count,
    'skipped_deleted', skipped_deleted
  );
end;
$$;

revoke all on function public.publish_featured_matches(jsonb) from public;
grant execute on function public.publish_featured_matches(jsonb) to authenticated;
