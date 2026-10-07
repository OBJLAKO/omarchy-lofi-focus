//! A bounded local soundscape mixer. Network sources remain in mpv.
//!
//! One Kira output owns sixteen reusable source tracks and two shared wet-only
//! effect buses. File decoding runs in cancellable workers with fixed PCM
//! queues; the renderer only consumes samples and applies prepared DSP.

use std::{
    collections::HashMap,
    fs::File,
    path::Path,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    thread::{self, JoinHandle},
    time::Duration,
};

use kira::{
    backend::{Backend, Renderer},
    command::{command_writer_and_reader, CommandReader, CommandWriter},
    effect::{
        delay::DelayBuilder,
        filter::{FilterBuilder, FilterHandle},
        reverb::{ReverbBuilder, ReverbHandle},
        Effect, EffectBuilder,
    },
    info::Info,
    sound::{Sound, SoundData},
    track::{MainTrackBuilder, SendTrackBuilder, SendTrackHandle, TrackBuilder, TrackHandle},
    AudioManager, AudioManagerSettings, Capacities, Decibels, DefaultBackend, Frame, Mix, Tween,
};
use rtrb::{Consumer, Producer, RingBuffer};
use symphonia::core::{
    audio::{conv::FromSample, sample::Sample, Audio, AudioBuffer, GenericAudioBufferRef},
    codecs::{audio::AudioDecoder, CodecParameters},
    formats::{probe::Hint, FormatReader, SeekMode, SeekTo, TrackType},
    io::MediaSourceStream,
    units::Timestamp,
};

pub const MAX_LOCAL_LAYERS: usize = 16;
// ~0.37 s at 44.1 kHz; queue memory is independent of the recording's duration.
const QUEUE_FRAMES: usize = 16_384;
const MAX_PACKET_FRAMES: usize = 65_536;
const PARAMETER_SMOOTHING: Duration = Duration::from_millis(45);

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct LayerParams {
    pub volume: f64,
    pub pan: f64,
    pub distance: f64,
    pub reflections: f64,
    pub softness: f64,
    pub width: f64,
    pub echo: f64,
    pub outside: bool,
}

impl Default for LayerParams {
    fn default() -> Self {
        Self {
            volume: 0.25,
            pan: 0.0,
            distance: 0.0,
            reflections: 0.0,
            softness: 0.0,
            width: 1.0,
            echo: 0.0,
            outside: false,
        }
    }
}

