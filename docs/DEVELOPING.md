# Developing Beady

How the app is put together, how to test it, and how the website and releases work. For what
the app does and how to use it, see the [user guide](https://dvhthomas.github.io/beady/guide/).

```bash
scripts/test.sh        # the whole suite (Swift Testing); the gate before any pull request
swift build            # compile check
scripts/bundle.sh      # build build/Beady.app
scripts/dev-watch.sh   # rebuild and relaunch the app on source changes
```

## Architecture

```
Beady (app target)      SwiftUI views + AppSession composition root
   │            │
   ▼            ▼
BeadsPresentation   BeadsData     WorkspaceModel (per-view state) │ BDGateway + BDStore
        │               │
        └──────► BeadsCore ◄──────┘  Issue, IssueSnapshot, Scope, IssueFilter,
                                     IssueQuery, IssueTree, IssueBoard  (pure, no I/O)
```

- **BeadsCore** is the domain: the snapshot, lifecycle scopes, Linear-style view filtering
  (`ViewSource`, `FilterRule`, `ViewFilter`, `FilterOptions`, `IssueGrouping`), sorting, tree
  building (cycle-safe), and the change pipeline (`IssueChange`, `ChangeValidator`, `ChangeGuard`,
  `ChangeRunner`). It defines the single `BeadsStore` port.
- **BeadsData** implements that port. Every bd invocation is a typed `BDCommand` run by one
  `BDGateway`, which also owns the change token and workspace detection. Reads always carry
  `--readonly`; the writes are `update`, `close`, `reopen`, `create`, `config set-many`, `backup`,
  the sharing commands (`dolt remote add`, `dolt push`, `dolt pull --strategy`, `sync`, and
  `federation status`, which fetches) and `init` and `bootstrap` (run inside the folder rather
  than through `-C`: bd refuses init that way, and bootstrap misses the origin's beads; see
  [plans/0006-sharing.md](plans/0006-sharing.md)). `BDStore` implements
  `BeadsStore` purely through the gateway, and an architecture test keeps it that way. Underneath:
  locating `bd` (Finder-launched apps get a minimal PATH), non-blocking pipe draining, timeouts and
  cancellation that escalate SIGTERM to SIGKILL (bd traps SIGTERM), and per-record JSON decoding.
- **BeadsPresentation** holds all view state and decisions in a UI-framework-free `@Observable`
  model, so it's unit-tested without SwiftUI.
- **Beady** is thin SwiftUI plus the composition root.

### Why the bd CLI rather than reading Dolt directly

bd owns its storage: embedded or server Dolt, schema migrations, and derived fields (`parent`,
dependency types, status categories). Reading Dolt tables directly would couple the viewer to
bd's internal schema and need a MySQL-protocol client or the Dolt engine embedded in the app.
One `bd --readonly list --json --all --limit 0 --flat` returns the whole database (about 0.3s for
~70 issues), and all filtering happens in memory, which keeps the UI instant. The loader sits
behind a protocol, so a direct Dolt adapter can replace it later without touching the rest.

### Change detection

Polling every 2s compares a fingerprint of `.beads/last-touched`, `.beads/issues.jsonl` (mtime
and size) and Dolt's `noms` files (**size only**). Even `bd --readonly` bumps the mtime of Dolt's
manifest and journal, so mtimes there would make every reload trigger another. Data older than
five minutes is reloaded regardless, to cover writes the probe can't see (such as a remote Dolt
server).

## Tests

```bash
scripts/test.sh
```

Swift Testing, test-first per layer: domain rules, JSON decoding against realistic bd output, the
CLI loader with a fake runner (asserting it only ever runs `--readonly list` / `statuses`), the
process runner (pipe deadlocks, timeouts), and the presentation model (loading, change-driven
refresh, scope/filter/sort, chips, tree, board).

An opt-in integration test uses the real `bd` against an existing workspace, read-only, and checks
that reading doesn't register as a change:

```bash
BEADY_IT_WORKSPACE=/path/to/project scripts/test.sh
```

A second opt-in test writes through the real bd: it creates epics and a bead, edits it, moves it
between epics, confirms a loop is refused, closes and reopens it, and checks the result. It only
runs against a workspace containing a `.beady-scratch` marker file, so it can't touch a real
project:

```bash
BEADY_IT_WRITABLE_WORKSPACE=/path/to/scratch-project scripts/test.sh
```

Behind the same gate, a third test creates a database the way the app does: `git init` in a
temporary folder, `bd init` with Beady's defaults through the real bd, then a check that the
result opens, took the prefix, and has no agent files or hooks. It never touches the scratch
workspace, only its own temporary folder.

`scripts/test.sh` also passes the Swift Testing macro plugin path when only the Command Line Tools
are installed, since SwiftPM doesn't find it on its own there. For the same reason (no SwiftUI
macro plugin in the Command Line Tools) the views use `State` as a plain stored property rather
than the `@State` macro.

## Seeing the UI without a window

`BEADY_SNAPSHOT_DIR=/tmp/shots build/Beady.app/Contents/MacOS/Beady --workspace <project>` renders
the main views to PNGs offscreen, which is how UI changes get checked without a window — and
how the website's screenshots are made (below). `BEADY_SNAPSHOT_SCALE=2` writes them at Retina
size. `BEADY_VERIFY_KEYS=1` types
into a real window and reports whether the single-key shortcuts and the keyboard focus behave.

`swift scripts/make-icon.swift` redraws `Resources/AppIcon.icns`.

## The website

The landing page and user guide at <https://dvhthomas.github.io/beady/> are a Hugo site in
[docs/website](website); its [README](website/README.md) says how it is laid out. The short
version:

```bash
brew install hugo
hugo server --source docs/website     # http://localhost:1313/beady/
scripts/screenshots.sh                # retake every screenshot from the app
```

`scripts/screenshots.sh` builds the app, makes a throwaway demo database with
`scripts/demo-workspace.sh`, runs the snapshot mode above against it under a scratch bundle
identifier (so your own settings neither show up in the pictures nor get touched), and copies
the snapshots the site uses into `docs/website/assets/screenshots`.

The Website workflow ([pages.yml](../.github/workflows/pages.yml)) does the same on every
merge to master, after the Version workflow, and deploys the result to GitHub Pages, so the
published pictures and version number always match the release. **A change a user would
notice updates the guide in the same pull request**; see "The website and user guide" in
[CLAUDE.md](../CLAUDE.md).

## Releasing

Every merge to master is a release. A `release:minor` or `release:major` label on the pull
request says how big it is; no label means a patch. CI works out the next version, writes
`VERSION`, tags it, builds the app, attaches the zip to a GitHub Release, and rewrites the
Homebrew cask. [RELEASE.md](../RELEASE.md) has the details and what to check afterwards.

This app's own work is tracked in beads — `bd list` in a clone of your own. The backlog
itself stays on the machine it's worked on; only bd's configuration is committed.
