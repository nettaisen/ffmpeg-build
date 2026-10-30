//! Writes the raw inputs the smoke test feeds the built ffmpeg: what nettai
//! writes to its children's standard inputs as it exports a replay
//! (crates/nettai-video/src/platform/desktop.rs). The picture's child is given
//! NV12 frames, one after another: a plane of luma, a byte a pixel, rows from
//! the top, then one of Cb and Cr in turn for each two by two pixels, made of
//! the game's RGB as nettai makes them (crates/nettai-video/src/yuv.rs, copied
//! below: BT.709, the video range, each chroma sample the mean of the four
//! pixels it covers). A sound track's child is given its samples at 48 kHz,
//! 32-bit little-endian floats, left then right.
//!
//! Usage: `make-streams DIR` writes into DIR:
//!
//! - `sound.nv12` and `sound.f32`: 120 frames (two seconds) at twice the frame's
//!   240x160, and the sound of those frames (as many samples as take it to the
//!   last frame's end: 96,437), as nettai's export writes a replay at scale 2;
//! - `silent.nv12`: 30 frames at three times the frame (an odd scale, where
//!   4:2:0's color samples straddle the game's pixels), as nettai writes a
//!   replay whose game was loaded without its sound.
//!
//! The pictures are flat tiles of saturated color with a white square moving
//! over them (sharp edges, like the game's), the sound a tone in each ear.

use std::f32::consts::TAU;
use std::fs::File;
use std::io::{BufWriter, Write};
use std::path::Path;

/// A tick's length in seconds (nettai_frontend::player::TICK_SECONDS), and the
/// rate the sound is given at (nettai-video's resample::RATE).
const TICK_SECONDS: (u64, u64) = (4389, 262_144);
const SAMPLE_RATE: u64 = 48_000;

/// The game's frame.
const WIDTH: usize = 240;
const HEIGHT: usize = 160;

const PALETTE: [[u8; 3]; 8] = [
    [248, 0, 0],
    [0, 200, 0],
    [0, 64, 248],
    [248, 216, 0],
    [216, 0, 216],
    [0, 216, 216],
    [32, 32, 32],
    [248, 128, 64],
];

fn main() {
    let dir = std::env::args().nth(1).expect("usage: make-streams DIR");
    let dir = Path::new(&dir);
    pictures(&dir.join("sound.nv12"), 2, 120);
    sound(&dir.join("sound.f32"), 120);
    pictures(&dir.join("silent.nv12"), 3, 30);
}

fn create(path: &Path) -> BufWriter<File> {
    BufWriter::new(File::create(path).expect("the file"))
}

/// `frames` frames at `scale` times the frame, as NV12.
fn pictures(path: &Path, scale: usize, frames: u32) {
    let (width, height) = (WIDTH * scale, HEIGHT * scale);
    let mut out = create(path);
    let mut rgb = vec![0u8; width * height * 3];
    let mut nv12 = Vec::new();
    for frame in 0..frames {
        // A tile is 8 game pixels square; the square is 16, moving 2 a frame.
        let (sx, sy) = ((frame as usize * 2) % (WIDTH - 16), (frame as usize) % (HEIGHT - 16));
        for y in 0..height {
            for x in 0..width {
                let (gx, gy) = (x / scale, y / scale);
                let color = if (sx..sx + 16).contains(&gx) && (sy..sy + 16).contains(&gy) {
                    [248, 248, 248]
                } else {
                    PALETTE[(gx / 8 + gy / 8 + frame as usize / 8) % PALETTE.len()]
                };
                rgb[(y * width + x) * 3..][..3].copy_from_slice(&color);
            }
        }
        to_nv12(&rgb, width, height, &mut nv12);
        out.write_all(&nv12).expect("a frame");
    }
    out.flush().expect("the file's end");
}

/// BT.709's luma weights.
const KR: f32 = 0.2126;
const KB: f32 = 0.0722;
const KG: f32 = 1.0 - KR - KB;

/// The NV12 of a frame of RGB bytes, `width` by `height` (both even), as nettai-video's `yuv::nv12` makes it.
fn to_nv12(rgb: &[u8], width: usize, height: usize, out: &mut Vec<u8>) {
    out.clear();
    out.resize(width * height * 3 / 2, 0);
    let (luma, chroma) = out.split_at_mut(width * height);
    let at = |x: usize, y: usize| {
        let p = &rgb[(y * width + x) * 3..][..3];
        (p[0] as f32, p[1] as f32, p[2] as f32)
    };
    for y in 0..height {
        for x in 0..width {
            let (r, g, b) = at(x, y);
            luma[y * width + x] = video_range(16.0 + 219.0 / 255.0 * (KR * r + KG * g + KB * b));
        }
    }
    for cy in 0..height / 2 {
        for cx in 0..width / 2 {
            let four = [at(2 * cx, 2 * cy), at(2 * cx + 1, 2 * cy), at(2 * cx, 2 * cy + 1), at(2 * cx + 1, 2 * cy + 1)];
            let mean = |f: fn(&(f32, f32, f32)) -> f32| four.iter().map(f).sum::<f32>() / 4.0;
            let (r, g, b) = (mean(|p| p.0), mean(|p| p.1), mean(|p| p.2));
            let y = KR * r + KG * g + KB * b;
            chroma[cy * width + 2 * cx] = video_range(128.0 + 224.0 / 255.0 * (b - y) / (2.0 * (1.0 - KB)));
            chroma[cy * width + 2 * cx + 1] = video_range(128.0 + 224.0 / 255.0 * (r - y) / (2.0 * (1.0 - KR)));
        }
    }
}

/// A sample rounded to the nearest byte.
fn video_range(v: f32) -> u8 {
    (v + 0.5).clamp(0.0, 255.0) as u8
}

/// The sound of `frames` frames: as many samples as take it to the last frame's end.
fn sound(path: &Path, frames: u64) {
    let mut out = create(path);
    let samples = frames * SAMPLE_RATE * TICK_SECONDS.0 / TICK_SECONDS.1;
    for n in 0..samples {
        let t = n as f32 / SAMPLE_RATE as f32;
        for v in [0.25 * (TAU * 440.0 * t).sin(), 0.25 * (TAU * 660.0 * t).sin()] {
            out.write_all(&v.to_le_bytes()).expect("a sample");
        }
    }
    out.flush().expect("the file's end");
}
