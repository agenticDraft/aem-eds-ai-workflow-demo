#!/usr/bin/env python3
"""Classify a design node from its get_metadata XML.

Usage:
  classify-node.py <metadata-file>             the classification table
  classify-node.py <metadata-file> --question  the question text, or nothing
  classify-node.py <metadata-file> --options   one option label per candidate, or nothing

<metadata-file> holds the tool's response as returned; text before the first
element and after the root element closes is ignored.

The table, tab-separated:
  class  <single|page|multi-frame|variants>
  node   <type> <id> <width> <name>
  child  <id> <width> <role> <rule> <name>     one per frame-like child, document order

role is `variant` for a child classified as a viewport variant, `candidate`
for any other child of a page or multi-frame node, `-` otherwise. rule is the
first rule the child's own name or size matched, or `none`:
  name:pattern=<word>  `X / Desktop`, `Hero - Mobile`, `Desktop View`, `@mobile`
  name:keyword=<word>  a name token is desktop, mobile, tablet, responsive, phone or web
  name:width=<n>       a name token is 1440, 1280, 1024, 768, 375, 390 or 414 (optionally px)
  size                 a same-name sibling group holds one frame wider than 900
                       and one narrower than 500

Classes:
  page         the node is a page; every frame-like child is a candidate
  variants     every frame-like child belongs to one variant group of two or more
  multi-frame  a section, or a node whose children hold variants mixed with other
               frames or several variant groups; every frame-like child is a candidate
  single       anything else

Exit codes: 0 classified; 2 usage, unreadable or unparseable input.
"""

import re
import sys
import xml.etree.ElementTree as ET

FRAME_LIKE = {"frame", "instance", "symbol", "component", "component-set", "section"}
VIEWPORT_WORDS = ("desktop", "mobile", "tablet", "responsive", "phone", "web")
WIDTH_TOKENS = ("1440", "1280", "1024", "768", "375", "390", "414")
WIDE = 900
NARROW = 500

_VP = "|".join(VIEWPORT_WORDS)
PATTERNS = (
    re.compile(r"^.*\S\s*[/|\-–—:]\s*(" + _VP + r")(?:\s+view)?$"),
    re.compile(r"^(" + _VP + r")\s+view$"),
    re.compile(r"(?:^|\s)@(" + _VP + r")\b"),
)
WIDTH_TOKEN = re.compile(r"^(\d+)(?:px)?$")


def die(message):
    print("classify-node: " + message, file=sys.stderr)
    sys.exit(2)


def root_element(text):
    if re.search(r"<!(?:DOCTYPE|ENTITY)", text, re.IGNORECASE):
        die("a document type declaration is not accepted")
    start = re.search(r"<[A-Za-z]", text)
    if not start:
        die("no XML element in the input")
    parser = ET.XMLPullParser(events=("start", "end"))
    depth = 0
    root = None
    try:
        for segment in re.finditer(r"[^>]*>|[^>]+$", text[start.start():]):
            parser.feed(segment.group(0))
            for event, element in parser.read_events():
                if event == "start":
                    if root is None:
                        root = element
                    depth += 1
                else:
                    depth -= 1
                    if depth == 0:
                        return root
    except ET.ParseError as error:
        die("unparseable XML: " + str(error))
    die("the root element never closes")


def tokens(name):
    return re.findall(r"[a-z0-9]+", name.lower())


def name_rule(name):
    lowered = " ".join(name.lower().split())
    for pattern in PATTERNS:
        match = pattern.search(lowered)
        if match:
            return "name:pattern=" + match.group(1)
    toks = tokens(name)
    for tok in toks:
        if tok in VIEWPORT_WORDS:
            return "name:keyword=" + tok
    for tok in toks:
        match = WIDTH_TOKEN.match(tok)
        if match and match.group(1) in WIDTH_TOKENS:
            return "name:width=" + match.group(1)
    return None


def base_name(name):
    kept = []
    for tok in tokens(name):
        if tok in VIEWPORT_WORDS or tok == "view" or WIDTH_TOKEN.match(tok):
            continue
        kept.append(tok)
    return " ".join(kept)


def width_of(element):
    raw = element.get("width", "")
    try:
        return raw, float(raw)
    except ValueError:
        return raw, None


def clean(value):
    return " ".join((value or "").split())


def classify(root):
    children = [c for c in root if c.tag in FRAME_LIKE]
    rows = []
    groups = {}
    for child in children:
        raw, width = width_of(child)
        row = {
            "id": child.get("id", ""),
            "name": clean(child.get("name")),
            "raw_width": raw,
            "width": width,
            "rule": name_rule(child.get("name", "")),
            "variant": False,
        }
        rows.append(row)
        groups.setdefault(base_name(child.get("name", "")), []).append(row)

    variant_groups = 0
    for members in groups.values():
        if len(members) < 2:
            continue
        named = [m for m in members if m["rule"]]
        widths = [m["width"] for m in members if m["width"] is not None]
        by_size = bool(widths) and max(widths) > WIDE and min(widths) < NARROW
        if by_size:
            for m in members:
                m["variant"] = True
                if not m["rule"]:
                    m["rule"] = "size"
            variant_groups += 1
        elif len(named) >= 2:
            for m in named:
                m["variant"] = True
            variant_groups += 1

    variants = [r for r in rows if r["variant"]]
    if root.tag == "canvas":
        cls = "page"
    elif len(variants) >= 2 and len(variants) == len(rows) and variant_groups == 1:
        cls = "variants"
    elif root.tag == "section" or variants:
        cls = "multi-frame"
    else:
        cls = "single"

    for row in rows:
        if row["variant"]:
            row["role"] = "variant"
        elif cls in ("page", "multi-frame"):
            row["role"] = "candidate"
        else:
            row["role"] = "-"
        row["rule"] = row["rule"] or "none"
    return cls, rows


def main(argv):
    if len(argv) not in (2, 3):
        die("usage: classify-node.py <metadata-file> [--question|--options]")
    mode = argv[2] if len(argv) == 3 else None
    if mode not in (None, "--question", "--options"):
        die("unknown option " + mode)
    try:
        with open(argv[1], encoding="utf-8") as handle:
            text = handle.read()
    except OSError as error:
        die("cannot read " + argv[1] + ": " + error.strerror)

    root = root_element(text)
    cls, rows = classify(root)
    asks = cls in ("page", "multi-frame")
    labels = ["%s (%s)" % (r["name"], r["id"]) for r in rows]

    if mode == "--question":
        if asks:
            kind = {"canvas": "page", "section": "section"}.get(root.tag, "frame")
            print("The design reference is a %s holding %d frame%s; which one is the reference? %s"
                  % (kind, len(rows), "" if len(rows) == 1 else "s", "; ".join(labels)))
        return 0
    if mode == "--options":
        if asks:
            for label in labels:
                print(label)
        return 0

    print("class\t" + cls)
    print("node\t%s\t%s\t%s\t%s" % (root.tag, root.get("id", ""), root.get("width", ""),
                                   clean(root.get("name"))))
    for r in rows:
        print("child\t%s\t%s\t%s\t%s\t%s" % (r["id"], r["raw_width"], r["role"], r["rule"], r["name"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
