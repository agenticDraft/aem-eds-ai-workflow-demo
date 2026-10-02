#!/usr/bin/env python3
# resolve-verify-target.py <fact-record.yaml> <sanitized-spec.md> <tracker-pack.yaml> <preview-url>
#
# Deterministic. Decides what the verify stage points a browser at, in order:
#   1. the fact record's `components`;
#   2. every distinct <name> in `files_named` paths of the form blocks/<name>/...;
#   3. the first URL under a heading the tracker pack lists in its
#      text_conventions `reproduction_headings`, when its host is the local
#      preview host or the platform's own delivery host (*.aem.page,
#      *.aem.live). Only its path is kept: the page is rendered from the
#      local preview origin, so the run checks its own working tree.
#
# Prints one line:
#   target=blocks names=<a,b>
#   target=page path=</path> source=<url as written>
#   target=none reason=<why>
#
# Exit codes: 0 a target was found; 1 none; 2 usage error.

import os
import re
import sys

URL_RE = re.compile(r"https?://\S+")
HEADING_RE = re.compile(r"^#{1,6}\s+(.*?)\s*$")
DELIVERY_HOST_RE = re.compile(r"\.aem\.(page|live)$")


def usage_error(msg):
    print(f"usage error: {msg}", file=sys.stderr)
    print("usage: resolve-verify-target.py <fact-record.yaml> <sanitized-spec.md> <tracker-pack.yaml> <preview-url>", file=sys.stderr)
    sys.exit(2)


def read_list(fact_record_path, key):
    """A one-line `key: [a, b]` list, the shape the intake extractor writes."""
    with open(fact_record_path, encoding="utf-8") as f:
        for line in f:
            m = re.match(rf"^{key}:\s*\[(.*)\]\s*$", line)
            if m:
                return [v.strip() for v in m.group(1).split(",") if v.strip()]
    return []


def reproduction_headings(pack_yaml_path):
    if not os.path.isfile(pack_yaml_path):
        return []
    with open(pack_yaml_path, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^\s\sreproduction_headings:\s\[(.*)\]$", line.rstrip("\n"))
            if m:
                return [v.strip() for v in m.group(1).split(",") if v.strip()]
    return []


def url_host(url):
    m = re.match(r"https?://([^/:?#]+)", url)
    return m.group(1).lower() if m else None


def first_reproduction_url(spec_path, headings):
    """The first URL inside a section whose heading is one of `headings`
    (case-insensitive, whole heading text). A section ends at the next heading."""
    wanted = {h.lower() for h in headings}
    inside = False
    with open(spec_path, encoding="utf-8") as f:
        for line in f:
            m = HEADING_RE.match(line)
            if m:
                inside = m.group(1).lower() in wanted
                continue
            if inside:
                found = URL_RE.search(line)
                if found:
                    return found.group(0).rstrip(".,;:)\"'`")
    return None


def main():
    if len(sys.argv) != 5:
        usage_error("expected exactly 4 arguments")
    fact_record, spec, pack_yaml, preview = sys.argv[1:5]
    for path in (fact_record, spec):
        if not os.path.isfile(path):
            usage_error(f"'{path}' not found")

    components = read_list(fact_record, "components")
    if components:
        print(f"target=blocks names={','.join(components)}")
        return 0

    names = []
    for path in read_list(fact_record, "files_named"):
        m = re.match(r"^blocks/([\w-]+)/", path)
        if m and m.group(1) not in names:
            names.append(m.group(1))
    if names:
        print(f"target=blocks names={','.join(names)}")
        return 0

    headings = reproduction_headings(pack_yaml)
    url = first_reproduction_url(spec, headings) if headings else None
    if url is None:
        print("target=none reason=no block in components or files_named, and no URL under a reproduction heading")
        return 1

    host = url_host(url)
    if host != url_host(preview) and not (host and DELIVERY_HOST_RE.search(host)):
        print(f"target=none reason=the reproduction URL's host {host} is neither the local preview nor the platform's delivery host")
        return 1

    path = re.sub(r"^https?://[^/?#]+", "", url).split("?")[0].split("#")[0] or "/"
    print(f"target=page path={path} source={url}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
