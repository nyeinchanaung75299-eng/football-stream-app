#!/usr/bin/env python3
"""Run after test_atomic_publish.sql in the disposable football_backend_test DB."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("--docker-container", help="Use the container's psql instead of local psql/DATABASE_URL")
args = parser.parse_args()
env = os.environ.copy()
if args.docker_container:
    for key in ("DOCKER_HOST", "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH"):
        env.pop(key, None)
    command = ["docker", "--host", "unix:///var/run/docker.sock", "exec", "-i", args.docker_container,
               "psql", "-U", "postgres", "-d", "football_backend_test"]
else:
    database_url = os.environ.get("DATABASE_URL")
    if not database_url:
        parser.error("Set DATABASE_URL or provide --docker-container")
    command = ["psql", database_url]
command += ["-X", "-A", "-t", "-v", "ON_ERROR_STOP=1"]


def sql(statement):
    result = subprocess.run(command, input=statement, text=True, capture_output=True, env=env, timeout=15)
    if result.returncode:
        raise AssertionError(result.stderr)
    return result.stdout.strip()


def wait_until(query, message):
    deadline = time.monotonic() + 6
    while time.monotonic() < deadline:
        if sql(query).splitlines()[-1] == "t":
            return
        time.sleep(0.05)
    raise AssertionError(message)


admin = "10000000-0000-0000-0000-000000000001"


def publication(ids, app_name, hold=False, legacy=False):
    fixtures = [{
        "external_fixture_id": fixture_id, "source": "api_football", "league": "Concurrency League",
        "home_team": f"Home {fixture_id}", "away_team": f"Away {fixture_id}",
        "kickoff_at": "2026-10-06T12:00:00Z", "status_short": "NS", "is_live": False,
    } for fixture_id in ids]
    if legacy:
        fixtures = [{
            'fixture_id': item['external_fixture_id'], 'provider': item['source'],
            'league_name': item['league'], 'home_name': item['home_team'],
            'away_name': item['away_team'], 'kickoff_at': item['kickoff_at'],
            'status_short': item['status_short'], 'is_live': item['is_live'],
        } for item in fixtures]
    payload = json.dumps(fixtures)
    rpc = 'publish_featured_matches' if legacy else 'publish_featured_fixtures'
    return f"""
begin;
set local statement_timeout = '10s';
set local application_name = '{app_name}';
set local role authenticated;
select set_config('request.jwt.claim.sub', '{admin}', true);
select public.{rpc}('{payload}'::jsonb);
{'select pg_sleep(2);' if hold else ''}
commit;
"""


assert sql("select current_database();") == "football_backend_test", "Use the disposable football_backend_test database."
sql(f"""
insert into auth.users(id) values ('{admin}') on conflict do nothing;
insert into public.profiles(id,role) values ('{admin}','admin') on conflict(id) do update set role='admin';
insert into public.matches(external_fixture_id,league,home_team,away_team,kickoff_at)
values (100,'Old League','Old Home','Old Away',now());
""")

try:
    with ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(sql, publication([10, 11], "football-publish-first", hold=True))
        wait_until("select exists(select 1 from pg_stat_activity where application_name='football-publish-first' and wait_event='PgSleep');",
                   "First publication did not hold its transaction open.")
        second = pool.submit(sql, publication([12, 13], "football-publish-second", legacy=True))
        wait_until("select exists(select 1 from pg_locks l join pg_stat_activity a on a.pid=l.pid where a.application_name='football-publish-second' and l.locktype='advisory' and not l.granted);",
                   "Concurrent publication did not wait for the transaction advisory lock.")
        first.result()
        second.result()

    assert sql("select array_agg(external_fixture_id order by external_fixture_id) from public.matches where is_featured;") == "{12,13}", \
        "The later complete publication must replace the earlier set without mixing both selections."

    # A soft deletion outside the RPC can win a conflicting row lock. The
    # publication must re-check deleted_at after the delete commits.
    sql("insert into public.matches(external_fixture_id,league,home_team,away_team,kickoff_at,is_featured) values (14,'Keep League','Keep Tombstone','Keep Away',now(),false);")
    soft_delete = f"""
begin;
set local statement_timeout = '10s';
set local application_name = 'football-soft-delete';
set local role authenticated;
select set_config('request.jwt.claim.sub', '{admin}', true);
update public.matches set deleted_at=now(),is_active=false,is_featured=false,publish_state='draft' where external_fixture_id=14;
select pg_sleep(2);
commit;
"""
    with ThreadPoolExecutor(max_workers=2) as pool:
        deletion = pool.submit(sql, soft_delete)
        wait_until("select exists(select 1 from pg_stat_activity where application_name='football-soft-delete' and wait_event='PgSleep');",
                   "Soft deletion did not hold its row lock.")
        publish = pool.submit(sql, publication([14, 15], "football-publish-tombstone"))
        wait_until("select exists(select 1 from pg_locks l join pg_stat_activity a on a.pid=l.pid where a.application_name='football-publish-tombstone' and not l.granted);",
                   "Publication did not wait for the conflicting tombstone update.")
        deletion.result()
        output = publish.result()
    result = next(json.loads(line) for line in output.splitlines() if line.startswith('{"'))
    assert result["skipped_deleted"] == 1 and len(result["published_ids"]) == 1
    assert sql("select deleted_at is not null and not is_active and not is_featured and home_team='Keep Tombstone' from public.matches where external_fixture_id=14;") == "t", \
        "A concurrent deletion tombstone must never be restored."
    assert sql("select array_agg(external_fixture_id) from public.matches where is_featured;") == "{15}"
finally:
    sql(f"""
delete from public.matches where external_fixture_id in (10,11,12,13,14,15,100);
delete from public.profiles where id='{admin}';
delete from auth.users where id='{admin}';
""")

print("Atomic publication concurrency regressions passed: serialized replacements and concurrent tombstone preservation.")
