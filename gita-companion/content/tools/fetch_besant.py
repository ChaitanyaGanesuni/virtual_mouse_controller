"""Fetch the proofread Wikisource transcription of Annie Besant's
Bhagavad-Gita, 4th edition (G. A. Natesan & Co., Madras, 1922).

Runs on a GitHub runner (this repository's build sandbox cannot reach
Wikisource). Prints one JSON line per page ("PAGE\\t{...}") with the page
number, revision id and wikitext, so the snapshot can be reviewed and
committed under content/sources/besant-1922/ with exact revision ids.
"""

from __future__ import annotations

import json
import time
import urllib.parse
import urllib.request

UA = "GitaCompanionSourceFetch/1.0 (https://github.com/ChaitanyaGanesuni/virtual_mouse_controller)"
API = "https://en.wikisource.org/w/api.php"
PREFIX = "Page:Bhagavad Gita - Annie Besant 4th edition.djvu/"
INDEX = "Index:Bhagavad Gita - Annie Besant 4th edition.djvu"


def call(**params) -> dict:
    params |= {"format": "json", "formatversion": "2"}
    req = urllib.request.Request(API + "?" + urllib.parse.urlencode(params), headers={"User-Agent": UA})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read())
        except Exception as e:
            print("retry", attempt, e)
            time.sleep(3 * (attempt + 1))
    raise SystemExit("Wikisource did not answer")


index = call(action="query", prop="revisions", rvprop="content|ids", rvslots="main", titles=INDEX)
page = index["query"]["pages"][0]
print(
    "INDEX\t"
    + json.dumps(
        {
            "revid": page.get("revisions", [{}])[0].get("revid"),
            "text": page.get("revisions", [{}])[0].get("slots", {}).get("main", {}).get("content"),
        },
        ensure_ascii=False,
    )
)

found = 0
for start in range(1, 321, 40):
    titles = [f"{PREFIX}{n}" for n in range(start, start + 40)]
    r = call(
        action="query",
        prop="revisions",
        rvprop="content|ids|timestamp",
        rvslots="main",
        titles="|".join(titles),
    )
    for p in r["query"]["pages"]:
        if p.get("missing"):
            continue
        rev = p["revisions"][0]
        n = int(p["title"].rsplit("/", 1)[1])
        found += 1
        print(
            "PAGE\t"
            + json.dumps(
                {
                    "n": n,
                    "revid": rev["revid"],
                    "timestamp": rev["timestamp"],
                    "text": rev["slots"]["main"]["content"],
                },
                ensure_ascii=False,
            )
        )
    time.sleep(1)
print("FOUND", found)
