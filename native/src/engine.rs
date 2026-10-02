use crate::{
    config::{self, enabled, number, preferences, Catalog, Paths, Station},
    process::{self, Process},
    transport::{self, Mpv},
    Event,
};
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    fs::{self, OpenOptions},
    io::{BufReader, Write},
    os::unix::fs::OpenOptionsExt,
    process::{Child, Command, Stdio},
    sync::mpsc::SyncSender,
    thread,
    time::{Duration, Instant},
};
const RETRY: [u64; 5] = [2, 5, 10, 20, 30];
fn ease(p: f64) -> f64 {
    p * p * (3.0 - 2.0 * p)
}
fn playback_ready(channel: &str, property: &str, value: &Value) -> bool {
    if channel.starts_with("nature-") {
        property == "audio-params" && value.is_object()
    } else {
        property == "time-pos" && value.is_number()
    }
}
struct Fade {
    from: f64,
    to: f64,
    started: Instant,
    duration: Duration,
    await_ready: bool,
}
struct Channel {
    generation: u64,
    child: Child,
    process: Process,
    ipc: Option<Mpv>,
    properties: HashMap<String, Value>,
    gain: f64,
    fade: Option<Fade>,
    applied: f64,
    youtube: bool,
    source: Station,
}
pub struct Engine {
    pub paths: Paths,
    pub settings: Value,
    pub catalog: Catalog,
    pub mode: String,
    pub station: String,
    channels: HashMap<String, Channel>,
    generation: u64,
    events: SyncSender<Event>,
    pending: Option<(String, Instant)>,
    retry_due: Option<Instant>,
    attempts: usize,
    started: Instant,
    progress: Instant,
    stable: Option<Instant>,
    ended: bool,
    feed_token: u64,
    feed_loading: bool,
    feed_process: Option<Process>,
    error: String,
    bg_error: String,
    recording: bool,
    duck_gain: f64,
    duck_from: f64,
    duck_target: f64,
    duck_started: Instant,
    next_maintenance: Instant,
    next_bookmark: Instant,
    pub revision: u64,
    youtube_available: bool,
    cancellation_failed: bool,
}
impl Engine {
    pub fn new(paths: Paths, events: SyncSender<Event>) -> Result<Self, String> {
        process::reap_orphans(&paths.runtime)
            .map_err(|e| format!("Cannot safely recover previous audio: {e}"))?;
        let settings_path = paths.state.join("settings.json");
        let initial = if settings_path.is_file() {
            config::read_json(&settings_path)
        } else {
            config::read_json(&paths.root.join("settings.json"))
        };
        let mut settings = preferences(initial);
        let catalog = Catalog::load(&paths.root, &settings);
        if !catalog
            .music
            .contains(&settings["defaultStation"].as_str().unwrap_or("").to_owned())
        {
            settings["defaultStation"] =
                json!(catalog.music.first().map(String::as_str).unwrap_or(""));
        }
        let prior = config::read_json(&paths.runtime.join("session.json"));
        let station = prior["station"]
            .as_str()
            .filter(|id| catalog.music.iter().any(|m| m == id))
            .unwrap_or(settings["defaultStation"].as_str().unwrap_or(""))
            .to_owned();
        let now = Instant::now();
        let mut engine = Self {
            paths,
            settings,
            catalog,
            mode: "stopped".into(),
            station,
            channels: HashMap::new(),
            generation: 0,
            events,
            pending: None,
            retry_due: None,
            attempts: 0,
            started: now,
            progress: now,
            stable: None,
            ended: false,
            feed_token: 0,
            feed_loading: false,
            feed_process: None,
            error: String::new(),
            bg_error: String::new(),
            recording: false,
            duck_gain: 1.0,
            duck_from: 1.0,
            duck_target: 1.0,
            duck_started: now,
            next_maintenance: now,
            next_bookmark: now,
            revision: 0,
            youtube_available: config::which("yt-dlp").is_some(),
            cancellation_failed: false,
        };
        engine.refresh_recording();
        if let Err(error) = engine.persist() {
            engine.error = error;
        }
        // A daemon restart never leaves detached audio. Playback intent survives
        // crash recovery; a normal shutdown persists a stopped session.
        if prior["mode"] == "playing" {
            let _ = engine.begin(None);
        } else if prior["mode"] == "paused" {
            engine.mode = "paused".into();
        }
        if let Err(error) = engine.persist() {
            engine.error = error;
        }
        Ok(engine)
    }
    fn changed(&mut self) {
        self.revision = self.revision.wrapping_add(1);
    }
    fn persist(&self) -> Result<(), String> {
        config::write_json(&self.paths.state.join("settings.json"), &self.settings)
            .map_err(|e| format!("Cannot save settings: {e}"))?;
        config::write_json(
            &self.paths.runtime.join("session.json"),
            &json!({"mode":self.mode,"station":self.station,"attempts":self.attempts,"pending":null}),
        ).map_err(|e|format!("Cannot save session: {e}"))
    }
    fn youtube(&self) -> bool {
        self.catalog
            .entries
            .get(&self.station)
            .is_some_and(|s| s.kind == "youtube" || s.category == "youtube")
    }
    fn fades_enabled(&self) -> bool {
        enabled(&self.settings, "fadeEnabled") && number(&self.settings, "fadeSeconds") > 0.0
    }
    fn fade_duration(&self, out: bool) -> Duration {
        if self.fades_enabled() {
            Duration::from_secs_f64(
                number(&self.settings, "fadeSeconds") * (if out { 0.6 } else { 1.0 }),
            )
        } else {
            Duration::ZERO
        }
    }
    fn alive(&self, channel: &str) -> bool {
        self.channels
            .get(channel)
            .is_some_and(|c| c.process.alive())
    }
    fn prop(&self, channel: &str, key: &str) -> Value {
        self.channels
            .get(channel)
            .and_then(|c| c.properties.get(key))
            .cloned()
            .unwrap_or(Value::Null)
    }
    fn ipc(&self, channel: &str, command: Value) {
        if let Some(ipc) = self.channels.get(channel).and_then(|c| c.ipc.as_ref()) {
            let _ = ipc.command(command);
        }
    }
    fn base(&self, channel: &str) -> f64 {
        if channel == "main" {
            number(&self.settings, "mainVolume")
        } else if channel == "bg" {
            number(&self.settings, "bgVolume")
        } else {
            config::level(
                &self.settings["natureLayers"][channel.strip_prefix("nature-").unwrap_or("")]
                    ["volume"],
                25.0,
            )
        }
    }
    fn volume(&self, channel: &str) -> f64 {
        self.base(channel) * number(&self.settings, "masterVolume") / 100.0 * self.duck_gain
    }
    fn stop_channel(&mut self, channel: &str) -> bool {
        if let Some(mut process) = self.channels.remove(channel) {
            if process.youtube {
                if let Err(error) = process.process.terminate_tree() {
                    // Ownership/PID/socket stay intact on refused cancellation.
                    // The active mix is silent and paused, never abandoned.
                    if let Some(ipc) = &process.ipc {
                        let _ = ipc.command(json!(["set_property", "volume", 0]));
                        let _ = ipc.command(json!(["set_property", "pause", true]));
                    }
                    self.station = process.source.id.clone();
                    self.catalog
                        .entries
                        .insert(process.source.id.clone(), process.source.clone());
                    process.gain = 0.0;
                    process.fade = None;
                    self.channels.insert(channel.into(), process);
                    self.mode = "paused".into();
                    self.pending = None;
                    self.cancellation_failed = true;
                    self.error = format!(
                        "Cannot safely cancel extractor; playback retained paused: {error}"
                    );
                    self.changed();
                    return false;
                }
            } else {
                process.process.terminate();
            }
            let _ = process.child.wait();
        }
        let _ = fs::remove_file(self.paths.runtime.join(format!("{channel}.pid")));
        let _ = fs::remove_file(
            self.paths
                .runtime
                .join("sockets")
                .join(format!("{channel}.sock")),
        );
        true
    }
    fn spawn(&mut self, channel: &str, station: &Station, loop_file: bool) -> Result<(), String> {
        let youtube = station.kind == "youtube" || station.category == "youtube";
        if youtube && config::which("yt-dlp").is_none() {
            return Err("YouTube playback needs yt-dlp. Install or update it, then retry.".into());
        }
        if !self.stop_channel(channel) {
            return Err(self.error.clone());
        }
        let socket = self
            .paths
            .runtime
            .join("sockets")
            .join(format!("{channel}.sock"));
        let log_path = self
            .paths
            .runtime
            .join("logs")
            .join(format!("{channel}.log"));
        if log_path.is_file() {
            let _ = fs::rename(&log_path, log_path.with_extension("log.previous"));
        }
        let log = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .custom_flags(libc::O_NOFOLLOW)
            .open(&log_path)
            .map_err(|e| e.to_string())?;
        let gain = if self.mode == "playing" && self.fades_enabled() {
            0.0
        } else {
            1.0
        };
        let mut command = Command::new("mpv");
        command
            .args([
                "--no-config",
                "--no-video",
                "--terminal=yes",
                "--input-terminal=no",
                "--load-scripts=no",
                "--audio-display=no",
                "--msg-level=all=warn,cplayer=info",
                "--msg-color=no",
                "--term-status-msg=",
                "--network-timeout=12",
                "--user-agent=sky.lofi/3.0 (mpv)",
            ])
            .arg(format!("--volume={}", self.volume(channel) * gain))
            .arg(format!("--input-ipc-server={}", socket.display()));
        if youtube {
            command.args(["--ytdl=yes","--ytdl-format=bestaudio","--keep-open=yes","--sid=no","--ytdl-raw-options=ignore-config=,no-plugin-dirs=,no-remote-components=,no-playlist=,socket-timeout=10,retries=1,extractor-retries=1"]);
            command.arg(format!(
                "--script-opts=ytdl_hook-ytdl_path={},ytdl_hook-force_all_formats=no",
                std::env::current_exe()
                    .map_err(|e| e.to_string())?
                    .display()
            ));
            command.env("SKYLOFI_EXTRACTOR_PROXY", "1").env(
                "SKYLOFI_EXTRACTOR_GENERATION",
                (self.generation + 1).to_string(),
            );
            if station.position > 0.0 {
                command.arg(format!("--start={}", station.position));
            }
        } else {
            command.arg("--ytdl=no");
        }
        if loop_file {
            command.arg("--loop-file=inf");
        }
        if self.mode == "paused" {
            command.arg("--pause");
        }
        let url = if loop_file {
            self.paths
                .root
                .join(&station.url)
                .to_string_lossy()
                .into_owned()
        } else {
            station.url.clone()
        };
        command.arg("--").arg(if youtube {
            config::canonical_url(&url)?
        } else {
            url
        });
        let mut child = command
            .stdin(Stdio::null())
            .stdout(log.try_clone().map_err(|e| e.to_string())?)
            .stderr(log)
            .spawn()
            .map_err(|e| format!("Cannot launch mpv: {e}"))?;
        let process = match Process::pin(child.id()) {
            Ok(p) => p,
            Err(e) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(e.to_string());
            }
        };
        let pid = child.id();
        self.generation += 1;
        let generation = self.generation;
        let fade = if gain == 0.0 {
            Some(Fade {
                from: 0.0,
                to: 1.0,
                started: Instant::now(),
                duration: self.fade_duration(false),
                await_ready: true,
            })
        } else {
            None
        };
        self.channels.insert(
            channel.into(),
            Channel {
                generation,
                child,
                process,
                ipc: None,
                properties: HashMap::new(),
                gain,
                fade,
                applied: f64::NAN,
                youtube,
                source: station.clone(),
            },
        );
        if let Err(error) = config::write_bytes(
            &self.paths.runtime.join(format!("{channel}.pid")),
            format!("{pid}\n").as_bytes(),
        ) {
            self.stop_channel(channel);
            return Err(format!("Cannot record playback process: {error}"));
        }
        transport::connect_mpv(socket, channel.into(), generation, self.events.clone());
        self.changed();
        Ok(())
    }
    fn start_main(&mut self, reset: bool) -> Result<(), String> {
        let Some(station) = self.catalog.entries.get(&self.station).cloned() else {
            return Err("No music sources available".into());
        };
        self.spawn("main", &station, false)?;
        self.started = Instant::now();
        self.progress = self.started;
        self.stable = None;
        self.retry_due = None;
        self.ended = false;
        self.error.clear();
        if reset {
            self.attempts = 0;
        }
        Ok(())
    }
    fn start_bg(&mut self) -> Result<(), String> {
        self.bg_error.clear();
        if self.youtube() || !enabled(&self.settings, "mix") {
            return Ok(());
        }
        let Some(station) = self
            .catalog
            .entries
            .get(self.settings["bgStation"].as_str().unwrap_or(""))
            .cloned()
        else {
            return Ok(());
        };
        if ["lofi", "youtube", "ambience"].contains(&station.category.as_str()) {
            return Ok(());
        }
        if station.kind == "podcast" {
            self.feed_token += 1;
            self.feed_loading = true;
            let token = self.feed_token;
            let destination = self.paths.runtime.join(format!("feed-{}.m3u", station.id));
            self.cancel_feed();
            let mut child = Command::new(std::env::current_exe().map_err(|e| e.to_string())?)
                .arg("--root")
                .arg(&self.paths.root)
                .arg("--fetch-feed")
                .arg(&station.url)
                .arg(&destination)
                .stdin(Stdio::null())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()
                .map_err(|e| e.to_string())?;
            let process = match Process::pin(child.id()) {
                Ok(process) => process,
                Err(error) => {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err(error.to_string());
                }
            };
            self.feed_process = Some(process);
            let _ = config::write_bytes(
                &self.paths.runtime.join("feed.pid"),
                format!("{}\n", child.id()).as_bytes(),
            );
            let events = self.events.clone();
            // Network work is a short-lived Rust helper: cancellation pins its
            // identity and terminates DNS/TLS/HTTP immediately, including stalls.
            // At most one feed helper exists; it cannot spawn late audio.
            thread::spawn(move || {
                let mut reader = BufReader::new(child.stdout.take().unwrap());
                let frame = transport::read_line(&mut reader, transport::CLIENT_FRAME)
                    .ok()
                    .flatten();
                let reply = frame
                    .and_then(|line| serde_json::from_slice::<Value>(&line).ok())
                    .unwrap_or(Value::Null);
                let _ = child.wait();
                let result = if reply["ok"] == true {
                    Ok(destination)
                } else {
                    Err(reply["error"]
                        .as_str()
                        .unwrap_or("Podcast request cancelled or unavailable")
                        .to_owned())
                };
                let _ = events.send(Event::Feed(token, result));
            });
            self.changed();
            Ok(())
        } else {
            let result = self.spawn("bg", &station, false);
            if let Err(error) = &result {
                self.bg_error = error.clone();
            }
            result
        }
    }
    fn cancel_feed(&mut self) {
        if let Some(process) = self.feed_process.take() {
            process.terminate();
        }
        let _ = fs::remove_file(self.paths.runtime.join("feed.pid"));
    }
    fn start_nature(&mut self, id: &str) -> Result<(), String> {
        if self.settings["natureLayers"][id]["enabled"] != true {
            return Ok(());
        }
        if let Some(station) = self.catalog.entries.get(id).cloned() {
            self.spawn(&format!("nature-{id}"), &station, true)
        } else {
            Ok(())
        }
    }
    fn fade_channel(&mut self, key: &str, to: f64, out: bool) {
        let duration = self.fade_duration(out);
        if let Some(channel) = self.channels.get_mut(key) {
            channel.fade = Some(Fade {
                from: channel.gain,
                to,
                started: Instant::now(),
                duration,
                await_ready: false,
            });
        }
    }
    fn begin(&mut self, station: Option<&str>) -> Result<(), String> {
        self.bookmark();
        if let Some(id) = station {
            if !self.catalog.music.iter().any(|s| s == id) {
                return Err(format!("Unknown music station: {id}"));
            }
        }
        let previous = self.mode.clone();
        let previous_station = self.station.clone();
        let previous_default = self.settings["defaultStation"].clone();
        if let Some(id) = station {
            self.station = id.into();
            self.settings["defaultStation"] = json!(id);
        }
        self.mode = "playing".into();
        self.pending = None;
        self.progress = Instant::now();
        if station.is_some() || previous == "stopped" || self.ended || !self.alive("main") {
            if let Err(e) = self.start_main(true) {
                if self.cancellation_failed {
                    self.station = previous_station;
                    self.settings["defaultStation"] = previous_default;
                }
                self.error = e.clone();
                self.attempts = RETRY.len();
                self.changed();
                let _ = self.persist();
                return Err(e);
            }
        } else {
            self.fade_channel("main", 1.0, false);
        }
        if self.youtube() {
            self.feed_token += 1;
            self.feed_loading = false;
            self.cancel_feed();
            self.stop_channel("bg");
        } else if !self.alive("bg") && !self.feed_loading {
            self.start_bg()?;
        } else {
            self.fade_channel("bg", 1.0, false);
        }
        for id in self.catalog.nature.clone() {
            let channel = format!("nature-{id}");
            if !self.alive(&channel) {
                self.start_nature(&id)?;
            } else if self.settings["natureLayers"][&id]["enabled"] == true {
                self.fade_channel(&channel, 1.0, false);
            }
        }
        for key in self.channels.keys() {
            self.ipc(key, json!(["set_property", "pause", false]));
        }
        let _ = fs::remove_file(self.paths.runtime.join("paused.flag"));
        self.next_maintenance = Instant::now();
        self.next_bookmark = Instant::now() + Duration::from_secs(10);
        self.changed();
        Ok(())
    }
    fn transport(&mut self, action: &str, immediate: bool) {
        self.bookmark();
        if action == "pause" && self.mode == "stopped" {
            return;
        }
        self.mode = if action == "pause" {
            "paused"
        } else {
            "stopped"
        }
        .into();
        self.retry_due = None;
        if action == "stop" {
            self.feed_token += 1;
            self.feed_loading = false;
            self.cancel_feed();
            self.attempts = 0;
        }
        let duration = if immediate {
            Duration::ZERO
        } else {
            self.fade_duration(true)
        };
        if duration.is_zero() {
            self.pending = None;
            self.commit_transport(action);
        } else {
            for key in self.channels.keys().cloned().collect::<Vec<_>>() {
                self.fade_channel(&key, 0.0, true);
            }
            self.pending = Some((action.into(), Instant::now() + duration));
        }
        self.changed();
    }
    fn commit_transport(&mut self, action: &str) {
        if action == "pause" {
            for key in self.channels.keys() {
                self.ipc(key, json!(["set_property", "pause", true]));
            }
            let _ = config::write_bytes(&self.paths.runtime.join("paused.flag"), b"");
        } else {
            for key in self.channels.keys().cloned().collect::<Vec<_>>() {
                self.stop_channel(&key);
            }
            let _ = fs::remove_file(self.paths.runtime.join("paused.flag"));
            for id in self.catalog.entries.keys() {
                let _ = fs::remove_file(self.paths.runtime.join(format!("feed-{id}.m3u")));
            }
        }
    }
    pub fn shutdown(&mut self) -> Result<(), String> {
        self.cancellation_failed = false;
        self.transport("stop", true);
        self.persist()?;
        if self.cancellation_failed {
            Err(self.error.clone())
        } else {
            Ok(())
        }
    }
    pub fn handle_command(&mut self, args: &[String]) -> Result<(), String> {
        let command = args.first().map(String::as_str).unwrap_or("status");
        self.cancellation_failed = false;
        let arg = |index: usize| {
            args.get(index)
                .map(String::as_str)
                .ok_or_else(|| format!("Missing argument for {command}"))
        };
        match command {
            "__source_kind" => {
                let generation = arg(1)?
                    .parse::<u64>()
                    .map_err(|_| "Invalid source generation")?;
                let kind = arg(2)?;
                if !["recording", "live", "unknown"].contains(&kind) {
                    return Err("Invalid source kind".into());
                }
                if let Some(channel) = self
                    .channels
                    .get_mut("main")
                    .filter(|channel| channel.generation == generation && channel.youtube)
                {
                    channel.properties.insert("source-kind".into(), json!(kind));
                    self.changed();
                }
                return Ok(());
            }
            "status" => return Ok(()),
            "start" | "station" => self.begin(Some(arg(1)?))?,
            "play" | "resume" => self.begin(args.get(1).map(String::as_str))?,
            "toggle" => {
                if self.mode == "playing" && !self.ended {
                    self.transport("pause", false);
                } else {
                    self.begin(None)?;
                }
            }
            "pause" => self.transport("pause", false),
            "stop" => self.transport("stop", false),
            "next" | "skip" | "prev" | "previous" => {
                let count = self.catalog.music.len();
                if count == 0 {
                    return Err("No sources available".into());
                }
                let current = self
                    .catalog
                    .music
                    .iter()
                    .position(|s| s == &self.station)
                    .unwrap_or(0);
                let next = if command == "next" || command == "skip" {
                    (current + 1) % count
                } else {
                    (current + count - 1) % count
                };
                self.begin(Some(&self.catalog.music[next].clone()))?;
            }
            "vol" | "volume" => {
                let channel = arg(1)?;
                let volume = arg(2)?.parse::<u32>().map_err(|_| "Volume must be 0–100")?;
                if volume > 100 {
                    return Err("Volume must be 0–100".into());
                }
                match channel {
                    "main" => self.settings["mainVolume"] = json!(volume),
                    "bg" => self.settings["bgVolume"] = json!(volume),
                    "master" => self.settings["masterVolume"] = json!(volume),
                    "nature" | "noise" => {
                        for layer in self.settings["natureLayers"]
                            .as_object_mut()
                            .unwrap()
                            .values_mut()
                        {
                            if layer["enabled"] == true {
                                layer["volume"] = json!(volume);
                            }
                        }
                    }
                    id if self.catalog.nature.iter().any(|s| s == id) => {
                        self.ensure_layer(id);
                        self.settings["natureLayers"][id]["volume"] = json!(volume);
                    }
                    _ => return Err("Unknown volume channel".into()),
                }
            }
            "bg" | "background" => {
                let id = arg(1)?;
                if id != "off"
                    && !self.catalog.entries.get(id).is_some_and(|s| {
                        !["lofi", "youtube", "ambience"].contains(&s.category.as_str())
                    })
                {
                    return Err("Unknown voice station".into());
                }
                self.bg_error.clear();
                self.settings["bgStation"] = json!(if id == "off" { "" } else { id });
                self.settings["mix"] = json!(id != "off");
                self.feed_token += 1;
                self.feed_loading = false;
                self.cancel_feed();
                self.stop_channel("bg");
                if self.mode != "stopped" {
                    self.start_bg()?;
                }
            }
            "mix" => {
                let choice = args.get(1).map(String::as_str).unwrap_or("toggle");
                let value = match choice {
                    "toggle" => !enabled(&self.settings, "mix"),
                    "on" | "true" => true,
                    "off" | "false" => false,
                    _ => return Err("mix takes on/off/toggle".into()),
                };
                self.settings["mix"] = json!(value);
                self.feed_token += 1;
                self.feed_loading = false;
                self.cancel_feed();
                if value && self.mode != "stopped" {
                    self.start_bg()?;
                } else {
                    self.stop_channel("bg");
                }
            }
            "nature" => {
                let id = arg(1)?;
                if !self.catalog.nature.iter().any(|s| s == id) {
                    return Err("Unknown nature sound".into());
                }
                self.ensure_layer(id);
                let value = match arg(2)? {
                    "on" => true,
                    "off" => false,
                    "toggle" => self.settings["natureLayers"][id]["enabled"] != true,
                    _ => return Err("nature takes on/off/toggle".into()),
                };
                self.settings["natureLayers"][id]["enabled"] = json!(value);
                if value && self.mode != "stopped" {
                    if !self.alive(&format!("nature-{id}")) {
                        self.start_nature(id)?;
                    }
                } else {
                    self.stop_channel(&format!("nature-{id}"));
                }
            }
            "noise" => {
                let id = arg(1)?;
                if id != "off" && !self.catalog.nature.iter().any(|s| s == id) {
                    return Err("Unknown nature sound".into());
                }
                for sound in self.catalog.nature.clone() {
                    self.ensure_layer(&sound);
                    self.settings["natureLayers"][&sound]["enabled"] = json!(sound == id);
                    self.stop_channel(&format!("nature-{sound}"));
                }
                if id != "off" && self.mode != "stopped" {
                    self.start_nature(id)?;
                }
            }
            "youtube-add" => {
                let url = config::canonical_url(arg(1)?)?;
                let video = url.rsplit('=').next().unwrap();
                let id = format!("youtube-{video}");
                let title = args
                    .get(2)
                    .map(|s| config::clean_title(s))
                    .unwrap_or_default();
                let videos = self.settings["youtube"].as_array_mut().unwrap();
                if let Some(entry) = videos.iter_mut().find(|e| e["id"] == id) {
                    if !title.is_empty() {
                        entry["name"] = json!(title);
                    }
                } else {
                    if videos.len() >= 40 {
                        return Err(
                            "Your library is full (40 videos). Remove one before adding another."
                                .into(),
                        );
                    }
                    videos.push(json!({"id":id,"url":url,"name":if title.is_empty() {format!("YouTube · {video}")} else {title},"position":0}));
                }
                self.reload_catalog();
            }
            "youtube-remove" => {
                let id = arg(1)?;
                if !self.settings["youtube"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|e| e["id"] == id)
                {
                    return Err("This saved video no longer exists.".into());
                }
                self.bookmark();
                let fallback = self
                    .catalog
                    .music
                    .iter()
                    .find(|s| self.catalog.entries[*s].category == "lofi")
                    .cloned()
                    .unwrap_or_default();
                if self.station == id {
                    if !self.stop_channel("main") {
                        return Err(self.error.clone());
                    }
                    self.station = fallback.clone();
                    self.transport("pause", true);
                    self.ended = false;
                }
                if self.settings["defaultStation"] == id {
                    self.settings["defaultStation"] = json!(fallback);
                }
                self.settings["youtube"]
                    .as_array_mut()
                    .unwrap()
                    .retain(|e| e["id"] != id);
                self.reload_catalog();
            }
            "seek" => {
                if !self.can_seek() {
                    return Err(
                        "Seeking is available only for a loaded recording, not live radio.".into(),
                    );
                }
                let seconds = arg(1)?
                    .parse::<f64>()
                    .map_err(|_| "Invalid seek position")?;
                let duration = self
                    .prop("main", "duration")
                    .as_f64()
                    .filter(|n| *n > 0.0)
                    .ok_or("Seeking is available once a video is playing.")?;
                if !seconds.is_finite() || !self.alive("main") {
                    return Err("Invalid seek position".into());
                }
                self.ipc(
                    "main",
                    json!([
                        "seek",
                        seconds.clamp(0.0, (duration - 0.1).max(0.0)),
                        "absolute"
                    ]),
                );
                if self.ended && self.mode == "playing" {
                    self.ipc("main", json!(["set_property", "pause", false]));
                }
                self.ended = false;
                self.progress = Instant::now();
            }
            "ducking" => {
                self.settings["ducking"] = json!(match arg(1)? {
                    "on" => true,
                    "off" => false,
                    _ => return Err("ducking takes on/off".into()),
                });
            }
            "ui" => {
                let key = arg(1)?;
                let value = arg(2)?;
                let boolean = match key {
                    "animations" => Some("animations"),
                    "reveal" => Some("revealAnimations"),
                    "steam" => Some("steamAnimation"),
                    "glow" => Some("glowAnimation"),
                    "equalizer" => Some("equalizerAnimation"),
                    "fade" => Some("fadeEnabled"),
                    "collapsible" => Some("collapsibleSections"),
                    _ => None,
                };
                if let Some(key) = boolean {
                    self.settings[key] = json!(match value {
                        "on" => true,
                        "off" => false,
                        _ => return Err("UI boolean settings take on/off".into()),
                    });
                } else {
                    let maximum = match key {
                        "fadeSeconds" => 8,
                        "revealSpeed" => 3,
                        "duckLevel" => 100,
                        _ => return Err("Unknown UI setting".into()),
                    };
                    let value = value
                        .parse::<u32>()
                        .map_err(|_| "Invalid UI setting value")?;
                    if value > maximum {
                        return Err(format!("{key} takes 0–{maximum}"));
                    }
                    self.settings[key] = json!(value);
                }
                if !self.fades_enabled() {
                    for channel in self.channels.values_mut() {
                        channel.fade = None;
                        channel.gain = if self.mode == "playing" { 1.0 } else { 0.0 };
                    }
                    if let Some((action, _)) = self.pending.take() {
                        self.commit_transport(&action);
                    }
                }
            }
            "default" => {
                let id = arg(1)?;
                if !self.catalog.music.iter().any(|s| s == id) {
                    return Err("Unknown music source".into());
                }
                self.settings["defaultStation"] = json!(id);
                if self.mode == "stopped" {
                    self.station = id.into();
                }
            }
            "bridge-restart" => {}
            _ => return Err(format!("Unknown command: {command}")),
        }
        self.refresh_recording();
        self.apply_volumes();
        self.changed();
        self.persist()?;
        if self.cancellation_failed {
            return Err(self.error.clone());
        }
        Ok(())
    }
    fn ensure_layer(&mut self, id: &str) {
        if !self.settings["natureLayers"][id].is_object() {
            self.settings["natureLayers"][id] = json!({"enabled":false,"volume":25});
        }
    }
    fn reload_catalog(&mut self) {
        self.catalog = Catalog::load(&self.paths.root, &self.settings);
        if !self.catalog.music.contains(&self.station) {
            if !self.stop_channel("main") {
                return;
            }
            self.station = self.settings["defaultStation"]
                .as_str()
                .filter(|id| self.catalog.music.iter().any(|s| s == id))
                .map(str::to_owned)
                .unwrap_or_else(|| self.catalog.music.first().cloned().unwrap_or_default());
            self.settings["defaultStation"] = json!(self.station);
            if self.mode == "playing" {
                let _ = self.start_main(true);
            }
        }
        self.changed();
    }
    pub fn reload_preferences(&mut self) {
        let fresh = preferences(config::read_json(&self.paths.state.join("settings.json")));
        if fresh != self.settings {
            let replace_bg = fresh["bgStation"] != self.settings["bgStation"]
                || fresh["mix"] != self.settings["mix"];
            self.settings = fresh;
            self.reload_catalog();
            if self.mode != "stopped" {
                if replace_bg {
                    self.feed_token += 1;
                    self.feed_loading = false;
                    self.cancel_feed();
                    self.stop_channel("bg");
                    if let Err(error) = self.start_bg() {
                        self.error = error;
                    }
                }
                for id in self.catalog.nature.clone() {
                    let channel = format!("nature-{id}");
                    if self.settings["natureLayers"][&id]["enabled"] == true {
                        if !self.alive(&channel) {
                            if let Err(error) = self.start_nature(&id) {
                                self.error = error;
                            }
                        }
                    } else {
                        self.stop_channel(&channel);
                    }
                }
            }
            self.refresh_recording();
            self.apply_volumes();
            if let Err(error) = self.persist() {
                self.error = error;
            }
            self.changed();
        }
    }
    pub fn catalog_changed(&mut self) {
        self.reload_catalog();
        if let Err(error) = self.persist() {
            self.error = error;
        }
    }
    pub fn recording_path(&self) -> std::path::PathBuf {
        let config = self.paths.config.join("voxtype/config.toml");
        if let Ok(text) = fs::read_to_string(config) {
            if let Ok(document) = text.parse::<toml::Value>() {
                if let Some(value) = document.get("state_file").and_then(toml::Value::as_str) {
                    if value == "disabled" {
                        return std::path::PathBuf::new();
                    }
                    if value != "auto" && !value.is_empty() {
                        return if let Some(tail) = value.strip_prefix("~/") {
                            std::path::PathBuf::from(std::env::var_os("HOME").unwrap_or_default())
                                .join(tail)
                        } else {
                            value.into()
                        };
                    }
                }
            }
        }
        self.paths.xdg_runtime.join("voxtype/state")
    }
    pub fn refresh_recording(&mut self) {
        let state = self.recording_path();
        let recording = !state.as_os_str().is_empty()
            && fs::read_to_string(self.paths.xdg_runtime.join("voxtype/pid"))
                .ok()
                .and_then(|s| s.trim().parse::<u32>().ok())
                .and_then(|pid| Process::pin(pid).ok())
                .is_some_and(|p| p.alive())
            && fs::read_to_string(state)
                .is_ok_and(|s| matches!(s.trim(), "recording" | "streaming"));
        self.recording = recording;
        let target = if recording && enabled(&self.settings, "ducking") {
            number(&self.settings, "duckLevel") / 100.0
        } else {
            1.0
        };
        if target != self.duck_target {
            self.duck_from = self.duck_gain;
            self.duck_target = target;
            self.duck_started = Instant::now();
            self.changed();
        }
    }
    fn apply_volumes(&mut self) {
        for key in self.channels.keys().cloned().collect::<Vec<_>>() {
            let volume = self.volume(&key) * self.channels[&key].gain;
            let channel = self.channels.get_mut(&key).unwrap();
            if (channel.applied - volume).abs() > 0.015 || !channel.applied.is_finite() {
                if let Some(ipc) = &channel.ipc {
                    if ipc
                        .command(json!(["set_property", "volume", volume]))
                        .is_ok()
                    {
                        channel.applied = volume;
                    }
                }
            }
        }
    }
    pub fn connected(&mut self, key: String, generation: u64, ipc: Mpv) {
        if let Some(channel) = self
            .channels
            .get_mut(&key)
            .filter(|c| c.generation == generation)
        {
            channel.ipc = Some(ipc);
            channel.applied = f64::NAN;
            self.apply_volumes();
            self.changed();
        }
    }
    pub fn disconnected(&mut self, key: &str, generation: u64) {
        if self
            .channels
            .get(key)
            .is_some_and(|c| c.generation == generation)
        {
            if key == "bg" && self.bg_error.is_empty() {
                self.bg_error =
                    "Background source disconnected. Choose another source or retry.".into();
            }
            self.stop_channel(key);
            self.changed();
            self.next_maintenance = Instant::now();
        }
    }
    pub fn property(&mut self, key: &str, generation: u64, value: Value) {
        let Some(channel) = self
            .channels
            .get_mut(key)
            .filter(|c| c.generation == generation)
        else {
            return;
        };
        if value["event"] == "end-file" {
            if value["reason"] == "error" {
                let error = value["file_error"]
                    .as_str()
                    .unwrap_or("Playback disconnected")
                    .to_owned();
                if key == "bg" {
                    self.bg_error = error;
                } else if key == "main" {
                    self.error = error;
                }
                self.next_maintenance = Instant::now();
            }
            self.changed();
            return;
        }
        let Some(name) = value["name"].as_str() else {
            return;
        };
        let data = if name == "media-title" {
            json!(value["data"]
                .as_str()
                .map(config::clean_title)
                .unwrap_or_default())
        } else {
            value["data"].clone()
        };
        if channel.properties.get(name) == Some(&data) {
            return;
        }
        channel.properties.insert(name.into(), data.clone());
        if key == "main" && name == "time-pos" && data.is_number() {
            self.progress = Instant::now();
            if self.stable.is_none() {
                self.stable = Some(self.progress);
            }
        }
        if playback_ready(key, name, &data) {
            if let Some(fade) = channel.fade.as_mut().filter(|f| f.await_ready) {
                fade.await_ready = false;
                fade.started = Instant::now();
            }
        }
        if key == "main"
            && name == "eof-reached"
            && data == true
            && self.source_kind() == "recording"
        {
            self.ended = true;
            self.retry_due = None;
            self.bookmark();
            if let Err(error) = self.persist() {
                self.error = error;
            }
        }
        self.changed();
    }
    pub fn feed_ready(&mut self, token: u64, result: Result<std::path::PathBuf, String>) {
        if token != self.feed_token || self.mode == "stopped" || self.youtube() {
            return;
        }
        self.feed_loading = false;
        self.feed_process = None;
        let _ = fs::remove_file(self.paths.runtime.join("feed.pid"));
        match result {
            Ok(path) => {
                if let Some(mut station) = self
                    .catalog
                    .entries
                    .get(self.settings["bgStation"].as_str().unwrap_or(""))
                    .cloned()
                {
                    station.url = path.to_string_lossy().into_owned();
                    station.kind.clear();
                    if let Err(error) = self.spawn("bg", &station, false) {
                        self.bg_error = error;
                    }
                }
            }
            Err(error) => self.bg_error = format!("Podcast unavailable: {error}"),
        }
        self.changed();
    }
    fn bookmark(&mut self) {
        if !self.youtube() {
            return;
        }
        let Some(position) = self.prop("main", "time-pos").as_f64() else {
            return;
        };
        let duration = self.prop("main", "duration").as_f64();
        let title = self
            .prop("main", "media-title")
            .as_str()
            .map(config::clean_title)
            .unwrap_or_default();
        let finite = self.prop("main", "source-kind") == "recording";
        for entry in self.settings["youtube"].as_array_mut().unwrap() {
            if entry["id"] != self.station {
                continue;
            }
            if entry["name"]
                .as_str()
                .is_some_and(|s| s.starts_with("YouTube · "))
                && !title.is_empty()
                && !title.starts_with("http")
            {
                entry["name"] = json!(title);
            }
            if let Some(duration) = duration.filter(|n| *n > 0.0) {
                entry["position"] = json!(if finite && position < duration - 5.0 {
                    (position * 10.0).round() / 10.0
                } else {
                    0.0
                });
            }
        }
        // Rebuild titles/positions without restarting current audio.
        self.catalog = Catalog::load(&self.paths.root, &self.settings);
    }
    pub fn tick(&mut self) {
        let now = Instant::now();
        if self.duck_gain != self.duck_target {
            let progress = (now.duration_since(self.duck_started).as_secs_f64() / 0.25).min(1.0);
            self.duck_gain = self.duck_from + (self.duck_target - self.duck_from) * ease(progress);
            if progress >= 1.0 {
                self.duck_gain = self.duck_target;
            }
        }
        for channel in self.channels.values_mut() {
            if let Some(fade) = channel.fade.as_ref() {
                if fade.await_ready {
                    continue;
                }
                let progress = if fade.duration.is_zero() {
                    1.0
                } else {
                    (now.duration_since(fade.started).as_secs_f64() / fade.duration.as_secs_f64())
                        .min(1.0)
                };
                channel.gain = fade.from + (fade.to - fade.from) * ease(progress);
                if progress >= 1.0 {
                    channel.fade = None;
                }
            }
        }
        self.apply_volumes();
        if self.pending.as_ref().is_some_and(|(_, due)| now >= *due) {
            let (action, _) = self.pending.take().unwrap();
            self.commit_transport(&action);
            if let Err(error) = self.persist() {
                self.error = error;
            }
            self.changed();
        }
        if self.mode == "playing" && now >= self.next_maintenance {
            self.next_maintenance = now + Duration::from_secs(1);
            if self.retry_due.is_some() {
                self.changed();
            }
            if self.youtube() && !matches!(self.source_kind(), "radio" | "live") {
                if !self.alive("main")
                    || (self.prop("main", "time-pos").is_null()
                        && now.duration_since(self.started) > Duration::from_secs(45))
                {
                    self.stop_channel("main");
                    self.attempts = RETRY.len();
                    self.retry_due = None;
                    self.changed();
                }
            } else if !self.ended {
                let ready = self.prop("main", "time-pos").is_number();
                let stalled = self.prop("main", "eof-reached") == true
                    || if ready {
                        now.duration_since(self.progress) >= Duration::from_secs(15)
                    } else {
                        let timeout = if self
                            .catalog
                            .entries
                            .get(&self.station)
                            .is_some_and(|s| s.kind == "youtube")
                        {
                            45
                        } else {
                            15
                        };
                        now.duration_since(self.started) >= Duration::from_secs(timeout)
                    };
                if self.alive("main") && !stalled {
                    self.retry_due = None;
                    if self
                        .stable
                        .is_some_and(|start| now.duration_since(start) >= Duration::from_secs(30))
                    {
                        self.attempts = 0;
                    }
                } else {
                    if self.alive("main") {
                        self.stop_channel("main");
                    }
                    if self.attempts < RETRY.len() {
                        match self.retry_due {
                            None => {
                                self.retry_due =
                                    Some(now + Duration::from_secs(RETRY[self.attempts]));
                                self.changed();
                            }
                            Some(due) if now >= due => {
                                self.attempts += 1;
                                let _ = self.start_main(false);
                                self.changed();
                            }
                            _ => {}
                        }
                    }
                }
            }
        }
        if self.mode == "playing" && self.youtube() && now >= self.next_bookmark {
            self.bookmark();
            if let Err(error) = self.persist() {
                self.error = error;
            }
            self.next_bookmark = now + Duration::from_secs(10);
        }
    }
    pub fn next_wakeup(&self) -> Duration {
        let mut duration = Duration::from_secs(3600);
        if self.duck_gain != self.duck_target
            || self
                .channels
                .values()
                .any(|c| c.fade.as_ref().is_some_and(|f| !f.await_ready))
        {
            duration = Duration::from_millis(30);
        }
        let now = Instant::now();
        if self.mode == "playing" {
            duration = duration.min(self.next_maintenance.saturating_duration_since(now));
        }
        if let Some((_, due)) = &self.pending {
            duration = duration.min(due.saturating_duration_since(now));
        }
        duration
    }
    pub fn has_duration(&self) -> bool {
        self.prop("main", "duration").is_number()
    }
    fn source_kind(&self) -> &str {
        let saved = self.settings["youtube"]
            .as_array()
            .is_some_and(|entries| entries.iter().any(|entry| entry["id"] == self.station));
        if !saved {
            "radio"
        } else {
            self.channels
                .get("main")
                .and_then(|channel| channel.properties.get("source-kind"))
                .and_then(Value::as_str)
                .unwrap_or("unknown")
        }
    }
    fn can_seek(&self) -> bool {
        // Radio decoders can report a growing duration or a seekable cache.
        // Only an explicitly saved finite recording gets a timeline.
        self.source_kind() == "recording"
            && self.alive("main")
            && self.prop("main", "seekable") == true
            && self
                .prop("main", "duration")
                .as_f64()
                .is_some_and(|duration| duration.is_finite() && duration > 0.0)
    }
    pub fn status(&self) -> Value {
        let main = self.catalog.entries.get(&self.station);
        let bg = self
            .catalog
            .entries
            .get(self.settings["bgStation"].as_str().unwrap_or(""));
        let ready = self.prop("main", "time-pos").is_number();
        let main_state = if self.mode == "stopped" {
            "stopped"
        } else if self.mode == "paused" {
            "paused"
        } else if self.ended {
            "ended"
        } else if ready && self.alive("main") {
            "playing"
        } else if self.alive("main") {
            if self.attempts == 0 {
                "connecting"
            } else {
                "reconnecting"
            }
        } else if self.attempts >= RETRY.len() {
            "failed"
        } else {
            "reconnecting"
        };
        let layers:Vec<_>=self.catalog.nature.iter().map(|id|json!({"id":id,"name":self.catalog.entries[id].name,"enabled":self.settings["natureLayers"][id]["enabled"]==true,"volume":config::level(&self.settings["natureLayers"][id]["volume"],25.0),"running":self.alive(&format!("nature-{id}"))})).collect();
        let selected = layers
            .iter()
            .find(|e| e["enabled"] == true)
            .and_then(|e| e["id"].as_str())
            .unwrap_or("off");
        let can_seek = self.can_seek();
        let mut status = json!({
            "running":self.mode!="stopped","paused":self.mode=="paused","main_running":self.alive("main"),"main_state":main_state,
            "retry_in":self.retry_due.map(|due|due.saturating_duration_since(Instant::now()).as_secs_f64().ceil() as u64).unwrap_or(0),"retry_attempt":self.attempts,
            "station":self.station,"name":main.map(|s|s.name.as_str()).unwrap_or("No sources available"),"category":if self.youtube() {"youtube"} else {main.map(|s|s.category.as_str()).unwrap_or("")},
            "category_name":main.map(|s|if s.kind=="youtube" && s.category != "youtube" {"YouTube live"} else {s.category_name.as_str()}).unwrap_or(""),"url":main.map(|s|s.url.as_str()).unwrap_or(""),
            "main_volume":self.settings["mainVolume"],"bg_volume":self.settings["bgVolume"],"master_volume":self.settings["masterVolume"],"ducking":self.settings["ducking"],
            "bg_station":bg.map(|s|s.id.as_str()).unwrap_or(""),"bg_name":bg.map(|s|s.name.as_str()).unwrap_or(""),"bg_running":self.alive("bg"),"mix":enabled(&self.settings,"mix") && !self.youtube(),
            "nature_layers":layers,"youtube_entries":self.settings["youtube"],"youtube_available":self.youtube_available,"nature_volume":self.settings["natureVolume"],"noise_volume":self.settings["natureVolume"],
            "noise_station":selected,"noise_running":layers.iter().any(|e|e["running"]==true),"index":self.catalog.music.iter().position(|s|s==&self.station).unwrap_or(0),"count":self.catalog.music.len(),
            "main_title":self.prop("main","media-title"),"bg_title":self.prop("bg","media-title"),"main_position":self.prop("main","time-pos"),"main_duration":if can_seek {self.prop("main","duration")} else {Value::Null},
            "bg_position":self.prop("bg","time-pos"),"bg_duration":self.prop("bg","duration"),"duck_level":self.settings["duckLevel"],"native_backend":true,"backend_version":env!("CARGO_PKG_VERSION"),"recording":self.recording,"error":self.error.split_whitespace().collect::<Vec<_>>().join(" ").chars().take(300).collect::<String>(),
            "bg_error":self.bg_error.split_whitespace().collect::<Vec<_>>().join(" ").chars().take(300).collect::<String>(),
            "bg_state":if self.feed_loading {"loading"} else if self.alive("bg") {if self.mode=="paused" {"paused"} else {"playing"}} else if !self.bg_error.is_empty() {"failed"} else {"stopped"}
        });
        status["can_seek"] = Value::Bool(can_seek);
        status["source_kind"] = json!(self.source_kind());
        for (target, source) in [
            ("animations", "animations"),
            ("reveal_animations", "revealAnimations"),
            ("steam_animation", "steamAnimation"),
            ("glow_animation", "glowAnimation"),
            ("equalizer_animation", "equalizerAnimation"),
            ("fade_enabled", "fadeEnabled"),
            ("fade_seconds", "fadeSeconds"),
            ("reveal_speed", "revealSpeed"),
            ("collapsible_sections", "collapsibleSections"),
        ] {
            status[target] = self.settings[source].clone();
        }
        status
    }
    pub fn log_command(&self, args: &[String], source: &str) {
        if args.first().is_some_and(|s| {
            [
                "start", "station", "play", "resume", "pause", "toggle", "stop", "next", "prev",
            ]
            .contains(&s.as_str())
        }) {
            let path = self.paths.runtime.join("logs/control.log");
            if fs::metadata(&path).is_ok_and(|m| m.len() > 65536) {
                let _ = fs::rename(&path, path.with_extension("log.previous"));
            }
            if let Ok(mut output) = OpenOptions::new()
                .append(true)
                .create(true)
                .mode(0o600)
                .custom_flags(libc::O_NOFOLLOW)
                .open(path)
            {
                let _ = writeln!(
                    output,
                    "{}",
                    json!({"command":args[0],"source":source,"before":self.mode})
                );
            }
        }
    }
}
impl Drop for Engine {
    fn drop(&mut self) {
        self.cancel_feed();
        for key in self.channels.keys().cloned().collect::<Vec<_>>() {
            self.stop_channel(&key);
        }
    }
}

#[cfg(test)]
mod readiness_tests {
    use super::*;
    #[test]
    fn nature_decoder_snapshot_releases_fade_without_clock() {
        assert!(playback_ready(
            "nature-noise-rain",
            "audio-params",
            &json!({"samplerate":44100,"channels":"stereo"})
        ));
        assert!(!playback_ready(
            "nature-noise-rain",
            "audio-params",
            &Value::Null
        ));
        assert!(!playback_ready(
            "nature-noise-rain",
            "time-pos",
            &json!(0.0)
        ));
        for channel in ["main", "bg"] {
            assert!(playback_ready(channel, "time-pos", &json!(0.0)));
            assert!(!playback_ready(channel, "time-pos", &Value::Null));
            assert!(!playback_ready(
                channel,
                "audio-params",
                &json!({"samplerate":44100})
            ));
        }
    }
}
