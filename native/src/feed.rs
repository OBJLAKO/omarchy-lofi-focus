use crate::config::write_bytes;
use quick_xml::{events::Event, Reader};
use std::{io::Read, path::Path, time::Duration};
use url::Url;
const MAX_FEED: usize = 8 * 1024 * 1024;
pub fn https_url(input: &str) -> bool {
    if input.bytes().any(|c| c < 33 || c == 127) {
        return false;
    }
    Url::parse(input).is_ok_and(|url| {
        url.scheme() == "https"
            && url.host_str().is_some()
            && url.username().is_empty()
            && url.password().is_none()
    })
}
pub fn parse(bytes: &[u8]) -> Result<Vec<String>, String> {
    if bytes.len() > MAX_FEED {
        return Err("Podcast feed is too large".into());
    }
    let mut reader = Reader::from_reader(bytes);
    let mut urls = Vec::new();
    loop {
        match reader.read_event() {
            Ok(Event::DocType(_)) => return Err("Podcast feeds must not contain a DTD".into()),
            Ok(Event::Start(element)) | Ok(Event::Empty(element))
                if element.name().as_ref() == b"enclosure" =>
            {
                for attribute in element.attributes() {
                    let attribute = attribute.map_err(|e| e.to_string())?;
                    if attribute.key.as_ref() == b"url" {
                        let value = attribute
                            .unescape_value()
                            .map_err(|e| e.to_string())?
                            .into_owned();
                        if https_url(&value) && urls.len() < 12 {
                            urls.push(value);
                        }
                    }
                }
            }
            Ok(Event::Eof) => break,
            Err(e) => return Err(format!("Invalid podcast feed: {e}")),
            _ => {}
        }
    }
    if urls.is_empty() {
        return Err("No HTTPS audio enclosures in podcast feed".into());
    }
    Ok(urls)
}
pub fn resolve(url: &str, path: &Path) -> Result<(), String> {
    if !https_url(url) {
        return Err("Podcast feed must use HTTPS".into());
    }
    if std::fs::metadata(path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.elapsed().ok())
        .is_some_and(|age| age < Duration::from_secs(21600))
    {
        return Ok(());
    }
    let result = (|| {
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(10))
            .user_agent("Skylofi/3.0")
            .redirect(reqwest::redirect::Policy::custom(|attempt| {
                if attempt.previous().len() >= 5 {
                    attempt.error("too many podcast redirects")
                } else if https_url(attempt.url().as_str()) {
                    attempt.follow()
                } else {
                    attempt.error("podcast redirects must use HTTPS")
                }
            }))
            .build()
            .map_err(|e| e.to_string())?;
        let response = client
            .get(url)
            .send()
            .and_then(|response| response.error_for_status())
            .map_err(|e| e.to_string())?;
        if response
            .content_length()
            .is_some_and(|n| n > MAX_FEED as u64)
        {
            return Err("Podcast feed is too large".into());
        }
        let mut bytes = Vec::new();
        response
            .take(MAX_FEED as u64 + 1)
            .read_to_end(&mut bytes)
            .map_err(|e| e.to_string())?;
        let urls = parse(&bytes)?;
        write_bytes(path, format!("#EXTM3U\n{}\n", urls.join("\n")).as_bytes())
            .map_err(|e| e.to_string())
    })();
    if result.is_err() && path.is_file() {
        Ok(())
    } else {
        result
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_dtd_and_insecure_enclosures() {
        assert!(
            parse(b"<!DOCTYPE rss [<!ENTITY foo SYSTEM 'file:///etc/passwd'>]><rss/>").is_err()
        );
        let urls=parse(b"<rss><enclosure url='http://bad/a'/><enclosure url='https://ok.example/audio?a=1&amp;b=2'/></rss>").unwrap();
        assert_eq!(urls, vec!["https://ok.example/audio?a=1&b=2"]);
        assert!(!https_url("https://user:secret@ok.example/a"));
    }
}
