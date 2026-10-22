#!/usr/bin/env bash
# Decode the MP4s smoke-test.sh made, with a full ffmpeg and ffprobe (the
# system's: not the minimal build, which decodes no H.264 or AAC), and check
# they are what nettai asked for: H.264 of every frame at the input's size and
# frame rate, in the pixel format asked for, tagged BT.709 limited range, the
# picture close to the input's (PSNR against the input put through the same
# conversion); AAC at 48 kHz in stereo, its edit list leaving the encoder's
# delay out (nettai keeps each track's edit list as it puts the tracks
# together), not silence; every packet decoding without an error.
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

# Every packet decodes, without a word at -v error.
decodes() {
  local said
  said="$(ffmpeg -nostdin -v error -xerror -i "$1" -f null - 2>&1)" || fail "$1 doesn't decode: $said"
  [ -z "$said" ] || fail "decoding $1 said: $said"
}

# A picture's MP4: what it should be made of.
picture() {
  local mp4="$1" input="$2" format="$3" size="$4" frames="$5"
  local probed want said psnr
  probed="$(ffprobe -v error -count_frames -select_streams v \
    -show_entries stream=codec_name,width,height,pix_fmt,color_range,color_space,color_transfer,color_primaries,r_frame_rate,nb_read_frames \
    -of compact=p=0:nk=0 "$mp4")"
  want="codec_name=h264|width=${size%x*}|height=${size#*x}|pix_fmt=$format|color_range=tv|color_space=bt709|color_transfer=bt709|color_primaries=bt709|r_frame_rate=262144/4389|nb_read_frames=$frames"
  [ "$probed" = "$want" ] || fail "$mp4's picture is
  $probed
not
  $want"
  decodes "$mp4"
  # The picture against the input's, converted as nettai's filter does.
  said="$(ffmpeg -nostdin -hide_banner -i "$mp4" -f rawvideo -pixel_format rgb24 -video_size "$size" -framerate 262144/4389 -i "$STREAMS/$input" -lavfi \
    "[1:v]scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int+area,format=${format}[ref];[0:v][ref]psnr" \
    -f null - 2>&1)" || fail "comparing $mp4: $said"
  psnr="$(printf '%s\n' "$said" | sed -n 's/.*PSNR .* average:\([0-9.]*\).*/\1/p' | tail -n1)"
  [ -n "$psnr" ] || fail "no PSNR for $mp4: $said"
  awk -v p="$psnr" 'BEGIN { exit !(p >= 30) }' || fail "$mp4's picture is $psnr dB from the input's (30 at least)"
  printf 'ok  %-48s %s, %s frames, PSNR %s dB\n' "$mp4" "$format" "$frames" "$psnr"
}

# A sound track's MP4.
sound() {
  local mp4="$1" input="$2"
  local probed want said volume samples given
  probed="$(ffprobe -v error -select_streams a -show_entries stream=codec_name,sample_rate,channels -of compact=p=0:nk=0 "$mp4")"
  want="codec_name=aac|sample_rate=48000|channels=2"
  [ "$probed" = "$want" ] || fail "$mp4's sound is '$probed', not '$want'"
  decodes "$mp4"
  # The samples given and less than an AAC frame (1024) more, its last frame's
  # padding (which nettai's own edit list, given the track's length, leaves
  # out): its first 1024, the encoder's delay, left out by its edit list
  # (delay_moov's; without one it decodes to 1024 more).
  samples="$(ffmpeg -nostdin -v error -i "$mp4" -f f32le - | wc -c | awk '{ print $1 / 8 }')"
  given="$(wc -c < "$STREAMS/$input" | awk '{ print $1 / 8 }')"
  awk -v s="$samples" -v g="$given" 'BEGIN { d = s - g; exit !(d >= 0 && d < 1024) }' \
    || fail "$mp4 decodes to $samples samples, of $given given (its edit list skips no encoder delay?)"
  said="$(ffmpeg -nostdin -hide_banner -i "$mp4" -af volumedetect -f null - 2>&1)" || fail "$mp4's sound: $said"
  volume="$(printf '%s\n' "$said" | sed -n 's/.*mean_volume: \([-0-9.]*\) dB.*/\1/p')"
  # (The input's tones are at a quarter of full scale: about -15 dB.)
  awk -v v="$volume" 'BEGIN { exit !(v > -20 && v < -10) }' || fail "$mp4's sound is at $volume dB"
  printf 'ok  %-48s %s samples of %s, %s dB\n' "$mp4" "$samples" "$given" "$volume"
}

for dir in "$@"; do
  picture "$dir/picture-yuv420p.mp4" sound.rgb yuv420p 480x320 120
  picture "$dir/picture-yuv444p.mp4" sound.rgb yuv444p 480x320 120
  picture "$dir/picture-odd-yuv420p.mp4" silent.rgb yuv420p 720x480 30
  sound "$dir/sound-192k.mp4" sound.f32
  sound "$dir/sound-128k.mp4" sound.f32
done
echo "ALL MP4s VERIFIED"
