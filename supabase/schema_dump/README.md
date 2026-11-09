# schema_dump — the migrations the database has actually run

This folder is a faithful export of `supabase_migrations.schema_migrations`
from the live project: every migration the database has applied, in order,
with its real version stamp as the filename.

It exists because `supabase/migrations/` had drifted. At the time of the
export the database had run **124** migrations and only **24** of them
matched a file in that folder by name — the other 100 lived nowhere but in
the database. A project whose schema exists only inside the service it runs
on has no backup, so this folder is the recoverable copy.

## Which folder is authoritative

| | `migrations/` | `schema_dump/` |
|---|---|---|
| Written by | hand, as changes were made | exported from the database |
| Complete | no — drifted | yes, as of the export |
| Use it to | read the intent behind a change | rebuild the schema |

`schema_dump/` is the one to trust for *what the database contains*.
`migrations/` is kept because its files carry the commentary explaining why
each change was made, which the export cannot recover.

## Rebuilding from this folder

Applied in filename order, these reproduce the schema:

```sh
for f in supabase/schema_dump/*.sql; do psql "$DATABASE_URL" -f "$f"; done
```

Order matters — the names sort chronologically, which is the order they were
originally applied in.

## Keeping it current

This is a point-in-time export, not a live mirror. Re-export after a batch of
schema changes:

```sql
select version, name, array_to_string(statements, E';\n\n') as sql
  from supabase_migrations.schema_migrations
 order by version;
```

and write one file per row as `<version>_<name>.sql`.

## What this is not

Not a data backup. It rebuilds tables, functions, views, policies and
triggers — not a single row of employee, attendance, leave or payroll data.
Those need Supabase's own database backups, which are configured in the
project dashboard and are a separate thing to verify.
