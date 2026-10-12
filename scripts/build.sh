#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist .build
python3 scripts/check_sources.py
mapfile -t inputs < <(find chapters -maxdepth 1 -name "[0-9][0-9]-*.md" -print | sort)
common=(--from=markdown+fenced_divs --metadata-file=metadata.yaml --standalone --toc --toc-depth=2 --lua-filter=filters/callouts.lua --highlight-style=styles/dracula.theme --syntax-definition=styles/hcl.xml)
pandoc "${inputs[@]}" "${common[@]}" --css=styles/epub.css --to=epub3 --epub-embed-font='fonts/*.otf' --epub-embed-font='fonts/*.ttf' --output=dist/scaling-multi-cloud.epub
pandoc "${inputs[@]}" "${common[@]}" --pdf-engine=xelatex --include-in-header=styles/book.tex -V documentclass=report --top-level-division=chapter -V geometry:margin=23mm -V mainfont=Inter -V sansfont=Inter -V monofont='JetBrains Mono' -V fontsize=11pt -V 'mainfontoptions=Path=fonts/,Extension=.otf,UprightFont=*-Regular,BoldFont=*-Bold,ItalicFont=*-Italic,BoldItalicFont=*-BoldItalic' -V 'sansfontoptions=Path=fonts/,Extension=.otf,UprightFont=*-Regular,BoldFont=*-Bold,ItalicFont=*-Italic,BoldItalicFont=*-BoldItalic' -V 'monofontoptions=Path=fonts/,Extension=.ttf,UprightFont=JetBrainsMono-Regular,BoldFont=JetBrainsMono-Bold,ItalicFont=JetBrainsMono-Italic,BoldItalicFont=JetBrainsMono-BoldItalic' --output=dist/scaling-multi-cloud.pdf
python3 scripts/check_epub.py
