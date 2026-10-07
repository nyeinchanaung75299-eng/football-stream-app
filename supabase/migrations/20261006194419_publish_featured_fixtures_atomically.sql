-- Keep the committed schema reproducible and preserve deleted fixture IDs.
alter table public.matches add column if not exists deleted_at timestamptz;

-- Publishing a selection is one transaction. A failed replacement never
-- clears the current selection, and concurrent publications are serialized.
create or replace function public.publish_featured_fixtures(p_fixtures jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_fixture jsonb;
  v_field text;
  v_external_fixture_id bigint;
  v_kickoff_at timestamptz;
  v_seen_fixture_ids bigint[] := '{}';
  v_published_ids uuid[] := '{}';
  v_published_id uuid;
  v_skipped_deleted integer := 0;
begin
  if (select public.is_admin()) is distinct from true then
    raise exception 'Admin access required.' using errcode = '42501';
  end if;

  if p_fixtures is null or pg_catalog.jsonb_typeof(p_fixtures) <> 'array' then
    raise exception 'p_fixtures must be a nonempty array.' using errcode = '22023';
  end if;
  if pg_catalog.jsonb_array_length(p_fixtures) = 0 then
    raise exception 'Select at least one fixture.' using errcode = '22023';
  end if;

  -- Validate the entire selection before changing any rows, including entries
  -- that will be skipped because their fixture ID has a deletion tombstone.
  for v_fixture in select value from pg_catalog.jsonb_array_elements(p_fixtures)
  loop
    if pg_catalog.jsonb_typeof(v_fixture) <> 'object' then
      raise exception 'Each fixture must be an object.' using errcode = '22023';
    end if;

    if pg_catalog.jsonb_typeof(v_fixture -> 'external_fixture_id') is distinct from 'number'
       or coalesce(v_fixture ->> 'external_fixture_id', '') !~ '^-?[1-9][0-9]*$' then
      raise exception 'external_fixture_id must be a nonzero integer.' using errcode = '22023';
    end if;
    v_external_fixture_id := (v_fixture ->> 'external_fixture_id')::bigint;
    if v_external_fixture_id = any(v_seen_fixture_ids) then
      raise exception 'Duplicate external_fixture_id in selection.' using errcode = '22023';
    end if;
    v_seen_fixture_ids := pg_catalog.array_append(v_seen_fixture_ids, v_external_fixture_id);

    foreach v_field in array array['source', 'league', 'home_team', 'away_team', 'kickoff_at']
    loop
      if pg_catalog.jsonb_typeof(v_fixture -> v_field) is distinct from 'string'
         or pg_catalog.btrim(v_fixture ->> v_field) = '' then
        raise exception '% must be a nonempty string.', v_field using errcode = '22023';
      end if;
    end loop;

    v_kickoff_at := (v_fixture ->> 'kickoff_at')::timestamptz;
    if not pg_catalog.isfinite(v_kickoff_at) then
      raise exception 'kickoff_at must be a finite timestamp.' using errcode = '22023';
    end if;

    foreach v_field in array array['home_logo_url', 'away_logo_url', 'status_short']
    loop
      if v_fixture ? v_field
         and pg_catalog.jsonb_typeof(v_fixture -> v_field) not in ('string', 'null') then
        raise exception '% must be a string or null.', v_field using errcode = '22023';
      end if;
    end loop;
    if v_fixture ? 'is_live'
       and pg_catalog.jsonb_typeof(v_fixture -> 'is_live') not in ('boolean', 'null') then
      raise exception 'is_live must be a boolean or null.' using errcode = '22023';
    end if;
  end loop;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('public.publish_featured_fixtures', 0)
  );

  for v_fixture in select value from pg_catalog.jsonb_array_elements(p_fixtures)
  loop
    v_published_id := null;
    insert into public.matches as existing (
      external_fixture_id, source, league, home_team, away_team,
      home_logo_url, away_logo_url, kickoff_at, status_short, is_live,
      is_active, is_featured, publish_state
    ) values (
      (v_fixture ->> 'external_fixture_id')::bigint,
      pg_catalog.btrim(v_fixture ->> 'source'),
      pg_catalog.btrim(v_fixture ->> 'league'),
      pg_catalog.btrim(v_fixture ->> 'home_team'),
      pg_catalog.btrim(v_fixture ->> 'away_team'),
      nullif(pg_catalog.btrim(v_fixture ->> 'home_logo_url'), ''),
      nullif(pg_catalog.btrim(v_fixture ->> 'away_logo_url'), ''),
      (v_fixture ->> 'kickoff_at')::timestamptz,
      coalesce(nullif(pg_catalog.btrim(v_fixture ->> 'status_short'), ''), 'NS'),
      coalesce((v_fixture ->> 'is_live')::boolean, false),
      true, true, 'published'
    )
    on conflict (external_fixture_id) do update set
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
    -- Re-check on the locked conflicting row so even a concurrent soft delete
    -- cannot be undone by a fixture publication.
    where existing.deleted_at is null
    returning existing.id into v_published_id;

    if v_published_id is null then
      v_skipped_deleted := v_skipped_deleted + 1;
    else
      v_published_ids := pg_catalog.array_append(v_published_ids, v_published_id);
    end if;
  end loop;

  -- An all-deleted selection preserves the current featured set.
  if pg_catalog.cardinality(v_published_ids) > 0 then
    update public.matches
    set is_featured = false
    where is_featured = true and not (id = any(v_published_ids));
  end if;

  return pg_catalog.jsonb_build_object(
    'published_ids', pg_catalog.to_jsonb(v_published_ids),
    'skipped_deleted', v_skipped_deleted
  );
end;
$$;

revoke all on function public.publish_featured_fixtures(jsonb) from public, anon;
grant execute on function public.publish_featured_fixtures(jsonb) to authenticated;
