# Languages

Beady speaks English, German, Spanish, French, Japanese, Korean and Brazilian Portuguese. It
follows the Mac's language by default; **Settings › Language** (⌘,) picks one for Beady alone,
and System Settings › General › Language & Region › Applications does the same thing — both
write macOS's own per-app `AppleLanguages` key, so they never disagree. A change takes effect at
the next launch; Settings offers **Relaunch Now**.

## How the strings are organised

Every module keeps its own [String Catalog](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog),
one JSON file, next to its code:

| Catalog | What's in it |
|---|---|
| `Sources/Beady/Localizable.xcstrings` | the windows, sheets, menus, tooltips and buttons |
| `Sources/BeadsPresentation/Localizable.xcstrings` | view names, command names, filter words, hover help, change descriptions |
| `Sources/BeadsCore/Localizable.xcstrings` | validation messages and failure reports |
| `Sources/BeadsData/Localizable.xcstrings` | errors from running bd |

The English text is the key. Each key carries a `localizations` entry per language, and often
a `comment` saying where the string appears and what its placeholders hold. `%@` is a string,
`%lld` a number; `%1$@` and `%2$lld` are the same with positions, for languages that need a
different order. Plural strings carry `variations.plural` with `one` and `other` forms (Japanese
and Korean use `other` only).

The code reads them the standard way: SwiftUI text in the app target (`Text("Filter")`,
`.help("…")`, `Button("Cancel")`) is looked up in the app bundle, and the library modules use
`String(localized: "…", bundle: .module)`. Nothing is wrapped in a helper, so Xcode's own
tooling understands all of it.

Beside each catalog sits an empty `en.lproj/Localizable.strings`. English is the source
language, so the catalog compiles it to a `Localizable.stringsdict` (the plural forms) and
nothing else, and macOS 15 reads a stringsdict only next to a strings file of the same name.
Leave the file empty: a key written there would override the catalog.

**The build system matters.** Only SwiftPM's Swift Build backend compiles a catalog into
`.lproj` folders; the older build system copies the `.xcstrings` file into the bundle untouched,
which Foundation can't read, and the app comes up in English with no plural forms. Swift 6.4
uses Swift Build by default; Swift 6.1 to 6.3 have it behind `--build-system swiftbuild`, which
`scripts/test.sh`, `scripts/bundle.sh` and `scripts/sync-strings.sh` pass whenever the toolchain
knows the flag (`scripts/swift-flags.sh`). The release workflow builds on macos-26 for the same
reason, and a test fails with a message saying so if a build ever ships uncompiled catalogs.

`scripts/bundle.sh` ships the compiled catalogs inside `Beady.app`: the modules' resource
bundles whole, and the app target's `.lproj` folders directly under `Contents/Resources`, which
is also what tells macOS the app is localised.

## Improving a translation

1. Open the catalog in Xcode (it has an editor for `.xcstrings`) or any text editor, find the
   key, and change the value under your language. Keep every placeholder.
2. Run the tests. `scripts/test.sh` checks every catalog is complete for every language Beady
   offers and that each translation keeps the placeholders the code fills in; a broken entry
   fails here, not in front of a user.
3. Open a pull request. Say which language you checked and in what, if you can (the Mac's
   language, or Settings › Language).

A translation that reads like Apple's own apps in that language is the aim: sentence case for
menu items outside English, the language's own quotation marks, Apple's names for things like
System Settings and Increase Contrast, and bd's own words (`open`, `in_progress`, `wip`,
`frozen`, `bd ready`…) left exactly as they are, because they are what the database says.

## Adding a language

1. Add its identifier to `LanguageSetting.supported` in
   `Sources/BeadsPresentation/LanguageSetting.swift` (Apple's identifiers: `it`, `zh-Hans`,
   `pt-PT`…). That is what the picker, the palette and the catalog tests read.
2. Add the language to each of the four catalogs — in Xcode, the + at the bottom of the catalog
   editor; by hand, a `localizations` entry per key.
3. Run `scripts/test.sh`: the catalog tests list every key still missing.

## Adding or changing text in the code

Write the English in the code as usual — `Text("New Bead")`, `.help("…")`,
`String(localized: "…", bundle: .module)` in a library module — with a `comment:` where a short
string could mean several things. Then:

```bash
scripts/sync-strings.sh
```

It builds, collects the strings the compiler saw in every module, and merges them into the
catalogs: new keys appear untranslated, keys no longer in the code are removed, existing
translations are untouched. Translate the new keys (the tests say which are missing), and
commit the catalogs with the code. The script needs Xcode, because it uses `xcstringstool`.
