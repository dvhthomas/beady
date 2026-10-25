#!/usr/bin/env bash
# Brings each module's String Catalog (Sources/<Module>/Localizable.xcstrings) up to date with
# the strings its code actually uses. The compiler records every localizable literal — SwiftUI
# text, String(localized:) — as .stringsdata while building, and xcstringstool merges them: new
# keys appear (untranslated), keys no longer in code are removed. Translations are untouched.
#
#     scripts/sync-strings.sh
#
# Run it after adding or changing on-screen text, then fill in the translations (see
# docs/LOCALIZATION.md). Needs Xcode (xcstringstool); the Command Line Tools don't carry it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${SCRATCH:-$ROOT/.build}"
# shellcheck source=swift-flags.sh
source "$ROOT/scripts/swift-flags.sh"

swift build --package-path "$ROOT" --scratch-path "$SCRATCH" "${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}" >/dev/null

for module in BeadsCore BeadsData BeadsPresentation Beady; do
  catalog="$ROOT/Sources/$module/Localizable.xcstrings"
  # The build keeps one .stringsdata per source file under the module's intermediates folder.
  files=()
  while IFS= read -r file; do files+=("$file"); done < <(
    find "$SCRATCH" -path "*/${module}-*.build/*" -name "*.stringsdata" \
      ! -name "resource_bundle_accessor.stringsdata" ! -name "GeneratedStringSymbols_*" | sort
  )
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "sync-strings: no .stringsdata for $module; was it built?" >&2
    exit 1
  fi
  xcrun xcstringstool sync "$catalog" --stringsdata "${files[@]}"
  echo "$module: $(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['strings']))" "$catalog") strings"
done