impl LayerParams {
    fn normalized(self) -> Self {
        Self {
            volume: unit(self.volume, 0.25),
            pan: finite(self.pan, 0.0).clamp(-1.0, 1.0),
            distance: unit(self.distance, 0.0),
            reflections: unit(self.reflections, 0.0),
            softness: unit(self.softness, 0.0),
            width: unit(self.width, 1.0),
            echo: unit(self.echo, 0.0),
            outside: self.outside,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct RoomParams {
    pub preset: String,
    pub size: f64,
    pub softness: f64,
    pub reflections: f64,
}

impl Default for RoomParams {
    fn default() -> Self {
        Self {
            preset: "room".into(),
            size: 0.35,
            softness: 0.65,
            reflections: 0.35,
        }
    }
}

impl RoomParams {
    fn normalized(&self) -> Self {
        Self {
            preset: self.preset.chars().take(40).collect(),
            size: unit(self.size, 0.35),
            softness: unit(self.softness, 0.65),
            reflections: unit(self.reflections, 0.35),
        }
    }
}

fn finite(value: f64, fallback: f64) -> f64 {
    if value.is_finite() {
        value
    } else {
        fallback
    }
}

fn unit(value: f64, fallback: f64) -> f64 {
    finite(value, fallback).clamp(0.0, 1.0)
}

fn db(gain: f64) -> Decibels {
    if gain <= 0.0 {
        Decibels::SILENCE
    } else {
        Decibels((20.0 * gain.log10()) as f32)
    }
}

fn smooth() -> Tween {
    Tween {
        duration: PARAMETER_SMOOTHING,
        ..Tween::default()
    }
}

fn immediate() -> Tween {
    Tween {
        duration: Duration::ZERO,
        ..Tween::default()
    }
}

#[derive(Debug, Clone, Copy)]
struct LayerResponse {
    gain: f64,
    cutoff: f64,
    filter_mix: f64,
    reverb_send: f64,
    echo_send: f64,
}

fn response(params: LayerParams) -> LayerResponse {
    let p = params.normalized();
    let obstruction = if p.outside { 0.4 } else { 0.0 };
    let dullness = (p.distance * 0.55 + p.softness * 0.7 + obstruction).min(1.0);
    LayerResponse {
        gain: p.volume / (1.0 + p.distance * 2.5) * if p.outside { 0.8 } else { 1.0 },
        cutoff: 20_000.0 * (900.0_f64 / 20_000.0).powf(dullness),
        filter_mix: if dullness == 0.0 { 0.0 } else { 1.0 },
        reverb_send: p.reflections
            * (0.12 + 0.65 * p.distance)
            * if p.outside { 0.25 } else { 1.0 },
        echo_send: p.echo * 0.28,
    }
}

struct Slot {
    track: TrackHandle,
    filter: FilterHandle,
    stereo: CommandWriter<(f64, f64)>,
    sound: Option<LoopHandle>,
    params: LayerParams,
}

/// Dropping or stopping this mixer cancels every decoder worker and releases
/// the single audio output. Callers should construct it lazily for active audio.
pub struct LocalAudio<B: Backend = LocalBackend> {
    manager: Option<AudioManager<B>>,
    slots: Vec<Slot>,
    active: HashMap<String, usize>,
    reverb_track: SendTrackHandle,
    echo_track: SendTrackHandle,
    reverb: ReverbHandle,
    room: RoomParams,
    paused: bool,
}

/// The null output is available only through an explicit test setting; normal
/// initialization always opens the system output and reports device failures.
pub struct LocalBackend(OutputKind);

#[derive(Default)]
pub struct LocalBackendSettings {
    mock: bool,
}

enum OutputKind {
    Real(DefaultBackend),
    Null {
        cancelled: Arc<AtomicBool>,
        worker: Option<JoinHandle<()>>,
        buffer_size: usize,
    },
}

impl Backend for LocalBackend {
    type Settings = LocalBackendSettings;
    type Error = String;
    fn setup(settings: LocalBackendSettings, buffer_size: usize) -> Result<(Self, u32), String> {
        if settings.mock {
            return Ok((
                Self(OutputKind::Null {
                    cancelled: Arc::new(AtomicBool::new(false)),
                    worker: None,
                    buffer_size,
                }),
                48_000,
            ));
        }
        let (backend, rate) = DefaultBackend::setup(Default::default(), buffer_size)
            .map_err(|error| error.to_string())?;
        Ok((Self(OutputKind::Real(backend)), rate))
    }
    fn start(&mut self, mut renderer: Renderer) -> Result<(), String> {
        match &mut self.0 {
            OutputKind::Real(backend) => backend.start(renderer).map_err(|error| error.to_string()),
            OutputKind::Null {
                cancelled,
                worker,
                buffer_size,
            } => {
                let flag = cancelled.clone();
                let size = *buffer_size;
                *worker = Some(
                    thread::Builder::new()
                        .name("skylofi-null-audio".into())
                        .spawn(move || {
                            let mut samples = vec![0.0; size * 2];
                            let period = Duration::from_secs_f64(size as f64 / 48_000.0);
                            while !flag.load(Ordering::Acquire) {
                                renderer.on_start_processing();
                                renderer.process(&mut samples, 2);
                                thread::park_timeout(period);
                            }
                        })
                        .map_err(|error| error.to_string())?,
                );
                Ok(())
            }
        }
    }
}

impl Drop for LocalBackend {
    fn drop(&mut self) {
        if let OutputKind::Null {
            cancelled, worker, ..
        } = &mut self.0
        {
            cancelled.store(true, Ordering::Release);
            if let Some(worker) = worker.take() {
                worker.thread().unpark();
                let _ = worker.join();
            }
        }
    }
}

impl LocalAudio<LocalBackend> {
    pub fn new() -> Result<Self, String> {
        Self::with_settings(AudioManagerSettings::default())
    }

    /// Explicit device-free output for hermetic process/integration fixtures.
    pub fn new_mock() -> Result<Self, String> {
        Self::with_settings(AudioManagerSettings {
            backend_settings: LocalBackendSettings { mock: true },
            ..AudioManagerSettings::default()
        })
    }
}

impl<B: Backend> LocalAudio<B>
where
    B::Error: std::fmt::Debug,
{
    fn with_settings(mut settings: AudioManagerSettings<B>) -> Result<Self, String> {
        settings.capacities = Capacities {
            sub_track_capacity: MAX_LOCAL_LAYERS,
            send_track_capacity: 2,
            clock_capacity: 0,
            modulator_capacity: 0,
            listener_capacity: 0,
        };
        settings.main_track_builder = MainTrackBuilder::new()
            .sound_capacity(0)
            .with_effect(PeakGuard);
        let mut manager = AudioManager::<B>::new(settings)
            .map_err(|error| format!("Cannot open local audio output: {error:?}"))?;
        let mut reverb_builder = SendTrackBuilder::new();
        let reverb = reverb_builder.add_effect(ReverbBuilder::new().mix(Mix::WET).feedback(0.7));
        let reverb_track = manager
            .add_send_track(reverb_builder)
            .map_err(|error| format!("Cannot create room reflections: {error}"))?;
        let echo_track = manager
            .add_send_track(
                SendTrackBuilder::new().with_effect(
                    DelayBuilder::new()
                        .delay_time(Duration::from_millis(280))
                        .feedback(-14.0)
                        .mix(Mix::WET)
                        .with_feedback_effect(FilterBuilder::new().cutoff(2800.0)),
                ),
            )
            .map_err(|error| format!("Cannot create room echo: {error}"))?;
        let mut slots = Vec::with_capacity(MAX_LOCAL_LAYERS);
        for _ in 0..MAX_LOCAL_LAYERS {
            let mut builder = TrackBuilder::new()
                .sub_track_capacity(0)
                .sound_capacity(2)
                .with_send(&reverb_track, Decibels::SILENCE)
                .with_send(&echo_track, Decibels::SILENCE);
            let filter = builder.add_effect(FilterBuilder::new().mix(Mix::DRY).cutoff(20_000.0));
            let stereo = builder.add_effect(StereoFieldBuilder);
            let track = manager
                .add_sub_track(builder)
                .map_err(|error| format!("Cannot create local audio layer: {error}"))?;
            slots.push(Slot {
                track,
                filter,
                stereo,
                sound: None,
                params: LayerParams::default(),
            });
        }
        let mut result = Self {
            manager: Some(manager),
            slots,
            active: HashMap::with_capacity(MAX_LOCAL_LAYERS),
            reverb_track,
            echo_track,
            reverb,
            room: RoomParams {
                preset: String::new(),
                ..RoomParams::default()
            },
            paused: false,
        };
        result.set_room(RoomParams::default());
        Ok(result)
    }

    pub fn play(
        &mut self,
        id: &str,
        path: &Path,
        params: LayerParams,
        room: RoomParams,
        paused: bool,
    ) -> Result<(), String> {
        if self.manager.is_none() {
            return Err("Local audio has stopped".into());
        }
        if id.is_empty() || id.len() > 80 {
            return Err("Invalid local sound ID".into());
        }
        // Validate/open the new file before disturbing an existing layer.
        let data = LoopData::from_file(path)?;
        let index = if let Some(index) = self.active.get(id).copied() {
            index
        } else {
            if self.active.len() >= MAX_LOCAL_LAYERS {
                return Err(format!(
                    "A room supports up to {MAX_LOCAL_LAYERS} active sounds"
                ));
            }
            self.slots
                .iter()
                .position(|slot| slot.sound.is_none())
                .ok_or("No local audio slot available")?
        };
        let slot = &mut self.slots[index];
        // There are at most two sounds per slot while the renderer retires the
        // old cancelled source. No unbounded track/worker creation on rapid edits.
        if slot.track.num_sounds() >= slot.track.sound_capacity() {
            return Err("This sound is still changing; retry shortly".into());
        }
        let next_sound = slot
            .track
            .play(data)
            .map_err(|error| format!("Cannot play local sound: {error}"))?;
        if let Some(old) = slot.sound.replace(next_sound) {
            drop(old);
        }
        if let Some(sound) = &slot.sound {
            sound.set_paused(paused);
        }
        self.active.insert(id.into(), index);
        self.apply_params(index, params, immediate());
        self.set_room(room);
        self.set_paused(paused);
        if paused {
            self.slots[index].track.pause(immediate());
        }
        Ok(())
    }

    pub fn remove(&mut self, id: &str) {
        if let Some(index) = self.active.remove(id) {
            let slot = &mut self.slots[index];
            slot.track.set_volume(Decibels::SILENCE, immediate());
            // Handle destruction cancels/joins directly, independent of output
            // callbacks, pause state, or whether the sound reached the renderer.
            slot.sound.take();
        }
    }

    pub fn contains(&self, id: &str) -> bool {
        self.active.get(id).is_some_and(|index| {
            self.slots[*index]
                .sound
                .as_ref()
                .is_some_and(|sound| !sound.finished())
        })
    }

    pub fn is_empty(&self) -> bool {
        self.active.is_empty()
    }

    pub fn set_params(&mut self, id: &str, params: LayerParams) {
        if let Some(index) = self.active.get(id).copied() {
            if self.slots[index].params == params.normalized() {
                return;
            }
            self.apply_params(index, params, smooth());
        }
    }

    fn apply_params(&mut self, index: usize, params: LayerParams, tween: Tween) {
        let params = params.normalized();
        let target = response(params);
        let slot = &mut self.slots[index];
        slot.params = params;
        slot.track.set_volume(db(target.gain), tween);
        slot.filter.set_cutoff(target.cutoff, tween);
        slot.filter.set_mix(Mix(target.filter_mix as f32), tween);
        slot.stereo.write((params.pan, params.width));
        let _ = slot
            .track
            .set_send(&self.reverb_track, db(target.reverb_send), tween);
        let _ = slot
            .track
            .set_send(&self.echo_track, db(target.echo_send), tween);
    }

    pub fn set_room(&mut self, room: RoomParams) {
        let room = room.normalized();
        if room == self.room {
            return;
        }
        let outdoors = matches!(
            room.preset.as_str(),
            "outside" | "outdoors" | "open-air" | "forest"
        );
        let wet = room.reflections * if outdoors { 0.12 } else { 0.6 };
        // Feedback stays below unity: room changes cannot create infinite tails.
        self.reverb.set_feedback(0.55 + room.size * 0.3, smooth());
        self.reverb
            .set_damping(0.05 + room.softness * 0.8, smooth());
        self.reverb
            .set_stereo_width(0.5 + room.size * 0.5, smooth());
        self.reverb_track.set_volume(
            if self.paused {
                Decibels::SILENCE
            } else {
                db(wet)
            },
            if self.paused { immediate() } else { smooth() },
        );
        self.room = room;
    }

    pub fn set_paused(&mut self, paused: bool) {
        if self.paused == paused {
            return;
        }
        self.paused = paused;
        for slot in &mut self.slots {
            if let Some(sound) = &slot.sound {
                sound.set_paused(paused);
            }
            if paused {
                slot.track.pause(immediate());
            } else {
                slot.track.resume(immediate());
            }
        }
        // Muting the final output also silences shared effect tails while paused.
        self.echo_track.set_volume(
            if paused {
                Decibels::SILENCE
            } else {
                Decibels::IDENTITY
            },
            immediate(),
        );
        let wet = self.room.reflections
            * if matches!(
                self.room.preset.as_str(),
                "outside" | "outdoors" | "open-air" | "forest"
            ) {
                0.12
            } else {
                0.6
            };
        self.reverb_track.set_volume(
            if paused { Decibels::SILENCE } else { db(wet) },
            immediate(),
        );
    }

    /// Combined master/fade/duck gain is supplied by the existing controller.
    pub fn set_master(&mut self, gain: f64) {
        if let Some(manager) = &mut self.manager {
            manager
                .main_track()
                .set_volume(db(unit(gain, 0.0)), immediate());
        }
    }

    /// Silence and cancel all sources while retaining the output briefly for
    /// a controller-owned reuse grace period. No decoder survives this call.
    pub fn clear(&mut self) {
        self.set_master(0.0);
        self.set_paused(true);
        for slot in &mut self.slots {
            slot.sound.take();
        }
        self.active.clear();
    }

    pub fn stop(&mut self) {
        self.clear();
        // Release the device instead of running an idle silent renderer forever.
        self.manager.take();
    }
}

impl<B: Backend> Drop for LocalAudio<B> {
    fn drop(&mut self) {
        for slot in &mut self.slots {
            slot.sound.take();
        }
        self.manager.take();
    }
}

struct StereoFieldBuilder;
struct StereoField {
    reader: CommandReader<(f64, f64)>,
    current: (f64, f64),
    target: (f64, f64),
}

impl EffectBuilder for StereoFieldBuilder {
    type Handle = CommandWriter<(f64, f64)>;
    fn build(self) -> (Box<dyn Effect>, Self::Handle) {
        let (writer, reader) = command_writer_and_reader();
        (
            Box::new(StereoField {
                reader,
                current: (0.0, 1.0),
                target: (0.0, 1.0),
            }),
            writer,
        )
    }
}

fn stereo_frame(frame: Frame, pan: f64, width: f64) -> Frame {
    if pan == 0.0 && width == 1.0 {
        return frame;
    }
    let mid = (frame.left + frame.right) * 0.5;
    let side = (frame.left - frame.right) * 0.5 * width as f32;
    // Centre/full width preserves the original stereo asset exactly. At the
    // edges the field narrows rather than simply discarding one source channel.
    let side = side * (1.0 - pan.abs()) as f32;
    let left = (1.0 - pan).sqrt() as f32;
    let right = (1.0 + pan).sqrt() as f32;
    Frame::new((mid + side) * left, (mid - side) * right)
}

impl Effect for StereoField {
    fn on_start_processing(&mut self) {
        if let Some(target) = self.reader.read() {
            self.target = (finite(target.0, 0.0).clamp(-1.0, 1.0), unit(target.1, 1.0));
        }
    }
    fn process(&mut self, input: &mut [Frame], dt: f64, _info: &Info) {
        let coefficient = 1.0 - (-dt / 0.025).exp();
        for frame in input {
            self.current.0 += (self.target.0 - self.current.0) * coefficient;
            self.current.1 += (self.target.1 - self.current.1) * coefficient;
            *frame = stereo_frame(*frame, self.current.0, self.current.1);
        }
    }
}

struct PeakGuard;
impl EffectBuilder for PeakGuard {
    type Handle = ();
    fn build(self) -> (Box<dyn Effect>, Self::Handle) {
        (Box::new(self), ())
    }
}
impl Effect for PeakGuard {
    fn process(&mut self, input: &mut [Frame], _dt: f64, _info: &Info) {
        for frame in input {
            let peak = frame.left.abs().max(frame.right.abs());
            if !peak.is_finite() {
                *frame = Frame::ZERO;
            } else if peak > 0.98 {
                *frame *= 0.98 / peak;
            }
        }
    }
}

struct LoopData {
    decoder: FileDecoder,
    first: Vec<Frame>,
}

/// Probe and decode a bounded initial packet without opening an output device
/// or starting a worker. This validates stopped-state library imports too.
pub fn validate_file(path: &Path) -> Result<(), String> {
    LoopData::from_file(path).map(|_| ())
}

impl LoopData {
    fn from_file(path: &Path) -> Result<Self, String> {
        if !path.is_file() {
            return Err("Local sound file is missing".into());
        }
        let mut decoder = FileDecoder::open(path)?;
        let first = decoder.decode_chunk()?;
        if first.is_empty() {
            return Err("Local sound file contains no audio".into());
        }
        Ok(Self { decoder, first })
    }
}

struct LoopShared {
    cancelled: AtomicBool,
    failed: AtomicBool,
    completed: AtomicBool,
    paused: AtomicBool,
}
struct LoopHandle {
    shared: Arc<LoopShared>,
    worker: Option<JoinHandle<()>>,
}
impl LoopHandle {
    fn set_paused(&self, paused: bool) {
        self.shared.paused.store(paused, Ordering::Release);
        if let Some(worker) = &self.worker {
            worker.thread().unpark();
        }
    }
    fn finished(&self) -> bool {
        self.shared.cancelled.load(Ordering::Acquire) || self.shared.failed.load(Ordering::Acquire)
    }
}
impl Drop for LoopHandle {
    fn drop(&mut self) {
        self.shared.cancelled.store(true, Ordering::Release);
        if let Some(worker) = self.worker.take() {
            // Never called from the renderer; every handle is owned by LocalAudio.
            worker.thread().unpark();
            let _ = worker.join();
        }
    }
}

struct LoopSound {
    shared: Arc<LoopShared>,
    frames: Consumer<Frame>,
    sample_rate: f64,
    samples: [Frame; 4],
    seeded: bool,
    fraction: f64,
}

impl SoundData for LoopData {
    type Error = String;
    type Handle = LoopHandle;
    fn into_sound(self) -> Result<(Box<dyn Sound>, Self::Handle), String> {
        let (mut producer, consumer) = RingBuffer::new(QUEUE_FRAMES);
        let sample_rate = self.decoder.sample_rate as f64;
        let shared = Arc::new(LoopShared {
            cancelled: AtomicBool::new(false),
            failed: AtomicBool::new(false),
            completed: AtomicBool::new(false),
            paused: AtomicBool::new(false),
        });
        // Seed before creating a sound so a new source starts with ready samples.
        let seeded = self.first.len().min(producer.slots());
        for frame in &self.first[..seeded] {
            producer.push(*frame).expect("new bounded PCM queue");
        }
        let worker_shared = shared.clone();
        let worker = thread::Builder::new()
            .name("skylofi-decode".into())
            .spawn(move || {
                decode_loop(self.decoder, self.first, seeded, producer, &worker_shared);
                worker_shared.completed.store(true, Ordering::Release);
            })
            .map_err(|error| format!("Cannot start local audio decoder: {error}"))?;
        Ok((
            Box::new(LoopSound {
                shared: shared.clone(),
                frames: consumer,
                sample_rate,
                samples: [Frame::ZERO; 4],
                seeded: false,
                fraction: 0.0,
            }),
            LoopHandle {
                shared,
                worker: Some(worker),
            },
        ))
    }
}

fn decode_loop(
    mut decoder: FileDecoder,
    mut chunk: Vec<Frame>,
    mut index: usize,
    mut producer: Producer<Frame>,
    shared: &LoopShared,
) {
    while !shared.cancelled.load(Ordering::Acquire) {
        if shared.paused.load(Ordering::Acquire) {
            thread::park();
            continue;
        }
        if producer.is_full() {
            thread::park_timeout(Duration::from_millis(12));
            continue;
        }
        if index == chunk.len() {
            match decoder.decode_chunk() {
                Ok(next) if !next.is_empty() => {
                    chunk = next;
                    index = 0;
                }
                Ok(_) => {
                    if decoder.rewind().is_err() {
                        shared.failed.store(true, Ordering::Release);
                        break;
                    }
                    // Empty packets at loop start are tolerated but bounded.
                    match decoder.decode_chunk() {
                        Ok(next) if !next.is_empty() => {
                            chunk = next;
                            index = 0;
                        }
                        _ => {
                            shared.failed.store(true, Ordering::Release);
                            break;
                        }
                    }
                }
                Err(_) => {
                    shared.failed.store(true, Ordering::Release);
                    break;
                }
            }
        }
        let count = producer.slots().min(chunk.len() - index);
        for frame in &chunk[index..index + count] {
            // Sole producer, consumer can only add capacity.
            if producer.push(*frame).is_err() {
                return;
            }
        }
        index += count;
    }
}

impl Sound for LoopSound {
    fn process(&mut self, out: &mut [Frame], dt: f64, _info: &Info) {
        if self.finished() {
            out.fill(Frame::ZERO);
            return;
        }
        if !self.seeded {
            if self.frames.slots() < 3 {
                out.fill(Frame::ZERO);
                return;
            }
            self.samples[1] = self.frames.pop().unwrap_or(Frame::ZERO);
            self.samples[2] = self.frames.pop().unwrap_or(Frame::ZERO);
            self.samples[3] = self.frames.pop().unwrap_or(Frame::ZERO);
            self.seeded = true;
        }
        let step = self.sample_rate * dt;
        for frame in out {
            // A temporarily empty queue pauses the source clock instead of
            // stretching stale data or blocking the real-time output thread.
            let advances = (self.fraction + step).floor() as usize;
            if self.frames.slots() < advances {
                *frame = Frame::ZERO;
                continue;
            }
            *frame = kira::interpolate_frame(
                self.samples[0],
                self.samples[1],
                self.samples[2],
                self.samples[3],
                self.fraction as f32,
            );
            self.fraction += step;
            while self.fraction >= 1.0 {
                self.samples[0] = self.samples[1];
                self.samples[1] = self.samples[2];
                self.samples[2] = self.samples[3];
                self.samples[3] = self.frames.pop().unwrap_or(Frame::ZERO);
                self.fraction -= 1.0;
            }
        }
    }
    fn finished(&self) -> bool {
        self.shared.cancelled.load(Ordering::Acquire) || self.shared.failed.load(Ordering::Acquire)
    }
}

struct FileDecoder {
    reader: Box<dyn FormatReader>,
    decoder: Box<dyn AudioDecoder>,
    track_id: u32,
    sample_rate: u32,
}

impl FileDecoder {
    fn open(path: &Path) -> Result<Self, String> {
        let file = File::open(path).map_err(|error| format!("Cannot open local sound: {error}"))?;
        let source = MediaSourceStream::new(Box::new(file), Default::default());
        let reader = symphonia::default::get_probe()
            .probe(
                &Hint::default(),
                source,
                Default::default(),
                Default::default(),
            )
            .map_err(|error| format!("Unsupported local sound: {error}"))?;
        let track = reader
            .default_track(TrackType::Audio)
            .ok_or("Local sound has no audio track")?;
        let params = match &track.codec_params {
            Some(CodecParameters::Audio(params)) => params,
            _ => return Err("Local sound has no supported audio track".into()),
        };
        let sample_rate = params.sample_rate.ok_or("Local sound has no sample rate")?;
        if !(8_000..=192_000).contains(&sample_rate) {
            return Err("Unsupported local sound sample rate".into());
        }
        if params
            .channels
            .as_ref()
            .is_some_and(|channels| !(1..=2).contains(&channels.count()))
        {
            return Err("Local sounds must be mono or stereo".into());
        }
        if params
            .max_frames_per_packet
            .is_some_and(|frames| frames > MAX_PACKET_FRAMES as u64)
        {
            return Err("Local sound audio packet is too large".into());
        }
        let decoder = symphonia::default::get_codecs()
            .make_audio_decoder(params, &Default::default())
            .map_err(|error| format!("Unsupported local sound codec: {error}"))?;
        let track_id = track.id;
        Ok(Self {
            reader,
            decoder,
            track_id,
            sample_rate,
        })
    }

    fn decode_chunk(&mut self) -> Result<Vec<Frame>, String> {
        // Some formats have metadata/empty audio packets. Keep cancellation and
        // corrupt input bounded instead of spinning forever looking for audio.
        for _ in 0..256 {
            let Some(packet) = self
                .reader
                .next_packet()
                .map_err(|error| error.to_string())?
            else {
                return Ok(vec![]);
            };
            if packet.track_id != self.track_id {
                continue;
            }
            let buffer = self
                .decoder
                .decode(&packet)
                .map_err(|error| error.to_string())?;
            let frames = convert_buffer(&buffer)?;
            if !frames.is_empty() {
                return Ok(frames);
            }
        }
        Err("Local sound contains too many empty packets".into())
    }

    fn rewind(&mut self) -> Result<(), String> {
        self.reader
            .seek(
                SeekMode::Accurate,
                SeekTo::Timestamp {
                    ts: Timestamp::new(0),
                    track_id: self.track_id,
                },
            )
            .map_err(|error| format!("Cannot loop local sound: {error}"))?;
        self.decoder.reset();
        Ok(())
    }
}

fn convert_buffer(buffer: &GenericAudioBufferRef<'_>) -> Result<Vec<Frame>, String> {
    match buffer {
        GenericAudioBufferRef::U8(buffer) => convert_samples(buffer),
        GenericAudioBufferRef::U16(buffer) => convert_samples(buffer),
        GenericAudioBufferRef::U24(buffer) => convert_samples(buffer),
        GenericAudioBufferRef::U32(buffer) => convert_samples(buffer),
        GenericAudioBufferRef::S8(buffer) => convert_samples(buffer),
        GenericAudioBufferRef::S16(buffer) => convert_samples(buffer),
        GenericAudioBufferRef::S24(buffer) => convert_samples(buffer),
        GenericAudioBufferRef::S32(buffer) => convert_samples(buffer),
        GenericAudioBufferRef::F32(buffer) => convert_samples(buffer),
        GenericAudioBufferRef::F64(buffer) => convert_samples(buffer),
    }
}

fn convert_samples<S: Sample>(buffer: &AudioBuffer<S>) -> Result<Vec<Frame>, String>
where
    f32: FromSample<S>,
{
    let left = buffer.plane(0).ok_or("Local sound has no channels")?;
    if left.len() > MAX_PACKET_FRAMES {
        return Err("Local sound audio packet is too large".into());
    }
    match buffer.num_planes() {
        1 => Ok(left
            .iter()
            .map(|sample| Frame::from_mono(decoded_sample(f32::from_sample(*sample))))
            .collect()),
        2 => Ok(left
            .iter()
            .zip(buffer.plane(1).ok_or("Missing stereo channel")?)
            .map(|(l, r)| {
                Frame::new(
                    decoded_sample(f32::from_sample(*l)),
                    decoded_sample(f32::from_sample(*r)),
                )
            })
            .collect()),
        _ => Err("Local sounds must be mono or stereo".into()),
    }
}

fn decoded_sample(sample: f32) -> f32 {
    // Float WAV imports can contain nonfinite samples. Remove them before they
    // poison a source filter's persistent state; normal levels remain intact.
    if sample.is_finite() {
        sample
    } else {
        0.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        alloc::{GlobalAlloc, Layout, System},
        cell::Cell,
        io::Write,
        path::PathBuf,
        sync::atomic::AtomicU64,
    };

    thread_local! {
        static AUDITING: Cell<bool> = const { Cell::new(false) };
        static ALLOCATOR_ACTIVITY: Cell<usize> = const { Cell::new(0) };
    }

    struct AuditAllocator;
    #[global_allocator]
    static ALLOCATOR: AuditAllocator = AuditAllocator;

    fn record_allocation() {
        if AUDITING.try_with(Cell::get).unwrap_or(false) {
            let _ = ALLOCATOR_ACTIVITY.try_with(|count| count.set(count.get() + 1));
        }
    }

    // This test allocator delegates every operation to the standard allocator;
    // it only counts operations on the thread explicitly auditing a callback.
    unsafe impl GlobalAlloc for AuditAllocator {
        unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
            record_allocation();
            // SAFETY: unchanged layout is forwarded to the system allocator.
            unsafe { System.alloc(layout) }
        }
        unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
            record_allocation();
            // SAFETY: the allocation and layout are forwarded unchanged.
            unsafe { System.dealloc(ptr, layout) }
        }
        unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, size: usize) -> *mut u8 {
            record_allocation();
            // SAFETY: the original allocation and requested size are unchanged.
            unsafe { System.realloc(ptr, layout, size) }
        }
    }

