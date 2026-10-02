#!/usr/bin/env python3
# Run: python3 plugins/eds/skills/eds-prototype/scripts/viewport-overrides.py .ai/run-context/design-reference.json <breakpoints>
#
# viewport-overrides.py <design-reference.json> <breakpoints>
#
# Deterministic. Diffs the design-context value tables of a reference's
# viewport variants into a mobile-first base and one override block per
# adopted breakpoint. <breakpoints> is the project's adopted breakpoints,
# comma-separated whole pixels, or `-` for none (the output of
# `pair-viewports.py breakpoints`). A variant's own width is never a threshold.
#
# Each variant's rows are the rows design-context-values.py reads from that
# variant's `context` file: the same classes, the same properties, the same
# node ids. Elements are matched across variants by their layer path inside
# the variant: from the exported frame's root element down, each element
# carrying a `data-node-id` is one segment, named by its `data-name`, or by
# its tag in angle brackets when it has none, plus `#<n>` for the n-th sibling
# of that segment. The root is `/`. An element outside the exported function
# (a helper component's definition) is keyed `def:<node id>`. Rendered text
# is never read. A context file with no `export default function` takes its
# first element as the root.
#
# The breakpoints cut the width axis into intervals, each closed at its lower
# end. Each variant belongs to the interval its width falls in. The narrowest
# variant is the base. In every other interval, the narrowest variant there
# overrides at that interval's lower bound, with only the values that differ
# from the effective value below it (hex colours compare case-insensitively).
# Any further variant in an interval already taken is a finding: its
# differences from that interval's variant are listed, and a threshold is
# proposed by derive-breakpoints.sh from its width and the next narrower
# variant's width. Its values are emitted nowhere else.
#
# Output, tab-separated, one record per line:
#   single                                         no viewports; nothing else
#   base <name> <node> <width>
#   media <breakpoint> <name> <node> <width>
#   value <base|breakpoint> <base node> <property> <value> <variant node> <path>
#   not-overridden <breakpoint> <base node> <property> <effective value> <variant node> <path>
#   unmatched <name> <variant node> <path>          element with values, no counterpart in the base
#   missing <name> <base node> <path>               base element with values, absent from <name>
#   same-interval <name> <node> <width> <interval variant> <proposed threshold or ->
#   differs <name> <interval variant node> <property> <value or -> <interval value or -> <node> <path>
#   no-context <name> <node> <width>                a variant with context null; not diffed
#
# Exit codes: 0 — printed; 2 — usage error, unreadable or malformed input.

import importlib.util
import json
import math
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DERIVER = os.path.join(HERE, "..", "..", "..", "..", "agentic-core", "shared", "lib", "derive-breakpoints.sh")

_spec = importlib.util.spec_from_file_location("design_context_values", os.path.join(HERE, "design-context-values.py"))
dcv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dcv)

TAG = re.compile(r"<(/?)([A-Za-z][\w.:-]*)")
EXPORT = re.compile(r"export\s+default\s+function\b")


def die(message):
    print("usage: viewport-overrides.py <design-reference.json> <breakpoints>\n" + message, file=sys.stderr)
    sys.exit(2)


def read_tag(code, i):
    """Attributes of the opening tag whose name ends at i; returns (attrs, end, self_closing)."""
    attrs = {}
    while i < len(code):
        while i < len(code) and code[i].isspace():
            i += 1
        if i >= len(code):
            break
        if code.startswith("/>", i):
            return attrs, i + 2, True
        if code[i] == ">":
            return attrs, i + 1, False
        if code[i] == "{":
            i = dcv.skip_braces(code, i)
            continue
        n = dcv.ATTR_NAME.match(code, i)
        if not n:
            i += 1
            continue
        name, i = n.group(0), n.end()
        while i < len(code) and code[i].isspace():
            i += 1
        if i < len(code) and code[i] == "=":
            i += 1
            while i < len(code) and code[i].isspace():
                i += 1
            if i < len(code) and code[i] in "\"'":
                end = dcv.skip_string(code, i)
                attrs[name] = code[i + 1:end - 1]
                i = end
            elif i < len(code) and code[i] == "{":
                end = dcv.skip_braces(code, i)
                attrs[name] = dcv.literal(code[i + 1:end - 1])
                i = end
    return attrs, i, True


