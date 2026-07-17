#!/usr/bin/env python3
"""Initialize a design-handout folder for a Figma selection URL."""

from __future__ import annotations

import argparse
import json
import re
from datetime import date
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse


def slugify(value: str) -> str:
    value = unquote(value).strip().lower()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-") or "figma-selection"


def parse_figma_url(raw_url: str) -> tuple[str, str]:
    parsed = urlparse(raw_url)
    hostname = (parsed.hostname or "").lower()
    if hostname not in {"figma.com", "www.figma.com"}:
        raise ValueError("URL must use figma.com")

    parts = [part for part in parsed.path.split("/") if part]
    if len(parts) < 3 or parts[0] not in {"design", "file"}:
        raise ValueError("URL must point to a Figma design or file")

    query = parse_qs(parsed.query)
    node_values = query.get("node-id")
    if not node_values or not node_values[0].strip():
        raise ValueError("Figma selection URL must include a node-id")

    file_name = parts[2]
    node_id = node_values[0].strip()
    return file_name, node_id


def handout_template(url: str, node_id: str, title: str) -> str:
    return f"""# {title} — Design Handout

## Source and scope

- Figma selection: {url}
- Node ID: `{node_id}`
- Captured: {date.today().isoformat()}
- Inspection mode: read-only

## Screenshot index

![Selection overview](assets/selection-overview.png)

## Directly observed facts

### Geometry and layout

### Layer hierarchy and components

### Typography

### Colors and appearance

### Resizing and constraints

### Prototype and interaction behavior

### Assets and export requirements

## Inferences

## Ambiguities and designer questions

## Implementation guidance

## Completeness checklist

- [ ] Dimensions and internal spacing recorded
- [ ] Typography recorded
- [ ] Colors and appearance recorded
- [ ] Components and states recorded
- [ ] Resizing rules and constraints recorded
- [ ] Prototype interactions recorded
- [ ] Assets and export needs recorded
- [ ] Observed facts separated from inferences
- [ ] Screenshots saved under `assets/`
- [ ] No Figma changes made
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("url", help="Figma selection URL containing node-id")
    parser.add_argument("--root", default=".", help="Workspace root")
    parser.add_argument("--name", help="Optional output folder slug")
    args = parser.parse_args()

    file_name, node_id = parse_figma_url(args.url)
    normalized_node = slugify(node_id.replace(":", "-"))
    folder_name = slugify(args.name) if args.name else (
        f"{slugify(file_name)}-{normalized_node}"
    )

    handout_dir = Path(args.root).expanduser().resolve() / "design-handout" / folder_name
    assets_dir = handout_dir / "assets"
    assets_dir.mkdir(parents=True, exist_ok=True)

    handout_path = handout_dir / "handoud.md"
    if not handout_path.exists():
        title = unquote(file_name).replace("-", " ").strip().title()
        handout_path.write_text(
            handout_template(args.url, node_id, title),
            encoding="utf-8",
        )

    print(
        json.dumps(
            {
                "handout_dir": str(handout_dir),
                "handout_file": str(handout_path),
                "assets_dir": str(assets_dir),
                "node_id": node_id,
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
