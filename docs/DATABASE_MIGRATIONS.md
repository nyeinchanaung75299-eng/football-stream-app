# Database setup and migration history

## Fresh project

1. Run `supabase/schema.sql` to create the base tables and required columns.
2. Apply every SQL file in `supabase/migrations/` in filename order. With the
   Supabase CLI, link the new project and run `supabase db push` after the base
   schema has been created. Inspect `supabase migration list --linked` afterward.
3. Configure server-side gateway and monitoring credentials separately. Do not
   put those credentials, raw playback URLs, or keys in migration files.
4. Publish the apps and add real stream data only after the migrations finish.

The base schema alone is not the production schema. Later migrations protect raw
stream rows, create the compatible public count view, add atomic publishing and
monitoring, and harden access policies. Anonymous clients read published match
metadata and safe counts; protected playback is resolved through the gateway.

The original `20261007_atomic_featured_publish.sql` has been renamed to
`20261007000000_atomic_featured_publish.sql`, retaining identical SQL. The CLI
accepts numeric versions of different lengths but sorts filenames bytewise.
The short filename sorted after `20261007134500_keep_existing_featured_matches.sql`
and could restore the older replacement implementation on a fresh database.
Padding its existing date with midnight makes the additive implementation run last.

## Existing production project

Do not rerun the base schema or old migrations to repair history. Some historical
SQL deliberately replaces earlier definitions; replaying it can change current
behavior or fail because monitoring tables and triggers already exist.

On 10 October 2026, the five recorded production migrations were matched to repo
SQL and their local filenames were aligned to their actual recorded versions:

| Previous repo version | Recorded production version | Migration |
| --- | --- | --- |
| `20261005145000` | `20261005145326` | `protect_stream_links_behind_gateway` |
| `20261005150000` | `20261005150014` | `exclude_unrewritten_dash_from_public_counts` |
| `20261006013000` | `20261005193334` | `include_protected_dash_in_public_counts` |
| `20261009041557` | `20261009043306` | `admin_system_monitor` |
| `20261009124857` | `20261009164926` | `gateway_stream_metadata` |

SQL contents are unchanged. The first recorded migration additionally contains an
operational gateway-secret seed that is intentionally absent from source control.
Do not export or commit its full recorded statements. Leave existing remote
records intact; use version/name metadata for reconciliation.

Three additional migrations were already effective despite missing history rows.
Read-only checks before the hardening migration established:

- `20261006024000_count_all_visible_stream_lines`: the count view exposed only
  `match_id uuid` and `stream_count integer`. Its definition matched active,
  non-WebView, nonempty-URL, current availability/expiry filtering for published
  featured matches, without excluding keyed streams. Comparing the view with
  the migration's query in both directions found zero different rows; all nine
  current keyed lines counted.
- `20261007000000_atomic_featured_publish`: `matches.deleted_at` already existed
  as nullable `timestamptz`, and the publishing RPC already returned JSON, checked
  Admin authorization, skipped deleted fixtures, and upserted by fixture ID.
  Its older replacement behavior had been superseded by the next migration.
- `20261007134500_keep_existing_featured_matches`: the live publishing function
  body matched the repo version after removing whitespace and comments. It kept
  existing available featured matches and cleaned only explicitly unavailable
  ones.

Production reconciliation used the authenticated Supabase SQL connector because
CLI database credentials were unavailable. It inserted only these three missing
`version`, `name`, and `statements` records into
`supabase_migrations.schema_migrations`, using the original repo SQL as stored
history text and `ON CONFLICT DO NOTHING`. The stored SQL was not executed, and
the five existing records were left untouched. This was a metadata-only repair
equivalent to recording those specific versions as applied.

The new `harden_stream_counts_and_policies` migration was then applied normally
and recorded as `20261010043548`; its committed filename uses that version.
The final history contains all nine matching repo versions. Live checks confirmed
an invoker count view, nine playable lines, and working Admin authorization.

Only after verifying those conditions for the target database, record these
specific migrations as applied without executing their SQL. When CLI database
credentials are available, the equivalent commands are:

```bash
supabase migration repair \
  20261006024000 20261007000000 20261007134500 \
  --status applied --linked --project-ref YOUR_PROJECT_REF
supabase migration list --linked --project-ref YOUR_PROJECT_REF
```

CLI `2.120.0` supports these commands. Never omit the explicit versions from
`migration repair`: that mode rebuilds the entire history table. For databases
where the checks do not pass, resolve the schema difference before recording an
applied version. A fresh database must execute the migrations normally.

Create future migration files using `supabase migration new <name>`. Apply final
DDL once, then ensure its recorded remote version matches the committed filename.
Verify public count reads, protected playback, Admin writes, and non-Admin denial
after security changes; run the Supabase advisors again.

## Local verification

With Docker available, run:

```bash
bash scripts/test_database_security.sh
```

The script creates a disposable `postgres:17` container, initializes test roles
and Auth helpers, applies the base schema and every migration in filename order,
and runs the database security checks. It removes the container afterward and
does not connect to production or require production credentials.
