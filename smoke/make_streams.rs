//! Writes the NUT streams the smoke test feeds the built ffmpeg, with nettai's
//! own writer: `nut.rs` beside this file is nettai's
//! `crates/nettai-video/src/nut.rs`, fetched at a pinned commit by
//! `scripts/make-streams.sh`, so the bytes are the ones nettai pipes to ffmpeg
//! when it exports a replay (one syncpoint a frame, the GBA frame's exact time
//! base, `RGB[24]` pictures and `PFD[32]` sound, the index at the end).
//!
//! Usage: `make-streams DIR` writes into DIR:
//!
//! - `sound.nut`: 120 frames (two seconds) at twice the frame's 240x160, with
//!   sound, as nettai's export writes a replay at scale 2;
//! - `silent.nut`: 30 frames at three times the frame (an odd scale, where
//!   4:2:0's color samples straddle the game's pixels), with no sound, as
//!   nettai writes a replay whose game was loaded without its sound.
//!
//! The pictures are flat tiles of saturated color with a white square moving
//! over them (sharp edges, like the game's), the sound a tone in each ear.

mod nut;

use std::f32::consts::TAU;
use std::fs::File;
use std::io::BufWriter;
use std::path::Path;

/// A tick's length in seconds (nettai_frontend::player::TICK_SECONDS), and the
/// sound's sample rate (nettai_audio::SAMPLE_RATE).
const TICK_SECONDS: (u32, u32) = (4389, 262_144);
const SAMPLE_RATE: u32 = 32_768;

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
    write(&dir.join("sound.nut"), 2, 120, true);
    write(&dir.join("silent.nut"), 3, 30, false);
}

fn write(path: &Path, scale: usize, frames: u32, sound: bool) {
    let (width, height) = (WIDTH * scale, HEIGHT * scale);
    let video = nut::Video { width: width as u32, height: height as u32, frame_time: TICK_SECONDS };
    let audio = sound.then_some(nut::Audio { sample_rate: SAMPLE_RATE });
    let out = BufWriter::new(File::create(path).expect("the stream's file"));
    let mut stream = nut::Writer::new(out, video, audio).expect("the stream's headers");
    let mut rgb = vec![0u8; width * height * 3];
    let mut samples = Vec::new();
    let mut heard = 0u64;
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
        // The tick's samples: as many as take the sound to the tick's end.
        samples.clear();
        if sound {
            let (num, den) = (TICK_SECONDS.0 as u64, TICK_SECONDS.1 as u64);
            let until = (frame as u64 + 1) * SAMPLE_RATE as u64 * num / den;
            while heard < until {
                let t = heard as f32 / SAMPLE_RATE as f32;
                samples.push([0.25 * (TAU * 440.0 * t).sin(), 0.25 * (TAU * 660.0 * t).sin()]);
                heard += 1;
            }
        }
        stream.frame(&rgb, &samples).expect("a frame");
    }
    stream.finish().expect("the stream's end");
}
