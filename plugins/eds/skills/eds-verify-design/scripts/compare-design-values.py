#!/usr/bin/env python3
# Run: python3 plugins/eds/skills/eds-verify-design/scripts/compare-design-values.py compare \
#        .ai/run-context/design-context-values.tsv .ai/run-context/prototype-report.md <measure.json>
#
# compare-design-values.py selectors <prototype-report.md>
# compare-design-values.py compare <values.tsv> <prototype-report.md> <measure.json>
#
# Deterministic. `selectors` prints, once each and in order, the selector of
# every `## Design values` line in the prototype report that names a node
# (`... — node: <node_id>`). Those are the selectors to measure. A line whose
# last part starts with `node:` but is not exactly one node id (a list, a
# range, nothing) exits 2 in both modes, naming the line on stderr.
#
# `compare` reads the value table (`<node_id> TAB <property> TAB <value> TAB
# <approx>`) and compares each row against the measurement file the browser
# role's `measure` wrote. A row is compared on the selectors of the report lines that name its
# node and its property (a trailing `(qualifier)` on the line's property is
# ignored); when no line names the property, on every selector the report names
# for the node.
#
# A value split across elements (D529) is compared as applied: a line whose
# value differs from the node's is a split when every component of it is `0` or
# the node's own value, position by position (border-radius, gap and padding
# only), and is then compared against the line's own value. Any other differing
# line is refused — a mismatch against the node's value. A line whose value
# equals the node's, or cannot be decided (var(), rem, ...), keeps the node's
# value. One line per compared value:
#
#   match       TAB <node> TAB <selector> TAB <property> TAB <value>
#   mismatch    TAB <node> TAB <selector> TAB <property> TAB expected <v>, measured <v>[ (<note>)]
#   unmeasured  TAB <node> TAB <selector|-> TAB <property> TAB <value>: <reason>
#   approx      TAB <node> TAB <selector|-> TAB <property> TAB expected <v>, measured box <w>x<h>px
#   approx      TAB <node> TAB <selector|-> TAB <property> TAB <value>: <reason>
#
# where <note> is `table: <property> <value>` for an expanded shorthand,
# `split of [<property> ]<value>` for a split line, and `line: <value> is not a
# split of <value>` for a refused one.
#
# Only the properties `measure` reports are compared: color, background-color,
# font-family, font-size, font-weight, line-height, padding-top,
# padding-right, padding-bottom, padding-left, gap, border-radius. Every other
# property is `unmeasured`. A padding shorthand (`padding`, `padding-inline`,
# `padding-block`, `padding-inline-start`, `padding-inline-end`) is expanded
# to the physical longhands first, for a horizontal left-to-right writing mode;
# the table line is named after a mismatch on an expanded value.
#
# A row whose <approx> is `true` depends on the design's content: it is never
# graded, never a match or a mismatch, and never changes the exit code. It is
# listed, one `approx` line per selector, with the selector's measured box
# (geometry width and height) beside the table's value, after every other
# line. `approx` is `true` or `false`; `true` on any property but width,
# height, min-height or aspect-ratio is a usage error.
#
# Values are compared by form, never guessed: lengths in px (and `0`) as
# numbers; colours as hex, rgb() or rgba(); `border-radius` and `gap` as the
# computed string, token by token, after normalising px; font-weight as an
# integer; font-family as its comma-separated list, unquoted, case-folded.
# Any other form (rem, em, %, var(), calc(), a unitless line-height, a colour
# keyword) is `unmeasured` as not comparable.
#
# Exit codes: 0 — no mismatch; 1 — at least one mismatch; 2 — usage error
# (missing argument, unreadable file, malformed table row or measurement).

import json
import os
import re
import sys

MEASURED = [
    "color", "background-color", "font-family", "font-size", "font-weight", "line-height",
    "padding-top", "padding-right", "padding-bottom", "padding-left", "gap", "border-radius",
]

