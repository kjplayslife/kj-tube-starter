#!/usr/bin/env python3
"""Turn docs/specs/verses.md into KJTube/KJTube/Resources/verses.json (D43).

Run after editing the verse list:  python3 scripts/build_verses.py
"""
import json
import pathlib
import re

root = pathlib.Path(__file__).resolve().parent.parent
source = root / "docs/specs/verses.md"
target = root / "KJTube/KJTube/Resources/verses.json"

verses, theme = [], None
for line in source.read_text().splitlines():
    if line.startswith("## "):
        theme = line[3:].strip()
        continue
    row = re.match(r"^\|\s*(☐|☑|✓|✅|x|X)?\s*\|\s*([^|]+?)\s*\|\s*(.+?)\s*\|\s*$", line)
    if not row or theme is None or row.group(2) in ("Reference", "---"):
        continue
    verses.append({"reference": row.group(2), "text": row.group(3), "theme": theme})

target.write_text(json.dumps(verses, ensure_ascii=False, indent=1) + "\n")
print(f"Wrote {len(verses)} verses to {target.relative_to(root)}")
