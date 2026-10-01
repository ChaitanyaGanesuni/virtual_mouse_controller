#!/usr/bin/env bash
# Rebuild the bundled content pack from the committed dataset
# (content/data/gita.json). Requires the content pipeline:
#   pip install -e ../content
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
gita-content pack \
  --dataset "$here/../content/data/gita.json" \
  --pack "$here/assets/content/gita_content_pack.sqlite" \
  --manifest "$here/assets/content/pack_manifest.json"