LENGTH_PX = re.compile(r"^(-?(?:\d+\.?\d*|\.\d+))px$")
HEX = re.compile(r"^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")
RGB = re.compile(r"^rgba?\(\s*([^)]*)\)$")
INTEGER = re.compile(r"^\d+$")
APPROX_PROPERTIES = {"width", "height", "min-height", "aspect-ratio"}
NODE_TAIL = re.compile(r"^node:\s*(I?\d+:\d+(?:;\d+:\d+)*)$")
QUALIFIER = re.compile(r"\s*\([^)]*\)$")
SPLITTABLE = {"border-radius", "gap", "padding", "padding-inline", "padding-block",
              "padding-top", "padding-right", "padding-bottom", "padding-left",
              "padding-inline-start", "padding-inline-end"}


def usage_error(msg):
    print(
        "usage: compare-design-values.py selectors <prototype-report.md>\n"
        "       compare-design-values.py compare <values.tsv> <prototype-report.md> <measure.json>\n"
        f"{msg}",
        file=sys.stderr,
    )
    sys.exit(2)


def read_text(path):
    if not os.path.isfile(path):
        usage_error(f"'{path}' not found")
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as e:
        usage_error(f"'{path}' is not readable: {e}")


# --- the prototype report -------------------------------------------------

def design_value_lines(report):
    """(selector, property, value, node) for each `## Design values` line that
    names a node; property (qualifier dropped, lower-cased) and value are None
    when the line is too short to carry them."""
    inside = False
    for raw in report.splitlines():
        line = raw.strip()
        if line.startswith("## "):
            inside = line[3:].strip().lower() == "design values"
            continue
        if not inside or not line:
            continue
        if line[:2] in ("- ", "* "):
            line = line[2:].strip()
        line = line.strip("`").strip()
        parts = [p.strip() for p in line.split(" — ")]
        if len(parts) < 2:
            continue
        m = NODE_TAIL.match(parts[-1])
        if not m and parts[-1].startswith("node:"):
            print(f"unreadable node: part (one node id expected): {raw.strip()}", file=sys.stderr)
            sys.exit(2)
        if m and parts[0]:
            prop = value = None
            if len(parts) >= 4:
                prop = QUALIFIER.sub("", parts[1]).strip().lower()
                value = parts[2]
            yield parts[0].strip("`").strip(), prop, value, m.group(1)


def selectors_by_node(report):
    by_node = {}
    for selector, _, _, node in design_value_lines(report):
        sels = by_node.setdefault(node, [])
        if selector not in sels:
            sels.append(selector)
    return by_node


# --- expansion ------------------------------------------------------------

def box_sides(tokens):
    """CSS one-to-four value box order -> (top, right, bottom, left)."""
    if len(tokens) == 1:
        return tokens * 4
    if len(tokens) == 2:
        return [tokens[0], tokens[1], tokens[0], tokens[1]]
    if len(tokens) == 3:
        return [tokens[0], tokens[1], tokens[2], tokens[1]]
    if len(tokens) == 4:
        return tokens
    return None


def expand(prop, value):
    """[(longhand, value)] for a padding shorthand; None when prop is not one."""
    tokens = value.split()
    if prop == "padding":
        sides = box_sides(tokens)
        if sides is None:
            return []
        return list(zip(["padding-top", "padding-right", "padding-bottom", "padding-left"], sides))
    if prop in ("padding-inline", "padding-block"):
        if len(tokens) not in (1, 2):
            return []
        start, end = tokens[0], tokens[-1]
        names = ("padding-left", "padding-right") if prop == "padding-inline" else ("padding-top", "padding-bottom")
        return [(names[0], start), (names[1], end)]
    if prop == "padding-inline-start":
        return [("padding-left", value)]
    if prop == "padding-inline-end":
        return [("padding-right", value)]
    return None


def components(prop, value):
    """[normalised px token] of a splittable value in a fixed positional form,
    or None when it cannot be decided."""
    if "/" in value:
        return None
    tokens = [px(t) for t in value.split()]
    if not tokens or any(t is None for t in tokens):
        return None
    if prop in ("border-radius", "padding"):
        return box_sides(tokens)
    if prop in ("gap", "padding-inline", "padding-block"):
        return [tokens[0], tokens[-1]] if len(tokens) in (1, 2) else None
    return tokens if len(tokens) == 1 else None


