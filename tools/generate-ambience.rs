// SPDX-License-Identifier: MIT
// Offline maintainer tool. Original synthesized audio is dedicated to CC0.
// Compile: rustc --edition=2021 -O tools/generate-ambience.rs -o /tmp/skylofi-ambience
// Run: /tmp/skylofi-ambience assets
// No network, samples, runtime dependencies, or changes to the nine recordings.
use std::{
    f64::consts::TAU,
    fs,
    io::{self, BufWriter, Write},
    path::Path,
    process::Command,
};

const RATE: usize = 44_100;
const SECONDS: usize = 72;
const OVERLAP: usize = 3 * RATE;

#[derive(Clone, Copy)]
struct Track {
    file: &'static str,
    title: &'static str,
    style: usize,
}
const TRACKS: [Track; 23] = [
    Track {
        file: "drizzle",
        title: "Soft drizzle",
        style: 0,
    },
    Track {
        file: "window-rain",
        title: "Window rain",
        style: 1,
    },
    Track {
        file: "roof-rain",
        title: "Rain on a roof",
        style: 2,
    },
    Track {
        file: "downpour",
        title: "Deep downpour",
        style: 3,
    },
    Track {
        file: "leaf-wind",
        title: "Wind in leaves",
        style: 4,
    },
    Track {
        file: "pine-wind",
        title: "Wind through pines",
        style: 5,
    },
    Track {
        file: "winter-wind",
        title: "Winter wind",
        style: 6,
    },
    Track {
        file: "river",
        title: "Wide river",
        style: 7,
    },
    Track {
        file: "waterfall",
        title: "Waterfall",
        style: 8,
    },
    Track {
        file: "harbour-water",
        title: "Harbour water",
        style: 9,
    },
    Track {
        file: "water-drops",
        title: "Scattered water drops",
        style: 10,
    },
    Track {
        file: "campfire",
        title: "Campfire",
        style: 11,
    },
    Track {
        file: "embers",
        title: "Glowing embers",
        style: 12,
    },
    Track {
        file: "desk-fan",
        title: "Desk fan",
        style: 13,
    },
    Track {
        file: "air-vent",
        title: "Soft ventilation",
        style: 14,
    },
    Track {
        file: "train-cabin",
        title: "Night train",
        style: 15,
    },
    Track {
        file: "cabin-hum",
        title: "Air cabin",
        style: 16,
    },
    Track {
        file: "brown-noise",
        title: "Brown noise",
        style: 17,
    },
    Track {
        file: "pink-noise",
        title: "Pink noise",
        style: 18,
    },
    Track {
        file: "white-noise",
        title: "White noise",
        style: 19,
    },
    Track {
        file: "tape-hiss",
        title: "Tape air",
        style: 20,
    },
    Track {
        file: "vinyl-texture",
        title: "Vinyl texture",
        style: 21,
    },
    Track {
        file: "soft-drone",
        title: "Soft drone",
        style: 22,
    },
];

struct Rng(u64);
impl Rng {
    fn next(&mut self) -> f64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        (self.0 >> 11) as f64 / (1u64 << 53) as f64
    }
    fn noise(&mut self) -> f64 {
        self.next() * 2.0 - 1.0
    }
}

#[derive(Default)]
struct Color {
    pink: [f64; 7],
    brown: f64,
    low: f64,
    mid: f64,
    high: f64,
    warm: f64,
}
impl Color {
    fn tick(&mut self, white: f64) -> [f64; 6] {
        self.pink[0] = 0.99886 * self.pink[0] + white * 0.0555179;
        self.pink[1] = 0.99332 * self.pink[1] + white * 0.0750759;
        self.pink[2] = 0.96900 * self.pink[2] + white * 0.1538520;
        self.pink[3] = 0.86650 * self.pink[3] + white * 0.3104856;
        self.pink[4] = 0.55000 * self.pink[4] + white * 0.5329522;
        self.pink[5] = -0.7616 * self.pink[5] - white * 0.0168980;
        let pink = (self.pink.iter().sum::<f64>() + white * 0.5362) * 0.11;
        self.pink[6] = white * 0.115926;
        self.brown = self.brown * 0.9985 + white * 0.018;
        self.low += 0.022 * (pink - self.low);
        self.mid += 0.15 * (pink - self.mid);
        self.high += 0.38 * (white - self.high);
        self.warm += 0.0035 * (pink - self.warm);
        [pink, self.brown, self.low, self.mid, self.high, self.warm]
    }
}

