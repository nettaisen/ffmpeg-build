# shellcheck shell=bash
# The minimal FFmpeg nettai bundles, in one place: the versions it is built
# from and every component it has.
#
# nettai links no FFmpeg library. Its replay export (crates/nettai-video's
# ffmpeg module, run by the app's crates/nettai/src/screens/replays/export.rs
# and by nettai-tool --mp4) runs an `ffmpeg` child a track: one for the
# picture, written the replay's raw RGB frames on its standard input, and one
# for each sound track, written its raw samples on its own. Each writes a
# fragmented MP4 of its track on its standard output, which nettai reads back
# and puts together into the MP4 itself. The ffmpeg built here has what those
# two commands need and nothing more: configure starts from
# --disable-everything and each component is enabled again below, with the
# part of nettai's commands it serves.

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
# What nettai runs (crates/nettai-video/src/ffmpeg.rs: picture_arguments and
# sound_arguments)
#
#   ffmpeg -hide_banner -nostdin -loglevel error
#          -f rawvideo -pixel_format rgb24 -video_size WxH -framerate 262144/4389 -i pipe:0
#          -vf scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int+area,format=yuv420p,setparams=color_primaries=bt709:color_trc=bt709
#          -c:v libx264 -preset medium -tune animation -crf 16 -g 120
#          -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv
#          -f mp4 -movflags +frag_keyframe+empty_moov+delay_moov+default_base_moof -frag_duration 2000000 pipe:1
#
#   ffmpeg -hide_banner -nostdin -loglevel error
#          -f f32le -sample_rate 48000 -ch_layout stereo -i pipe:0
#          -c:a aac -b:a 192k
#          -f mp4 -movflags +empty_moov+delay_moov+default_base_moof -frag_duration 2000000 pipe:1
#
# with format=yuv444p in place of yuv420p for Chroma::Full, and other CRFs
# and audio bit rates by its settings (options of the same encoders). The
# picture is 8-bit RGB, square pixels, at the GBA frame's exact rate
# (262144/4389 a second); the sound is 32-bit float little-endian stereo at
# 48 kHz, which nettai resamples to itself (from the GBA's 32768 Hz). nettai
# asks ffmpeg nothing else: no -version, no probing.
#
# Why each component is here:
#
#   Demuxers
#     rawvideo       "-f rawvideo -i pipe:0": the picture's frames
#     pcm_f32le      "-f f32le -i pipe:0": a sound track's samples
#   Decoders
#     rawvideo       the frames' RGB
#     pcm_f32le      the samples' floats
#   Protocol
#     pipe           "-i pipe:0" and "pipe:1": nettai writes the file itself
#   Filters
#     scale          "scale=out_color_matrix=bt709:out_range=tv:flags=...":
#                    RGB to BT.709 limited-range YUV (swscale)
#     format         "format=yuv420p" (or yuv444p)
#     setparams      "setparams=color_primaries=bt709:color_trc=bt709": the
#                    primaries and transfer tagged on the frames (FFmpeg
#                    9.0's encoder takes them from the frames, which raw
#                    RGB gives none, and with -color_primaries and
#                    -color_trc alone the MP4 says "unknown")
#     aresample      the float samples made the planar floats AAC takes,
#                    inserted by ffmpeg (swresample; nothing is resampled)
#     aformat        the formats AAC takes, inserted by ffmpeg
#     null, anull    the pass-through ends ffmpeg puts in a stream's graph
#                    where it has no filter of its own (the sound's)
#   Encoders
#     libx264        "-c:v libx264 -preset medium -tune animation -crf 16"
#     aac            "-c:a aac -b:a 192k"
#   Muxer
#     mp4            "-f mp4 -movflags +...": a fragmented MP4 on the pipe
#                    (libavformat's movenc)
#   External library
#     libx264 (--enable-gpl)   the H.264 encoder; it makes the binary GPL
#
# Configure adds what these need on its own, and nothing here asks for it:
# the ffmpeg program brings its filter graph's ends (buffer, buffersink,
# abuffer, abuffersink) and the filters its own options use (atrim, crop,
# hflip, rotate, transpose, trim, vflip: configure's ffmpeg_select); the mp4
# muxer brings the mov muxer (the same code), the aac_adtstoasc and
# vp9_superframe bitstream filters and the ac3 parser (mov_muxer_select).
# No extract_extradata bitstream filter: libx264 gives the H.264 track's
# parameter sets itself (the smoke test's MP4s decode without it). Nothing
# else is built: no other codec, container, protocol, device, network, or
# hardware API.
# ---------------------------------------------------------------------------

ffmpeg_component_flags() {
  cat <<'FLAGS'
--disable-everything
--enable-gpl
--enable-libx264
--enable-demuxer=rawvideo,pcm_f32le
--enable-decoder=rawvideo,pcm_f32le
--enable-protocol=pipe
--enable-filter=scale,format,setparams,aresample,aformat,null,anull
--enable-encoder=libx264,aac
--enable-muxer=mp4
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
