\set ON_ERROR_STOP on

-- Only run this harness in a disposable local/CI database.
do $$ begin
  if current_database() <> 'football_backend_test' then
    raise exception 'Use a disposable database named football_backend_test.';
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end $$;
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key);
create or replace function auth.uid() returns uuid language sql stable
as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to anon, authenticated;
do $$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;

\ir ../supabase/schema.sql
-- Simulate the existing-project upgrade too: the migration must add the column
-- even when it was omitted by an older bootstrap schema.
alter table public.matches drop column deleted_at;
\ir ../supabase/migrations/20261006194419_publish_featured_fixtures_atomically.sql
-- Verify that operationally reapplying this additive migration is harmless.
\ir ../supabase/migrations/20261006194419_publish_featured_fixtures_atomically.sql
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to anon, authenticated;

create schema if not exists backend_test;
grant usage on schema backend_test to anon, authenticated;
create or replace function backend_test.assert_true(ok boolean, message text)
returns void language plpgsql as $$ begin
  if ok is distinct from true then raise exception '%', message; end if;
end $$;
create or replace function backend_test.fixture(fixture_id bigint)
returns jsonb language sql as $$
  select jsonb_build_object(
    'external_fixture_id', fixture_id, 'source', 'api_football',
    'league', 'Regression League', 'home_team', 'Home ' || fixture_id,
    'away_team', 'Away ' || fixture_id, 'home_logo_url', null,
    'away_logo_url', null, 'kickoff_at', '2026-10-06T12:00:00Z',
    'status_short', 'NS', 'is_live', false
  )
$$;
create or replace function backend_test.expect_rejection(payload jsonb, expected_state text)
returns void language plpgsql as $$
declare actual_state text;
begin
  begin
    perform public.publish_featured_fixtures(payload);
  exception when others then
    get stacked diagnostics actual_state = returned_sqlstate;
    if actual_state <> expected_state then
      raise exception 'Expected SQLSTATE %, got %.', expected_state, actual_state;
    end if;
    return;
  end;
  raise exception 'Expected publication to fail with SQLSTATE %.', expected_state;
end $$;

select backend_test.assert_true(
  not has_function_privilege('anon', 'public.publish_featured_fixtures(jsonb)', 'EXECUTE'),
  'Anonymous callers must not have RPC EXECUTE permission.'
);
select backend_test.assert_true(
  has_function_privilege('authenticated', 'public.publish_featured_fixtures(jsonb)', 'EXECUTE'),
  'Signed-in admins need RPC EXECUTE permission.'
);
select backend_test.assert_true(
  (select not prosecdef and proconfig = array['search_path=""'] from pg_proc
   where oid = 'public.publish_featured_fixtures(jsonb)'::regprocedure),
  'RPC must remain SECURITY INVOKER with a fixed empty search_path.'
);

begin;
insert into auth.users(id) values
  ('10000000-0000-0000-0000-000000000001'),
  ('10000000-0000-0000-0000-000000000002');
insert into public.profiles(id, role) values
  ('10000000-0000-0000-0000-000000000001', 'admin'),
  ('10000000-0000-0000-0000-000000000002', 'viewer');
insert into public.matches(external_fixture_id, league, home_team, away_team, kickoff_at)
values (1, 'Old League', 'Old Home', 'Old Away', now());
insert into public.matches(external_fixture_id, league, home_team, away_team, kickoff_at,
                           deleted_at, is_active, is_featured, publish_state)
values (9, 'Deleted League', 'Keep tombstone', 'Deleted Away', now(), now(), false, false, 'draft');

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
select backend_test.expect_rejection(jsonb_build_array(backend_test.fixture(2)), '42501');
select set_config('request.jwt.claim.sub', '', true);
select backend_test.expect_rejection(jsonb_build_array(backend_test.fixture(2)), '42501');
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

