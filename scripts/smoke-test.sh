#!/usr/bin/env bash
# Run the built ffmpeg exactly as nettai runs it (crates/nettai-video/src/ffmpeg.rs:
# picture_arguments and sound_arguments) on the raw inputs nettai writes
# (scripts/make-streams.sh), so a build missing anything nettai's export needs
# fails here and not in a player's export. nettai runs a child a track, each
# reading its track's raw bytes on its standard input and writing a fragmented
# MP4 of it on its standard output; here each child's input is a file
# redirected in and its output a file redirected out. What it checks: ffmpeg
# ends well and says nothing at -loglevel error, and writes a fragmented MP4
# whose index (its moov, with the track's edit list: delay_moov) comes before
# its first fragment. The MP4s are left in OUT_DIR for scripts/verify-mp4s.sh,
# which decodes them with a full ffmpeg.
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

# The fragmented MP4 every child writes on its standard output.
QUIET=(-hide_banner -nostdin -loglevel error)

# One child: its arguments, its input, the MP4 it writes.
run() {
  local input="$1" name="$2"
  shift 2
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
  # Fragmented, its index first: a moov, then a moof (a fragment) and its mdat.
  local moov moof
  moov="$(grep -aobF moov "$name" | head -n1 | cut -d: -f1)"
  moof="$(grep -aobF moof "$name" | head -n1 | cut -d: -f1)"
  [ -n "$moov" ] && [ -n "$moof" ] || { echo "FAIL: $name has no moov or no moof box" >&2; exit 1; }
  [ "$moov" -lt "$moof" ] || { echo "FAIL: $name's moov is after its first fragment" >&2; exit 1; }
  printf 'ok  %-24s %9s bytes, moov at %s, first fragment at %s\n' "$name" "$(wc -c < "$name" | tr -d ' ')" "$moov" "$moof"
}

# The picture's child (picture_arguments) with the chroma's format and the CRF
# given (16 is nettai's default), at the size given.
picture() {
  local input="$1" name="$2" size="$3" format="$4" crf="$5"
  local filter="scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int+area,format=$format,setparams=color_primaries=bt709:color_trc=bt709"
  run "$input" "$name" "${QUIET[@]}" \
    -f rawvideo -pixel_format rgb24 -video_size "$size" -framerate 262144/4389 -i pipe:0 \
    -vf "$filter" \
    -c:v libx264 -preset medium -tune animation -crf "$crf" -g 120 \
    -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv \
    -f mp4 -movflags +frag_keyframe+empty_moov+delay_moov+default_base_moof -frag_duration 2000000 pipe:1
}

# A sound track's child (sound_arguments) with the bit rate given (192 is
# nettai's default).
sound() {
  local input="$1" name="$2" kbps="$3"
  run "$input" "$name" "${QUIET[@]}" \
    -f f32le -sample_rate 48000 -ch_layout stereo -i pipe:0 \
    -c:a aac -b:a "${kbps}k" \
    -f mp4 -movflags +empty_moov+delay_moov+default_base_moof -frag_duration 2000000 pipe:1
}

# A replay at twice the frame, as exported by default (4:2:0)...
picture sound.rgb picture-yuv420p.mp4 480x320 yuv420p 16
# ...with Chroma::Full (4:4:4)...
picture sound.rgb picture-yuv444p.mp4 480x320 yuv444p 16
# ...and at an odd scale, with another CRF.
picture silent.rgb picture-odd-yuv420p.mp4 720x480 yuv420p 23
# Its sound, at the default bit rate and another.
sound sound.f32 sound-192k.mp4 192
sound sound.f32 sound-128k.mp4 128

echo "SMOKE TEST PASSED"
