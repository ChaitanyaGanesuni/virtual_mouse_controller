"""Download catalog and pack files (offline packs for the app)."""

from __future__ import annotations

import hashlib
import json
import sqlite3

import pytest
from gita_content.pack import write_pack

from app.modules.packs.catalog import CONTENT_PACK, PackCatalog


@pytest.fixture(scope="module")
def packs_dir(tmp_path_factory, dataset):
    d = tmp_path_factory.mktemp("packs")
    write_pack(dataset, d / CONTENT_PACK)
    (d / "extra.json").write_text(
        json.dumps(
            [
                {
                    "id": "recitation-ch1",
                    "kind": "audio",
                    "title": "Chapter 1 recitation",
                    "version": "1",
                    "size": 10,
                    "sha256": "0" * 64,
                    "url": "https://cdn.example.org/recitation-ch1.zip",
                },
                {
                    "id": "insecure",
                    "kind": "audio",
                    "title": "x",
                    "version": "1",
                    "size": 1,
                    "sha256": "0" * 64,
                    "url": "http://cdn.example.org/x.zip",
                },
                {"id": "incomplete", "kind": "audio"},
            ]
        )
    )
    return d


@pytest.fixture
def client(make_client, packs_dir):
    c, _ = make_client(packs=PackCatalog.load(packs_dir), downloads_per_ip_per_hour=3)
    return c


def test_catalog_describes_the_content_pack(client, packs_dir, dataset):
    r = client.get("/v1/packs")
    assert r.status_code == 200
    packs = {p["id"]: p for p in r.json()["packs"]}
    assert set(packs) == {"content", "recitation-ch1"}, "invalid extra entries are skipped"
    content = packs["content"]
    data = (packs_dir / CONTENT_PACK).read_bytes()
    assert content["size"] == len(data)
    assert content["sha256"] == hashlib.sha256(data).hexdigest()
    assert content["content_hash"] == dataset["content_hash"]
    assert content["pack_schema_version"] == 3
    assert content["url"] == f"/v1/packs/files/{CONTENT_PACK}"
    db = sqlite3.connect(packs_dir / CONTENT_PACK)
    assert (
        content["version"] == db.execute("SELECT value FROM pack_meta WHERE key = 'built_at'").fetchone()[0]
    )


def test_download_whole_and_resumed(client, packs_dir):
    data = (packs_dir / CONTENT_PACK).read_bytes()
    url = f"/v1/packs/files/{CONTENT_PACK}"
    full = client.get(url)
    assert full.status_code == 200 and full.content == data
    assert full.headers["accept-ranges"] == "bytes"
    assert full.headers["etag"].strip('"') == hashlib.sha256(data).hexdigest()
    # Interrupted after 1000 bytes: the app asks for the rest.
    rest = client.get(url, headers={"Range": "bytes=1000-"})
    assert rest.status_code == 206
    assert data[:1000] + rest.content == data
    assert client.head(url).headers["content-length"] == str(len(data))


def test_only_catalogued_files_are_served(client):
    for name in ("nope.sqlite", "..%2F..%2Fapp%2Fmain.py", "extra.json"):
        r = client.get(f"/v1/packs/files/{name}")
        assert r.status_code == 404, name


def test_new_downloads_are_rate_limited_but_resumes_are_not(client):
    url = f"/v1/packs/files/{CONTENT_PACK}"
    for _ in range(3):
        assert client.get(url).status_code == 200
    assert client.get(url).status_code == 429
    assert client.get(url, headers={"Range": "bytes=10-"}).status_code == 206


def test_no_packs_directory_means_an_empty_catalog(make_client, tmp_path):
    c, _ = make_client(packs=PackCatalog.load(tmp_path / "missing"))
    assert c.get("/v1/packs").json() == {"packs": []}
