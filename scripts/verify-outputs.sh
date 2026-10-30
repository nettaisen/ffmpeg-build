#!/usr/bin/env bash
# Decode what smoke-test.sh made, with a full ffmpeg and ffprobe (the system's:
# not the minimal build, which decodes no H.264 or AAC), and check it is what
# nettai asks for: H.264 High of every frame at the input's size, with no
# B-frames (nettai times each picture by its place: it takes them in order),
# 4:2:0, tagged BT.709 limited range in the stream itself, the picture close to
# the NV12 it was given; AAC LC at 48 kHz in stereo, decoding to the samples
# given after the encoder's delay of 1024 (which nettai's edit list leaves out)
# and less than a frame of padding, not silence; every packet decoding without
# an error.
#
# Usage: verify-outputs.sh STREAMS_DIR OUT_DIR...
set -euo pipefail
export LC_ALL=C

[ $# -ge 2 ] || { echo "usage: $0 STREAMS_DIR OUT_DIR..." >&2; exit 2; }
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

# A picture's H.264: what it should be made of.
picture() {
  local h264="$1" input="$2" size="$3" frames="$4"
  local probed want said psnr
  probed="$(ffprobe -v error -count_frames -select_streams v \
    -show_entries stream=codec_name,profile,width,height,has_b_frames,pix_fmt,color_range,color_space,color_transfer,color_primaries,nb_read_frames \
    -of compact=p=0:nk=0 "$h264")"
  want="codec_name=h264|profile=High|width=${size%x*}|height=${size#*x}|has_b_frames=0|pix_fmt=yuv420p|color_range=tv|color_space=bt709|color_transfer=bt709|color_primaries=bt709|nb_read_frames=$frames"
  [ "$probed" = "$want" ] || fail "$h264's picture is
  $probed
not
  $want"
  decodes "$h264"
  # The picture against the NV12 given, frame for frame (an H.264 stream has no
  # times of its own: each is numbered, in one time base), the NV12 tagged as
  # nettai makes it (BT.709, the video range) so nothing converts it.
  said="$(ffmpeg -nostdin -hide_banner -i "$h264" -f rawvideo -pixel_format nv12 -video_size "$size" -framerate 262144/4389 -i "$STREAMS/$input" -lavfi \
    "[0:v]settb=1,setpts=N[made];[1:v]setparams=range=tv:color_primaries=bt709:color_trc=bt709:colorspace=bt709,format=yuv420p,settb=1,setpts=N[given];[made][given]psnr" \
    -f null - 2>&1)" || fail "comparing $h264: $said"
  psnr="$(printf '%s\n' "$said" | sed -n 's/.*PSNR .* average:\([0-9.]*\).*/\1/p' | tail -n1)"
  [ -n "$psnr" ] || fail "no PSNR for $h264: $said"
  awk -v p="$psnr" 'BEGIN { exit !(p >= 45) }' || fail "$h264's picture is $psnr dB from the input's (45 at least)"
  printf 'ok  %-48s %s frames, PSNR %s dB\n' "$h264" "$frames" "$psnr"
}

# A sound track's ADTS.
sound() {
  local aac="$1" input="$2"
  local probed want said volume samples given
  probed="$(ffprobe -v error -select_streams a -show_entries stream=codec_name,profile,sample_rate,channels -of compact=p=0:nk=0 "$aac")"
  want="codec_name=aac|profile=LC|sample_rate=48000|channels=2"
  [ "$probed" = "$want" ] || fail "$aac's sound is '$probed', not '$want'"
  decodes "$aac"
  # The encoder's delay (1024: libavcodec's aacenc.c, initial_padding), then
  # the samples given, then less than an AAC frame (1024) of the last frame's
  # padding: nettai's edit list skips the first and stops at the given's end.
  samples="$(ffmpeg -nostdin -v error -i "$aac" -f f32le - | wc -c | awk '{ print $1 / 8 }')"
  given="$(wc -c < "$STREAMS/$input" | awk '{ print $1 / 8 }')"
  awk -v s="$samples" -v g="$given" 'BEGIN { d = s - g - 1024; exit !(d >= 0 && d < 1024) }' \
    || fail "$aac decodes to $samples samples, of $given given (not 1024 of delay and less than a frame of padding)"
  said="$(ffmpeg -nostdin -hide_banner -i "$aac" -af volumedetect -f null - 2>&1)" || fail "$aac's sound: $said"
  volume="$(printf '%s\n' "$said" | sed -n 's/.*mean_volume: \([-0-9.]*\) dB.*/\1/p')"
  # (The input's tones are at a quarter of full scale: about -15 dB.)
  awk -v v="$volume" 'BEGIN { exit !(v > -20 && v < -10) }' || fail "$aac's sound is at $volume dB"
  printf 'ok  %-48s %s samples of %s, %s dB\n' "$aac" "$samples" "$given" "$volume"
}

for dir in "$@"; do
  picture "$dir/picture.h264" sound.nv12 480x320 120
  picture "$dir/picture-odd.h264" silent.nv12 720x480 30
  sound "$dir/sound.aac" sound.f32
done
echo "ALL OUTPUTS VERIFIED"
