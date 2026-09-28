#!/usr/bin/env python3
"""Pair browser captures with a design reference's viewport variants.

Usage:
  pair-viewports.py breakpoints <stylesheet>
  pair-viewports.py targets <design-reference.json> <default-width>
  pair-viewports.py pair <design-reference.json> <widths> <breakpoints>

breakpoints prints the project's adopted breakpoints: every N in an
`@media (width >= Npx)` rule of <stylesheet>, unique, ascending, joined by
commas; `-` when there is none.

targets prints one tab-separated line per comparison a design check makes,
widest first:
  <capture width> <node id> <variant width> <image> <resolution> <name>
With viewport variants, one line per variant, captured at the variant's own
width rounded to the nearest whole pixel. Without (no `viewports` key, or an
empty list), one line: <default-width>, the reference image, and `-` for node
id, variant width and name.

pair prints one tab-separated line per capture width, in the order given:
  <capture width> <status> <node id> <variant width> <image> <resolution> <also at> <name>
<widths> and <breakpoints> are comma-separated whole pixels; <breakpoints> is
`-` for none. The breakpoints cut the width axis into intervals, each closed
at its lower end: with 900, `< 900` and `>= 900`. A capture pairs with the
variant whose width is in the same interval; of several, the one nearest in
width, the wider on a tie. status is:
  variant  paired with that variant
  none     no variant is in the capture's interval; every other field is `-`
  single   the reference has one width; its one image is paired with every capture
<also at> names the other capture widths paired with the same image, or `-`.

<node id> is the colon form (`1-118` is printed `1:118`). <resolution> is
`full` or `reduced` from the reference's `screenshots` entry for that image
(its `downscaled`), or `unknown` when the reference records none.

Exit codes: 0 printed; 2 usage, unreadable input or a malformed reference.
"""

import json
import re
import sys

MEDIA = re.compile(r"@media[^{]*\(\s*width\s*>=\s*(\d+)px\s*\)")


def die(message):
    print("pair-viewports: " + message, file=sys.stderr)
    sys.exit(2)


def whole(raw, what):
    if not re.fullmatch(r"[1-9][0-9]*", raw or ""):
        die(what + " must be a positive whole number, got " + repr(raw))
    return int(raw)


def width_list(raw, what, allow_none):
    if allow_none and raw == "-":
        return []
    return [whole(part, what) for part in raw.split(",")]


def colon(node_id):
    return node_id.replace("-", ":")


def number(value):
    return not isinstance(value, bool) and isinstance(value, (int, float)) and value > 0


def load(path):
    try:
        with open(path, encoding="utf-8") as handle:
            ref = json.load(handle)
    except OSError as error:
        die("cannot read " + path + ": " + error.strerror)
    except ValueError as error:
        die(path + " is not JSON: " + str(error))
    if not isinstance(ref, dict) or not isinstance(ref.get("reference_image"), str):
        die(path + " has no reference_image")

    viewports = ref.get("viewports") or []
    if not isinstance(viewports, list):
        die(path + ": viewports must be a list")
    for v in viewports:
        if (not isinstance(v, dict) or not isinstance(v.get("node_id"), str)
                or not isinstance(v.get("name"), str) or not isinstance(v.get("image"), str)
                or not number(v.get("width"))):
            die(path + ": each viewport needs a name, node_id, numeric width and image")

    resolution = {}
    shots = ref.get("screenshots") or []
    if not isinstance(shots, list):
        die(path + ": screenshots must be a list")
    for s in shots:
        if not isinstance(s, dict) or not isinstance(s.get("image"), str) or not isinstance(s.get("downscaled"), bool):
            die(path + ": each screenshots entry needs an image and a downscaled flag")
        resolution[s["image"]] = "reduced" if s["downscaled"] else "full"
    return ref, viewports, resolution


def fmt(width):
    return str(int(width)) if float(width).is_integer() else str(width)


def interval(width, breakpoints):
    return sum(1 for b in breakpoints if width >= b)


def nearest(capture, candidates):
    return min(candidates, key=lambda v: (abs(v["width"] - capture), -v["width"]))


def breakpoints_mode(argv):
    if len(argv) != 3:
        die("usage: pair-viewports.py breakpoints <stylesheet>")
    try:
        with open(argv[2], encoding="utf-8") as handle:
            css = handle.read()
    except OSError as error:
        die("cannot read " + argv[2] + ": " + error.strerror)
    found = sorted({int(n) for n in MEDIA.findall(css)})
    print(",".join(str(n) for n in found) if found else "-")
    return 0


def targets_mode(argv):
    if len(argv) != 4:
        die("usage: pair-viewports.py targets <design-reference.json> <default-width>")
    default = whole(argv[3], "the default width")
    ref, viewports, resolution = load(argv[2])
    if not viewports:
        image = ref["reference_image"]
        print("\t".join([str(default), "-", "-", image, resolution.get(image, "unknown"), "-"]))
        return 0
    for v in sorted(viewports, key=lambda v: v["width"], reverse=True):
        capture = int(v["width"] + 0.5)
        print("\t".join([str(capture), colon(v["node_id"]), fmt(v["width"]), v["image"],
                         resolution.get(v["image"], "unknown"), v["name"]]))
    return 0


def pair_mode(argv):
    if len(argv) != 5:
        die("usage: pair-viewports.py pair <design-reference.json> <widths> <breakpoints>")
    widths = width_list(argv[3], "a capture width", False)
    breakpoints = sorted(set(width_list(argv[4], "a breakpoint", True)))
    ref, viewports, resolution = load(argv[2])

    rows = []
    for capture in widths:
        if not viewports:
            rows.append((capture, "single", None))
            continue
        here = [v for v in viewports if interval(v["width"], breakpoints) == interval(capture, breakpoints)]
        rows.append((capture, "variant", nearest(capture, here)) if here else (capture, "none", None))

    def image_of(row):
        if row[1] == "single":
            return ref["reference_image"]
        return row[2]["image"] if row[2] else None

    for row in rows:
        capture, status, v = row
        image = image_of(row)
        if image is None:
            print("\t".join([str(capture), status] + ["-"] * 6))
            continue
        others = [str(r[0]) for r in rows if r is not row and image_of(r) == image]
        also = ",".join(others) if others else "-"
        if status == "single":
            fields = [str(capture), status, "-", "-", image, resolution.get(image, "unknown"), also, "-"]
        else:
            fields = [str(capture), status, colon(v["node_id"]), fmt(v["width"]), image,
                      resolution.get(image, "unknown"), also, v["name"]]
        print("\t".join(fields))
    return 0


def main(argv):
    modes = {"breakpoints": breakpoints_mode, "targets": targets_mode, "pair": pair_mode}
    if len(argv) < 2 or argv[1] not in modes:
        die("usage: pair-viewports.py breakpoints <stylesheet> | "
            "targets <design-reference.json> <default-width> | "
            "pair <design-reference.json> <widths> <breakpoints>")
    return modes[argv[1]](argv)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