    struct Audit;
    impl Audit {
        fn start() -> Self {
            ALLOCATOR_ACTIVITY.with(|count| count.set(0));
            AUDITING.with(|enabled| enabled.set(true));
            Self
        }
        fn finish(self) -> usize {
            AUDITING.with(|enabled| enabled.set(false));
            ALLOCATOR_ACTIVITY.with(Cell::get)
        }
    }
    impl Drop for Audit {
        fn drop(&mut self) {
            AUDITING.with(|enabled| enabled.set(false));
        }
    }

    struct RenderBackend {
        renderer: Option<Renderer>,
    }
    impl Backend for RenderBackend {
        type Settings = ();
        type Error = ();
        fn setup(_: (), _: usize) -> Result<(Self, u32), ()> {
            Ok((Self { renderer: None }, 48_000))
        }
        fn start(&mut self, renderer: Renderer) -> Result<(), ()> {
            self.renderer = Some(renderer);
            Ok(())
        }
    }
    impl RenderBackend {
        fn render(&mut self, out: &mut [f32]) {
            let renderer = self.renderer.as_mut().unwrap();
            renderer.on_start_processing();
            renderer.process(out, 2);
        }
    }

    static NEXT_FILE: AtomicU64 = AtomicU64::new(0);
    struct TestFile(PathBuf);
    impl TestFile {
        fn wave(frequency: f64, seconds: f64) -> Self {
            let path = std::env::temp_dir().join(format!(
                "skylofi-audio-{}-{}.wav",
                std::process::id(),
                NEXT_FILE.fetch_add(1, Ordering::Relaxed)
            ));
            let frames = (48_000.0 * seconds) as u32;
            let length = frames * 4;
            let mut file = File::create(&path).unwrap();
            file.write_all(b"RIFF").unwrap();
            file.write_all(&(36 + length).to_le_bytes()).unwrap();
            file.write_all(b"WAVEfmt ").unwrap();
            file.write_all(&16_u32.to_le_bytes()).unwrap();
            file.write_all(&1_u16.to_le_bytes()).unwrap();
            file.write_all(&2_u16.to_le_bytes()).unwrap();
            file.write_all(&48_000_u32.to_le_bytes()).unwrap();
            file.write_all(&192_000_u32.to_le_bytes()).unwrap();
            file.write_all(&4_u16.to_le_bytes()).unwrap();
            file.write_all(&16_u16.to_le_bytes()).unwrap();
            file.write_all(b"data").unwrap();
            file.write_all(&length.to_le_bytes()).unwrap();
            for index in 0..frames {
                let value = ((index as f64 * frequency * std::f64::consts::TAU / 48_000.0).sin()
                    * 10_000.0) as i16;
                file.write_all(&value.to_le_bytes()).unwrap();
                file.write_all(&value.to_le_bytes()).unwrap();
            }
            Self(path)
        }
    }
    impl Drop for TestFile {
        fn drop(&mut self) {
            let _ = std::fs::remove_file(&self.0);
        }
    }

