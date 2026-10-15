#!/usr/bin/env bash
# Write the notice a release carries and nettai ships beside the ffmpeg it
# bundles: what the program is built from, under what license, where its
# complete source is (the release's own tarballs), and the license texts.
#
# Usage: notice.sh SOURCES_DIR TAG SCRIPTS_TARBALL > ffmpeg-NOTICE.txt
#   TAG: the release's tag; SCRIPTS_TARBALL: the name of the release's
#   tarball of this repository's build scripts.
set -euo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ffmpeg-config-common.sh
source "$HERE/ffmpeg-config-common.sh"

[ $# -eq 3 ] || { echo "usage: $0 SOURCES_DIR TAG SCRIPTS_TARBALL" >&2; exit 2; }
SOURCES="$1" TAG="$2" SCRIPTS="$3"
: "${GITHUB_REPOSITORY:=bigfarts/nettai-ffmpeg-build}"
releases="https://github.com/${GITHUB_REPOSITORY}/releases/download/${TAG}"
ffmpeg="ffmpeg-${FFMPEG_VERSION}.tar.xz"
x264="x264-${X264_COMMIT}.tar.bz2"
sha() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

cat <<EOF
ffmpeg, as bundled with nettai
==============================

This ffmpeg program is FFmpeg ${FFMPEG_VERSION} (https://ffmpeg.org/), built
with --enable-gpl and linked statically with x264 (https://www.videolan.org/developers/x264.html),
commit ${X264_COMMIT}, by https://github.com/${GITHUB_REPOSITORY}
(release ${TAG}). It holds only what nettai's replay export uses.

FFmpeg is licensed under the GNU Lesser General Public License, version 2.1
or later, with parts under the GNU General Public License, version 2 or
later; x264 is licensed under the GNU General Public License, version 2 or
later. Built with --enable-gpl and with x264, the program as a whole is
licensed under the GNU General Public License, version 2 or later
(GPL-2.0-or-later). It is distributed WITHOUT ANY WARRANTY; see the license
below.

Its complete corresponding source, as the release carries it:

  FFmpeg:  ${releases}/${ffmpeg}
           sha256 $(sha "$SOURCES/$ffmpeg")
  x264:    ${releases}/${x264}
           sha256 $(sha "$SOURCES/$x264")
  the scripts that configure and build them:
           ${releases}/${SCRIPTS}

configure's flags (scripts/ffmpeg-config-common.sh says why each is there):

$(ffmpeg_shape_flags | sed 's/^/  /')
$(ffmpeg_component_flags | sed 's/^/  /')


FFmpeg's LICENSE.md
-------------------

$(tar -xJOf "$SOURCES/$ffmpeg" "ffmpeg-${FFMPEG_VERSION}/LICENSE.md")


The GNU General Public License, version 2 (FFmpeg's COPYING.GPLv2)
------------------------------------------------------------------

$(tar -xJOf "$SOURCES/$ffmpeg" "ffmpeg-${FFMPEG_VERSION}/COPYING.GPLv2")


x264's COPYING
--------------

$(tar -xjOf "$SOURCES/$x264" "x264-${X264_COMMIT}/COPYING")
EOF
