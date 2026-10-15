#!/usr/bin/env bash
# Build the minimal static ffmpeg from the release tarball, with the static
# libx264 build-x264.sh installed into $PREFIX. The components are
# scripts/ffmpeg-config-common.sh's.
#
# Environment:
#   PREFIX        where libx264 is installed (required)
#   OUTPUT        the path the ffmpeg binary is written to (required)
#   SOURCES_DIR   where the source tarballs are (default $PWD/sources)
#   BUILD_DIR     where it is unpacked and built (default $PWD/build)
#   EXE_SUFFIX    ".exe" on Windows
#   EXTRA_CFLAGS, EXTRA_LDFLAGS   added to configure's
#   PREFIX_CFLAGS, PREFIX_LDFLAGS how the compiler and linker find $PREFIX
#                 (default -I$PREFIX/include and -L$PREFIX/lib; MSVC's link
#                 takes no -L, and finds x264 through pkg-config)
#   FFMPEG_EXTRA  more configure flags, split at spaces (cross-compiling, the
#                 toolchain)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ffmpeg-config-common.sh
source "$HERE/ffmpeg-config-common.sh"

: "${PREFIX:?set PREFIX}"
: "${OUTPUT:?set OUTPUT}"
: "${SOURCES_DIR:=$PWD/sources}"
: "${BUILD_DIR:=$PWD/build}"
case "$OUTPUT" in /*) ;; *) OUTPUT="$PWD/$OUTPUT" ;; esac

tarball="$SOURCES_DIR/ffmpeg-${FFMPEG_VERSION}.tar.xz"
[ -f "$tarball" ] || "$HERE/fetch-sources.sh" "$SOURCES_DIR"
src="$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}"
rm -rf "$src"
mkdir -p "$BUILD_DIR"
tar -xJf "$tarball" -C "$BUILD_DIR"
cd "$src"

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
# (`=`, not `:=`: an empty value set on purpose stays empty.)
: "${PREFIX_CFLAGS=-I$PREFIX/include}"
: "${PREFIX_LDFLAGS=-L$PREFIX/lib}"

args=(
  --pkg-config-flags=--static
  --extra-cflags="$PREFIX_CFLAGS ${EXTRA_CFLAGS:-}"
  --extra-ldflags="$PREFIX_LDFLAGS ${EXTRA_LDFLAGS:-}"
)
if [ -n "${FFMPEG_EXTRA:-}" ]; then
  read -ra extra <<< "$FFMPEG_EXTRA"
  args+=("${extra[@]}")
fi
# (Read word by word, which no flag has a space in; not mapfile, which
# macOS's bash 3.2 lacks.)
read -ra shape <<< "$(ffmpeg_shape_flags | tr '\n' ' ')"
read -ra components <<< "$(ffmpeg_component_flags | tr '\n' ' ')"

echo "+ ffmpeg configure ${args[*]} ${shape[*]} ${components[*]}"
./configure "${args[@]}" "${shape[@]}" "${components[@]}"
make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"

mkdir -p "$(dirname "$OUTPUT")"
cp "ffmpeg${EXE_SUFFIX:-}" "$OUTPUT"
strip "$OUTPUT" >/dev/null 2>&1 || true
echo "=== built $OUTPUT ==="
"$OUTPUT" -hide_banner -version