    fn mixer() -> LocalAudio<RenderBackend> {
        LocalAudio::with_settings(AudioManagerSettings::default()).unwrap()
    }
    fn render(mixer: &mut LocalAudio<RenderBackend>, out: &mut [f32]) {
        mixer.manager.as_mut().unwrap().backend_mut().render(out);
    }

    #[test]
    fn distance_and_outside_reduce_direct_sound_without_nan() {
        assert_eq!(decoded_sample(f32::NAN), 0.0);
        assert_eq!(decoded_sample(f32::INFINITY), 0.0);
        assert_eq!(decoded_sample(f32::NEG_INFINITY), 0.0);
        assert_eq!(decoded_sample(0.75), 0.75);
        let near = response(LayerParams {
            volume: 1.0,
            ..LayerParams::default()
        });
        let far = response(LayerParams {
            volume: 1.0,
            distance: 1.0,
            ..LayerParams::default()
        });
        let outside = response(LayerParams {
            volume: 1.0,
            outside: true,
            ..LayerParams::default()
        });
        assert!(far.gain < near.gain && far.cutoff < near.cutoff);
        assert!(outside.gain < near.gain && outside.cutoff < near.cutoff);
        let invalid = LayerParams {
            volume: f64::INFINITY,
            pan: f64::NAN,
            distance: -5.0,
            reflections: 99.0,
            softness: f64::NAN,
            width: f64::NEG_INFINITY,
            echo: 50.0,
            outside: true,
        }
        .normalized();
        assert_eq!(invalid.pan, 0.0);
        assert_eq!(invalid.reflections, 1.0);
        assert!(response(invalid).gain.is_finite());
        assert!(db(0.0).as_amplitude() < 0.0001);
    }

