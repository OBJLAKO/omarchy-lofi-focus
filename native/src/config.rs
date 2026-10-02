use serde_json::{json, Value};
use std::{
    collections::{HashMap, HashSet},
    fs::{self, OpenOptions},
    io::{self, Read, Write},
    os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt},
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
};
use url::Url;

pub const MAX_JSON: usize = 1024 * 1024;
static TEMPORARY: AtomicU64 = AtomicU64::new(0);

#[derive(Clone)]
pub struct Paths {
    pub root: PathBuf,
    pub runtime: PathBuf,
    pub state: PathBuf,
    pub xdg_runtime: PathBuf,
    pub config: PathBuf,
}
impl Paths {
    pub fn new(root: PathBuf) -> io::Result<Self> {
        let home = std::env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/tmp"));
        let xdg_runtime = std::env::var_os("XDG_RUNTIME_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(format!("/run/user/{}", unsafe { libc::geteuid() })));
        let state = std::env::var_os("XDG_STATE_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(".local/state"))
            .join("sky.lofi");
        let config = std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(".config"));
        let paths = Self {
            root,
            runtime: xdg_runtime.join("sky.lofi"),
            state,
            xdg_runtime,
            config,
        };
        for path in [
            &paths.runtime,
            &paths.state,
            &paths.runtime.join("sockets"),
            &paths.runtime.join("logs"),
        ] {
            private_directory(path)?;
        }
        Ok(paths)
    }
    pub fn socket(&self) -> PathBuf {
        self.runtime.join("controller.sock")
    }
}
pub fn private_directory(path: &Path) -> io::Result<()> {
    fs::create_dir_all(path)?;
    let info = fs::symlink_metadata(path)?;
    if !info.is_dir() || info.uid() != unsafe { libc::geteuid() } {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            "runtime/state must be an owned directory, never a symlink",
        ));
    }
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))
}
pub fn read_json(path: &Path) -> Value {
    let mut bytes = Vec::new();
    if fs::File::open(path)
        .and_then(|f| f.take((MAX_JSON + 1) as u64).read_to_end(&mut bytes))
        .is_err()
        || bytes.len() > MAX_JSON
    {
        return json!({});
    }
    match serde_json::from_slice::<Value>(&bytes) {
        Ok(v) if v.is_object() => v,
        _ => json!({}),
    }
}
pub fn write_bytes(path: &Path, bytes: &[u8]) -> io::Result<()> {
    if fs::read(path).is_ok_and(|old| old == bytes) {
        return Ok(());
    }
    let tmp = path.with_file_name(format!(
        ".{}.{}.{}",
        path.file_name().unwrap().to_string_lossy(),
        std::process::id(),
        TEMPORARY.fetch_add(1, Ordering::Relaxed)
    ));
    let result = (|| {
        let mut output = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .custom_flags(libc::O_NOFOLLOW)
            .open(&tmp)?;
        output.write_all(bytes)?;
        fs::rename(&tmp, path)
    })();
    let _ = fs::remove_file(&tmp);
    result
}
pub fn write_json(path: &Path, value: &Value) -> io::Result<()> {
    let mut bytes = serde_json::to_vec_pretty(value)?;
    bytes.push(b'\n');
    write_bytes(path, &bytes)
}
pub fn level(value: &Value, default: f64) -> f64 {
    value
        .as_f64()
        .or_else(|| value.as_str().and_then(|s| s.parse().ok()))
        .filter(|n| n.is_finite())
        .unwrap_or(default)
        .clamp(0.0, 100.0)
}
pub fn number(settings: &Value, key: &str) -> f64 {
    level(&settings[key], 0.0)
}
pub fn enabled(settings: &Value, key: &str) -> bool {
    settings[key].as_bool().unwrap_or(true)
}
pub fn valid_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 80 && id.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-')
}
pub fn canonical_url(input: &str) -> Result<String, String> {
    if input.len() > 2048 {
        return Err("Paste a YouTube video link (up to 2048 characters).".into());
    }
    let text = input.trim();
    if text.bytes().any(|c| c < 33 || c == 127) {
        return Err("Paste a valid YouTube video link.".into());
    }
    let prefixed = if [
        "youtube.com/",
        "www.youtube.com/",
        "m.youtube.com/",
        "music.youtube.com/",
        "youtu.be/",
    ]
    .iter()
    .any(|prefix| text.starts_with(prefix))
    {
        format!("https://{text}")
    } else {
        text.into()
    };
    let failure = || {
        "Use a YouTube video, Shorts or live link; playlists and other sites are not supported."
            .to_owned()
    };
    let url = Url::parse(&prefixed).map_err(|_| failure())?;
    if url.scheme() != "https"
        || !url.username().is_empty()
        || url.password().is_some()
        || url.port().is_some_and(|port| port != 443)
    {
        return Err(failure());
    }
    let host = url.host_str().unwrap_or("");
    let parts: Vec<_> = url.path().trim_matches('/').split('/').collect();
    let id = if host == "youtu.be" && parts.len() == 1 {
        parts[0].to_owned()
    } else if [
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "music.youtube.com",
    ]
    .contains(&host)
    {
        if url.path() == "/watch" {
            let ids: Vec<_> = url
                .query_pairs()
                .filter(|(key, _)| key == "v")
                .map(|(_, v)| v.into_owned())
                .collect();
            if ids.len() == 1 {
                ids[0].clone()
            } else {
                String::new()
            }
        } else if parts.len() == 2 && ["shorts", "live", "embed"].contains(&parts[0]) {
            parts[1].into()
        } else {
            String::new()
        }
    } else {
        String::new()
    };
    if id.len() != 11
        || !id
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || c == b'_' || c == b'-')
    {
        return Err(failure());
    }
    Ok(format!("https://www.youtube.com/watch?v={id}"))
}
pub fn clean_title(text: &str) -> String {
    text.split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .chars()
        .take(160)
        .collect()
}
pub fn preferences(mut value: Value) -> Value {
    if !value.is_object() {
        value = json!({});
    }
    for (key, default) in [
        ("mainVolume", 65.0),
        ("bgVolume", 20.0),
        ("masterVolume", 100.0),
        ("natureVolume", 25.0),
        ("noiseVolume", 25.0),
        ("duckLevel", 35.0),
        ("fadeSeconds", 3.0),
        ("revealSpeed", 1.0),
    ] {
        value[key] = json!(level(&value[key], default));
    }
    for (key, default) in [
        ("mix", true),
        ("ducking", true),
        ("animations", true),
        ("revealAnimations", true),
        ("steamAnimation", true),
        ("glowAnimation", true),
        ("equalizerAnimation", true),
        ("fadeEnabled", true),
        ("collapsibleSections", true),
    ] {
        if !value[key].is_boolean() {
            value[key] = json!(default);
        }
    }
    for (key, default) in [
        ("defaultStation", "lofi-lilo"),
        ("bgStation", "talk-bbc-world"),
        ("noiseStation", "off"),
    ] {
        if !value[key].is_string() {
            value[key] = json!(default);
        }
    }
    if value.get("natureLayers").is_none() {
        let id = value["noiseStation"].as_str().unwrap_or("off").to_owned();
        value["natureLayers"] = if valid_id(&id) && id.starts_with("noise-") {
            json!({id:{"enabled":true,"volume":100}})
        } else {
            json!({})
        };
        value["natureVolume"] = value["noiseVolume"].clone();
    }
    let mut layers = serde_json::Map::new();
    if let Some(source) = value["natureLayers"].as_object() {
        for (id, layer) in source {
            if valid_id(id) && id.starts_with("noise-") && layer.is_object() {
                layers.insert(id.clone(), json!({"enabled":layer["enabled"] == true,"volume":level(&layer["volume"],25.0)}));
            }
        }
    }
    if value["natureMixVersion"] != 2 {
        let gain = number(&value, "natureVolume") / 100.0;
        for layer in layers.values_mut() {
            layer["volume"] = json!(level(&layer["volume"], 25.0) * gain);
        }
        value["natureMixVersion"] = json!(2);
        value["natureVolume"] = json!(100.0);
    }
    value["natureLayers"] = Value::Object(layers);
    let mut videos = vec![];
    let mut seen = HashSet::new();
    if let Some(source) = value["youtube"].as_array() {
        for entry in source {
            if let Some(raw) = entry["url"].as_str() {
                if let Ok(url) = canonical_url(raw) {
                    let video = url.rsplit('=').next().unwrap();
                    let id = format!("youtube-{video}");
                    if !seen.insert(id.clone()) {
                        continue;
                    }
                    let title = entry["name"]
                        .as_str()
                        .filter(|s| !s.is_empty())
                        .map(clean_title)
                        .unwrap_or_else(|| format!("YouTube · {video}"));
                    let position = entry["position"]
                        .as_f64()
                        .filter(|n| n.is_finite() && *n >= 0.0 && *n < 604800.0)
                        .unwrap_or(0.0);
                    videos.push(json!({"id":id,"name":title,"url":url,"position":(position*10.0).round()/10.0}));
                    if videos.len() == 40 {
                        break;
                    }
                }
            }
        }
    }
    value["youtube"] = json!(videos);
    value
}
#[derive(Clone)]
pub struct Station {
    pub id: String,
    pub name: String,
    pub url: String,
    pub category: String,
    pub category_name: String,
    pub kind: String,
    pub position: f64,
}
pub struct Catalog {
    pub entries: HashMap<String, Station>,
    pub music: Vec<String>,
    pub nature: Vec<String>,
}
impl Catalog {
    pub fn load(root: &Path, settings: &Value) -> Self {
        let mut catalog = Self {
            entries: HashMap::new(),
            music: vec![],
            nature: vec![],
        };
        let raw = read_json(&root.join("stations.json"));
        for category in raw["categories"].as_array().into_iter().flatten() {
            let (Some(category_id), Some(category_name)) =
                (category["id"].as_str(), category["name"].as_str())
            else {
                continue;
            };
            for station in category["stations"].as_array().into_iter().flatten() {
                let (Some(id), Some(name), Some(url)) = (
                    station["id"].as_str(),
                    station["name"].as_str(),
                    station["url"].as_str(),
                ) else {
                    continue;
                };
                if !valid_id(id) || url.len() > 8192 {
                    continue;
                }
                catalog.entries.insert(
                    id.into(),
                    Station {
                        id: id.into(),
                        name: clean_title(name),
                        url: url.into(),
                        category: category_id.into(),
                        category_name: clean_title(category_name),
                        kind: station["kind"].as_str().unwrap_or("").into(),
                        position: 0.0,
                    },
                );
                if category_id == "lofi" {
                    catalog.music.push(id.into());
                }
                if category_id == "ambience" {
                    catalog.nature.push(id.into());
                }
            }
        }
        for entry in settings["youtube"].as_array().into_iter().flatten() {
            let id = entry["id"].as_str().unwrap().to_owned();
            catalog.entries.insert(
                id.clone(),
                Station {
                    id: id.clone(),
                    name: entry["name"].as_str().unwrap().into(),
                    url: entry["url"].as_str().unwrap().into(),
                    category: "youtube".into(),
                    category_name: "YouTube".into(),
                    kind: "youtube".into(),
                    position: entry["position"].as_f64().unwrap_or(0.0),
                },
            );
            catalog.music.push(id);
        }
        catalog
    }
}
pub fn which(name: &str) -> Option<PathBuf> {
    std::env::var_os("PATH").and_then(|paths| {
        std::env::split_paths(&paths)
            .map(|p| p.join(name))
            .find(|p| {
                fs::metadata(p).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
            })
    })
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn youtube_is_strict() {
        assert_eq!(
            canonical_url("https://youtu.be/abcdefghijk?t=30").unwrap(),
            "https://www.youtube.com/watch?v=abcdefghijk"
        );
        for s in [
            "http://youtu.be/abcdefghijk",
            "https://youtube.com.evil/watch?v=abcdefghijk",
            "https://user@youtu.be/abcdefghijk",
            "https://youtube.com/watch?v=abcdefghijk&v=zyxwvutsrqp",
            "https://youtube.com/playlist?list=PL",
            "https://youtu.be/abcdefghijk\nfoo",
        ] {
            assert!(canonical_url(s).is_err(), "{s}");
        }
    }
    #[test]
    fn corrupt_settings_recover_and_migrate() {
        let p = preferences(
            json!({"masterVolume":"NaN","mix":[],"natureLayers":{"../evil":{},"noise-rain":{"enabled":true,"volume":80}},"natureVolume":25}),
        );
        assert_eq!(p["masterVolume"], 100.0);
        assert_eq!(p["mix"], true);
        assert_eq!(p["natureLayers"]["noise-rain"]["volume"], 20.0);
        assert!(p["natureLayers"].get("../evil").is_none());
        assert_eq!(preferences(p.clone()), p);
    }
}
