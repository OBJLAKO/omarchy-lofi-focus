//! Bounded scene data and slow independent level modulation.
//! Random motion is a gain envelope, never a mutation of the saved faders.
use crate::config::{clean_title, level, valid_id, Catalog};
use serde_json::{json, Map, Value};
use std::collections::{HashMap, HashSet};

pub const MAX_LAYERS: usize = 16;
pub const MAX_SCENES: usize = 32;

pub fn layer(value: &Value) -> Value {
    let pan = value["pan"]
        .as_f64()
        .filter(|n| n.is_finite())
        .unwrap_or(0.0)
        .clamp(-100.0, 100.0);
    json!({"enabled":value["enabled"]==true,"volume":level(&value["volume"],25.0),
        "distance":level(&value["distance"],0.0),"pan":pan,
        "width":level(&value["width"],100.0),"softness":level(&value["softness"],0.0),
        "reflections":level(&value["reflections"],25.0),"echo":level(&value["echo"],0.0),
        "outside":value["outside"]==true,"living":value["living"]!=false})
}
pub fn room(value: &Value) -> Value {
    let preset = value["preset"]
        .as_str()
        .filter(|s| ["cozy", "cafe", "outside", "hall"].contains(s))
        .unwrap_or("cozy");
    json!({"preset":preset,"size":level(&value["size"],35.0),"softness":level(&value["softness"],55.0),"reflections":level(&value["reflections"],25.0)})
}
pub fn preset(name: &str) -> Option<Value> {
    let (size, softness, reflections) = match name {
        "cozy" => (35, 70, 20),
        "cafe" => (55, 40, 40),
        "outside" => (70, 90, 2),
        "hall" => (85, 15, 65),
        _ => return None,
    };
    Some(json!({"preset":name,"size":size,"softness":softness,"reflections":reflections}))
}
pub fn wander(value: &Value) -> Value {
    json!({"enabled":value["enabled"]==true,"amount":level(&value["amount"],35.0)})
}
fn layers(value: &Value) -> Value {
    let mut out = Map::new();
    let mut active = 0;
    if let Some(entries) = value.as_object() {
        for (id, v) in entries.iter().take(64) {
            if !valid_id(id) || !id.starts_with("noise-") || !v.is_object() {
                continue;
            }
            let mut v = layer(v);
            if v["enabled"] == true {
                active += 1;
                if active > MAX_LAYERS {
                    v["enabled"] = json!(false);
                }
            }
            out.insert(id.clone(), v);
        }
    }
    Value::Object(out)
}
fn scene_state(value: &Value) -> Option<Value> {
    let station = value["station"].as_str().filter(|s| valid_id(s))?;
    let bg = value["bgStation"].as_str().unwrap_or("");
    if !bg.is_empty() && !valid_id(bg) {
        return None;
    }
    Some(
        json!({"station":station,"bgStation":bg,"mix":value["mix"]==true,
        "mainVolume":level(&value["mainVolume"],65.0),"bgVolume":level(&value["bgVolume"],20.0),
        "natureLayers":layers(&value["natureLayers"]),"room":room(&value["room"]),"wander":wander(&value["wander"])}),
    )
}
pub fn normalize(settings: &mut Value) {
    settings["natureLayers"] = layers(&settings["natureLayers"]);
    settings["room"] = room(&settings["room"]);
    settings["wander"] = wander(&settings["wander"]);
    let mut scenes = Vec::new();
    let mut seen = HashSet::new();
    if let Some(entries) = settings["scenes"].as_array() {
        for entry in entries.iter().take(MAX_SCENES) {
            let Some(id) = entry["id"].as_str().filter(|id| valid_id(id)) else {
                continue;
            };
            let name = clean_title(entry["name"].as_str().unwrap_or(""))
                .chars()
                .take(40)
                .collect::<String>();
            if name.is_empty() || !seen.insert(id.to_owned()) {
                continue;
            }
            if let Some(state) = scene_state(&entry["state"]) {
                scenes.push(json!({"id":id,"name":name,"state":state}));
            }
        }
    }
    settings["scenes"] = json!(scenes);
    if !settings["sceneId"]
        .as_str()
        .is_some_and(|id| scenes.iter().any(|s| s["id"] == id))
    {
        settings["sceneId"] = json!("");
    }
    settings["spaceVersion"] = json!(1);
}
pub fn snapshot(settings: &Value, station: &str) -> Value {
    json!({"station":station,"bgStation":settings["bgStation"],"mix":settings["mix"],
        "mainVolume":settings["mainVolume"],"bgVolume":settings["bgVolume"],
        "natureLayers":settings["natureLayers"],"room":settings["room"],"wander":settings["wander"]})
}
pub fn validate(state: &Value, catalog: &Catalog) -> Result<(), String> {
    if !catalog.music.iter().any(|id| state["station"] == *id) {
        return Err(
            "The scene's soundtrack is missing. Choose a replacement and save again.".into(),
        );
    }
    if state["mix"] == true {
        let bg = state["bgStation"].as_str().unwrap_or("");
        if !bg.is_empty()
            && !catalog
                .entries
                .get(bg)
                .is_some_and(|s| !["lofi", "youtube", "ambience"].contains(&s.category.as_str()))
        {
            return Err("The scene's voice source is missing.".into());
        }
    }
    let mut active = 0;
    if let Some(entries) = state["natureLayers"].as_object() {
        for (id, v) in entries {
            if v["enabled"] == true {
                if !catalog.nature.contains(id) {
                    return Err(format!("The scene's sound {id} is missing."));
                }
                active += 1;
            }
        }
    }
    if active > MAX_LAYERS {
        return Err(format!(
            "A scene supports up to {MAX_LAYERS} active sounds."
        ));
    }
    Ok(())
}
pub fn dirty(settings: &Value, station: &str) -> bool {
    let id = settings["sceneId"].as_str().unwrap_or("");
    settings["scenes"]
        .as_array()
        .and_then(|s| s.iter().find(|s| s["id"] == id))
        .is_some_and(|s| s["state"] != snapshot(settings, station))
}

