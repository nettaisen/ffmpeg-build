# shellcheck shell=bash
# The minimal FFmpeg nettai bundles, in one place: the versions it is built
# from and every component it has.
#
# nettai links no FFmpeg library. Its replay export (crates/nettai-video's
# desktop platform, run by the app's crates/nettai/src/screens/replays/export.rs
# and by nettai-tool --mp4) runs an `ffmpeg` child a track: one for the
# picture, written the replay's frames as raw NV12 on its standard input, and
# one for each sound track, written its raw samples on its own. Each writes its
# track's codec data on its standard output (the picture's H.264 as an Annex B
# stream, a sound track's AAC as ADTS), of which nettai makes the MP4 itself.
# The ffmpeg built here has what those two commands need and nothing more:
# configure starts from --disable-everything and each component is enabled
# again below, with the part of nettai's commands it serves.

# ---------------------------------------------------------------------------
# Versions
#
# FFMPEG_VERSION: the FFmpeg release (its source tarball from
#   ffmpeg.org/releases). The workflow's input, defaulting to this one; never
#   "the latest".
: "${FFMPEG_VERSION:=9.0.2}"
# X264_COMMIT: x264 has no release tags; this is the head of its `stable`
#   branch on 2026-10-14. Its source is the tarball code.videolan.org makes of
#   that commit.
: "${X264_COMMIT:=b35605ace3ddf7c1a5d67a2eb553f034aef41d55}"
export FFMPEG_VERSION X264_COMMIT

# ---------------------------------------------------------------------------
# What nettai runs (crates/nettai-video/src/platform/desktop.rs:
# picture_arguments and sound_arguments)
#
#   ffmpeg -hide_banner -nostdin -loglevel error
#          -f rawvideo -pixel_format nv12 -video_size WxH -framerate 262144/4389 -i pipe:0
#          -c:v libx264 -preset medium -tune animation -crf 16 -g 120 -bf 0
#          -x264-params aud=1:colorprim=bt709:transfer=bt709:colormatrix=bt709:range=tv
#          -f h264 pipe:1
#
#   ffmpeg -hide_banner -nostdin -loglevel error
#          -f f32le -sample_rate 48000 -ch_layout stereo -i pipe:0
#          -c:a aac -b:a 192000
#          -f adts pipe:1
#
# The picture is NV12 (BT.709's matrix, the video range: nettai converts the
# game's RGB itself, the same bytes every platform's encoder is given), at the
# GBA frame's exact rate (262144/4389 a second); the sound is 32-bit float
# little-endian stereo at 48 kHz, which nettai resamples to itself (from the
# GBA's 32768 Hz). No B-frames: nettai times each picture by its place. The
# color is tagged in the H.264 stream itself (x264's VUI), which nettai's MP4
# carries. nettai asks ffmpeg nothing else: no -version, no probing.
#
# Why each component is here:
#
#   Demuxers
#     rawvideo       "-f rawvideo -i pipe:0": the picture's frames
#     pcm_f32le      "-f f32le -i pipe:0": a sound track's samples
#   Decoders
#     rawvideo       the frames' NV12
#     pcm_f32le      the samples' floats
#   Protocol
#     pipe           "-i pipe:0" and "pipe:1": nettai writes the file itself
#   Filters
#     aresample      the float samples made the planar floats AAC takes,
#                    inserted by ffmpeg (swresample; nothing is resampled)
#     aformat        the formats AAC takes, inserted by ffmpeg
#     null, anull    the pass-through ends ffmpeg puts in a stream's graph
#                    where it has no filter of its own
#   Encoders
#     libx264        "-c:v libx264 -preset medium -tune animation -crf 16"
#                    (it takes NV12 as it is: no scaling, no conversion)
#     aac            "-c:a aac -b:a 192000"
#   Muxers
#     h264           "-f h264": the picture's Annex B stream on the pipe
#     adts           "-f adts": a sound track's AAC frames on the pipe
#   External library
#     libx264 (--enable-gpl)   the H.264 encoder; it makes the binary GPL
#
# Configure adds what these need on its own, and nothing here asks for it:
# the ffmpeg program brings its filter graph's ends (buffer, buffersink,
# abuffer, abuffersink) and the filters its own options use (atrim, crop,
# hflip, rotate, transpose, trim, vflip: configure's ffmpeg_select); the adts
# muxer brings the mpeg4audio code (adts_muxer_select). No bitstream filter:
# libx264 writes Annex B itself, which the h264 muxer passes on. Nothing else
# is built: no other codec, container, protocol, device, network, or hardware
# API.
# ---------------------------------------------------------------------------

ffmpeg_component_flags() {
  cat <<'FLAGS'
--disable-everything
--enable-gpl
--enable-libx264
--enable-demuxer=rawvideo,pcm_f32le
--enable-decoder=rawvideo,pcm_f32le
--enable-protocol=pipe
--enable-filter=aresample,aformat,null,anull
--enable-encoder=libx264,aac
--enable-muxer=h264,adts
FLAGS
}

# The build's shape, on every platform: one static `ffmpeg` executable; no
# ffplay or ffprobe, no documentation, no network, no devices, nothing found
# on the build machine by itself (--disable-autodetect), built for size.
ffmpeg_shape_flags() {
  cat <<'FLAGS'
--enable-static
--disable-shared
--enable-small
--disable-autodetect
--disable-debug
--disable-doc
--disable-network
--disable-avdevice
--disable-devices
--disable-ffplay
--disable-ffprobe
--enable-ffmpeg
FLAGS
}
