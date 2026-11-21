#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_container="nca-db-security-test-$$"
trap 'docker rm -f "$test_container" >/dev/null 2>&1 || true' EXIT
docker run --rm -d --name "$test_container" -v "$repo_root:/nca-repo:ro" -e POSTGRES_PASSWORD=local-test-only postgres:17 -c wal_level=logical >/dev/null
for attempt in {1..60}; do
  if docker exec "$test_container" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then break; fi
  sleep 1
done
docker exec "$test_container" createdb -U postgres nca_security_test
run_sql() { docker exec -i -w /nca-repo/scripts "$test_container" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d nca_security_test "$@"; }
run_sql <<'SQL'
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create schema extensions;
create extension pgcrypto with schema extensions;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable set search_path='' as $$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
$$;
grant usage on schema public, auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
create publication supabase_realtime;
SQL
run_sql < "$repo_root/supabase/schema.sql"
# Replay all historical migrations in filename order, just like the CLI.
for migration in "$repo_root"/supabase/migrations/*.sql; do
  run_sql --single-transaction < "$migration"
done
run_sql < "$repo_root/scripts/test_database_security.sql"
run_sql < "$repo_root/scripts/test_channel_station_names.sql"
run_sql < "$repo_root/scripts/test_channel_logo_sync.sql"
run_sql < "$repo_root/scripts/test_channel_permanent_delete.sql"

run_sql < "$repo_root/scripts/test_repository_match_publish.sql"

run_sql < "$repo_root/scripts/test_atomic_channel_editor.sql"

run_sql < "$repo_root/scripts/test_source_import_workflows.sql"

run_sql < "$repo_root/scripts/test_repository_snapshot_removals.sql"
run_sql < "$repo_root/scripts/test_repository_partial_imports.sql"
run_sql < "$repo_root/scripts/test_four_github_sources.sql"
run_sql < "$repo_root/scripts/test_metadata_only_match_import.sql"
run_sql < "$repo_root/scripts/test_stream_hub_pipeline.sql"

run_sql < "$repo_root/scripts/test_stream_hub_commit_budget.sql"
