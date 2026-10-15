#!/usr/bin/env bash
# Run the built ffmpeg exactly as nettai runs it (crates/nettai-video/src/mp4.rs,
# Settings::arguments) on NUT streams nettai's writer made
# (scripts/make-streams.sh), so a build missing anything nettai's export needs
# fails here and not in a player's export. What it checks: ffmpeg ends well
# and says nothing at -loglevel error, writes the MP4 to the .part name it is
# given (nettai renames it when ffmpeg is done), and puts the index before the
# media (+faststart). The MP4s are left in OUT_DIR for
# scripts/verify-mp4s.sh, which decodes them with a full ffmpeg.
#
# Usage: smoke-test.sh /path/to/ffmpeg[.exe] STREAMS_DIR OUT_DIR
set -euo pipefail
export LC_ALL=C

[ $# -eq 3 ] || { echo "usage: $0 /path/to/ffmpeg STREAMS_DIR OUT_DIR" >&2; exit 2; }
FF="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
STREAMS="$(cd "$2" && pwd)"
mkdir -p "$3"
OUT="$(cd "$3" && pwd)"
# (Relative names from here on: a Windows ffmpeg under MSYS2 is given no
# MSYS path to translate.)
cd "$OUT"

echo "== $("$FF" -hide_banner -version | head -n1) =="

# nettai's command for one MP4: Settings::arguments with the chroma's format,
# the CRF and the audio bit rate given (16 and 192 are nettai's defaults).
encode() {
  local stream="$1" name="$2" format="$3" crf="$4" kbps="$5"
  local filter="scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int+area,format=$format,setparams=color_primaries=bt709:color_trc=bt709"
  local args=(
    -hide_banner -nostdin -loglevel error
    -f nut -i pipe:0
    -vf "$filter"
    -c:v libx264 -preset medium -tune animation -crf "$crf"
    -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv
    -c:a aac -b:a "${kbps}k" -ar 48000
    -movflags +faststart -f mp4 -y "$name.part"
  )
  echo "+ ffmpeg ${args[*]} < $stream"
  rm -f "$name" "$name.part"
  local said
  if ! said="$("$FF" "${args[@]}" < "$STREAMS/$stream" 2>&1)"; then
    echo "FAIL: ffmpeg failed on $stream:" >&2
    echo "$said" >&2
    exit 1
  fi
  [ -z "$said" ] || { echo "FAIL: ffmpeg said, at -loglevel error:" >&2; echo "$said" >&2; exit 1; }
  [ -s "$name.part" ] || { echo "FAIL: no $name.part" >&2; exit 1; }
  mv "$name.part" "$name"
  # +faststart: the moov box (the index) before the mdat box (the media).
  local moov mdat
  moov="$(grep -aobF moov "$name" | head -n1 | cut -d: -f1)"
  mdat="$(grep -aobF mdat "$name" | head -n1 | cut -d: -f1)"
  [ -n "$moov" ] && [ -n "$mdat" ] || { echo "FAIL: $name has no moov or no mdat box" >&2; exit 1; }
  [ "$moov" -lt "$mdat" ] || { echo "FAIL: $name's moov is after its mdat (+faststart not done)" >&2; exit 1; }
  printf 'ok  %-20s %9s bytes, moov at %s, mdat at %s\n' "$name" "$(wc -c < "$name" | tr -d ' ')" "$moov" "$mdat"
}

# A replay with sound at twice the frame, as exported by default (4:2:0)...
encode sound.nut sound-yuv420p.mp4 yuv420p 16 192
# ...with Chroma::Full (4:4:4)...
encode sound.nut sound-yuv444p.mp4 yuv444p 16 192
# ...and one without sound, at an odd scale (the audio options stand, with no
# sound to apply them to), with another CRF and bit rate.
encode silent.nut silent-yuv420p.mp4 yuv420p 23 128

echo "SMOKE TEST PASSED"
