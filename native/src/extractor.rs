//! Preserve mpv's extraction workflow while reporting source capabilities in Rust.
//! Old mpv versions do not export is_live in metadata for single-track streams.
use crate::{config, process::Process, transport};
use serde_json::{json, Value};
use std::{
    io::{self, BufReader, Read, Write},
    os::unix::net::UnixStream,
    path::PathBuf,
    process::{Command, Stdio},
    time::Duration,
};

const MAX_EXTRACTOR_JSON: usize = 8 * 1024 * 1024;

fn source_kind(info: &Value) -> &'static str {
    let live_status = info["live_status"].as_str().unwrap_or("");
    if info["is_live"] == true || ["is_live", "is_upcoming", "post_live"].contains(&live_status) {
        "live"
    } else if (info["is_live"] == false || ["not_live", "was_live"].contains(&live_status))
        && info["duration"]
            .as_f64()
            .is_some_and(|duration| duration.is_finite() && duration > 0.0)
    {
        "recording"
    } else {
        "unknown"
    }
}

fn notify_source(kind: &str) -> io::Result<()> {
    let generation = std::env::var("SKYLOFI_EXTRACTOR_GENERATION").map_err(io::Error::other)?;
    let runtime = std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(format!("/run/user/{}", unsafe { libc::geteuid() })));
    let mut stream = UnixStream::connect(runtime.join("sky.lofi/controller.sock"))?;
    stream.set_read_timeout(Some(Duration::from_millis(750)))?;
    stream.set_write_timeout(Some(Duration::from_millis(100)))?;
    transport::send_json(
        &mut stream,
        &json!({"id":0,"args":["__source_kind",generation,kind],"source":"extractor"}),
    )?;
    let mut reader = BufReader::new(stream);
    let _ = transport::read_line(&mut reader, transport::CLIENT_FRAME)?;
    Ok(())
}

pub fn run(args: &[String]) -> Result<(), Box<dyn std::error::Error>> {
    let extractor = config::which("yt-dlp").ok_or("YouTube playback needs yt-dlp")?;
    let mut child = Command::new(extractor)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()?;
    let pinned = match Process::pin(child.id()) {
        Ok(process) => process,
        Err(error) => {
            let _ = child.kill();
            let _ = child.wait();
            return Err(error.into());
        }
    };
    let mut bytes = Vec::new();
    let read_result = child
        .stdout
        .take()
        .ok_or("extractor stdout unavailable")?
        .take((MAX_EXTRACTOR_JSON + 1) as u64)
        .read_to_end(&mut bytes);
    if read_result.is_err() || bytes.len() > MAX_EXTRACTOR_JSON {
        // Keep ownership of the whole extractor tree until it exits, including
        // the rare case where safe cancellation refuses a partial capture.
        let _ = pinned.terminate_tree();
        let _ = child.wait();
        read_result?;
        return Err("YouTube extraction response exceeded 8 MiB".into());
    }
    let result = child.wait()?;
    if !result.success() {
        return Err("YouTube extraction failed; see the player log".into());
    }
    let kind = serde_json::from_slice::<Value>(&bytes)
        .map(|value| source_kind(&value))
        .unwrap_or("unknown");
    // If the controller has closed, playback may finish without a timeline.
    // Never bootstrap another daemon or repeat the network extraction.
    let _ = notify_source(kind);
    io::stdout().lock().write_all(&bytes)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn live_and_unknown_sources_never_gain_recording_capabilities_from_duration() {
        assert_eq!(source_kind(&json!({"is_live":true,"duration":120})), "live");
        assert_eq!(source_kind(&json!({"duration":120})), "unknown");
        assert_eq!(
            source_kind(&json!({"is_live":false,"duration":120})),
            "recording"
        );
        assert_eq!(
            source_kind(&json!({"live_status":"was_live","duration":120})),
            "recording"
        );
        assert_eq!(
            source_kind(&json!({"is_live":false,"duration":null})),
            "unknown"
        );
        assert_eq!(
            source_kind(&json!({"is_live":false,"live_status":"is_upcoming","duration":120})),
            "live"
        );
    }
}
