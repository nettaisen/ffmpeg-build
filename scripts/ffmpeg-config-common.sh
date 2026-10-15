# shellcheck shell=bash
# The minimal FFmpeg nettai bundles, in one place: the versions it is built
# from and every component it has.
#
# nettai links no FFmpeg library. Its replay export (crates/nettai-video's
# mp4 module, run by the app's crates/nettai/src/screens/replays/export.rs
# and by nettai-tool --mp4) writes the replay as a NUT stream of raw frames
# and PCM sound (crates/nettai-video/src/nut.rs) into the standard input of
# an `ffmpeg` child, which writes the MP4. The ffmpeg built here has what that
# one command needs and nothing more: configure starts from
# --disable-everything and each component is enabled again below, with the
# part of nettai's command it serves.

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
# NETTAI_REF: the nettai commit whose NUT writer makes the smoke test's
#   streams (scripts/make-streams.sh).
: "${NETTAI_REF:=620c4a423c57f014d786467c4a29f3d7a95abcbe}"
export FFMPEG_VERSION X264_COMMIT NETTAI_REF

# ---------------------------------------------------------------------------
# What nettai runs (crates/nettai-video/src/mp4.rs, Settings::arguments)
#
#   ffmpeg -hide_banner -nostdin -loglevel error -f nut -i pipe:0
#          -vf scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int+area,format=yuv420p,setparams=color_primaries=bt709:color_trc=bt709
#          -c:v libx264 -preset medium -tune animation -crf 16
#          -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv
#          -c:a aac -b:a 192k -ar 48000
#          -movflags +faststart -f mp4 -y FILE.mp4.part
#
# with format=yuv444p in place of yuv420p for Chroma::Full, and other CRFs
# and audio bit rates by Settings (options of the same encoders). The stream
# on its standard input is RGB[24] video (8-bit RGB, square pixels, at the
# GBA frame's exact time base 4389/262144 s) and, where the game has sound,
# PFD[32] audio (32-bit float little-endian stereo at 32768 Hz). nettai asks
# ffmpeg nothing else: no -version, no probing.
#
# Why each component is here:
#
#   Demuxer
#     nut            "-f nut -i pipe:0": the stream nettai writes
#   Decoders
#     rawvideo       the stream's RGB[24] pictures
#     pcm_f32le      the stream's PFD[32] sound
#   Protocols
#     pipe           "-i pipe:0"
#     file           the MP4 at FILE.mp4.part, which ffmpeg writes itself
#                    (+faststart rewrites it with the index at the front)
#   Filters
#     scale          "scale=out_color_matrix=bt709:out_range=tv:flags=...":
#                    RGB to BT.709 limited-range YUV (swscale)
#     format         "format=yuv420p" (or yuv444p)
#     setparams      "setparams=color_primaries=bt709:color_trc=bt709": the
#                    primaries and transfer tagged on the frames (FFmpeg
#                    9.0's encoder takes them from the frames, which the
#                    stream's RGB gives none, and with -color_primaries and
#                    -color_trc alone the MP4 says "unknown")
#     aresample      "-ar 48000": the GBA's 32768 Hz to 48 kHz (swresample)
#     aformat        the float to planar float AAC takes, inserted by ffmpeg
#     null, anull    the pass-through ends ffmpeg puts in a stream's graph
#                    where it has no filter of its own (the sound's)
#   Encoders
#     libx264        "-c:v libx264 -preset medium -tune animation -crf 16"
#     aac            "-c:a aac -b:a 192k"
#   Muxer
#     mp4            "-f mp4" with "-movflags +faststart" (libavformat's
#                    movenc)
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
--enable-demuxer=nut
--enable-decoder=rawvideo,pcm_f32le
--enable-protocol=pipe,file
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
