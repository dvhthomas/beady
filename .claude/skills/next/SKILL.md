---
name: next
description: Pick up the next piece of beady work — triage bd ready, claim an issue, restate acceptance criteria, and start tests-first. Use at the start of a session, or when the user says "what's next" or "work the backlog".
---

# Next

1. `bd ready` (and `bd blocked` if it is empty). If the user named specific work, find its
   bead with `bd search` or create one with `bd create` instead of picking from the backlog.
2. Pick the highest-priority ready issue unless told otherwise. `bd show <id>` and read any
   linked design notes or plans under `docs/plans/`.
3. `bd update <id> --claim`.
4. Restate the goal and acceptance criteria in one short paragraph and surface your
   assumptions before writing code. If a user will notice the change, name the page of the
   user guide (`docs/website/content/guide/`) that will need updating: it ships in the same
   pull request.
5. Work tests-first. Pure logic (filtering, views, glossary, rendering) belongs in
   `BeadsCore`, `BeadsData` or `BeadsPresentation` with tests; the `Beady` app target only
   wires those to AppKit, the filesystem and the `bd` CLI. Anything that moves or
   acknowledges something on screen follows `docs/INTERACTION-DESIGN.md`.
6. When the work is done and verified, use the **ship** skill.
