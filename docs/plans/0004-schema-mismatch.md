# 0004 · A database on another schema

Status: implemented · Owner request, 2026-10-05: the "Couldn't load beads … schema version
mismatch" panel "is a bug more than a safeguard"; handle it automatically, with a helpful opt-in
UI, defaulting to a copy before upgrading and asking for a folder.

## What happens

Each bd release expects a database schema version (bd 1.3.0 expects v66; 1.2.2 wrote v53). bd
upgrades a database whenever a command opens it for writing, but Beady reads with `--readonly`,
and a read-only open can't upgrade anything
([`SchemaBehindError`](https://github.com/gastownhall/beads/blob/v1.3.0/internal/storage/schema/schema.go#L165)).
So after a bd upgrade Beady can be the first thing to meet an old workspace, and it showed bd's
error verbatim.

The upgrade is one-way. Any older bd still writing to the workspace (an agent, CI, another
machine) then refuses the database with the opposite error, "database is at v66, binary knows up
to v53". For a database shared through a Dolt remote, bd may refuse to upgrade in place, because
clones upgrading independently can fork the schema; bd's own guidance is to surface the options to
a person and not auto-run anything
([`AgentDirective`](https://github.com/gastownhall/beads/blob/v1.3.0/internal/storage/schema/remote_migrate_gate.go)).

## A bug found on the way

Two of Beady's own background reads upgraded old databases silently, so most users never saw the
panel at all:

- `bd backup status` ran without `--readonly`, on the belief that bd rejected the flag there.
  bd 1.2.2 and 1.3.0 both accept it.
- `bd config get` (the events-journal check from 0003) also ran without it.

Both opened the store for writing, which applied the migration as a side effect. Both now carry
`--readonly`, and an integration test runs every read the window makes around a load against an
older database and checks it is still on the older schema afterwards.

## What changes

- **Recognised, not echoed.** A failed load whose message is a schema mismatch becomes a typed
  `SchemaMismatch` (behind or ahead, with both versions). bd words the first as plain text and the
  second as JSON with a `schema_skew` object; both are parsed.
- **Behind: offered, never assumed.** The panel explains the versions and that the upgrade is
  one-way. **Upgrade Database…** shows the steps and the exact command, then:
  1. if **Copy the database to a folder first** is ticked (the default), asks for a folder and
     copies `.beads` there as a plain file copy, named with the old schema version;
  2. runs `bd migrate schema`;
  3. reloads, and says where the copy went.
  If the copy fails, nothing is upgraded.
- **The copy is a file copy, not `bd backup`.** Any bd command that opens the database for
  writing, `bd backup` included, applies the migration first, so a bd backup taken "before" the
  upgrade would already hold the new schema. The integration test checks the copy is still the old
  schema by having the new bd refuse it.
- **Shared databases.** If bd refuses (`refusing to … (#4259)`), Beady shows bd's reason and
  points to `bd migrate --inspect`. It never passes `--force`.
- **Ahead: read-only.** For a database a newer bd upgraded, **Open Read-Only** reads with
  `--ignore-schema-skew` for as long as the window is open, with editing off. This isn't offered
  for an older database: bd 1.3.0's own `bd list` fails on schema v53 even with the skew ignored
  ("table not found: leases").