    #[test]
    fn stereo_width_preserves_diffuse_asset_and_position_keeps_both_channels() {
        let input = Frame::new(0.8, 0.2);
        assert_eq!(stereo_frame(input, 0.0, 1.0), input);
        assert_eq!(stereo_frame(input, 0.0, 0.0), Frame::from_mono(0.5));
        let left = stereo_frame(input, -1.0, 1.0);
        assert_eq!(left.right, 0.0);
        assert!((left.left - 0.5 * 2.0_f32.sqrt()).abs() < 0.0001);
    }

    #[test]
    fn renders_looped_audio_position_pause_and_no_callback_allocations() {
        let file = TestFile::wave(500.0, 0.02);
        let mut mixer = mixer();
        let params = LayerParams {
            volume: 1.0,
            pan: -1.0,
            width: 0.0,
            ..LayerParams::default()
        };
        mixer
            .play("tone", &file.0, params, RoomParams::default(), false)
            .unwrap();
        thread::sleep(Duration::from_millis(20));
        let mut out = [0.0_f32; 256];
        let mut left = 0.0_f64;
        let mut right = 0.0_f64;
        // Multiple complete source loops, through the actual Kira mixer.
        let audit = Audit::start();
        for _ in 0..100 {
            render(&mut mixer, &mut out);
            for frame in out.as_chunks::<2>().0 {
                left += f64::from(frame[0]).powi(2);
                right += f64::from(frame[1]).powi(2);
            }
        }
        let allocations = audit.finish();
        assert_eq!(allocations, 0, "renderer allocated or freed memory");
        assert!(
            left > 50.0 && right < left * 0.12,
            "panning or streaming did not render ({left}, {right})"
        );
        assert!(mixer.contains("tone"));
        mixer.set_paused(true);
        mixer.set_room(RoomParams {
            reflections: 1.0,
            size: 1.0,
            ..RoomParams::default()
        });
        render(&mut mixer, &mut out);
        assert!(out.iter().all(|sample| *sample == 0.0));
        mixer.set_paused(false);
        render(&mut mixer, &mut out);
        assert!(out.iter().any(|sample| *sample != 0.0));
        let shared = mixer.slots[mixer.active["tone"]]
            .sound
            .as_ref()
            .unwrap()
            .shared
            .clone();
        mixer.remove("tone");
        assert!(
            shared.completed.load(Ordering::Acquire),
            "decoder not joined after removal"
        );
        assert!(mixer.is_empty());
        mixer.stop();
        assert!(mixer.manager.is_none());
    }

