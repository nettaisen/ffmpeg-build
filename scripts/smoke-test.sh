#!/usr/bin/env bash
# Run the built ffmpeg exactly as nettai runs it (crates/nettai-video/src/platform/desktop.rs:
# picture_arguments and sound_arguments) on the raw inputs nettai writes
# (scripts/make-streams.sh), so a build missing anything nettai's export needs
# fails here and not in a player's export. nettai runs a child a track, each
# reading its track's raw bytes on its standard input and writing the track's
# codec data on its standard output: the picture's H.264 as an Annex B stream,
# a sound track's AAC as ADTS; nettai makes the MP4 of them itself. Here each
# child's input is a file redirected in and its output a file redirected out.
# What it checks: ffmpeg ends well and says nothing at -loglevel error, and
# writes an H.264 stream that starts with an access unit delimiter (aud=1), or
# ADTS that starts with its sync word. The outputs are left in OUT_DIR for
# scripts/verify-outputs.sh, which decodes them with a full ffmpeg.
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

QUIET=(-hide_banner -nostdin -loglevel error)

# One child: its arguments, its input, what it writes, and the bytes that
# must start it (hex).
run() {
  local input="$1" name="$2" start="$3"
  shift 3
  echo "+ ffmpeg $* < $input > $name"
  rm -f "$name"
  local said
  if ! said="$("$FF" "$@" < "$STREAMS/$input" 2>&1 > "$name")"; then
    echo "FAIL: ffmpeg failed on $input:" >&2
    echo "$said" >&2
    exit 1
  fi
  [ -z "$said" ] || { echo "FAIL: ffmpeg said, at -loglevel error:" >&2; echo "$said" >&2; exit 1; }
  [ -s "$name" ] || { echo "FAIL: no $name" >&2; exit 1; }
  local head
  head="$(head -c $(( ${#start} / 2 )) "$name" | od -An -tx1 | tr -d ' \n')"
  [ "$head" = "$start" ] || { echo "FAIL: $name starts $head, not $start" >&2; exit 1; }
  printf 'ok  %-24s %9s bytes, starting %s\n' "$name" "$(wc -c < "$name" | tr -d ' ')" "$head"
}

# The picture's child (picture_arguments), at the size given: its H.264 starts
# with a start code and an access unit delimiter (NAL type 9).
picture() {
  local input="$1" name="$2" size="$3"
  run "$input" "$name" 0000000109 "${QUIET[@]}" \
    -f rawvideo -pixel_format nv12 -video_size "$size" -framerate 262144/4389 -i pipe:0 \
    -c:v libx264 -preset medium -tune animation -crf 16 -g 120 -bf 0 \
    -x264-params aud=1:colorprim=bt709:transfer=bt709:colormatrix=bt709:range=tv \
    -f h264 pipe:1
}

# A sound track's child (sound_arguments): its ADTS starts with the sync word
# (twelve ones) and MPEG-4 audio with no CRC (0xF1).
sound() {
  local input="$1" name="$2"
  run "$input" "$name" fff1 "${QUIET[@]}" \
    -f f32le -sample_rate 48000 -ch_layout stereo -i pipe:0 \
    -c:a aac -b:a 192000 \
    -f adts pipe:1
}

# A replay at twice the frame, as exported by default...
picture sound.nv12 picture.h264 480x320
# ...and at an odd scale, where 4:2:0's color straddles the game's pixels.
picture silent.nv12 picture-odd.h264 720x480
# Its sound.
sound sound.f32 sound.aac

echo "SMOKE TEST PASSED"