def classify_line(prop, node_value, line_value):
    """`node` — compare against the node's value (equal, undecidable, or not a
    splittable property); `split` — compare against the line's value;
    `refused` — the line differs and is not a split of the node's value."""
    if prop not in SPLITTABLE or line_value is None:
        return "node"
    want = components(prop, node_value)
    have = components(prop, line_value)
    if want is None or have is None or have == want:
        return "node"
    if len(have) != len(want):
        return "refused"
    if all(h == "0px" or h == w for h, w in zip(have, want)):
        return "split"
    return "refused"


# --- normalisation --------------------------------------------------------

def px(token):
    """A px length (or `0`) as its normalised string, else None."""
    if token == "0":
        return "0px"
    m = LENGTH_PX.match(token)
    if not m:
        return None
    text = f"{float(m.group(1)):f}".rstrip("0").rstrip(".")
    if text in ("-0", ""):
        text = "0"
    return f"{text}px"


def rgba(value):
    v = value.strip().lower()
    m = HEX.match(v)
    if m:
        h = m.group(1)
        if len(h) in (3, 4):
            h = "".join(c * 2 for c in h)
        a = int(h[6:8], 16) / 255 if len(h) == 8 else 1.0
        return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), round(a, 3))
    m = RGB.match(v)
    if m:
        parts = [p for p in re.split(r"[\s,/]+", m.group(1)) if p]
        if len(parts) not in (3, 4):
            return None
        try:
            rgb = [int(round(float(p))) for p in parts[:3]]
            a = float(parts[3].rstrip("%")) / (100 if parts[3].endswith("%") else 1) if len(parts) == 4 else 1.0
        except ValueError:
            return None
        return (rgb[0], rgb[1], rgb[2], round(a, 3))
    return None


def families(value):
    return [f.strip().strip("'\"").strip().lower() for f in value.split(",")]


def compare_value(prop, expected, measured):
    """(comparable, expected_display, equal)."""
    if prop in ("color", "background-color"):
        want = rgba(expected)
        if want is None:
            return False, expected, False
        return True, expected, rgba(measured) == want
    if prop == "font-weight":
        if not INTEGER.match(expected):
            return False, expected, False
        return True, expected, measured.strip() == str(int(expected))
    if prop == "font-family":
        return True, expected, families(measured) == families(expected)
    if prop in ("gap", "border-radius"):
        want = [px(t) if t != "/" else "/" for t in expected.replace("/", " / ").split()]
        if not want or any(t is None for t in want):
            return False, expected, False
        got = [(px(t) or t.lower()) if t != "/" else "/" for t in measured.replace("/", " / ").split()]
        return True, " ".join(want), got == want
    want = px(expected.strip())
    if want is None:
        return False, expected, False
    return True, want, px(measured.strip()) == want


# --- main -----------------------------------------------------------------

def read_table(path):
    rows = []
    for n, line in enumerate(read_text(path).splitlines(), 1):
        if not line.strip():
            continue
        cols = [c.strip() for c in line.split("\t")]
        if len(cols) != 4 or not all(cols):
            usage_error(f"'{path}' line {n}: expected <node_id> TAB <property> TAB <value> TAB <approx>")
        if cols[3] not in ("true", "false"):
            usage_error(f"'{path}' line {n}: approx must be true or false, got '{cols[3]}'")
        if cols[3] == "true" and cols[1] not in APPROX_PROPERTIES:
            usage_error(f"'{path}' line {n}: {cols[1]} is never approx")
        rows.append((cols[0], cols[1], cols[2], cols[3] == "true"))
    return rows


def box(result):
    """'<w>x<h>px' from a measurement's geometry, or None."""
    geometry = result.get("geometry") if isinstance(result, dict) else None
    if not isinstance(geometry, dict):
        return None
    sides = []
    for key in ("width", "height"):
        v = geometry.get(key)
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            return None
        sides.append(f"{round(float(v), 2):f}".rstrip("0").rstrip("."))
    return f"{sides[0]}x{sides[1]}px"


