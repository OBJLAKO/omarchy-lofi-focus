"""Resolve publisher RSS enclosures; usable in the cancellable feed worker."""
import os
from pathlib import Path
import time
import urllib.request
import xml.etree.ElementTree as ET


def resolve(url, destination):
    path = Path(destination)
    try:
        if path.exists() and time.time() - path.stat().st_mtime < 21600:
            return path
        request = urllib.request.Request(url, headers={"User-Agent": "LofiFocus/1.1"})
        urls = []
        with urllib.request.urlopen(request, timeout=10) as response:
            for event, element in ET.iterparse(response, events=("end",)):
                if element.tag == "enclosure":
                    u = element.get("url", "")
                    if u.startswith("https://") and not any(c in u for c in "\r\n"):
                        urls.append(u)
                        if len(urls) == 12:
                            break
                element.clear()
        if not urls:
            raise ValueError("No audio enclosures in podcast feed")
        temp = path.with_suffix(".tmp")
        temp.write_text("#EXTM3U\n" + "\n".join(urls) + "\n")
        os.replace(temp, path)
    except Exception as error:
        if not path.exists():
            raise ValueError(f"Podcast unavailable: {error}") from error
    return path
