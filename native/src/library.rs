//! User-selected audio is copied to a bounded, private library.
use crate::config::{self, clean_title, valid_id, Paths};
use serde_json::{json, Value};
use std::{
    fs::{self, OpenOptions},
    io::Read,
    os::unix::fs::OpenOptionsExt,
    path::Path,
};
pub const MAX_FILES: usize = 24;
pub const MAX_BYTES: u64 = 64 * 1024 * 1024;
pub const MAX_LIBRARY_BYTES: u64 = 512 * 1024 * 1024;
pub fn normalize(settings: &mut Value) {
    let mut entries = Vec::new();
    if let Some(source) = settings["importedSounds"].as_array() {
        for item in source.iter().take(MAX_FILES) {
            let Some(id) = item["id"]
                .as_str()
                .filter(|id| valid_id(id) && id.starts_with("noise-user-"))
            else {
                continue;
            };
            let Some(file) = item["file"].as_str().filter(|file| safe_file(id, file)) else {
                continue;
            };
            if entries.iter().any(|e: &Value| e["id"] == id) {
                continue;
            }
            let name = clean_title(item["name"].as_str().unwrap_or("Imported sound"));
            entries.push(json!({"id":id,"name":name,"file":file}));
        }
    }
    settings["importedSounds"] = json!(entries);
}
pub fn safe_file(id: &str, file: &str) -> bool {
    file.rsplit_once('.').is_some_and(|(base, extension)| {
        base == id && ["ogg", "wav", "flac", "mp3"].contains(&extension)
    })
}
pub fn import(
    paths: &Paths,
    settings: &mut Value,
    path: &str,
    title: Option<&str>,
) -> Result<String, String> {
    if path.len() > 4096 || path.chars().any(char::is_control) {
        return Err("Invalid audio path.".into());
    }
    let source = Path::new(path);
    if !source.is_absolute() {
        return Err("Choose an absolute local audio path.".into());
    }
    let info = fs::symlink_metadata(source).map_err(|e| format!("Cannot open sound: {e}"))?;
    if !info.is_file() || info.len() == 0 || info.len() > MAX_BYTES {
        return Err("Choose a regular audio file up to 64 MiB.".into());
    }
    let extension = source
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    if !["ogg", "wav", "flac", "mp3"].contains(&extension.as_str()) {
        return Err("Supported formats: Ogg, WAV, FLAC and MP3.".into());
    }
    if settings["importedSounds"].as_array().unwrap().len() >= MAX_FILES {
        return Err("Your sound library is full (24 imported files).".into());
    }
    let directory = paths.state.join("sounds");
    config::private_directory(&directory).map_err(|e| e.to_string())?;
    let bytes = fs::read_dir(&directory)
        .map_err(|e| e.to_string())?
        .filter_map(Result::ok)
        .filter_map(|p| p.metadata().ok())
        .filter(|m| m.is_file())
        .map(|m| m.len())
        .sum::<u64>();
    if bytes.saturating_add(info.len()) > MAX_LIBRARY_BYTES {
        return Err("Imported sound storage is full (512 MiB).".into());
    }
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let id = format!("noise-user-{stamp:x}");
    let file = format!("{id}.{extension}");
    let mut input = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK)
        .open(source)
        .map_err(|e| e.to_string())?;
    let opened = input.metadata().map_err(|e| e.to_string())?;
    if !opened.is_file() || opened.len() == 0 || opened.len() > MAX_BYTES {
        return Err("Choose a regular audio file up to 64 MiB.".into());
    }
    let mut data = Vec::new();
    input
        .by_ref()
        .take(MAX_BYTES + 1)
        .read_to_end(&mut data)
        .map_err(|e| e.to_string())?;
    if data.len() as u64 > MAX_BYTES {
        return Err("Audio file grew beyond 64 MiB during import.".into());
    }
    if bytes.saturating_add(data.len() as u64) > MAX_LIBRARY_BYTES {
        return Err("Imported sound storage is full (512 MiB).".into());
    }
    config::write_bytes(&directory.join(&file), &data)
        .map_err(|e| format!("Cannot import sound: {e}"))?;
    if let Err(error) = crate::audio::validate_file(&directory.join(&file)) {
        let _ = fs::remove_file(directory.join(&file));
        return Err(format!("Unsupported or damaged audio: {error}"));
    }
    let name = clean_title(title.filter(|s| !s.trim().is_empty()).unwrap_or_else(|| {
        source
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("Imported sound")
    }));
    settings["importedSounds"]
        .as_array_mut()
        .unwrap()
        .push(json!({"id":id,"name":name,"file":file}));
    Ok(id)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn private_library_rejects_traversal_and_invalid_entries() {
        assert!(!safe_file("noise-user-1", "../noise-user-1.ogg"));
        assert!(!safe_file("noise-user-1", "noise-user-1.sh"));
        let mut s = json!({"importedSounds":[{"id":"noise-user-1","name":"rain\nwindow","file":"noise-user-1.ogg"},{"id":"noise-user-2","file":"/etc/passwd"}]});
        normalize(&mut s);
        assert_eq!(s["importedSounds"].as_array().unwrap().len(), 1);
        assert_eq!(s["importedSounds"][0]["name"], "rain window");
    }
}