    #[test]
    fn invalid_replacement_retains_sound_and_stop_joins_paused_workers() {
        let file = TestFile::wave(400.0, 0.1);
        let mut mixer = mixer();
        mixer
            .play(
                "tone",
                &file.0,
                LayerParams::default(),
                RoomParams::default(),
                true,
            )
            .unwrap();
        assert!(mixer
            .play(
                "tone",
                Path::new("/missing/skylofi.wav"),
                LayerParams::default(),
                RoomParams::default(),
                false
            )
            .is_err());
        assert!(mixer.contains("tone"));
        let shared = mixer.slots[mixer.active["tone"]]
            .sound
            .as_ref()
            .unwrap()
            .shared
            .clone();
        // No renderer callbacks are needed for cancellation, even while paused.
        mixer.stop();
        assert!(shared.completed.load(Ordering::Acquire));
        assert!(mixer.is_empty());
    }

    #[test]
    fn clear_joins_decoders_and_reuses_the_existing_output() {
        let file = TestFile::wave(400.0, 0.1);
        let mut mixer = mixer();
        let mut out = [0.0_f32; 256];
        for _ in 0..10 {
            mixer.set_master(1.0);
            mixer
                .play(
                    "tone",
                    &file.0,
                    LayerParams::default(),
                    RoomParams::default(),
                    false,
                )
                .unwrap();
            render(&mut mixer, &mut out);
            assert!(out.iter().any(|sample| *sample != 0.0));
            let shared = mixer.slots[mixer.active["tone"]]
                .sound
                .as_ref()
                .unwrap()
                .shared
                .clone();
            mixer.clear();
            assert!(shared.completed.load(Ordering::Acquire));
            assert!(mixer.is_empty());
            assert!(mixer.manager.is_some());
            assert_eq!(
                mixer.manager.as_ref().unwrap().num_sub_tracks(),
                MAX_LOCAL_LAYERS
            );
            let audit = Audit::start();
            render(&mut mixer, &mut out);
            assert_eq!(
                audit.finish(),
                0,
                "source retirement allocated or freed in renderer"
            );
            assert!(out.iter().all(|sample| *sample == 0.0));
        }
        mixer.stop();
        assert!(mixer.manager.is_none());
    }

