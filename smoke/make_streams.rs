//! Writes the raw inputs the smoke test feeds the built ffmpeg: what nettai
//! writes to its children's standard inputs as it exports a replay
//! (crates/nettai-video/src/ffmpeg.rs). The picture's child is given RGB
//! frames, 8 bits a color, rows from the top, one after another; a sound
//! track's child is given its samples at 48 kHz, 32-bit little-endian floats,
//! left then right.
//!
//! Usage: `make-streams DIR` writes into DIR:
//!
//! - `sound.rgb` and `sound.f32`: 120 frames (two seconds) at twice the frame's
//!   240x160, and the sound of those frames (as many samples as take it to the
//!   last frame's end: 96,437), as nettai's export writes a replay at scale 2;
//! - `silent.rgb`: 30 frames at three times the frame (an odd scale, where
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
    pictures(&dir.join("sound.rgb"), 2, 120);
    sound(&dir.join("sound.f32"), 120);
    pictures(&dir.join("silent.rgb"), 3, 30);
}

fn create(path: &Path) -> BufWriter<File> {
    BufWriter::new(File::create(path).expect("the file"))
}

/// `frames` frames at `scale` times the frame.
fn pictures(path: &Path, scale: usize, frames: u32) {
    let (width, height) = (WIDTH * scale, HEIGHT * scale);
    let mut out = create(path);
    let mut rgb = vec![0u8; width * height * 3];
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
        out.write_all(&rgb).expect("a frame");
    }
    out.flush().expect("the file's end");
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
