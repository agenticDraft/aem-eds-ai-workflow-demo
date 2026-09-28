#!/usr/bin/env python3
# Run: python3 plugins/eds/skills/eds-prototype/scripts/place-assets.py .ai/run-context/design-reference.json <item_id> <node_id>...
#
# place-assets.py <design-reference.json> <item_id> <node_id>...
#
# Deterministic. Run from the project root. Places the downloaded asset files
# the prototype uses, found only through `design-reference.json`'s `assets`
# list (node id -> local file), never through a URL or the reference code's
# asset constants. Every entry for each named node is placed:
#
#   image/svg+xml   icons/<name>.svg, used as <span class="icon icon-<name>"></span>
#                   <name> is the node's layer name (`data-name` in the reference
#                   code, then in each viewport variant's code), lower-cased, every
#                   run of other characters than a-z and 0-9 turned into one `-`,
#                   trimmed. A node with no layer name, or one that slugifies to
#                   nothing, is named by the first 16 hex of its bytes' SHA-256.
#   raster          drafts/<item_id>-<sha16>.<ext>, next to the draft, used as
#                   ./<item_id>-<sha16>.<ext>; <sha16> is taken from the bytes.
#
# It prints one tab-separated row per placed entry, in argument order (a node
# named twice is placed once):
#
#   placed    <node> <mime> <dest> <reference>        written by this run
#   reused    <node> <mime> <dest> <reference>        identical bytes already there
#   collision <node> <mime> <dest> <asset file> <held by>
#
# A collision is an icon name already held by different bytes: <held by> is
# the existing file on disk, or the other asset file this run would place
# there. An existing file is never overwritten. With any collision, nothing
# at all is written.
#
# Exit codes: 0 — every entry placed or reused; 4 — at least one collision,
# nothing written; 2 — refused, nothing written and nothing printed: bad
# arguments, an item id holding `/` or `..`, an unreadable reference, no
# `assets` list, a node the list does not name, an asset file that is missing
# or given as a URL, an unsupported MIME type, or a draft photo name already
# holding other bytes.

import hashlib
import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("design_context_values", os.path.join(HERE, "design-context-values.py"))
dcv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dcv)

RASTER_EXT = {"image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/webp": "webp"}
SVG = "image/svg+xml"


class Refused(Exception):
    pass


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def layer_names(ref):
    files = []
    context = ref.get("design_context")
    if isinstance(context, dict) and isinstance(context.get("code_file"), str):
        files.append(context["code_file"])
    for variant in ref.get("viewports") or []:
        if isinstance(variant, dict) and isinstance(variant.get("context"), str):
            files.append(variant["context"])
    names = {}
    for path in files:
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8") as handle:
            code = handle.read()
        for attrs in dcv.elements(code):
            node, name = attrs.get("data-node-id"), attrs.get("data-name")
            if node and name and node not in names:
                names[node] = name
    return names


def read_reference(path):
    if not os.path.isfile(path):
        raise Refused(f"'{path}' not found")
    try:
        with open(path, encoding="utf-8") as handle:
            ref = json.load(handle)
    except (OSError, ValueError) as error:
        raise Refused(f"'{path}' is not readable JSON: {error}")
    if not isinstance(ref, dict) or not isinstance(ref.get("assets"), list):
        raise Refused(f"'{path}' has no assets list")
    return ref


def plan(ref, item_id, nodes):
    names = layer_names(ref)
    entries = []
    for node in dict.fromkeys(nodes):
        found = [a for a in ref["assets"] if isinstance(a, dict) and a.get("node_id") == node]
        if not found:
            raise Refused(f"node {node} has no entry in the assets list")
        for asset in found:
            source, mime = asset.get("file"), asset.get("mime")
            if not isinstance(source, str) or "://" in source:
                raise Refused(f"node {node}: asset file must be a local path")
            if not os.path.isfile(source):
                raise Refused(f"node {node}: asset file not found: {source}")
            if mime != SVG and mime not in RASTER_EXT:
                raise Refused(f"node {node}: unsupported MIME type: {mime}")
            with open(source, "rb") as handle:
                data = handle.read()
            sha16 = hashlib.sha256(data).hexdigest()[:16]
            if mime == SVG:
                name = slug(names.get(node, "")) or sha16
                dest = f"icons/{name}.svg"
                reference = f'<span class="icon icon-{name}"></span>'
            else:
                file = f"{item_id}-{sha16}.{RASTER_EXT[mime]}"
                dest = f"drafts/{file}"
                reference = f"./{file}"
            entries.append((node, mime, source, data, dest, reference))
    return entries


def resolve(entries):
    rows, claimed, writes = [], {}, []
    for node, mime, source, data, dest, reference in entries:
        if dest in claimed:
            held_source, held_data = claimed[dest]
            if held_data == data:
                rows.append(("reused", node, mime, dest, reference))
            else:
                rows.append(("collision", node, mime, dest, source, held_source))
            continue
        if os.path.exists(dest):
            with open(dest, "rb") as handle:
                existing = handle.read()
            if existing == data:
                claimed[dest] = (dest, data)
                rows.append(("reused", node, mime, dest, reference))
            elif mime == SVG:
                claimed[dest] = (dest, existing)
                rows.append(("collision", node, mime, dest, source, dest))
            else:
                raise Refused(f"'{dest}' already holds other bytes")
            continue
        claimed[dest] = (source, data)
        writes.append((dest, data))
        rows.append(("placed", node, mime, dest, reference))
    return rows, writes


def main(argv):
    if len(argv) < 4:
        raise Refused("usage: place-assets.py <design-reference.json> <item_id> <node_id>...")
    ref_path, item_id, nodes = argv[1], argv[2], argv[3:]
    if not item_id or "/" in item_id or ".." in item_id:
        raise Refused(f"item id must be one path segment: {item_id}")
    ref = read_reference(ref_path)
    rows, writes = resolve(plan(ref, item_id, nodes))
    collided = any(row[0] == "collision" for row in rows)
    if not collided:
        for dest, data in writes:
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "xb") as handle:
                handle.write(data)
    for row in rows:
        print("\t".join(row))
    return 4 if collided else 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Refused as refusal:
        print(f"place-assets: {refusal}", file=sys.stderr)
        sys.exit(2)
