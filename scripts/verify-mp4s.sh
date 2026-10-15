#!/usr/bin/env bash
# Decode the MP4s smoke-test.sh made, with a full ffmpeg and ffprobe (the
# system's: not the minimal build, which decodes no H.264 or AAC), and check
# they are what nettai asked for: H.264 of every frame at the stream's size
# and frame rate, in the pixel format asked for, tagged BT.709 limited range;
# AAC at 48 kHz in stereo where the stream had sound and no sound where it had
# none; every packet decoding without an error; the picture close to the
# stream's (PSNR against the stream put through the same conversion); the
# sound not silence.
#
# Usage: verify-mp4s.sh STREAMS_DIR MP4_DIR...
set -euo pipefail
export LC_ALL=C

[ $# -ge 2 ] || { echo "usage: $0 STREAMS_DIR MP4_DIR..." >&2; exit 2; }
STREAMS="$1"
shift
ffmpeg -hide_banner -version | head -n1

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# One MP4: what it should be made of.
check() {
  local mp4="$1" stream="$2" format="$3" size="$4" frames="$5" sound="$6"
  local probed want said psnr volume
  probed="$(ffprobe -v error -count_frames -select_streams v \
    -show_entries stream=codec_name,width,height,pix_fmt,color_range,color_space,color_transfer,color_primaries,r_frame_rate,nb_read_frames \
    -of compact=p=0:nk=0 "$mp4")"
  want="codec_name=h264|width=${size%x*}|height=${size#*x}|pix_fmt=$format|color_range=tv|color_space=bt709|color_transfer=bt709|color_primaries=bt709|r_frame_rate=262144/4389|nb_read_frames=$frames"
  [ "$probed" = "$want" ] || fail "$mp4's picture is
  $probed
not
  $want"
  probed="$(ffprobe -v error -select_streams a -show_entries stream=codec_name,sample_rate,channels -of compact=p=0:nk=0 "$mp4")"
  if [ "$sound" = yes ]; then
    want="codec_name=aac|sample_rate=48000|channels=2"
  else
    want=""
  fi
  [ "$probed" = "$want" ] || fail "$mp4's sound is '$probed', not '$want'"
  # Every packet decodes, without a word at -v error.
  said="$(ffmpeg -nostdin -v error -xerror -i "$mp4" -f null - 2>&1)" || fail "$mp4 doesn't decode: $said"
  [ -z "$said" ] || fail "decoding $mp4 said: $said"
  # The picture against the stream's, converted as nettai's filter does.
  said="$(ffmpeg -nostdin -hide_banner -i "$mp4" -i "$STREAMS/$stream" -lavfi \
    "[1:v]scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int+area,format=${format}[ref];[0:v][ref]psnr" \
    -f null - 2>&1)" || fail "comparing $mp4: $said"
  psnr="$(printf '%s\n' "$said" | sed -n 's/.*PSNR .* average:\([0-9.]*\).*/\1/p' | tail -n1)"
  [ -n "$psnr" ] || fail "no PSNR for $mp4: $said"
  awk -v p="$psnr" 'BEGIN { exit !(p >= 30) }' || fail "$mp4's picture is $psnr dB from the stream's (30 at least)"
  volume="-"
  if [ "$sound" = yes ]; then
    said="$(ffmpeg -nostdin -hide_banner -i "$mp4" -map 0:a -af volumedetect -f null - 2>&1)" || fail "$mp4's sound: $said"
    volume="$(printf '%s\n' "$said" | sed -n 's/.*mean_volume: \([-0-9.]*\) dB.*/\1/p')"
    # (The stream's tones are at a quarter of full scale: about -15 dB.)
    awk -v v="$volume" 'BEGIN { exit !(v > -20 && v < -10) }' || fail "$mp4's sound is at $volume dB"
  fi
  printf 'ok  %-40s %s, %s frames, PSNR %s dB, sound %s dB\n' "$mp4" "$format" "$frames" "$psnr" "$volume"
}

for dir in "$@"; do
  check "$dir/sound-yuv420p.mp4" sound.nut yuv420p 480x320 120 yes
  check "$dir/sound-yuv444p.mp4" sound.nut yuv444p 480x320 120 yes
  check "$dir/silent-yuv420p.mp4" silent.nut yuv420p 720x480 30 no
done
echo "ALL MP4s VERIFIED"