struct Envelope {
    from: f64,
    to: f64,
    elapsed: f64,
    duration: f64,
    gain: f64,
}
pub struct Wander {
    random: u64,
    envelopes: HashMap<String, Envelope>,
}
impl Wander {
    pub fn new(seed: u64) -> Self {
        Self {
            random: seed.max(1),
            envelopes: HashMap::new(),
        }
    }
    fn random(&mut self) -> f64 {
        self.random ^= self.random << 13;
        self.random ^= self.random >> 7;
        self.random ^= self.random << 17;
        (self.random >> 11) as f64 / ((1u64 << 53) as f64)
    }
    pub fn gain(&self, id: &str) -> f64 {
        self.envelopes.get(id).map(|e| e.gain).unwrap_or(1.0)
    }
    pub fn clear(&mut self) {
        self.envelopes.clear();
    }
    pub fn step(&mut self, seconds: f64, settings: &Value) -> bool {
        let on = settings["wander"]["enabled"] == true;
        let amount = level(&settings["wander"]["amount"], 35.0) / 100.0;
        let enabled: HashSet<_> = settings["natureLayers"]
            .as_object()
            .into_iter()
            .flatten()
            .filter(|(_, v)| v["enabled"] == true)
            .map(|(id, _)| id.clone())
            .collect();
        self.envelopes.retain(|id, _| enabled.contains(id));
        let mut changed = false;
        for id in enabled {
            let living = settings["natureLayers"][&id]["living"] != false;
            if !self.envelopes.contains_key(&id) {
                let duration = 18.0 + self.random() * 37.0;
                let to = if on && living {
                    1.0 - self.random() * amount * 0.8
                } else {
                    1.0
                };
                self.envelopes.insert(
                    id.clone(),
                    Envelope {
                        from: 1.0,
                        to,
                        elapsed: 0.0,
                        duration,
                        gain: 1.0,
                    },
                );
            }
            let e = self.envelopes.get_mut(&id).unwrap();
            if (!on || !living || amount == 0.0) && e.to != 1.0 {
                e.from = e.gain;
                e.to = 1.0;
                e.elapsed = 0.0;
                e.duration = 2.0;
            }
            e.elapsed += seconds.clamp(0.0, 2.0);
            let p = (e.elapsed / e.duration).min(1.0);
            let eased = p * p * (3.0 - 2.0 * p);
            let gain = e.from + (e.to - e.from) * eased;
            changed |= (gain - e.gain).abs() > 0.0001;
            e.gain = gain;
            if p >= 1.0 && on && living && amount > 0.0 {
                let from = e.gain;
                let to = 1.0 - self.random() * amount * 0.8;
                let duration = 18.0 + self.random() * 37.0;
                self.envelopes.insert(
                    id,
                    Envelope {
                        from,
                        to,
                        elapsed: 0.0,
                        duration,
                        gain: from,
                    },
                );
            }
        }
        changed
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn settings_bound_and_preserve_depth() {
        let mut s = json!({"natureLayers":{"noise-rain":{"enabled":true,"volume":0,"distance":80,"pan":-400,"echo":"NaN"},"../evil":{"enabled":true}},"room":{"preset":"unknown","size":900},"wander":{"enabled":true,"amount":900}});
        normalize(&mut s);
        assert_eq!(s["natureLayers"]["noise-rain"]["volume"], 0.0);
        assert_eq!(s["natureLayers"]["noise-rain"]["distance"], 80.0);
        assert_eq!(s["natureLayers"]["noise-rain"]["pan"], -100.0);
        assert_eq!(s["room"]["size"], 100.0);
        assert_eq!(s["wander"]["amount"], 100.0);
        assert!(s["natureLayers"].get("../evil").is_none());
        let first = s.clone();
        normalize(&mut s);
        assert_eq!(s, first);
    }
    #[test]
    fn independent_smooth_bounded_motion_and_return() {
        let mut s = json!({"natureLayers":{"noise-rain":{"enabled":true},"noise-wind":{"enabled":true},"noise-locked":{"enabled":true,"living":false}},"wander":{"enabled":true,"amount":80}});
        let mut w = Wander::new(42);
        let mut prior = 1.0;
        for _ in 0..600 {
            w.step(0.1, &s);
            let g = w.gain("noise-rain");
            assert!((0.36..=1.0).contains(&g));
            assert!((g - prior).abs() < 0.01);
            prior = g;
            assert_eq!(w.gain("noise-locked"), 1.0);
        }
        assert!((w.gain("noise-rain") - w.gain("noise-wind")).abs() > 0.001);
        s["wander"]["enabled"] = json!(false);
        for _ in 0..21 {
            w.step(0.1, &s);
        }
        assert_eq!(w.gain("noise-rain"), 1.0);
    }
    #[test]
    fn scenes_never_capture_master_or_runtime_motion() {
        let mut s = json!({"mainVolume":65,"bgVolume":20,"bgStation":"","mix":false,"masterVolume":1,"natureLayers":{}});
        normalize(&mut s);
        let v = snapshot(&s, "lofi-test");
        assert!(v.get("masterVolume").is_none());
        s["masterVolume"] = json!(100);
        assert_eq!(v, snapshot(&s, "lofi-test"));
    }
}