-- Reject invalid whole batches before replacing the selection.
select backend_test.expect_rejection(null, '22023');
select backend_test.expect_rejection('{}'::jsonb, '22023');
select backend_test.expect_rejection('[]'::jsonb, '22023');
select backend_test.expect_rejection('[null]'::jsonb, '22023');
select backend_test.expect_rejection(jsonb_build_array(backend_test.fixture(2) || '{"home_team":"   "}'::jsonb), '22023');
select backend_test.expect_rejection(jsonb_build_array(backend_test.fixture(2) || '{"kickoff_at":"not-a-date"}'::jsonb), '22007');
select backend_test.expect_rejection(jsonb_build_array(backend_test.fixture(2) || '{"kickoff_at":"infinity"}'::jsonb), '22023');
select backend_test.expect_rejection(jsonb_build_array(backend_test.fixture(2) || '{"external_fixture_id":2.5}'::jsonb), '22023');
select backend_test.expect_rejection(jsonb_build_array(backend_test.fixture(2) || '{"is_live":"false"}'::jsonb), '22023');
select backend_test.expect_rejection(jsonb_build_array(backend_test.fixture(2) || '{"home_logo_url":42}'::jsonb), '22023');
select backend_test.expect_rejection(jsonb_build_array(backend_test.fixture(2), backend_test.fixture(2)), '22023');
select backend_test.expect_rejection(jsonb_build_array(backend_test.fixture(2), backend_test.fixture(3) || '{"league":null}'::jsonb), '22023');
select backend_test.assert_true(
  (select array_agg(external_fixture_id order by external_fixture_id) = array[1]::bigint[] from public.matches where is_featured),
  'Rejected input must preserve the old featured selection.'
);
select backend_test.assert_true((select count(*) = 2 from public.matches), 'Rejected input must not insert partial fixtures.');

-- Successful replacement publishes every requested row and clears the old set.
do $$ declare result jsonb; begin
  result := public.publish_featured_fixtures(jsonb_build_array(backend_test.fixture(2), backend_test.fixture(-3)));
  perform backend_test.assert_true(jsonb_array_length(result -> 'published_ids') = 2 and (result ->> 'skipped_deleted')::int = 0, 'Return the actual published IDs.');
  perform backend_test.assert_true(
    (select array_agg(external_fixture_id order by external_fixture_id) = array[-3, 2]::bigint[] from public.matches where is_featured),
    'Successful publication must replace the complete featured set.'
  );
end $$;

-- An existing published row is updated in place; deleted IDs are never restored.
do $$ declare result jsonb; original_id uuid; begin
  select id into original_id from public.matches where external_fixture_id = 2;
  result := public.publish_featured_fixtures(jsonb_build_array(backend_test.fixture(2) || '{"home_team":"Updated Home","is_live":true}'::jsonb, backend_test.fixture(9)));
  perform backend_test.assert_true(result -> 'published_ids' = jsonb_build_array(original_id) and (result ->> 'skipped_deleted')::int = 1, 'Mixed selections must report published IDs and skipped tombstones.');
  perform backend_test.assert_true((select home_team = 'Updated Home' and is_live and is_active and publish_state = 'published' from public.matches where id = original_id), 'Existing fixture metadata must be updated.');
  perform backend_test.assert_true((select deleted_at is not null and not is_featured and not is_active and home_team = 'Keep tombstone' from public.matches where external_fixture_id = 9), 'A tombstone must remain unchanged.');
  result := public.publish_featured_fixtures(jsonb_build_array(backend_test.fixture(9)));
  perform backend_test.assert_true(result -> 'published_ids' = '[]'::jsonb and (result ->> 'skipped_deleted')::int = 1, 'All-deleted selections must return no published IDs.');
  perform backend_test.assert_true((select array_agg(external_fixture_id) = array[2]::bigint[] from public.matches where is_featured), 'All-deleted selections must preserve the featured set.');
end $$;

reset role;
create or replace function backend_test.fail_publication_write()
returns trigger language plpgsql as $$ begin
  if new.external_fixture_id = 4 then
    raise exception 'Simulated replacement write failure.' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger backend_test_fail_publication_write
before insert or update on public.matches
for each row execute function backend_test.fail_publication_write();
set local role authenticated;

-- A failure after the first valid upsert must roll back the entire call.
select backend_test.expect_rejection(jsonb_build_array(backend_test.fixture(5), backend_test.fixture(4)), '23514');
select backend_test.assert_true((select array_agg(external_fixture_id) = array[2]::bigint[] from public.matches where is_featured), 'Write failure must preserve the old featured set.');
select backend_test.assert_true(not exists(select 1 from public.matches where external_fixture_id in (4, 5)), 'Write failure must roll back earlier upserts.');

rollback;
\echo Atomic publication regressions passed: invoker permissions, admin guard, validation, replacement, updates, tombstones, and rollback.