def scan(code):
    """Every element with a data-node-id: (offset, node, name, tag, parent index, classes)."""
    out = []
    stack = []
    pos = 0
    while True:
        m = TAG.search(code, pos)
        if not m:
            return out
        closing, tag = m.group(1), m.group(2)
        if closing:
            while stack and stack[-1][0] != tag:
                stack.pop()
            if stack:
                stack.pop()
            pos = m.end()
            continue
        attrs, pos, self_closing = read_tag(code, m.end())
        parent = next((s[1] for s in reversed(stack) if s[1] is not None), None)
        index = None
        node = attrs.get("data-node-id")
        if node:
            out.append((m.start(), node, attrs.get("data-name"), tag, parent,
                        attrs.get("className") or attrs.get("class")))
            index = len(out) - 1
        if not self_closing:
            stack.append((tag, index))


def variant_table(path):
    """{key: (node, {property: value})} for one variant's reference code, plus its root node."""
    if not os.path.isfile(path):
        die("'" + path + "' not found — a viewport names it as its context")
    with open(path, encoding="utf-8") as f:
        code = f.read()
    elements = scan(code)
    if not elements:
        die("'" + path + "' holds no element with a data-node-id")
    export = EXPORT.search(code)
    start = export.end() if export else 0
    root = next((k for k, e in enumerate(elements) if e[0] >= start and e[4] is None), None)
    if root is None:
        die("'" + path + "' has no element after its exported function")

    def in_tree(k):
        while k is not None:
            if k == root:
                return True
            k = elements[k][4]
        return False

    keys = {root: "/"}
    counts = {}
    for k, e in enumerate(elements):
        if k == root or not in_tree(k):
            continue
        parent_key = keys[e[4]]
        segment = escape(e[2]) if e[2] is not None else "<" + e[3] + ">"
        n = counts[(e[4], segment)] = counts.get((e[4], segment), 0) + 1
        keys[k] = (parent_key.rstrip("/")) + "/" + segment + "#" + str(n)
    table = {}
    order = []
    for k, e in enumerate(elements):
        key = keys.get(k, "def:" + e[1])
        props = table.setdefault(key, (e[1], {}))[1]
        if key not in order:
            order.append(key)
        for cls in (e[5] or "").split():
            for prop, value in dcv.class_rows(cls):
                if prop not in props:
                    props[prop] = value
    return {k: table[k] for k in order}, elements[root][1]


def escape(name):
    return (name.replace("%", "%25").replace("/", "%2F").replace("\t", "%09")
            .replace("\n", "%0A").replace("\r", "%0D"))


def same(a, b):
    if a is None or b is None:
        return a is b
    if a.startswith("#") and b.startswith("#"):
        return a.lower() == b.lower()
    return a == b


def fmt(width):
    return str(int(width)) if float(width).is_integer() else str(width)


def breakpoint_list(raw):
    if raw == "-":
        return []
    parts = raw.split(",")
    if not all(re.fullmatch(r"[1-9][0-9]*", p) for p in parts):
        die("breakpoints must be comma-separated whole pixels or '-', got " + repr(raw))
    return sorted({int(p) for p in parts})


def threshold(low, high):
    try:
        run = subprocess.run(["bash", DERIVER, fmt(low), fmt(high)], capture_output=True, text=True)
    except OSError:
        return "-"
    if run.returncode != 0:
        return "-"
    for line in run.stdout.splitlines():
        fields = line.split("\t")
        if fields[0] == "threshold":
            return fields[4]
    return "-"


