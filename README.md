# nettai-ffmpeg-build

Builds of a **minimal static `ffmpeg`** for [nettai](https://github.com/nettaisen/nettai), which bundles it in
every package so a replay can be exported as video with nothing else installed.

nettai links no FFmpeg library. Its replay export (`crates/nettai-video`'s desktop platform, run by the app and by
`nettai-tool --mp4`) runs an `ffmpeg` child a track: one for the picture, written the replay's frames as raw NV12
on its standard input, and one for each sound track, written its raw samples. Each writes its track's codec data
on its standard output (the picture's H.264 as an Annex B stream, a sound track's AAC as ADTS), of which nettai
makes the MP4 itself. This repository
builds that program for every platform nettai's release packages, with what those two commands need and nothing
more: configure starts from `--disable-everything` and each component is enabled again, traced to nettai's
commands. The user's request: "it should support whatever
nettai needs and nothing more so the build is minimal", built "with a separate workflow ... so you don't have
to build ffmpeg every time".

## Releases

The [`build-ffmpeg`](.github/workflows/build.yaml) workflow is run by hand (Actions → build-ffmpeg → Run
workflow) with an FFmpeg release (`ffmpeg_version`, 9.0.2 by default) and a revision (`revision`, 1 by
default; a new one for each rebuild of the same version). On main, with `publish` on (the default), it
publishes a GitHub Release tagged `ffmpeg-<version>-<revision>` and refuses a tag that is released already.
With `publish` off it builds and tests everything and keeps the binaries (with their `.sha256`s) as the run's
artifacts, and releases nothing: how a change is tried on a branch, and how nettai's packaging is tried with
binaries not yet released (its `NETTAI_BUNDLE_FFMPEG`). Each release carries:

| Asset                                   | What                                                                       |
| --------------------------------------- | -------------------------------------------------------------------------- |
| `ffmpeg-linux-x86_64`                   | Linux x86_64, built on ubuntu-22.04, fully static (runs on any distro)     |
| `ffmpeg-linux-arm64`                    | Linux arm64, built on ubuntu-22.04-arm, fully static                       |
| `ffmpeg-windows-x86_64.exe`             | Windows x86_64, MSVC with the static CRT: needs no DLL beyond Windows' own |
| `ffmpeg-windows-arm64.exe`              | Windows on Arm, cross-compiled with llvm-mingw against the UCRT, static: needs no DLL beyond Windows' own; tested on windows-11-arm |
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

Windows on Arm's is cross-compiled on Linux with [llvm-mingw](https://github.com/mstorsjo/llvm-mingw) (a pinned
release, checked by its SHA-256): Clang and LLD for `aarch64-w64-mingw32`, which assemble x264's and FFmpeg's NEON
code as they are. The program links against the UCRT (`api-ms-win-crt-*`, Windows' own since Windows 10, so on
every Windows that runs on Arm) and has everything else linked in (`-static`); the job fails if it imports a DLL
that isn't Windows' own. MSVC's way, as x86_64 is built, would need MSYS2 for configure and make, which the
`windows-11-arm` runner doesn't have. The program built is then smoke-tested natively on `windows-11-arm`.

Download URLs are stable, e.g.
`https://github.com/nettaisen/ffmpeg-build/releases/download/ffmpeg-9.0.2-2/ffmpeg-linux-x86_64`. nettai
pins a release by its tag and each file it takes by its SHA-256 (`packaging/ffmpeg.sha256` in nettai).

## What's enabled, and why

nettai's commands (`crates/nettai-video/src/platform/desktop.rs`, `picture_arguments` and `sound_arguments`):

```text
ffmpeg -hide_banner -nostdin -loglevel error
       -f rawvideo -pixel_format nv12 -video_size WxH -framerate 262144/4389 -i pipe:0
       -c:v libx264 -preset medium -tune animation -crf 16 -g 120 -bf 0
       -x264-params aud=1:colorprim=bt709:transfer=bt709:colormatrix=bt709:range=tv
       -f h264 pipe:1

ffmpeg -hide_banner -nostdin -loglevel error
       -f f32le -sample_rate 48000 -ch_layout stereo -i pipe:0
       -c:a aac -b:a 192000
       -f adts pipe:1
```

