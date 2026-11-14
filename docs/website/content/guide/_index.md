---
title: The Beady guide
linkTitle: Guide
description: How to install Beady and use it to read, filter and change a beads database.
---

Beady is a Mac app for [beads](https://github.com/steveyegge/beads), the issue tracker built
for agents. It reads a `bd` database, keeps up as agents write to it, and lets you change it
with every write previewed first. This guide goes through the app in the order you'll meet it.

If you haven't used beads: a **bead** is an issue. Beads have a status, a priority from P0 to
P4, a type, an optional parent, and dependencies on one another. bd stores them in a database
inside your project's `.beads` folder.
