#!/usr/bin/env bash
# Write the NUT streams the smoke test feeds ffmpeg (smoke/make_streams.rs
# says what they are), with nettai's own NUT writer: nettai's
# crates/nettai-video/src/nut.rs at the commit NETTAI_REF names (pinned in
# scripts/ffmpeg-config-common.sh), compiled beside smoke/make_streams.rs with
# rustc. Needs curl and rustc.
#
# Usage: make-streams.sh OUT_DIR
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ffmpeg-config-common.sh
source "$HERE/ffmpeg-config-common.sh"

[ $# -eq 1 ] || { echo "usage: $0 OUT_DIR" >&2; exit 2; }
mkdir -p "$1"
OUT="$(cd "$1" && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -fsSL -o "$WORK/nut.rs" \
  "https://raw.githubusercontent.com/bigfarts/nettai/${NETTAI_REF}/crates/nettai-video/src/nut.rs"
cp "$HERE/../smoke/make_streams.rs" "$WORK/main.rs"
rustc --edition 2024 -O -A dead_code -o "$WORK/make-streams" "$WORK/main.rs"
"$WORK/make-streams" "$OUT"
ls -l "$OUT"
