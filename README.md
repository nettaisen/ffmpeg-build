# nettai-ffmpeg-build

Builds of a **minimal static `ffmpeg`** for [nettai](https://github.com/bigfarts/nettai), which bundles it in
every package so a replay can be exported as video with nothing else installed.

nettai links no FFmpeg library. Its replay export (`crates/nettai-video`'s `mp4` module, run by the app and by
`nettai-tool --mp4`) writes the replay as a NUT stream of raw frames and PCM sound into the standard input of an
`ffmpeg` child, which writes the MP4. This repository builds that program for every platform nettai's release
packages, with what that one command needs and nothing more: configure starts from `--disable-everything` and
each component is enabled again, traced to nettai's command. The user's request: "it should support whatever
nettai needs and nothing more so the build is minimal", built "with a separate workflow ... so you don't have
to build ffmpeg every time".

## Releases

The [`build-ffmpeg`](.github/workflows/build.yaml) workflow is run by hand (Actions → build-ffmpeg → Run
workflow) with an FFmpeg release (`ffmpeg_version`, 9.0.2 by default) and a revision (`revision`, 1 by
default; a new one for each rebuild of the same version). It publishes a GitHub Release tagged
`ffmpeg-<version>-<revision>` and refuses a tag that is released already. Each release carries:

| Asset                                   | What                                                                       |
| --------------------------------------- | -------------------------------------------------------------------------- |
| `ffmpeg-linux-x86_64`                   | Linux x86_64, built on ubuntu-22.04, fully static (runs on any distro)     |
| `ffmpeg-windows-x86_64.exe`             | Windows x86_64, MSVC with the static CRT: needs no DLL beyond Windows' own |
| `ffmpeg-macos-arm64`                    | macOS arm64, for macOS 11 and later                                        |
| `ffmpeg-macos-x86_64`                   | macOS x86_64, cross-compiled on the arm64 runner, tested under Rosetta     |
| `*.sha256`                              | each binary's (and the notice's) SHA-256                                   |
| `ffmpeg-<version>.tar.xz`               | the FFmpeg source tarball the binaries were built from (ffmpeg.org's)      |
| `x264-<commit>.tar.bz2`                 | the x264 source tarball they were built from (code.videolan.org's)         |
| `nettai-ffmpeg-build-<commit>.tar.gz`   | this repository at the commit that built them: the build scripts           |
| `ffmpeg-NOTICE.txt`                     | what the program is, its license, where its source is, the license texts   |
| `FFmpeg-LICENSE.md`, `FFmpeg-COPYING.GPLv2`, `x264-COPYING` | the license files, as the tarballs have them           |

The two macOS slices are released apart; nettai's macOS packaging joins them into one universal binary with
`lipo` (and an arm64-only local package takes the arm64 slice alone).

Download URLs are stable, e.g.
`https://github.com/bigfarts/nettai-ffmpeg-build/releases/download/ffmpeg-9.0.2-1/ffmpeg-linux-x86_64`. nettai
pins a release by its tag and each binary by its SHA-256 (`packaging/ffmpeg.sh` in nettai).

## What's enabled, and why

nettai's command (`crates/nettai-video/src/mp4.rs`, `Settings::arguments`):

```text
ffmpeg -hide_banner -nostdin -loglevel error -f nut -i pipe:0
       -vf scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int+area,format=yuv420p,setparams=color_primaries=bt709:color_trc=bt709
       -c:v libx264 -preset medium -tune animation -crf 16
       -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv
       -c:a aac -b:a 192k -ar 48000
       -movflags +faststart -f mp4 -y FILE.mp4.part
```

with `format=yuv444p` for `Chroma::Full`, and other CRFs and audio bit rates by its settings. The stream is
`RGB[24]` video (8-bit RGB at the GBA frame's exact time base, 4389/262144 s) and, where the game has sound,
`PFD[32]` audio (32-bit float stereo at 32768 Hz). nettai asks ffmpeg nothing else (no `-version`, no probing).

The one place the components are named is [`scripts/ffmpeg-config-common.sh`](scripts/ffmpeg-config-common.sh):

| Component                            | nettai's use                                                                   |
| ------------------------------------ | ------------------------------------------------------------------------------ |
| demuxer `nut`                        | `-f nut -i pipe:0`: the stream nettai writes                                   |
| decoder `rawvideo`                   | the stream's `RGB[24]` pictures                                                |
| decoder `pcm_f32le`                  | the stream's `PFD[32]` sound                                                   |
| protocol `pipe`                      | `-i pipe:0`                                                                    |
| protocol `file`                      | the MP4 at `FILE.mp4.part`, written by ffmpeg (`+faststart` rewrites it)       |
| filter `scale` (swscale)             | `scale=out_color_matrix=bt709:out_range=tv:flags=…`: RGB to BT.709 TV-range YUV |
| filter `format`                      | `format=yuv420p` (or `yuv444p`)                                                |
| filter `setparams`                   | `setparams=color_primaries=bt709:color_trc=bt709`: FFmpeg 9.0's encoder takes the primaries and transfer from the frames, and with `-color_primaries`/`-color_trc` alone the MP4 says "unknown" |
| filter `aresample` (swresample)      | `-ar 48000`: 32768 Hz to 48 kHz                                                |
| filter `aformat`                     | float to the planar float AAC takes, inserted by ffmpeg                        |
| filters `null`, `anull`              | the pass-through ends of a stream's graph where it has no filter of its own   |
| encoder `libx264`                    | `-c:v libx264 -preset medium -tune animation -crf 16`                          |
| encoder `aac`                        | `-c:a aac -b:a 192k`                                                           |
| muxer `mp4` (movenc)                 | `-f mp4 -movflags +faststart`                                                  |
| external library `libx264` (`--enable-gpl`) | the H.264 encoder; it makes the binary GPL                              |

Configure adds what these need by itself: the `ffmpeg` program brings its filter graph's ends and the filters
its own options use (`atrim`, `crop`, `hflip`, `rotate`, `transpose`, `trim`, `vflip`), and the `mp4` muxer
brings `mov` (the same code), the `aac_adtstoasc` and `vp9_superframe` bitstream filters and the `ac3` parser.
There is no `extract_extradata` bitstream filter: libx264 gives the H.264 track's parameter sets itself, and the
MP4s decode without it. Nothing else is built: no other codec, container, protocol, device, network, or
hardware API; no `ffprobe` or `ffplay`. x264 is built 8-bit only, with every chroma format (4:4:4 is
`Chroma::Full`).

## Tests

Each platform's binary is **smoke-tested** ([`scripts/smoke-test.sh`](scripts/smoke-test.sh)) with nettai's
exact command on NUT streams made by nettai's own writer: `crates/nettai-video/src/nut.rs` at a pinned nettai
commit, compiled with [`smoke/make_streams.rs`](smoke/make_streams.rs) by
[`scripts/make-streams.sh`](scripts/make-streams.sh): two seconds at twice the frame with sound, encoded in
4:2:0 and in 4:4:4, and a picture-only stream at three times the frame. ffmpeg must end well, say nothing at
`-loglevel error`, write the `.part` file it is given, and put the index before the media. Then
[`scripts/verify-mp4s.sh`](scripts/verify-mp4s.sh) decodes every platform's MP4s with the runner's full ffmpeg
and checks them: H.264 of every frame at the stream's size and frame rate, the pixel format asked for, tagged
BT.709 TV range; AAC at 48 kHz stereo where there was sound and no sound where there was none; every packet
decoding without an error; the picture close to the stream's (PSNR against the stream put through the same
conversion); the sound not silence. A release is published only when all of it passes.

## Versions

- **FFmpeg**: the `ffmpeg_version` input, 9.0.2 by default (`FFMPEG_VERSION` in
  `scripts/ffmpeg-config-common.sh`): a release's tarball from ffmpeg.org, never "the latest".
- **x264**: the commit `X264_COMMIT` (the head of its `stable` branch on 2026-10-14); x264 has no release tags.
- **The smoke test's streams**: nettai's commit `NETTAI_REF`.

## Licensing

FFmpeg is LGPL-2.1-or-later with optional GPL parts; x264 is GPL-2.0-or-later. Built with `--enable-gpl` and
linked with x264, **each binary is licensed GPL-2.0-or-later as a whole**. Whoever distributes one must make its
complete corresponding source available under the GPL. So every release carries, beside the binaries, the exact
source tarballs they were built from, this repository's scripts at the commit that built them (how they were
configured and built), and the license texts, and its `ffmpeg-NOTICE.txt` says what is where. nettai ships that
notice beside the `ffmpeg` it bundles.

## Building locally

```sh
# Linux or macOS: needs a C compiler, make, nasm (on x86_64), pkg-config, curl; rustc for the test streams.
export PREFIX="$PWD/prefix" OUTPUT="$PWD/out/ffmpeg"
scripts/fetch-sources.sh sources
scripts/build-x264.sh
scripts/build-ffmpeg.sh
scripts/make-streams.sh streams
scripts/smoke-test.sh out/ffmpeg streams mp4s
scripts/verify-mp4s.sh streams mp4s        # with a full ffmpeg and ffprobe on PATH
```

On macOS, set `MACOSX_DEPLOYMENT_TARGET=11.0` and `EXTRA_CFLAGS`/`EXTRA_LDFLAGS` to
`-mmacosx-version-min=11.0`, as the workflow does.

This repository's build scripts started as [tangobattle/ffmpeg-build](https://github.com/tangobattle/ffmpeg-build)'s.
