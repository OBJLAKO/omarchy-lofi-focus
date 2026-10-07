mod audio;
mod config;
mod engine;
mod extractor;
mod feed;
mod library;
mod mpris;
mod process;
mod room;
mod transport;
use config::{write_bytes, write_json, Paths};
use engine::Engine;
use notify::{RecursiveMode, Watcher};
use serde_json::{json, Value};
use std::{
    fs::{self, OpenOptions},
    io::{self, BufReader, Write},
    os::{
        fd::AsRawFd,
        unix::{
            fs::{MetadataExt, OpenOptionsExt, PermissionsExt},
            net::{UnixListener, UnixStream},
        },
    },
    path::PathBuf,
    process::{Command, Stdio},
    sync::{
        atomic::{AtomicU64, AtomicUsize, Ordering},
        mpsc::{self, SyncSender},
        Arc, Mutex,
    },
    thread,
    time::{Duration, Instant},
};

pub enum Event {
    Command {
        id: Value,
        args: Vec<String>,
        source: String,
        reply: SyncSender<Value>,
    },
    Subscribe(u64, SyncSender<Value>),
    Unsubscribe(u64),
    Connected(String, u64, transport::Mpv),
    Disconnected(String, u64),
    Property(String, u64, Value),
    Files(Vec<PathBuf>),
    Feed(u64, Result<PathBuf, String>),
    Shutdown,
}
fn main() {
    if let Err(error) = run() {
        eprintln!("Skylofi: {error}");
        std::process::exit(1);
    }
}
fn run() -> Result<(), Box<dyn std::error::Error>> {
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    if std::env::var("SKYLOFI_EXTRACTOR_PROXY").as_deref() == Ok("1") {
        return extractor::run(&args);
    }
    let root = if let Some(index) = args.iter().position(|a| a == "--root") {
        if index + 1 >= args.len() {
            return Err("--root needs a plugin directory".into());
        }
        let root = PathBuf::from(args.remove(index + 1));
        args.remove(index);
        root
    } else {
        std::env::current_dir()?
    };
    if args.first().is_some_and(|a| a == "--version") {
        println!("skylofi {}", env!("CARGO_PKG_VERSION"));
        return Ok(());
    }
    if args.first().is_some_and(|a| a == "--fetch-feed") {
        if args.len() != 3 {
            return Err("--fetch-feed needs HTTPS URL and destination".into());
        }
        let result = feed::resolve(&args[1], std::path::Path::new(&args[2]));
        println!(
            "{}",
            match result {
                Ok(()) => json!({"ok":true}),
                Err(error) => json!({"ok":false,"error":error}),
            }
        );
        return Ok(());
    }
    let paths = Paths::new(fs::canonicalize(root)?)?;
    if args.first().is_some_and(|a| a == "--daemon") {
        return daemon(paths);
    }
    let stdio = args.first().is_some_and(|a| a == "--stdio");
    if args.is_empty() {
        args.push("status".into());
    }
    let mut stream = connect(&paths)?;
    if stdio {
        return stdio_client(stream);
    }
    stream.set_read_timeout(Some(Duration::from_secs(4)))?;
    stream.set_write_timeout(Some(Duration::from_secs(1)))?;
    transport::send_json(
        &mut stream,
        &json!({"id":1,"args":args,"source":std::env::var("LOFI_CONTROL_SOURCE").unwrap_or_else(|_|"cli".into())}),
    )?;
    let mut reader = BufReader::new(stream);
    let line = transport::read_line(&mut reader, config::MAX_JSON)?.ok_or("daemon disconnected")?;
    let reply: Value = serde_json::from_slice(&line)?;
    if reply["ok"] != true {
        return Err(reply["error"]
            .as_str()
            .unwrap_or("control command failed")
            .into());
    }
    println!("{}", reply["status"]);
    Ok(())
}
fn executable_identity() -> Value {
    match fs::metadata("/proc/self/exe") {
        Ok(info) => {
            json!({"device":info.dev(),"inode":info.ino(),"size":info.len(),"mtime":info.mtime(),"mtime_ns":info.mtime_nsec(),"version":env!("CARGO_PKG_VERSION")})
        }
        Err(_) => Value::Null,
    }
}
fn connect(paths: &Paths) -> io::Result<UnixStream> {
    let deadline = Instant::now() + Duration::from_secs(5);
    let mut launched = false;
    loop {
        if let Ok(mut stream) = UnixStream::connect(paths.socket()) {
            stream.set_read_timeout(Some(Duration::from_secs(3)))?;
            stream.set_write_timeout(Some(Duration::from_secs(1)))?;
            let hello = (|| -> io::Result<Value> {
                transport::send_json(&mut stream, &json!({"id":0,"args":["__hello"]}))?;
                let mut reader = BufReader::new(stream.try_clone()?);
                let bytes = transport::read_line(&mut reader, transport::CLIENT_FRAME)?
                    .ok_or_else(|| {
                        io::Error::new(io::ErrorKind::UnexpectedEof, "controller is exiting")
                    })?;
                serde_json::from_slice(&bytes).map_err(io::Error::other)
            })();
            let reply = match hello {
                Ok(reply) => reply,
                Err(_) if Instant::now() < deadline => {
                    thread::sleep(Duration::from_millis(10));
                    continue;
                }
                Err(error) => return Err(error),
            };
            if reply["ok"] == true
                && reply["identity"] == executable_identity()
                && reply["root"] == paths.root.to_string_lossy().as_ref()
            {
                stream.set_read_timeout(None)?;
                return Ok(stream);
            }
            if reply["protocol"] == 1 {
                transport::send_json(&mut stream, &json!({"id":0,"args":["__replace"]}))?;
                let mut reader = BufReader::new(stream.try_clone()?);
                let response = transport::read_line(&mut reader, transport::CLIENT_FRAME)?
                    .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
                    .unwrap_or(Value::Null);
                if response["ok"] != true {
                    return Err(io::Error::other(
                        response["error"]
                            .as_str()
                            .unwrap_or("existing controller refused replacement"),
                    ));
                }
                thread::sleep(Duration::from_millis(30));
            } else {
                return Err(io::Error::other("existing Skylofi controller has an incompatible protocol; stop it before updating"));
            }
        }
        if !launched {
            let log = OpenOptions::new()
                .append(true)
                .create(true)
                .mode(0o600)
                .custom_flags(libc::O_NOFOLLOW)
                .open(paths.runtime.join("logs/controller.log"))?;
            Command::new(std::env::current_exe()?)
                .arg("--root")
                .arg(&paths.root)
                .arg("--daemon")
                .stdin(Stdio::null())
                .stdout(log.try_clone()?)
                .stderr(log)
                .spawn()?;
            launched = true;
        }
        if Instant::now() >= deadline {
            return Err(io::Error::other("Skylofi controller did not become ready"));
        }
        thread::sleep(Duration::from_millis(10));
    }
}
fn stdio_client(mut stream: UnixStream) -> Result<(), Box<dyn std::error::Error>> {
    stream.set_write_timeout(Some(Duration::from_secs(1)))?;
    transport::send_json(&mut stream, &json!({"subscribe":true}))?;
    let mut writer = stream.try_clone()?;
    thread::spawn(move || {
        let stdin = io::stdin();
        let mut reader = stdin.lock();
        while let Ok(Some(line)) = transport::read_line(&mut reader, transport::CLIENT_FRAME) {
            let Ok(value) = serde_json::from_slice::<Value>(&line) else {
                continue;
            };
            if transport::send_json(&mut writer, &value).is_err() {
                break;
            }
        }
        let _ = writer.shutdown(std::net::Shutdown::Both);
    });
    let stdout = io::stdout();
    let mut output = stdout.lock();
    let mut reader = BufReader::new(stream);
    while let Some(line) = transport::read_line(&mut reader, config::MAX_JSON)? {
        output.write_all(&line)?;
        output.flush()?;
    }
    Ok(())
}
static CLIENT_ID: AtomicU64 = AtomicU64::new(1);
fn client(stream: UnixStream, events: SyncSender<Event>, count: Arc<AtomicUsize>) {
    let client_id = CLIENT_ID.fetch_add(1, Ordering::Relaxed);
    thread::spawn(move || {
        struct Count(Arc<AtomicUsize>);
        impl Drop for Count {
            fn drop(&mut self) {
                self.0.fetch_sub(1, Ordering::Relaxed);
            }
        }
        let _count = Count(count);
        let Ok(mut writer) = stream.try_clone() else {
            return;
        };
        let _ = writer.set_write_timeout(Some(Duration::from_millis(150)));
        let (reply, output) = mpsc::sync_channel::<Value>(16);
        thread::spawn(move || {
            while let Ok(value) = output.recv() {
                if transport::send_json(&mut writer, &value).is_err() {
                    break;
                }
            }
            let _ = writer.shutdown(std::net::Shutdown::Both);
        });
        let mut reader = BufReader::new(stream);
        let mut subscribed = false;
        while let Ok(Some(line)) = transport::read_line(&mut reader, transport::CLIENT_FRAME) {
            let Ok(request) = serde_json::from_slice::<Value>(&line) else {
                break;
            };
            if request["subscribe"] == true {
                if subscribed {
                    continue;
                }
                subscribed = true;
                if events
                    .send(Event::Subscribe(client_id, reply.clone()))
                    .is_err()
                {
                    break;
                }
                continue;
            }
            if !(request["id"].is_null()
                || request["id"].is_number()
                || request["id"].as_str().is_some_and(|id| id.len() <= 128))
            {
                let _ = reply.try_send(
                    json!({"id":null,"ok":false,"error":"id must be a number or short string"}),
                );
                continue;
            }
            let Some(raw) = request["args"].as_array() else {
                let _=reply.try_send(json!({"id":request["id"],"ok":false,"error":"args must be an array of strings"}));
                continue;
            };
            if raw.len() > 8
                || raw
                    .iter()
                    .any(|v| !v.is_string() || v.as_str().unwrap().len() > 4096)
            {
                let _ = reply.try_send(
                    json!({"id":request["id"],"ok":false,"error":"invalid command arguments"}),
                );
                continue;
            }
            let args = raw.iter().map(|v| v.as_str().unwrap().to_owned()).collect();
            let source = request["source"]
                .as_str()
                .unwrap_or("stdio")
                .chars()
                .take(160)
                .collect();
            if events
                .send(Event::Command {
                    id: request["id"].clone(),
                    args,
                    source,
                    reply: reply.clone(),
                })
                .is_err()
            {
                break;
            }
        }
        let _ = events.send(Event::Unsubscribe(client_id));
        let _ = reader.get_ref().shutdown(std::net::Shutdown::Both);
    });
}
fn is_content_change(kind: &notify::EventKind) -> bool {
    // Reading a watched file must never enqueue another reload: inotify Access
    // events include our own open/read/close operations on cached preferences.
    matches!(
        kind,
        notify::EventKind::Create(_) | notify::EventKind::Modify(_) | notify::EventKind::Remove(_)
    )
}
fn daemon(paths: Paths) -> Result<(), Box<dyn std::error::Error>> {
    let lock = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW)
        .open(paths.runtime.join("daemon.lock"))?;
    if unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        return Ok(());
    }
    process::retire_legacy(&paths.root, &paths.runtime);
    let _ = fs::remove_file(paths.socket());
    let listener = UnixListener::bind(paths.socket())?;
    fs::set_permissions(paths.socket(), fs::Permissions::from_mode(0o600))?;
    write_bytes(
        &paths.runtime.join("controller.pid"),
        format!("{}\n", std::process::id()).as_bytes(),
    )?;
    let (events, receiver) = mpsc::sync_channel::<Event>(256);
    let accept_events = events.clone();
    let count = Arc::new(AtomicUsize::new(0));
    thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            if count.load(Ordering::Relaxed) >= 24 {
                let _ = stream.shutdown(std::net::Shutdown::Both);
                continue;
            }
            count.fetch_add(1, Ordering::Relaxed);
            client(stream, accept_events.clone(), count.clone());
        }
    });
    let signal_events = events.clone();
    let mut signals = signal_hook::iterator::Signals::new([libc::SIGINT, libc::SIGTERM])?;
    thread::spawn(move || {
        if signals.forever().next().is_some() {
            let _ = signal_events.send(Event::Shutdown);
        }
    });
    let mut engine = Engine::new(paths.clone(), events.clone())?;
    let status = Arc::new(Mutex::new(engine.status()));
    let mpris_events = events.clone();
    let media = mpris::start(status.clone(), mpris_events, &paths);
    let watch_events = events.clone();
    let mut watcher =
        notify::recommended_watcher(move |result: Result<notify::Event, notify::Error>| {
            if let Ok(event) = result {
                if !is_content_change(&event.kind) {
                    return;
                }
                let _ = watch_events.send(Event::Files(event.paths));
            }
        })?;
    watcher.watch(&paths.state, RecursiveMode::NonRecursive)?;
    watcher.watch(&paths.xdg_runtime, RecursiveMode::NonRecursive)?;
    let _ = watcher.watch(&paths.config, RecursiveMode::NonRecursive);
    let _ = watcher.watch(&paths.root, RecursiveMode::NonRecursive);
    let mut watched = std::collections::HashSet::new();
    let update_watches =
        |watcher: &mut notify::RecommendedWatcher,
         engine: &Engine,
         watched: &mut std::collections::HashSet<PathBuf>| {
            let mut candidates = vec![
                paths.xdg_runtime.join("voxtype"),
                paths.config.join("voxtype"),
            ];
            if let Some(parent) = engine
                .recording_path()
                .parent()
                .filter(|p| !p.as_os_str().is_empty())
            {
                candidates.push(parent.to_path_buf());
            }
            for candidate in candidates {
                if candidate.is_dir()
                    && !watched.contains(&candidate)
                    && watcher
                        .watch(&candidate, RecursiveMode::NonRecursive)
                        .is_ok()
                {
                    watched.insert(candidate);
                }
            }
        };
    update_watches(&mut watcher, &engine, &mut watched);
    let mut subscribers = Vec::<(u64, SyncSender<Value>)>::new();
    let mut published = 0;
    let mut last_publish = Instant::now() - Duration::from_secs(1);
    let publish = |engine: &Engine,
                   subscribers: &mut Vec<(u64, SyncSender<Value>)>,
                   status: &Arc<Mutex<Value>>| {
        let snapshot = engine.status();
        let _ = write_json(&paths.runtime.join("status.json"), &snapshot);
        if let Ok(mut shared) = status.lock() {
            *shared = snapshot.clone();
        }
        let _ = media.try_send(());
        subscribers.retain(|(_, sender)| {
            sender
                .try_send(json!({"event":"status","status":snapshot}))
                .is_ok()
        });
    };
    publish(&engine, &mut subscribers, &status);
    loop {
        let timeout = engine.next_wakeup();
        let mut force = false;
        match receiver.recv_timeout(timeout) {
            Ok(Event::Command {
                id,
                args,
                source,
                reply,
            }) => {
                if args.first().is_some_and(|a| a == "__hello") {
                    let _=reply.try_send(json!({"id":id,"ok":true,"protocol":1,"identity":executable_identity(),"root":paths.root.to_string_lossy()}));
                    continue;
                }
                if args.first().is_some_and(|a| a == "__replace") {
                    let intent = json!({"mode":engine.mode,"station":engine.station,"attempts":0,"pending":null});
                    if let Err(error) = engine.shutdown() {
                        let _ = reply.try_send(
                            json!({"id":id,"ok":false,"error":error,"status":engine.status()}),
                        );
                        continue;
                    }
                    let _ = write_json(&paths.runtime.join("session.json"), &intent);
                    let _ = reply.try_send(json!({"id":id,"ok":true}));
                    thread::sleep(Duration::from_millis(20));
                    break;
                }
                if args.first().is_some_and(|a| a == "shutdown") {
                    if let Err(error) = engine.shutdown() {
                        let _ = reply.try_send(
                            json!({"id":id,"ok":false,"error":error,"status":engine.status()}),
                        );
                        continue;
                    }
                    let _ = reply.try_send(json!({"id":id,"ok":true,"status":engine.status()}));
                    thread::sleep(Duration::from_millis(20));
                    break;
                }
                engine.log_command(&args, &source);
                let result = engine.handle_command(&args);
                let snapshot = engine.status();
                let response = match result {
                    Ok(()) => json!({"id":id,"ok":true,"status":snapshot}),
                    Err(error) => json!({"id":id,"ok":false,"error":error,"status":snapshot}),
                };
                let _ = reply.try_send(response);
                force = true;
            }
            Ok(Event::Unsubscribe(client_id)) => subscribers.retain(|(id, _)| *id != client_id),
            Ok(Event::Subscribe(client_id, reply)) => {
                let _ = reply.try_send(json!({"event":"status","status":engine.status()}));
                subscribers.push((client_id, reply));
            }
            Ok(Event::Connected(key, generation, ipc)) => engine.connected(key, generation, ipc),
            Ok(Event::Property(key, generation, value)) => engine.property(&key, generation, value),
            Ok(Event::Disconnected(key, generation)) => engine.disconnected(&key, generation),
            Ok(Event::Feed(token, result)) => engine.feed_ready(token, result),
            Ok(Event::Files(files)) => {
                if !paths.runtime.is_dir() && engine.shutdown().is_ok() {
                    break;
                }
                if files
                    .iter()
                    .any(|p| p == &paths.state.join("settings.json"))
                {
                    engine.reload_preferences();
                    force = true;
                }
                if files.iter().any(|p| p == &paths.root.join("stations.json")) {
                    engine.catalog_changed();
                    force = true;
                }
                if files.iter().any(|p| {
                    p.starts_with(paths.xdg_runtime.join("voxtype"))
                        || p.starts_with(paths.config.join("voxtype"))
                        || p == &engine.recording_path()
                }) {
                    engine.refresh_recording();
                }
                update_watches(&mut watcher, &engine, &mut watched);
            }
            Ok(Event::Shutdown) | Err(mpsc::RecvTimeoutError::Disconnected) => {
                if engine.shutdown().is_ok() {
                    break;
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {}
        }
        engine.tick();
        let interval = if engine.has_duration() {
            Duration::from_millis(250)
        } else {
            Duration::from_secs(1)
        };
        if force || (engine.revision != published && last_publish.elapsed() >= interval) {
            publish(&engine, &mut subscribers, &status);
            published = engine.revision;
            last_publish = Instant::now();
        }
    }
    let _ = fs::remove_file(paths.socket());
    let _ = fs::remove_file(paths.runtime.join("controller.pid"));
    let _ = write_json(&paths.runtime.join("status.json"), &engine.status());
    drop(lock);
    Ok(())
}

#[cfg(test)]
mod watch_tests {
    use super::*;
    use notify::event::{AccessKind, AccessMode, CreateKind, DataChange, ModifyKind, RemoveKind};
    #[test]
    fn read_access_cannot_requeue_a_preferences_reload() {
        for kind in [
            AccessKind::Read,
            AccessKind::Open(AccessMode::Read),
            AccessKind::Close(AccessMode::Read),
        ] {
            assert!(!is_content_change(&notify::EventKind::Access(kind)));
        }
        for kind in [
            notify::EventKind::Modify(ModifyKind::Data(DataChange::Any)),
            notify::EventKind::Create(CreateKind::File),
            notify::EventKind::Remove(RemoveKind::File),
        ] {
            assert!(is_content_change(&kind));
        }
    }
}
