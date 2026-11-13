---
title: Beady
description: A native macOS app for seeing what a beads (bd) database is doing, and changing it without holding your breath.

# Everything the landing page says is here; layouts/home.html only arranges it.
hero:
  eyebrow: A native macOS app for [beads](https://github.com/steveyegge/beads)
  headline: See what your beads are doing.
  lede: >-
    Beads is an issue tracker built for agents: several of them may be writing to the database
    while you read it. Beady is the window onto that. It keeps up with every write, shows what's
    ready, in flight and stuck, and puts each change of your own behind a preview of the exact
    `bd` commands.
  alt: >-
    Beady's main window. A sidebar lists the views Pipeline, Ready, In Flight, Stuck, Recent,
    Landed, Deferred and Everything with a count beside each. Ready is selected, showing the
    beads that can start now in a table; the details of the first one are open on the right.

views:
  title: Every entry in the sidebar answers a question
  body: >-
    A view is a saved filter with a saved layout, grouping and ordering. The built-in ones are the
    questions you actually ask of a backlog, each with its count. Add a filter on top and save
    the result as a view of your own.
  link: Views and filters
  items:
    - name: Pipeline
      means: Everything live plus the last week of done, as a board.
    - name: Ready
      means: What can start now. Nothing open is blocking it and it isn't deferred.
    - name: In Flight
      means: Work somebody has picked up.
    - name: Stuck
      means: What's waiting on something upstream, with the blocker named.
    - name: Recent
      means: Touched in the last 24 hours, grouped by who has it.
    - name: Landed
      means: Finished and closed in the last week.
    - name: Deferred
      means: Deliberately put on ice.
    - name: Starred
      means: The beads you starred, wherever they are.

layouts:
  title: Three ways to look
  body: >-
    Each view remembers the layout you left it in. Switch with ⌘1, ⌘2 and ⌘3.
  link: Lists, boards and trees
  items:
    - id: list
      name: List
      shot: in-flight
      crop: 640
      caption: A real table, grouped any way you like. Resize and reorder the columns; pinned beads lead every group.
      alt: The In Flight view as a table grouped by status, five beads in progress, with a pinned P0 bug at the top and its details alongside.
    - id: board
      name: Board
      shot: board
      caption: A column per group. Drag a card between columns and the grouping decides what the drop means.
      alt: The Pipeline view as a board with Open, In Flight and Deferred columns of cards, each showing priority, type, title, assignee and labels.
    - id: tree
      name: Tree
      shot: tree
      crop: 640
      caption: Parents and children as an outline, here focused on one epic. Ancestors stay visible when a filter matches a child.
      alt: The tree layout focused on the Offline maps epic, with its six child beads indented beneath it and a progress bar on the parent.

blockers:
  title: Ask what's in the way
  body: >-
    In bd, “blocked” means something upstream has to land first, so Beady says so quietly
    rather than sounding an alarm: a waiting mark on the row, a Blocked by column naming the
    blocker, and the chain in the details as “start now” and “then”. ⌘G opens every dependency
    as one graph. Click a bead and the graph recentres on it, with what it's waiting on drawn
    bold and what's waiting on it tinted.
  link: Blockers and the dependency graph
  shot: graph
  alt: The dependency graph focused on one bead, with arrows running left to right from the beads that must finish first to the beads waiting on them; unrelated chains are faded.

changes:
  title: Change things carefully
  body: >-
    bd has no lock, and agents write whenever they like. So Beady behaves as one writer among
    several, and nothing is written until you've seen exactly what will happen.
  link: Making changes
  shot: confirm
  alt: A confirmation sheet titled “Move map-1.1 to map-2” that spells out the change of parent, with a disclosure for the bd commands that will run and Cancel and Apply Change buttons.
  items:
    - name: Checked first
      means: Each change is validated against the loaded data, then compared with what's in bd at that moment.
    - name: Shown to you
      means: The confirmation lists the change, any warnings, and the bd commands themselves.
    - name: Read back
      means: Afterwards Beady re-reads the bead. Landed, failed or uncertain is looked up, never guessed.
    - name: Live-work warnings
      means: If another actor touched the bead recently, the row and the sheet say who and when.

keyboard:
  title: Everything from the keyboard
  body: >-
    ⌘P runs any command or jumps to a bead by id or title. It answers to the words you'd actually
    type: “kanban” finds the board, “drac” finds the theme.
  link: The keyboard
  shot: palette
  alt: The command palette, a search field above a list of commands such as Open Beads Workspace, New Bead, Toggle Pin and Show Dependency Graph, each with its shortcut.
  keys:
    - { key: "⌘P", does: "Command palette" }
    - { key: "/", does: "Search" }
    - { key: "F", does: "Filter" }
    - { key: "⇧V", does: "Display options" }
    - { key: "⌘N", does: "New bead" }
    - { key: "⌘E", does: "Edit" }
    - { key: "⌘G", does: "Dependency graph" }
    - { key: "⇧⌘P", does: "Pin" }
    - { key: "⇧⌘S", does: "Star" }
    - { key: "?", does: "Every shortcut" }

themes:
  title: Themes, and eyes that need help
  body: >-
    Dracula, One Dark, Nord, Solarized Light, GitHub Light and One Light, plus a high-contrast
    pair that follows macOS's Increase Contrast setting. A theme paints the whole window, and the
    picker repaints the app as you arrow through it, so you judge a theme by the app rather than
    by five dots. Every theme's contrast is checked by tests. Text scales from Small to Extra
    Large, and the app speaks seven languages.
  link: Themes, text size and languages
  shot: themes
  alt: The theme picker listing Dracula, One Dark, Nord and High Contrast Dark, then the light themes, each with a row of sample colours.

install:
  title: Install it
  body: >-
    You need macOS 15 or later and `bd` on your PATH (`brew install beads`). The Homebrew cask is
    built for Apple silicon.
  note: >-
    The app is ad-hoc signed rather than notarised, so the first launch needs **Open Anyway** in
    System Settings → Privacy & Security. The guide covers that, Intel Macs and building from source.
  link: Installing and first launch
---
