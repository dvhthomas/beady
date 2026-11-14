# The Beady website

The landing page and user guide published at <https://dvhthomas.github.io/beady/>. It is a
[Hugo](https://gohugo.io) site with no theme and no dependencies: the layouts, stylesheet and
script are all in this folder.

```bash
brew install hugo                    # the extended build, 0.146 or later
hugo server --source docs/website    # from the repository root; http://localhost:1313/beady/
```

## Where things are

| What | Where |
|---|---|
| The landing page's words | `content/_index.md` (front matter; `layouts/home.html` arranges it) |
| The guide, one page per file | `content/guide/*.md`, ordered by `weight` |
| Screenshots | `assets/screenshots/*.png`, written by `scripts/screenshots.sh` |
| Page templates | `layouts/` (`home.html`, `section.html`, `page.html`, `_partials/`) |
| Styles and script | `assets/css/main.css`, `assets/js/site.js` |
| The search index | `layouts/home.json`, built into `/index.json` |
| The version shown | The repository's `VERSION` file, mounted in `hugo.toml` |

## Writing guide pages

Plain Markdown, plus two shortcodes:

```text
{{</* k "⌘P" */>}}                               a key, drawn as a keycap
{{</* shot name="board" alt="…" caption="…" */>}}   a screenshot from assets/screenshots
```

`shot` also takes `crop="600"` (keep that many points from the top; the snapshot window is
tall), `light="ready-light"` (a second screenshot for readers in light mode) and
`frame="window"` or `"panel"`. A name that isn't in `assets/screenshots` fails the build.

Search needs nothing from you: every page and every `##` section is indexed when the site is
built, and the matching happens in the reader's browser.

## Screenshots

Nobody takes them by hand. `scripts/screenshots.sh` builds the app, creates a demo database
(`scripts/demo-workspace.sh`), renders the app's views offscreen and copies the ones listed at
the top of the script into `assets/screenshots`. To add a picture:

1. Make sure `SnapshotMode.run` in `Sources/Beady/SnapshotMode.swift` captures the view.
2. Add a `site-name=snapshot-name` line to `SHOTS` in `scripts/screenshots.sh`.
3. Run the script, then use `{{</* shot name="site-name" … */>}}`.

The copies in the repository are what a local preview and the README show. The published site
doesn't depend on them being fresh: the Website workflow retakes them on every deploy.

## Publishing

`.github/workflows/pages.yml` builds and deploys the site after every merge to master (it
follows the Version workflow, so the version shown is the one just released), and builds it
without deploying on pull requests that touch it. Pages is set to deploy from GitHub Actions;
there is no `gh-pages` branch.
