#!/usr/bin/env bash
# Download the source tarballs the build is made from into SOURCES_DIR: FFmpeg's
# release tarball (ffmpeg.org) and the tarball code.videolan.org makes of the
# pinned x264 commit. These exact files are what the binaries are built from
# and what each release carries beside them (the GPL's corresponding source).
#
# Usage: fetch-sources.sh SOURCES_DIR
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ffmpeg-config-common.sh
source "$HERE/ffmpeg-config-common.sh"

[ $# -eq 1 ] || { echo "usage: $0 SOURCES_DIR" >&2; exit 2; }
mkdir -p "$1"
cd "$1"

ffmpeg="ffmpeg-${FFMPEG_VERSION}.tar.xz"
x264="x264-${X264_COMMIT}.tar.bz2"
[ -f "$ffmpeg" ] || curl -fsSL -o "$ffmpeg" "https://ffmpeg.org/releases/${ffmpeg}"
[ -f "$x264" ] || curl -fsSL -o "$x264" \
  "https://code.videolan.org/videolan/x264/-/archive/${X264_COMMIT}/${x264}"

# (Each is what it says it is: a whole tarball of the version named.)
tar -tJf "$ffmpeg" "ffmpeg-${FFMPEG_VERSION}/configure" >/dev/null
tar -tjf "$x264" "x264-${X264_COMMIT}/configure" >/dev/null
if command -v sha256sum >/dev/null; then sha256sum "$ffmpeg" "$x264"; else shasum -a 256 "$ffmpeg" "$x264"; fi
