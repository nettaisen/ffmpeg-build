#!/usr/bin/env bash
# Write the raw inputs the smoke test feeds ffmpeg (smoke/make_streams.rs says
# what they are): the bytes nettai writes to its children's standard inputs.
# Needs rustc.
#
# Usage: make-streams.sh OUT_DIR
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ $# -eq 1 ] || { echo "usage: $0 OUT_DIR" >&2; exit 2; }
mkdir -p "$1"
OUT="$(cd "$1" && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

rustc --edition 2024 -O -o "$WORK/make-streams" "$HERE/../smoke/make_streams.rs"
"$WORK/make-streams" "$OUT"
ls -l "$OUT"
