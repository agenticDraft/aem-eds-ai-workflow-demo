#!/usr/bin/env python3
# resolve-design-source.py <fact-record.yaml> <sanitized-spec.md> <fetched-item.json>
#
# Deterministic. Decides which of core contract §6.1's three design-source
# forms this item actually has, given the artifacts `intake` already wrote:
# the fact record's own design_source/design_mentioned booleans, the
# sanitized spec's plain text, and the raw fetched item (for its attachment
# list — `fetch_item`'s own JSON is where an image attachment's binary is
# addressable, per §6.1: "arrives through tracker.fetch_item, not the
# design role").
#
# A design-tool URL is detected the same way this pack's own intake stage
# detects one (host is figma.com or www.figma.com, the only design provider
# pack this project ships), applied to the identical sanitized text intake
# itself scanned — so this script's belief about a URL's presence always
# agrees with the fact record's design_source it is reading.
#
# Prints exactly one `decision=...` line to stdout and exits 0 for every
# outcome this script is able to determine at all, including a decline or an
# irreducible ambiguity — those are legitimate decisions, not errors. Only a
# usage error (bad arguments, an unreadable fact record) exits non-zero, so
# the caller can distinguish "I resolved this item's design source" from "I
# could not even read the input" without inspecting stdout.
#
# Exit codes: 0 always paired with a `decision=` line; 2 for a usage error.

import json
import os
import re
import sys


def usage_error(msg):
    print(
        f"usage: resolve-design-source.py <fact-record.yaml> <sanitized-spec.md> <fetched-item.json>\n{msg}",
        file=sys.stderr,
    )
    sys.exit(2)


URL_RE = re.compile(r"https?://\S+")
FIGMA_HOSTS = ("figma.com", "www.figma.com")


def find_design_url(text):
    for url in URL_RE.findall(text):
        host_match = re.match(r"https?://([^/]+)", url)
        if host_match and host_match.group(1).lower() in FIGMA_HOSTS:
            return url.rstrip(").,;")
    return None


def read_fact_record(path):
    """Flat `key: value` reader, the same shape every fact-record.yaml
    consumer in this project uses — one key per line, no nesting."""
    values = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            m = re.match(r"^([A-Za-z0-9_]+):\s*(.*)$", stripped)
            if not m:
                continue
            values[m.group(1)] = m.group(2).strip()
    return values


def as_bool(value):
    return (value or "").strip().lower() == "true"


def main():
    if len(sys.argv) != 4:
        usage_error("expected exactly 3 arguments")
    fact_record_path, sanitized_spec_path, fetched_item_path = sys.argv[1:4]

    if not os.path.isfile(fact_record_path):
        usage_error(f"'{fact_record_path}' not found")
    facts = read_fact_record(fact_record_path)

    design_source = as_bool(facts.get("design_source"))
    design_mentioned = as_bool(facts.get("design_mentioned"))

    if not design_source and not design_mentioned:
        print("decision=decline")
        sys.exit(0)

    spec_text = ""
    if os.path.isfile(sanitized_spec_path):
        with open(sanitized_spec_path, encoding="utf-8") as f:
            spec_text = f.read()

    design_url = find_design_url(spec_text)
    if design_url:
        print(f"decision=url reference={design_url}")
        sys.exit(0)

    image_attachments = []
    if os.path.isfile(fetched_item_path):
        with open(fetched_item_path, encoding="utf-8") as f:
            try:
                item = json.load(f)
            except json.JSONDecodeError:
                item = {}
        attachments = ((item.get("fields") or {}).get("attachment")) or []
        for a in attachments:
            mime = a.get("mimeType") or ""
            if mime.startswith("image/"):
                image_attachments.append(
                    {
                        "filename": a.get("filename") or "",
                        "content_url": a.get("content") or "",
                        "mime": mime,
                    }
                )

    if len(image_attachments) == 1:
        a = image_attachments[0]
        print(f"decision=image filename={a['filename']} content_url={a['content_url']} mime={a['mime']}")
        sys.exit(0)

    if len(image_attachments) > 1:
        filenames = ",".join(a["filename"] for a in image_attachments)
        print(f"decision=ambiguous count={len(image_attachments)} filenames={filenames}")
        sys.exit(0)

    print("decision=missing")
    sys.exit(0)


if __name__ == "__main__":
    main()
