#!/usr/bin/env bash
# Copies the harness overrides into a powersync-reference-write-implementation checkout, keeping .orig backups.
#   ./apply.sh /path/to/powersync-reference-write-implementation          apply
#   ./apply.sh /path/to/powersync-reference-write-implementation --revert restore the originals
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
target="${1:?usage: apply.sh /path/to/powersync-reference-write-implementation [--revert]}"
files=("authorizer.ts:backend/src/auth/authorizer.ts" "fatal-error-handler.ts:backend/src/fatal-error-handler.ts")

for pair in "${files[@]}"; do
  src="${pair%%:*}"; dest="$target/${pair#*:}"
  [ -f "$dest" ] || { echo "missing $dest — is $target a powersync-reference-write-implementation checkout?" >&2; exit 1; }
  if [ "${2:-}" = "--revert" ]; then
    if [ -f "$dest.orig" ]; then mv "$dest.orig" "$dest"; echo "restored $dest"; else echo "no backup for $dest"; fi
  else
    [ -f "$dest.orig" ] || cp "$dest" "$dest.orig"
    cp "$here/$src" "$dest"
    echo "applied $src -> $dest"
  fi
done
