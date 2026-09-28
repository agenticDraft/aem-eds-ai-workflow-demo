#!/usr/bin/env python3
"""Plan and list a node's viewport variants from classify-node.py's table.

Usage:
  viewports.py plan <classification.tsv> <file_key>
  viewports.py list <classification.tsv> <file_key> <node_id>=<code|structure_only>...

Both read only the table classify-node.py wrote. A node whose class is not
`variants`, or whose frame-like children are not all variants, is refused:
nothing is planned or listed that the classifier did not detect.

plan prints one tab-separated line per variant, widest first (document order
for equal widths):
  <node_id> <width> <image> <context> <name>
node_id is the hyphen form (`1:118` becomes `1-118`); image and context are
the paths the variant's screenshot and design context are written to:
  .ai/figma/<file_key>-<node_id>.png
  .ai/figma/<file_key>-<node_id>.context.txt

list prints the `viewports` JSON array, in the same order:
  [{"name", "node_id", "width", "image", "context"}]
Each variant needs exactly one outcome argument: `code` when its design
context returned a code block (the context file must exist), `structure_only`
when it did not (context is null, whatever is on disk). Every image must exist.

Paths are relative to the project root; run from there.

Exit codes: 0 printed; 2 usage, unreadable table, refused class or a missing
file.
"""

import json
import os
import sys

FIGMA_DIR = ".ai/figma"
OUTCOMES = ("code", "structure_only")


def die(message):
    print("viewports: " + message, file=sys.stderr)
    sys.exit(2)


def number(raw):
    try:
        value = float(raw)
    except ValueError:
        return None
    if value != value or value <= 0:
        return None
    return int(value) if value.is_integer() else value


def variants(table_path, file_key):
    try:
        with open(table_path, encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except OSError as error:
        die("cannot read " + table_path + ": " + error.strerror)
    if not lines or lines[0] != "class\tvariants":
        die("the node is not classified as viewport variants: " + (lines[0] if lines else "empty table"))

    rows = []
    for line in lines[1:]:
        fields = line.split("\t")
        if fields[0] != "child":
            continue
        if len(fields) != 6:
            die("malformed child line: " + line)
        _, node, raw_width, role, _rule, name = fields
        if role != "variant":
            die("child " + node + " is not a variant")
        width = number(raw_width)
        if width is None:
            die("child " + node + " has no usable width: " + repr(raw_width))
        node_id = node.replace(":", "-")
        stem = "%s/%s-%s" % (FIGMA_DIR, file_key, node_id)
        rows.append({
            "name": name,
            "node_id": node_id,
            "width": width,
            "image": stem + ".png",
            "context": stem + ".context.txt",
        })
    if len(rows) < 2:
        die("fewer than two variants in the table")
    rows.sort(key=lambda r: r["width"], reverse=True)
    return rows


def outcomes(args, rows):
    known = {r["node_id"] for r in rows}
    seen = {}
    for arg in args:
        node, sep, outcome = arg.partition("=")
        if not sep or outcome not in OUTCOMES:
            die("expected <node_id>=code or <node_id>=structure_only, got " + repr(arg))
        if node not in known:
            die("node " + node + " is not a detected variant")
        if node in seen:
            die("node " + node + " has two outcomes")
        seen[node] = outcome
    missing = [r["node_id"] for r in rows if r["node_id"] not in seen]
    if missing:
        die("no outcome for " + ", ".join(missing))
    return seen


def main(argv):
    if len(argv) < 4 or argv[1] not in ("plan", "list"):
        die("usage: viewports.py plan <classification.tsv> <file_key> | "
            "list <classification.tsv> <file_key> <node_id>=<code|structure_only>...")
    mode, table, file_key = argv[1], argv[2], argv[3]
    if mode == "plan" and len(argv) != 4:
        die("plan takes no outcome arguments")
    rows = variants(table, file_key)

    if mode == "plan":
        for r in rows:
            print("\t".join([r["node_id"], str(r["width"]), r["image"], r["context"], r["name"]]))
        return 0

    seen = outcomes(argv[4:], rows)
    listed = []
    for r in rows:
        if not os.path.isfile(r["image"]):
            die("image " + r["image"] + " not found")
        context = r["context"] if seen[r["node_id"]] == "code" else None
        if context is not None and not os.path.isfile(context):
            die("context " + context + " not found, but " + r["node_id"] + " is marked code")
        listed.append({
            "name": r["name"],
            "node_id": r["node_id"],
            "width": r["width"],
            "image": r["image"],
            "context": context,
        })
    print(json.dumps(listed, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