    #[test]
    fn active_sources_and_effect_buses_remain_bounded() {
        let file = TestFile::wave(200.0, 0.05);
        let mut mixer = mixer();
        for index in 0..MAX_LOCAL_LAYERS {
            mixer
                .play(
                    &format!("sound-{index}"),
                    &file.0,
                    LayerParams::default(),
                    RoomParams::default(),
                    false,
                )
                .unwrap();
        }
        assert!(mixer
            .play(
                "too-many",
                &file.0,
                LayerParams::default(),
                RoomParams::default(),
                false
            )
            .is_err());
        let manager = mixer.manager.as_ref().unwrap();
        assert_eq!(manager.num_sub_tracks(), MAX_LOCAL_LAYERS);
        assert_eq!(manager.num_send_tracks(), 2);
        let shared: Vec<_> = mixer
            .slots
            .iter()
            .filter_map(|slot| slot.sound.as_ref().map(|sound| sound.shared.clone()))
            .collect();
        mixer.stop();
        assert!(shared
            .iter()
            .all(|sound| sound.completed.load(Ordering::Acquire)));
    }

    #[test]
    fn repeated_room_edits_render_sends_without_allocation() {
        let file = TestFile::wave(700.0, 0.05);
        let mut mixer = mixer();
        mixer
            .play(
                "tone",
                &file.0,
                LayerParams {
                    reflections: 1.0,
                    echo: 1.0,
                    ..LayerParams::default()
                },
                RoomParams::default(),
                false,
            )
            .unwrap();
        let mut out = [0.0; 256];
        for index in 0..30 {
            mixer.set_room(RoomParams {
                preset: "cafe".into(),
                size: index as f64 / 30.0,
                softness: 0.5,
                reflections: 0.6,
            });
            mixer.set_params(
                "tone",
                LayerParams {
                    distance: index as f64 / 30.0,
                    reflections: 1.0,
                    echo: 1.0,
                    ..LayerParams::default()
                },
            );
            let audit = Audit::start();
            render(&mut mixer, &mut out);
            let allocations = audit.finish();
            assert_eq!(allocations, 0);
            assert!(out
                .iter()
                .all(|sample| sample.is_finite() && sample.abs() <= 1.0));
        }
    }

    #[test]
    fn bundled_vorbis_assets_probe_decode_and_rewind() {
        let source = Path::new(env!("CARGO_MANIFEST_DIR")).join(file!());
        let root = source.parent().unwrap().parent().unwrap().parent().unwrap();
        for name in [
            "rain",
            "wind",
            "storm",
            "fireplace",
            "waves",
            "tent-rain",
            "stream",
            "birds",
            "night",
        ] {
            let path = root.join("assets").join(format!("{name}.ogg"));
            validate_file(&path).unwrap_or_else(|error| panic!("{name}: {error}"));
            let mut decoder = FileDecoder::open(&path).unwrap();
            let first = decoder.decode_chunk().unwrap();
            assert!(!first.is_empty());
            decoder
                .rewind()
                .unwrap_or_else(|error| panic!("{name}: {error}"));
            let repeated = decoder.decode_chunk().unwrap();
            assert_eq!(first, repeated, "{name}: loop start changed after rewind");
        }
    }

    #[test]
    fn validation_rejects_corrupt_audio_without_starting_workers() {
        let file = TestFile::wave(200.0, 0.1);
        std::fs::write(&file.0, b"not an audio file").unwrap();
        assert!(validate_file(&file.0).is_err());
    }
}