// Low-rate physical textures; every onset, timbre and side varies independently.
struct Event {
    start: usize,
    length: usize,
    frequency: f64,
    gain: f64,
    pan: f64,
    kind: usize,
}
fn events(style: usize, rng: &mut Rng) -> Vec<Event> {
    let (density, duration, frequency, gain, kind) = match style {
        0 => (1.9, 0.023, 2600.0, 0.018, 0),
        1 => (3.2, 0.070, 1700.0, 0.050, 0),
        2 => (8.0, 0.047, 490.0, 0.035, 0),
        3 => (12.0, 0.024, 1900.0, 0.013, 0),
        4 => (0.7, 0.60, 3000.0, 0.009, 1),
        7 => (2.6, 0.10, 340.0, 0.022, 2),
        9 => (0.6, 0.38, 170.0, 0.032, 2),
        10 => (0.65, 0.15, 930.0, 0.07, 2),
        11 => (2.8, 0.030, 760.0, 0.07, 1),
        12 => (0.7, 0.080, 360.0, 0.027, 1),
        15 => (0.5, 0.36, 64.0, 0.034, 3),
        21 => (0.65, 0.006, 2400.0, 0.022, 1),
        _ => return vec![],
    };
    let mut result = vec![];
    let mut seconds = 0.0;
    while seconds < SECONDS as f64 {
        seconds += -(1.0 - rng.next().min(0.999999)).ln() / density;
        result.push(Event {
            start: (seconds * RATE as f64) as usize,
            length: (duration * (0.45 + 1.1 * rng.next()) * RATE as f64) as usize,
            frequency: frequency * (0.6 + 0.8 * rng.next()),
            gain: gain * (0.5 + rng.next()),
            pan: rng.next() * 1.3 - 0.65,
            kind,
        });
    }
    result
}

fn bed(style: usize, t: f64, color: [f64; 6], side: usize) -> f64 {
    let [pink, brown, low, mid, air, warm] = color;
    let gust = 0.67 + 0.18 * (TAU * t / 17.1).sin() + 0.12 * (TAU * t / 9.7 + 1.2).sin();
    let swell = 0.56 + 0.24 * (TAU * t / 11.8).sin() + 0.16 * (TAU * t / 7.3 + 0.9).sin();
    let slow = 0.87 + 0.09 * (TAU * t / 27.3).sin() + 0.04 * (TAU * t / 13.7).sin();
    let tone = |hz: f64| (TAU * hz * t + side as f64 * 0.045).sin();
    match style {
        0 => (0.17 * pink + 0.035 * air) * slow,
        1 => (0.24 * mid + 0.12 * low + 0.025 * air) * slow,
        2 => (0.34 * mid + 0.035 * brown) * slow,
        3 => (0.48 * pink + 0.30 * low + 0.06 * air) * slow,
        4 => (0.22 * (pink - low) + 0.055 * air) * gust,
        5 => (0.41 * low + 0.20 * mid + 0.009 * tone(182.0) * gust) * gust,
        6 => (0.19 * brown + 0.18 * low + 0.065 * air + 0.012 * tone(128.0)) * gust,
        7 => (0.35 * mid + 0.25 * low + 0.11 * (pink - low)) * slow,
        8 => (0.38 * brown + 0.36 * pink + 0.08 * air) * slow,
        9 => (0.35 * low + 0.20 * mid + 0.05 * air) * swell,
        10 => 0.017 * low,
        11 => 0.13 * brown + 0.052 * mid,
        12 => 0.17 * warm + 0.027 * (pink - low),
        13 => 0.033 * tone(73.4) + 0.011 * tone(146.8) + 0.20 * mid * (0.94 + 0.06 * tone(6.2)),
        14 => 0.35 * low + 0.25 * mid + 0.025 * tone(96.0),
        15 => (0.27 * brown + 0.25 * low) * slow + 0.013 * tone(47.2) + 0.006 * tone(118.0),
        16 => 0.19 * brown + 0.34 * low + 0.015 * tone(83.7) + 0.09 * mid,
        17 => 0.45 * brown,
        18 => 0.47 * pink,
        19 => 0.32 * air,
        20 => (0.24 * (air - mid) + 0.035 * pink) * slow,
        21 => 0.11 * (pink - low) + 0.09 * warm,
        22 => (0.030 * tone(74.2) + 0.014 * tone(111.3) + 0.009 * tone(148.4)) * slow + 0.08 * low,
        _ => unreachable!(),
    }
}

