#!/usr/bin/env python3
"""Size a node's reference screenshot, and record what size came back.

Usage:
  screenshot-size.py max <metadata-file> <node_id>
  screenshot-size.py list <node_id>=<width>x<height>/<original_width>x<original_height>...

max prints the `maxDimension` to request for <node_id>: its longer edge from
the get_metadata XML in <metadata-file>, rounded up to a whole pixel, capped
at 65536. <node_id> is matched in colon or hyphen form (`1:118` or `1-118`)
against any element of the tree.

list prints a JSON array, one entry per argument, in the order given:
  [{"node_id", "width", "height", "original_width", "original_height", "downscaled"}]
width/height are the rendered size the screenshot tool returned,
original_width/original_height the node's own. node_id is written in hyphen
form. downscaled is true when the render is at least one pixel smaller than
the original on either edge.

Exit codes: 0 printed; 2 usage, unreadable input, an unknown node, or a node
with no usable size.
"""

import importlib.util
import json
import math
import os
import re
import sys

LIMIT = 65536
NODE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9:;_-]*$")
SIZE = re.compile(r"^([^=]+)=([^x/]+)x([^x/]+)/([^x/]+)x([^x/]+)$")


def die(message):
    print("screenshot-size: " + message, file=sys.stderr)
    sys.exit(2)


def classifier():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "classify-node.py")
    spec = importlib.util.spec_from_file_location("classify_node", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def positive(raw):
    try:
        value = float(raw)
    except (TypeError, ValueError):
        return None
    if value != value or value <= 0 or math.isinf(value):
        return None
    return int(value) if value.is_integer() else value


def hyphen(node_id):
    return node_id.replace(":", "-")


def max_mode(argv):
    if len(argv) != 4:
        die("usage: screenshot-size.py max <metadata-file> <node_id>")
    try:
        with open(argv[2], encoding="utf-8") as handle:
            text = handle.read()
    except OSError as error:
        die("cannot read " + argv[2] + ": " + error.strerror)
    root = classifier().root_element(text)
    wanted = hyphen(argv[3])
    for element in root.iter():
        if hyphen(element.get("id", "")) == wanted:
            width, height = positive(element.get("width")), positive(element.get("height"))
            if width is None or height is None:
                die("node " + argv[3] + " has no usable width and height")
            print(min(LIMIT, math.ceil(max(width, height))))
            return 0
    die("node " + argv[3] + " is not in " + argv[2])


def list_mode(argv):
    if len(argv) < 3:
        die("usage: screenshot-size.py list <node_id>=<width>x<height>/<original_width>x<original_height>...")
    entries = []
    seen = set()
    for arg in argv[2:]:
        match = SIZE.match(arg)
        if not match:
            die("expected <node_id>=<width>x<height>/<original_width>x<original_height>, got " + repr(arg))
        node, *raw = match.groups()
        if not NODE_ID.match(node):
            die("not a node id: " + repr(node))
        sizes = [positive(r) for r in raw]
        if any(s is None for s in sizes):
            die("every size must be a positive number, got " + repr(arg))
        node = hyphen(node)
        if node in seen:
            die("node " + node + " has two sizes")
        seen.add(node)
        width, height, original_width, original_height = sizes
        entries.append({
            "node_id": node,
            "width": width,
            "height": height,
            "original_width": original_width,
            "original_height": original_height,
            "downscaled": width + 1 <= original_width or height + 1 <= original_height,
        })
    print(json.dumps(entries, indent=2))
    return 0


def main(argv):
    modes = {"max": max_mode, "list": list_mode}
    if len(argv) < 2 or argv[1] not in modes:
        die("usage: screenshot-size.py max <metadata-file> <node_id> | "
            "list <node_id>=<width>x<height>/<original_width>x<original_height>...")
    return modes[argv[1]](argv)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
