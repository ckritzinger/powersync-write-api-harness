#!/usr/bin/env bash
# Points src/example-client at a powersync-reference-write-implementation checkout's example-client/src, so the harness runs
# the reference connector itself rather than a copy. Default: the sibling checkout ../powersync-reference-write-implementation.
#   scripts/link-example-client.sh [/path/to/powersync-reference-write-implementation]
set -euo pipefail
app="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-$app/../../powersync-reference-write-implementation}"
src="$(cd "$target/example-client/src" && pwd)"
[ -f "$src/PowersyncConnector.ts" ] || { echo "No PowersyncConnector.ts under $src" >&2; exit 1; }
ln -sfn "$src" "$app/src/example-client"
echo "src/example-client -> $src"