fn generate(track: Track) -> Vec<[f64; 2]> {
    let seed = 0x9e3779b97f4a7c15u64 ^ ((track.style as u64 + 1) * 0x100000001b3);
    let mut common = Rng(seed);
    let mut left = Rng(seed ^ 0xd1b54a32d192ed03);
    let mut right = Rng(seed ^ 0x94d049bb133111eb);
    let occurrences = events(track.style, &mut Rng(seed ^ 0x243f6a8885a308d3));
    let mut colors = [Color::default(), Color::default()];
    let mut result = Vec::with_capacity(SECONDS * RATE);
    let mut cursor = 0;
    let mut active: Vec<usize> = vec![];
    for n in 0..SECONDS * RATE {
        let t = n as f64 / RATE as f64;
        let center = common.noise();
        let white = [
            center * 0.75 + left.noise() * 0.25,
            center * 0.75 + right.noise() * 0.25,
        ];
        let mut frame = [
            bed(track.style, t, colors[0].tick(white[0]), 0),
            bed(track.style, t, colors[1].tick(white[1]), 1),
        ];
        while cursor < occurrences.len() && occurrences[cursor].start <= n {
            active.push(cursor);
            cursor += 1;
        }
        active.retain(|&index| n < occurrences[index].start + occurrences[index].length);
        for &index in &active {
            let event = &occurrences[index];
            let elapsed = (n - event.start) as f64 / RATE as f64;
            let progress = (n - event.start) as f64 / event.length as f64;
            let attack = (progress * 45.0).min(1.0);
            let envelope = attack * (1.0 - progress).powi(2) * (-progress * 3.5).exp();
            let pitch = event.frequency * elapsed;
            let sample = match event.kind {
                0 => (0.65 * (TAU * pitch).sin() + 0.35 * center) * envelope,
                1 => center * envelope,
                2 => (TAU * pitch * (1.0 + progress * 0.21)).sin() * envelope,
                3 => {
                    ((TAU * pitch).sin() * 0.35 + colors[0].low)
                        * (std::f64::consts::PI * progress).sin()
                }
                _ => unreachable!(),
            } * event.gain;
            frame[0] += sample * (0.5 - event.pan * 0.4).sqrt();
            frame[1] += sample * (0.5 + event.pan * 0.4).sqrt();
        }
        result.push(frame);
    }
    seamless(&result)
}