def list_approx(node, prop, value, lines, by_node, results):
    """The `approx` lines for one content-dependent row; nothing is graded."""
    selectors = by_node.get(node)
    if not selectors:
        return [("approx", node, "-", prop, f"{value}: no selector recorded for this node")]
    named = [sel for sel, lprop, _, lnode in lines if lnode == node and lprop == prop]
    out = []
    for selector in named or selectors:
        result = results.get(selector)
        if not isinstance(result, dict) or not result.get("found"):
            out.append(("approx", node, selector, prop, f"{value}: selector not found on the page"))
            continue
        measured = box(result)
        if measured is None:
            out.append(("approx", node, selector, prop, f"{value}: no box in the measurement"))
        else:
            out.append(("approx", node, selector, prop, f"expected {value}, measured box {measured}"))
    return out


def read_measurement(path):
    try:
        data = json.loads(read_text(path))
    except ValueError as e:
        usage_error(f"'{path}' is not readable JSON: {e}")
    if not isinstance(data, dict) or not isinstance(data.get("results"), dict):
        usage_error(f"'{path}': expected an object with a `results` object")
    return data["results"]


def compare(table_path, report_path, measure_path):
    rows = read_table(table_path)
    report = read_text(report_path)
    lines = list(design_value_lines(report))
    by_node = selectors_by_node(report)
    results = read_measurement(measure_path)

    out = []
    listed = []
    mismatches = 0
    for node, prop, value, approx in rows:
        if approx:
            listed += list_approx(node, prop, value, lines, by_node, results)
            continue
        longhands = expand(prop, value)
        if longhands is None:
            longhands = [(prop, value)]
        if not longhands or any(p not in MEASURED for p, _ in longhands):
            out.append(("unmeasured", node, "-", prop, f"{value}: not in measure's property set"))
            continue
        selectors = by_node.get(node)
        if not selectors:
            out.append(("unmeasured", node, "-", prop, f"{value}: no selector recorded for this node"))
            continue
        expanded = (prop, value) != longhands[0] or len(longhands) > 1
        named = [(sel, lval) for sel, lprop, lval, lnode in lines if lnode == node and lprop == prop]
        targets = named or [(sel, None) for sel in selectors]
        for selector, line_value in targets:
            kind = classify_line(prop, value, line_value)
            wants = longhands
            note = f"table: {prop} {value}" if expanded else None
            if kind == "split":
                wants = expand(prop, line_value) or [(prop, line_value)]
                note = f"split of {prop} {value}" if expanded else f"split of {value}"
            elif kind == "refused":
                note = f"line: {line_value} is not a split of {value}"
            result = results.get(selector)
            for longhand, want in wants:
                if not isinstance(result, dict) or not result.get("found"):
                    out.append(("unmeasured", node, selector, longhand, f"{want}: selector not found on the page"))
                    continue
                computed = result.get("computed") or {}
                if not isinstance(computed.get(longhand), str):
                    out.append(("unmeasured", node, selector, longhand, f"{want}: not in the measurement"))
                    continue
                measured = computed[longhand]
                comparable, shown, equal = compare_value(longhand, want, measured)
                if not comparable:
                    out.append(("unmeasured", node, selector, longhand, f"{want}: not comparable to the computed value"))
                elif equal and kind != "refused":
                    out.append(("match", node, selector, longhand, shown))
                else:
                    detail = f"expected {shown}, measured {measured}"
                    if note:
                        detail += f" ({note})"
                    out.append(("mismatch", node, selector, longhand, detail))
                    mismatches += 1

    for line in out + listed:
        print("\t".join(line))
    sys.exit(1 if mismatches else 0)


def main():
    args = sys.argv[1:]
    if args[:1] == ["selectors"] and len(args) == 2:
        seen = []
        for selector, _, _, _ in design_value_lines(read_text(args[1])):
            if selector not in seen:
                seen.append(selector)
                print(selector)
        sys.exit(0)
    if args[:1] == ["compare"] and len(args) == 4:
        compare(args[1], args[2], args[3])
    usage_error("expected `selectors <report>` or `compare <table> <report> <measurement>`")


if __name__ == "__main__":
    main()
