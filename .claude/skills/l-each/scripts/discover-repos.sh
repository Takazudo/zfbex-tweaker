#!/usr/bin/env bash
# Print absolute paths of the zfb example sites that /l-each operates on, one per line.
#
# A "zfb example site" is a git repository named zfb-example-* sitting next to
# zfbex-tweaker (same parent directory). zfbex-tweaker itself is excluded because it
# does not match zfb-example-* ("zfbex", no dash). New example sites are picked up
# automatically just by being cloned as a sibling -- no edit to this script needed.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# scripts/ -> l-each/ -> skills/ -> .claude/ -> <zfbex-tweaker repo root>
tweaker_root="$(cd "$script_dir/../../../.." && pwd)"
parent="$(cd "$tweaker_root/.." && pwd)"

found=0
for d in "$parent"/zfb-example-*; do
  [ -d "$d/.git" ] || continue
  printf '%s\n' "$d"
  found=1
done

if [ "$found" -eq 0 ]; then
  echo "no zfb-example-* sibling git repos found next to $tweaker_root" >&2
  exit 1
fi
