"""Look for public-domain, verse-aligned English translations of the Gita.

Runs on a GitHub runner (open internet), not in the app or the build. It
only saves what it finds as an artifact for a human (or Claude) to review
before anything is imported and registered in sources.yaml.
"""

from __future__ import annotations

import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

UA = "GitaCompanionSourceDiscovery/1.0 (https://github.com/ChaitanyaGanesuni/virtual_mouse_controller)"
OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "discovery")
OUT.mkdir(parents=True, exist_ok=True)
WS = "https://en.wikisource.org/w/api.php"


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except Exception as e:
            err = e
            time.sleep(2 * (attempt + 1))
    return f"ERROR {err}".encode()


def ws(**params) -> dict:
    params |= {"format": "json", "formatversion": "2"}
    raw = get(WS + "?" + urllib.parse.urlencode(params))
    try:
        return json.loads(raw)
    except ValueError:
        return {"error": raw[:500].decode(errors="replace")}


def save(name: str, data: bytes | str | dict | list) -> None:
    path = OUT / name
    if isinstance(data, (dict, list)):
        path.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    elif isinstance(data, str):
        path.write_text(data, encoding="utf-8")
    else:
        path.write_bytes(data)


titles: set[str] = set()
for q in [
    "Bhagavad Gita",
    "Bhagavadgita",
    "Bhagavad-Gita",
    "Song Celestial",
    "Telang Bhagavadgita",
    "Swarupananda Gita",
    "Besant Bhagavad Gita",
    "Lord's Song Gita",
]:
    r = ws(action="query", list="search", srsearch=q, srlimit=50, srnamespace="0|104|106")
    save(f"ws_search_{q.replace(' ', '_')}.json", r)
    titles |= {h["title"] for h in r.get("query", {}).get("search", [])}

for prefix in [
    "The Bhagavad Gita",
    "Bhagavad Gita",
    "The Bhagavadgita",
    "Bhagavadgita",
    "Sacred Books of the East",
    "The Sacred Books of the East",
    "Srimad Bhagavad Gita",
    "The Bhagavad-Gita",
    "Bhagavad-Gita",
    "The Song Celestial",
    "The Lord's Song",
]:
    r = ws(action="query", list="allpages", apprefix=prefix, aplimit=500)
    save(f"ws_allpages_{prefix.replace(' ', '_')}.json", r)
    titles |= {p["title"] for p in r.get("query", {}).get("allpages", [])}

save("ws_titles.json", sorted(titles))

# Raw wikitext of promising pages (titles mentioning Gita), capped.
gita = sorted(t for t in titles if "gita" in t.lower() or "gītā" in t.lower())[:120]
pages = {}
for t in gita:
    r = ws(action="query", prop="revisions", rvprop="content", rvslots="main", titles=t)
    try:
        page = r["query"]["pages"][0]
        pages[t] = page["revisions"][0]["slots"]["main"]["content"][:6000]
    except (KeyError, IndexError):
        pages[t] = None
save("ws_pages_head.json", pages)

for name, url in {
    "st_sbe08_index.html": "https://sacred-texts.com/hin/sbe08/index.htm",
    "st_sbe08_ch2.html": "https://sacred-texts.com/hin/sbe08/sbe0805.htm",
    "st_gita_index.html": "https://sacred-texts.com/hin/gita/index.htm",
    "st_hin_index.html": "https://sacred-texts.com/hin/index.htm",
    "gutenberg_search.html": "https://www.gutenberg.org/ebooks/search/?query=bhagavad",
}.items():
    save(name, get(url))
print("saved", len(list(OUT.iterdir())), "files;", len(titles), "titles")

# Artifacts may not be downloadable from where the results are reviewed, so
# print a compact summary to the job log as well.
print("=== TITLES ===")
for t in sorted(titles):
    print("T|", t)
print("=== PAGE HEADS ===")
for t, text in pages.items():
    print(f"P| {t} | {len(text or '')} chars")
    if text:
        print("\n".join("  " + line for line in text[:1500].splitlines()[:40]))
for name in ["st_sbe08_index.html", "st_sbe08_ch2.html", "st_gita_index.html"]:
    raw = (OUT / name).read_bytes()[:20000].decode("utf-8", "replace")
    import re as _re

    text = _re.sub(r"<[^>]+>", " ", raw)
    text = _re.sub(r"\s+", " ", text)
    print(f"=== {name} ===")
    print(text[:3000])