fn seamless(source: &[[f64; 2]]) -> Vec<[f64; 2]> {
    let length = source.len() - OVERLAP;
    let mut result = source[OVERLAP..].to_vec();
    for i in 0..OVERLAP {
        let progress = i as f64 / (OVERLAP - 1) as f64;
        let a = (progress * std::f64::consts::FRAC_PI_2).cos();
        let b = (progress * std::f64::consts::FRAC_PI_2).sin();
        for side in 0..2 {
            result[length - OVERLAP + i][side] = source[length + i][side] * a + source[i][side] * b;
        }
    }
    // Global DC removal and matched average energy. Gain is bounded by peaks,
    // so rare drops/crackles remain quiet instead of being hard-limited.
    let dc = result.iter().fold([0.0, 0.0], |mut total, frame| {
        total[0] += frame[0];
        total[1] += frame[1];
        total
    });
    let dc = [dc[0] / length as f64, dc[1] / length as f64];
    for frame in &mut result {
        for side in 0..2 {
            frame[side] -= dc[side];
        }
    }
    let peak = result.iter().flatten().map(|v| v.abs()).fold(0.0, f64::max);
    let rms = (result.iter().flatten().map(|v| v * v).sum::<f64>() / (length * 2) as f64).sqrt();
    // Match the quiet bundled recordings: continuous beds target -31 dBFS RMS.
    // Sparse drops may stay quieter; their peaks never drive a hard limiter.
    let gain = (0.028_183_829 / rms.max(1e-10)).min(0.35 / peak.max(1e-10));
    for frame in &mut result {
        for sample in frame {
            *sample *= gain;
        }
    }
    result
}

fn write_wav(path: &Path, frames: &[[f64; 2]]) -> io::Result<()> {
    let size = (frames.len() * 4) as u32;
    let mut out = BufWriter::new(fs::File::create(path)?);
    out.write_all(b"RIFF")?;
    out.write_all(&(size + 36).to_le_bytes())?;
    out.write_all(b"WAVEfmt ")?;
    out.write_all(&16u32.to_le_bytes())?;
    out.write_all(&1u16.to_le_bytes())?;
    out.write_all(&2u16.to_le_bytes())?;
    out.write_all(&(RATE as u32).to_le_bytes())?;
    out.write_all(&((RATE * 4) as u32).to_le_bytes())?;
    out.write_all(&4u16.to_le_bytes())?;
    out.write_all(&16u16.to_le_bytes())?;
    out.write_all(b"data")?;
    out.write_all(&size.to_le_bytes())?;
    for frame in frames {
        for sample in frame {
            out.write_all(&((sample * 32767.0).round() as i16).to_le_bytes())?;
        }
    }
    out.flush()
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let destination = std::env::args_os()
        .nth(1)
        .ok_or("Pass an output assets directory")?;
    let destination = Path::new(&destination);
    fs::create_dir_all(destination)?;
    for track in TRACKS {
        let frames = generate(track);
        let peak = frames.iter().flatten().map(|v| v.abs()).fold(0.0, f64::max);
        let rms = (frames.iter().flatten().map(|v| v * v).sum::<f64>() / (frames.len() * 2) as f64)
            .sqrt();
        let wav = destination.join(format!(".generated-{}.wav", track.file));
        let ogg = destination.join(format!("{}.ogg", track.file));
        write_wav(&wav, &frames)?;
        let encoded = Command::new("ffmpeg")
            .args(["-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i"])
            .arg(&wav)
            .args([
                "-c:a",
                "libvorbis",
                "-q:a",
                "4",
                "-map_metadata",
                "-1",
                "-fflags",
                "+bitexact",
                "-flags:a",
                "+bitexact",
                "-metadata",
            ])
            .arg(format!("title={}", track.title))
            .args([
                "-metadata",
                "artist=OBJLAKO",
                "-metadata",
                "copyright=CC0 1.0 Universal",
                "-metadata",
                "comment=Original procedural ambience; not a field recording",
            ])
            .arg(&ogg)
            .status();
        fs::remove_file(&wav)?;
        if !encoded?.success() {
            return Err(format!("FFmpeg could not encode {}", track.file).into());
        }
        println!(
            "{} duration=69s peak={:.2}dBFS rms={:.2}dBFS",
            track.file,
            20.0 * peak.log10(),
            20.0 * rms.log10()
        );
    }
    Ok(())
}
