#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist .build
python3 scripts/check_sources.py
# Explicit ordering excludes unfinished chapters and accidental README content.
mapfile -t inputs < <(find chapters -maxdepth 1 -name "[0-9][0-9]-*.md" -print | sort)
pandoc "${inputs[@]}" --metadata-file=metadata.yaml --standalone --toc --toc-depth=2 --highlight-style=tango --css=styles/epub.css --to=epub3 --output=dist/scaling-multi-cloud.epub
pandoc "${inputs[@]}" --metadata-file=metadata.yaml --standalone --toc --toc-depth=2 --highlight-style=tango --pdf-engine=xelatex --include-in-header=styles/pdf-header.tex -V documentclass=report --top-level-division=chapter -V geometry:margin=22mm -V mainfont="DejaVu Serif" -V monofont="DejaVu Sans Mono" -V fontsize=10pt --output=dist/scaling-multi-cloud.pdf
python3 scripts/check_epub.py