The picture is NV12 (BT.709's matrix, the video range: nettai converts the game's RGB itself, the same bytes
every platform's encoder is given) at the GBA frame's exact rate (262144/4389 a second), with no B-frames (nettai
times each picture by its place) and its color tagged in the stream itself; the sound is 32-bit float stereo at
48 kHz, which nettai resamples to itself (from the GBA's 32768 Hz). nettai asks ffmpeg nothing else (no
`-version`, no probing).

The one place the components are named is [`scripts/ffmpeg-config-common.sh`](scripts/ffmpeg-config-common.sh):

| Component                            | nettai's use                                                                   |
| ------------------------------------ | ------------------------------------------------------------------------------ |
| demuxer `rawvideo`                   | `-f rawvideo -i pipe:0`: the picture's frames                                  |
| demuxer `pcm_f32le`                  | `-f f32le -i pipe:0`: a sound track's samples                                  |
| decoder `rawvideo`                   | the frames' NV12                                                               |
| decoder `pcm_f32le`                  | the samples' floats                                                            |
| protocol `pipe`                      | `-i pipe:0` and `pipe:1`: nettai writes the file itself                        |
| filter `aresample` (swresample)      | the float samples made the planar floats AAC takes, inserted by ffmpeg (nothing is resampled) |
| filter `aformat`                     | the formats AAC takes, inserted by ffmpeg                                      |
| filters `null`, `anull`              | the pass-through ends of a stream's graph where it has no filter of its own   |
| encoder `libx264`                    | `-c:v libx264 -preset medium -tune animation -crf 16 -bf 0`, NV12 as it is     |
| encoder `aac`                        | `-c:a aac -b:a 192000`                                                         |
| muxer `h264`                         | `-f h264`: the picture's Annex B stream on the pipe                            |
| muxer `adts`                         | `-f adts`: a sound track's AAC frames on the pipe                              |
| external library `libx264` (`--enable-gpl`) | the H.264 encoder; it makes the binary GPL                              |

Configure adds what these need by itself: the `ffmpeg` program brings its filter graph's ends and the filters
its own options use (`atrim`, `crop`, `hflip`, `rotate`, `transpose`, `trim`, `vflip`), and the `adts` muxer the
`mpeg4audio` code. No bitstream filter: libx264 writes Annex B itself, which the `h264` muxer passes on. Nothing
else is built: no other codec, container, protocol, device, network, or hardware API; no `ffprobe` or
`ffplay`. x264 is built 8-bit only (nettai gives it 4:2:0).

## Tests

Each platform's binary is **smoke-tested** ([`scripts/smoke-test.sh`](scripts/smoke-test.sh)), on that
platform (Windows on Arm's in a job of its own on `windows-11-arm`, after it is built on Linux), with nettai's
exact commands on the raw bytes nettai writes, made by [`smoke/make_streams.rs`](smoke/make_streams.rs)
([`scripts/make-streams.sh`](scripts/make-streams.sh)): two seconds of NV12 frames at twice the frame (made of
RGB as nettai makes them), a second at three times the frame, and their sound. ffmpeg must end well, say nothing
at `-loglevel error`, and write an H.264 stream that starts with an access unit delimiter, and ADTS that starts
with its sync word. Then [`scripts/verify-outputs.sh`](scripts/verify-outputs.sh) decodes every platform's
outputs with the runner's full ffmpeg and checks them: H.264 High of every frame at the input's size, no
B-frames, 4:2:0, tagged BT.709 TV range, the picture close to the NV12 given (PSNR 45 dB at least); AAC LC at
48 kHz stereo, decoding to the encoder's delay of 1024 samples, the samples given and less than a frame of
padding, not silence; every packet decoding without an error. A release is published only when all of it
passes.

## Versions

- **FFmpeg**: the `ffmpeg_version` input, 9.0.2 by default (`FFMPEG_VERSION` in
  `scripts/ffmpeg-config-common.sh`): a release's tarball from ffmpeg.org, never "the latest".
- **x264**: the commit `X264_COMMIT` (the head of its `stable` branch on 2026-10-14); x264 has no release tags.

## Licensing

FFmpeg is LGPL-2.1-or-later with optional GPL parts; x264 is GPL-2.0-or-later. Built with `--enable-gpl` and
linked with x264, **each binary is licensed GPL-2.0-or-later as a whole**. Whoever distributes one must make its
complete corresponding source available under the GPL. So every release carries, beside the binaries, the exact
source tarballs they were built from, this repository's scripts at the commit that built them (how they were
configured and built), and the license texts, and its `ffmpeg-NOTICE.txt` says what is where. nettai ships that
notice beside the `ffmpeg` it bundles.

## Building locally

```sh
# Linux or macOS: needs a C compiler, make, nasm (on x86_64), pkg-config, curl; rustc for the test inputs.
export PREFIX="$PWD/prefix" OUTPUT="$PWD/out/ffmpeg"
scripts/fetch-sources.sh sources
scripts/build-x264.sh
scripts/build-ffmpeg.sh
scripts/make-streams.sh streams
scripts/smoke-test.sh out/ffmpeg streams outputs
scripts/verify-outputs.sh streams outputs  # with a full ffmpeg and ffprobe on PATH
```

On macOS, set `MACOSX_DEPLOYMENT_TARGET=11.0` and `EXTRA_CFLAGS`/`EXTRA_LDFLAGS` to
`-mmacosx-version-min=11.0`, as the workflow does.

Windows on Arm's, on Linux or macOS with llvm-mingw's `bin` on PATH (the program runs on Windows on Arm alone, so
the build doesn't run it: `RUN_BUILT=no`; smoke-test it there):

```sh
export PREFIX="$PWD/prefix" OUTPUT="$PWD/out/ffmpeg-windows-arm64.exe" EXE_SUFFIX=.exe RUN_BUILT=no
export X264_HOST=aarch64-w64-mingw32 X264_CROSS_PREFIX=aarch64-w64-mingw32- EXTRA_LDFLAGS=-static
export FFMPEG_EXTRA="--enable-cross-compile --arch=aarch64 --target-os=mingw32 --cross-prefix=aarch64-w64-mingw32- --pkg-config=pkg-config"
scripts/build-x264.sh
scripts/build-ffmpeg.sh
```

This repository's build scripts started as [tangobattle/ffmpeg-build](https://github.com/tangobattle/ffmpeg-build)'s.
