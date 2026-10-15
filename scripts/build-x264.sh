#!/usr/bin/env bash
# Build a static libx264 into $PREFIX from the pinned commit's tarball. It is
# the minimal ffmpeg's one external library (its H.264 encoder).
#
# Environment:
#   PREFIX        where it is installed (required), e.g. $PWD/prefix
#   SOURCES_DIR   where the source tarballs are (default $PWD/sources; fetched
#                 by scripts/fetch-sources.sh when missing)
#   BUILD_DIR     where it is unpacked and built (default $PWD/build)
#   X264_HOST     a host triple to cross-compile for, e.g. x86_64-apple-darwin
#   EXTRA_CFLAGS, EXTRA_LDFLAGS   added to configure's (architecture, CRT)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ffmpeg-config-common.sh
source "$HERE/ffmpeg-config-common.sh"

: "${PREFIX:?set PREFIX}"
: "${SOURCES_DIR:=$PWD/sources}"
: "${BUILD_DIR:=$PWD/build}"

tarball="$SOURCES_DIR/x264-${X264_COMMIT}.tar.bz2"
[ -f "$tarball" ] || "$HERE/fetch-sources.sh" "$SOURCES_DIR"
src="$BUILD_DIR/x264-${X264_COMMIT}"
rm -rf "$src"
mkdir -p "$BUILD_DIR"
tar -xjf "$tarball" -C "$BUILD_DIR"
cd "$src"

args=(
  --prefix="$PREFIX"
  --enable-static
  --enable-pic
  --disable-cli
  --disable-opencl
  # nettai's pictures are 8-bit (RGB[24] in, yuv420p or yuv444p out); every
  # chroma format stays (the default), since Chroma::Full is 4:4:4.
  --bit-depth=8
)
[ -n "${X264_HOST:-}" ] && args+=("--host=${X264_HOST}")
[ -n "${EXTRA_CFLAGS:-}" ] && args+=("--extra-cflags=${EXTRA_CFLAGS}")
[ -n "${EXTRA_LDFLAGS:-}" ] && args+=("--extra-ldflags=${EXTRA_LDFLAGS}")

echo "+ x264 configure ${args[*]}"
./configure "${args[@]}"
make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
make install
echo "x264 installed into $PREFIX"
