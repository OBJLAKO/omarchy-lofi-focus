use crate::Event;
use serde_json::{json, Value};
use std::{
    io::{self, BufRead, BufReader, Write},
    os::unix::net::UnixStream,
    path::PathBuf,
    sync::{mpsc::SyncSender, Arc, Mutex},
    thread,
    time::{Duration, Instant},
};

pub const CLIENT_FRAME: usize = 64 * 1024;
pub fn read_line<R: BufRead>(reader: &mut R, maximum: usize) -> io::Result<Option<Vec<u8>>> {
    let mut line = Vec::new();
    loop {
        let buffer = reader.fill_buf()?;
        if buffer.is_empty() {
            return if line.is_empty() {
                Ok(None)
            } else {
                Err(io::Error::other("truncated JSON frame"))
            };
        }
        let end = buffer.iter().position(|c| *c == b'\n').map(|n| n + 1);
        let count = end.unwrap_or(buffer.len());
        if line.len() + count > maximum {
            return Err(io::Error::other("JSON frame exceeded limit"));
        }
        line.extend_from_slice(&buffer[..count]);
        reader.consume(count);
        if end.is_some() {
            return Ok(Some(line));
        }
    }
}
pub fn send_json(stream: &mut UnixStream, value: &Value) -> io::Result<()> {
    let mut bytes = serde_json::to_vec(value)?;
    bytes.push(b'\n');
    if bytes.len() > CLIENT_FRAME {
        return Err(io::Error::other("outgoing JSON frame exceeded limit"));
    }
    stream.write_all(&bytes)
}
#[derive(Clone)]
pub struct Mpv {
    stream: Arc<Mutex<UnixStream>>,
}
impl Mpv {
    pub fn command(&self, args: Value) -> io::Result<()> {
        let mut stream = self
            .stream
            .lock()
            .map_err(|_| io::Error::other("mpv writer poisoned"))?;
        send_json(&mut stream, &json!({"command":args}))
    }
}
fn observed_properties(channel: &str) -> &'static [&'static str] {
    if channel.starts_with("nature-") {
        // Nature loops have no progress UI or radio stall recovery. A static
        // decoder snapshot releases the first fade without nine clock streams.
        &["audio-params"]
    } else {
        &[
            "time-pos",
            "duration",
            "pause",
            "media-title",
            "eof-reached",
            "metadata",
            "idle-active",
        ]
    }
}
pub fn connect_mpv(path: PathBuf, channel: String, generation: u64, events: SyncSender<Event>) {
    thread::spawn(move || {
        let deadline = Instant::now() + Duration::from_secs(2);
        let stream = loop {
            match UnixStream::connect(&path) {
                Ok(stream) => break stream,
                Err(_) if Instant::now() < deadline => thread::sleep(Duration::from_millis(10)),
                Err(_) => {
                    let _ = events.send(Event::Disconnected(channel, generation));
                    return;
                }
            }
        };
        let _ = stream.set_write_timeout(Some(Duration::from_millis(100)));
        let Ok(writer) = stream.try_clone() else {
            return;
        };
        let mpv = Mpv {
            stream: Arc::new(Mutex::new(writer)),
        };
        for (id, property) in observed_properties(&channel).iter().enumerate() {
            if mpv
                .command(json!(["observe_property", id + 1, property]))
                .is_err()
            {
                let _ = events.send(Event::Disconnected(channel, generation));
                return;
            }
        }
        if events
            .send(Event::Connected(channel.clone(), generation, mpv))
            .is_err()
        {
            return;
        }
        let mut reader = BufReader::new(stream);
        while let Ok(Some(line)) = read_line(&mut reader, crate::config::MAX_JSON) {
            let Ok(value) = serde_json::from_slice::<Value>(&line) else {
                break;
            };
            if !value.is_object() {
                break;
            }
            if (value["event"] == "property-change" || value["event"] == "end-file")
                && events
                    .send(Event::Property(channel.clone(), generation, value))
                    .is_err()
            {
                return;
            }
        }
        let _ = events.send(Event::Disconnected(channel, generation));
    });
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn frames_are_bounded_and_complete() {
        let mut reader = std::io::Cursor::new(b"12345\n");
        assert!(read_line(&mut reader, 5).is_err());
        let mut reader = std::io::Cursor::new(b"{}\n[]\n");
        assert_eq!(read_line(&mut reader, 10).unwrap().unwrap(), b"{}\n");
        assert_eq!(read_line(&mut reader, 10).unwrap().unwrap(), b"[]\n");
        assert!(read_line(&mut reader, 10).unwrap().is_none());
        assert!(read_line(&mut std::io::Cursor::new(b"{\"id\":1}"), 100).is_err());
    }
    #[test]
    fn nature_readiness_has_no_continuous_clock_observation() {
        let nature = observed_properties("nature-noise-rain");
        assert_eq!(nature, &["audio-params"]);
        for unused in ["time-pos", "duration", "media-title", "metadata"] {
            assert!(!nature.contains(&unused));
        }
        for channel in ["main", "bg"] {
            let properties = observed_properties(channel);
            for needed in ["time-pos", "duration", "media-title"] {
                assert!(properties.contains(&needed));
            }
        }
    }
}
