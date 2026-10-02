use crate::{
    config::{self, Paths},
    Event,
};
use serde_json::{json, Value};
use std::{
    collections::{HashMap, HashSet},
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc::{self, SyncSender},
        Arc, Mutex,
    },
    thread,
    time::{Duration, Instant},
};
use zbus::{
    blocking::{connection::Builder, Connection, Proxy},
    message::Header,
    zvariant::{OwnedObjectPath, OwnedValue, Str},
};
const OBJECT: &str = "/org/mpris/MediaPlayer2";
const PLAYER: &str = "org.mpris.MediaPlayer2.Player";
fn text(state: &Value) -> String {
    state["name"].as_str().unwrap_or("Skylofi").to_owned()
}
fn metadata(state: &Value) -> HashMap<String, OwnedValue> {
    let mut result = HashMap::new();
    if state["running"] != true {
        return result;
    }
    result.insert(
        "mpris:trackid".into(),
        OwnedValue::try_from(zbus::zvariant::Value::from(
            OwnedObjectPath::try_from(format!(
                "/sky/lofi/{}",
                state["index"].as_u64().unwrap_or(0)
            ))
            .unwrap(),
        ))
        .unwrap(),
    );
    result.insert(
        "mpris:length".into(),
        OwnedValue::from((state["main_duration"].as_f64().unwrap_or(0.0) * 1e6) as i64),
    );
    result.insert(
        "xesam:title".into(),
        OwnedValue::from(Str::from(text(state))),
    );
    result.insert(
        "xesam:artist".into(),
        OwnedValue::try_from(zbus::zvariant::Value::from(vec![state["category_name"]
            .as_str()
            .unwrap_or("Skylofi")
            .to_owned()]))
        .unwrap(),
    );
    result.insert(
        "xesam:comment".into(),
        OwnedValue::try_from(zbus::zvariant::Value::from(vec![state["url"]
            .as_str()
            .unwrap_or("")
            .to_owned()]))
        .unwrap(),
    );
    result
}
fn playback(state: &Value) -> String {
    if state["running"] != true {
        "Stopped"
    } else if state["paused"] == true {
        "Paused"
    } else {
        "Playing"
    }
    .into()
}
struct App {
    events: SyncSender<Event>,
}
#[zbus::interface(name = "org.mpris.MediaPlayer2")]
impl App {
    fn raise(&self) {}
    fn quit(&self) {
        send(&self.events, &["stop"], "mpris");
    }
    #[zbus(property)]
    fn can_quit(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_raise(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn has_track_list(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn identity(&self) -> &str {
        "Skylofi"
    }
    #[zbus(property)]
    fn desktop_entry(&self) -> &str {
        "sky.lofi"
    }
    #[zbus(property)]
    fn supported_uri_schemes(&self) -> Vec<&str> {
        vec!["http", "https"]
    }
    #[zbus(property)]
    fn supported_mime_types(&self) -> Vec<&str> {
        vec![]
    }
}
fn send(events: &SyncSender<Event>, args: &[&str], source: &str) {
    let (reply, _) = mpsc::sync_channel(1);
    let _ = events.send(Event::Command {
        id: Value::Null,
        args: args.iter().map(|s| s.to_string()).collect(),
        source: source.into(),
        reply,
    });
}
struct Media {
    events: SyncSender<Event>,
    state: Arc<Mutex<Value>>,
    bus: Connection,
    suppressed: Mutex<HashSet<u32>>,
}
impl Media {
    fn state(&self) -> Value {
        self.state
            .lock()
            .map(|s| s.clone())
            .unwrap_or_else(|_| json!({}))
    }
    fn transport(&self, args: &[&str], method: &str, header: Header<'_>) {
        let pid = header.sender().and_then(|sender| {
            Proxy::new(
                &self.bus,
                "org.freedesktop.DBus",
                "/org/freedesktop/DBus",
                "org.freedesktop.DBus",
            )
            .ok()
            .and_then(|proxy| {
                proxy
                    .call::<_, _, u32>("GetConnectionUnixProcessID", &(sender.as_str(),))
                    .ok()
            })
        });
        let voxtype = pid
            .and_then(|pid| std::fs::read_link(format!("/proc/{pid}/exe")).ok())
            .zip(config::which("voxtype").and_then(|p| p.canonicalize().ok()))
            .is_some_and(|(running, installed)| running == installed);
        if let Some(pid) = pid.filter(|_| voxtype) {
            let ducking = self.state()["ducking"] != false;
            if let Ok(mut suppressed) = self.suppressed.lock() {
                if method == "Pause" && ducking {
                    suppressed.insert(pid);
                    return;
                }
                if method == "Play" && (ducking || suppressed.remove(&pid)) {
                    suppressed.remove(&pid);
                    return;
                }
            }
        }
        send(&self.events, args, &format!("mpris:{method}"));
    }
}
#[zbus::interface(name = "org.mpris.MediaPlayer2.Player")]
impl Media {
    fn next(&self, #[zbus(header)] header: Header<'_>) {
        self.transport(&["next"], "Next", header);
    }
    fn previous(&self, #[zbus(header)] header: Header<'_>) {
        self.transport(&["prev"], "Previous", header);
    }
    fn pause(&self, #[zbus(header)] header: Header<'_>) {
        self.transport(&["pause"], "Pause", header);
    }
    fn play_pause(&self, #[zbus(header)] header: Header<'_>) {
        self.transport(&["toggle"], "PlayPause", header);
    }
    fn stop(&self, #[zbus(header)] header: Header<'_>) {
        self.transport(&["stop"], "Stop", header);
    }
    fn play(&self, #[zbus(header)] header: Header<'_>) {
        self.transport(&["play"], "Play", header);
    }
    fn seek(&self, offset: i64) {
        let state = self.state();
        if let Some(position) = state["main_position"].as_f64() {
            let target = (position + offset as f64 / 1e6).to_string();
            send(&self.events, &["seek", &target], "mpris:Seek");
        }
    }
    fn set_position(&self, track_id: OwnedObjectPath, position: i64) {
        let state = self.state();
        if track_id.as_str() == format!("/sky/lofi/{}", state["index"].as_u64().unwrap_or(0)) {
            let target = (position as f64 / 1e6).to_string();
            send(&self.events, &["seek", &target], "mpris:SetPosition");
        }
    }
    fn open_uri(&self, _uri: &str) {}
    #[zbus(property)]
    fn playback_status(&self) -> String {
        playback(&self.state())
    }
    #[zbus(property)]
    fn loop_status(&self) -> &str {
        "None"
    }
    #[zbus(property)]
    fn rate(&self) -> f64 {
        1.0
    }
    #[zbus(property)]
    fn shuffle(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn metadata(&self) -> HashMap<String, OwnedValue> {
        metadata(&self.state())
    }
    #[zbus(property)]
    fn volume(&self) -> f64 {
        self.state()["master_volume"].as_f64().unwrap_or(100.0) / 100.0
    }
    #[zbus(property)]
    fn set_volume(&self, value: f64) {
        if value.is_finite() {
            let volume = (value.clamp(0.0, 1.0) * 100.0).round().to_string();
            send(&self.events, &["vol", "master", &volume], "mpris:Volume");
        }
    }
    #[zbus(property)]
    fn position(&self) -> i64 {
        (self.state()["main_position"].as_f64().unwrap_or(0.0) * 1e6) as i64
    }
    #[zbus(property)]
    fn minimum_rate(&self) -> f64 {
        1.0
    }
    #[zbus(property)]
    fn maximum_rate(&self) -> f64 {
        1.0
    }
    #[zbus(property)]
    fn can_go_next(&self) -> bool {
        self.state()["count"].as_u64().unwrap_or(0) > 1
    }
    #[zbus(property)]
    fn can_go_previous(&self) -> bool {
        self.can_go_next()
    }
    #[zbus(property)]
    fn can_play(&self) -> bool {
        self.state()["count"].as_u64().unwrap_or(0) > 0
    }
    #[zbus(property)]
    fn can_pause(&self) -> bool {
        self.state()["running"] == true
    }
    #[zbus(property)]
    fn can_seek(&self) -> bool {
        self.state()["main_duration"]
            .as_f64()
            .is_some_and(|n| n > 0.0)
    }
    #[zbus(property)]
    fn can_control(&self) -> bool {
        true
    }
}
pub fn start(
    state: Arc<Mutex<Value>>,
    events: SyncSender<Event>,
    _paths: &Paths,
) -> SyncSender<()> {
    let (sender, receiver) = mpsc::sync_channel(4);
    let wake = sender.clone();
    thread::spawn(move || {
        let mut backoff = Duration::from_millis(250);
        loop {
            let result = (|| -> zbus::Result<()> {
                let bus = Connection::session()?;
                let connection = Builder::session()?
                    .serve_at(
                        OBJECT,
                        App {
                            events: events.clone(),
                        },
                    )?
                    .serve_at(
                        OBJECT,
                        Media {
                            events: events.clone(),
                            state: state.clone(),
                            bus,
                            suppressed: Mutex::new(HashSet::new()),
                        },
                    )?
                    .build()?;
                connection.request_name_with_flags(
                    "org.mpris.MediaPlayer2.sky.lofi",
                    Default::default(),
                )?;
                backoff = Duration::from_millis(250);
                let closed = Arc::new(AtomicBool::new(false));
                let monitor_closed = closed.clone();
                let monitor_connection = connection.clone();
                let monitor_wake = wake.clone();
                thread::spawn(move || {
                    let mut messages = zbus::blocking::MessageIterator::from(&monitor_connection);
                    while let Some(Ok(_)) = messages.next() {}
                    monitor_closed.store(true, Ordering::Relaxed);
                    let _ = monitor_wake.try_send(());
                });
                let mut last = Value::Null;
                let outcome = (|| -> zbus::Result<()> {
                    while receiver.recv().is_ok() {
                        if closed.load(Ordering::Relaxed) {
                            return Err(zbus::Error::Failure("session bus disconnected".into()));
                        }
                        let current = state
                            .lock()
                            .map(|s| s.clone())
                            .unwrap_or_else(|_| json!({}));
                        let fingerprint = json!([
                            current["running"],
                            current["paused"],
                            current["name"],
                            current["station"],
                            current["master_volume"],
                            current["main_duration"],
                            current["count"]
                        ]);
                        if fingerprint == last {
                            continue;
                        }
                        last = fingerprint;
                        let mut changed = HashMap::new();
                        changed.insert(
                            "PlaybackStatus",
                            OwnedValue::from(Str::from(playback(&current))),
                        );
                        changed.insert(
                            "Metadata",
                            OwnedValue::try_from(zbus::zvariant::Value::from(metadata(&current)))
                                .unwrap(),
                        );
                        changed.insert(
                            "Volume",
                            OwnedValue::from(
                                current["master_volume"].as_f64().unwrap_or(100.0) / 100.0,
                            ),
                        );
                        connection.emit_signal(
                            None::<&str>,
                            OBJECT,
                            "org.freedesktop.DBus.Properties",
                            "PropertiesChanged",
                            &(PLAYER, changed, Vec::<String>::new()),
                        )?;
                    }
                    Ok(())
                })();
                let _ = connection.close();
                outcome
            })();
            if result.is_ok() {
                return;
            }
            // Reconnect only after a transport failure, with bounded backoff. A
            // live bus consumes property notifications and socket closure events;
            // it never polls the bus or reads files on playback timer ticks.
            let deadline = Instant::now() + backoff;
            loop {
                match receiver.recv_timeout(deadline.saturating_duration_since(Instant::now())) {
                    Err(mpsc::RecvTimeoutError::Disconnected) => return,
                    Err(mpsc::RecvTimeoutError::Timeout) => break,
                    Ok(()) => {
                        if Instant::now() >= deadline {
                            break;
                        }
                    }
                }
            }
            backoff = (backoff * 2).min(Duration::from_secs(5));
        }
    });
    sender
}