def load(path):
    if not os.path.isfile(path):
        die("'" + path + "' not found")
    try:
        with open(path, encoding="utf-8") as f:
            ref = json.load(f)
    except (OSError, ValueError) as e:
        die("'" + path + "' is not readable JSON: " + str(e))
    if not isinstance(ref, dict):
        die("'" + path + "' is not an object")
    viewports = ref.get("viewports") or []
    if not isinstance(viewports, list):
        die("'" + path + "': viewports must be a list")
    for v in viewports:
        width = v.get("width") if isinstance(v, dict) else None
        if (not isinstance(v, dict) or not isinstance(v.get("name"), str)
                or not isinstance(v.get("node_id"), str) or isinstance(width, bool)
                or not isinstance(width, (int, float)) or not width > 0 or math.isnan(width)
                or not (v.get("context") is None or isinstance(v.get("context"), str))):
            die("'" + path + "': each viewport needs a name, node_id, positive width and a context path or null")
    return viewports


def main(argv):
    if len(argv) != 3:
        die("expected exactly two arguments")
    breakpoints = breakpoint_list(argv[2])
    viewports = load(argv[1])
    if not viewports:
        print("single")
        return 0

    out = []
    variants = []
    for v in sorted(viewports, key=lambda v: v["width"]):
        node = v["node_id"].replace("-", ":")
        if v["context"] is None:
            out.append(["no-context", v["name"], node, fmt(v["width"])])
            continue
        table, _ = variant_table(v["context"])
        variants.append({"name": v["name"], "node": node, "width": v["width"], "table": table})
    if not variants:
        return emit(out)

    def interval(width):
        return sum(1 for b in breakpoints if width >= b)

    base = variants[0]
    lines = [["base", base["name"], base["node"], fmt(base["width"])]]
    for key, (node, props) in base["table"].items():
        for prop, value in props.items():
            lines.append(["value", "base", node, prop, value, node, key])

    effective = {key: dict(props) for key, (_, props) in base["table"].items()}
    taken = {interval(base["width"]): base}
    narrower = base
    for v in variants[1:]:
        slot = interval(v["width"])
        if slot in taken:
            lines += finding(v, taken[slot], narrower)
        else:
            taken[slot] = v
            lines += override(v, breakpoints[slot - 1], base, effective)
        narrower = v
    return emit(out + lines)


def override(v, at, base, effective):
    lines = [["media", str(at), v["name"], v["node"], fmt(v["width"])]]
    for key, (node, props) in v["table"].items():
        if key not in base["table"]:
            if props:
                lines.append(["unmatched", v["name"], node, key])
            continue
        base_node = base["table"][key][0]
        for prop, value in props.items():
            if not same(effective[key].get(prop), value):
                lines.append(["value", str(at), base_node, prop, value, node, key])
                effective[key][prop] = value
        for prop, value in effective[key].items():
            if prop not in props:
                lines.append(["not-overridden", str(at), base_node, prop, value, node, key])
    for key, (node, props) in base["table"].items():
        if props and key not in v["table"]:
            lines.append(["missing", v["name"], node, key])
    return lines


def finding(v, rep, narrower):
    lines = [["same-interval", v["name"], v["node"], fmt(v["width"]), rep["name"],
              threshold(narrower["width"], v["width"])]]
    for key, (node, props) in v["table"].items():
        if key not in rep["table"]:
            if props:
                lines.append(["unmatched", v["name"], node, key])
            continue
        rep_node, rep_props = rep["table"][key]
        for prop in list(props) + [p for p in rep_props if p not in props]:
            if not same(props.get(prop), rep_props.get(prop)):
                lines.append(["differs", v["name"], rep_node, prop, props.get(prop, "-"),
                              rep_props.get(prop, "-"), node, key])
    for key, (node, props) in rep["table"].items():
        if props and key not in v["table"]:
            lines.append(["missing", v["name"], node, key])
    return lines


def emit(lines):
    for line in lines:
        print("\t".join(line))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
