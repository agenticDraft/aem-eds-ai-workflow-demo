#!/usr/bin/env python3
# Run: python3 plugins/eds/shared/scripts/design-fonts.py .ai/run-context/design-reference.json .
#
# design-fonts.py <design-reference.json> [project-root]
#
# Deterministic (D530). Prints each font family the design names that the
# project does not declare, one per line, in first-seen order, each once.
#
# The design names a family in, read in this order:
#   1. `variables` — a value holding `Font(family: "<name>", ...)`;
#   2. `design_context.styles` — the same form inside the string;
#   3. `design_context.code_file`, then each `viewports[].context` — a class
#      `font-['<name>:<style>']`, `font-[<name>]` (never an integer, which is
#      a weight) or `[font-family:<a>,<b>]`; an underscore is a space.
#
# The project declares a family with an `@font-face` rule's `font-family` in
# a `.css` file under `<project-root>/styles/` or `<project-root>/blocks/`.
# A family only named in a `font-family` declaration is not declared: nothing
# loads it. Comments are ignored.
#
# Two names are the same family when they match ignoring case, quotes, and
# any run of spaces, underscores and hyphens (`DM_Sans` = `'DM Sans'` =
# `dm-sans`). A generic family (`sans-serif`, `monospace`, `system-ui`, ...)
# and a CSS-wide keyword are never named.
#
# A project may declare design fonts out of scope, once, in
# `<project-root>/.ai/design/fonts.yaml`:
#
#   version: 1
#   design_fonts: out-of-scope
#
# With that file present, an undeclared family is still named, but the exit
# code says it is not a warning (3, below): the project has decided that no
# run adds, loads or asks for a font. Any other content in that file is a
# usage error — `out-of-scope` is the only value defined.
#
# Exit codes: 0 — every family is declared (nothing printed); 1 — at least one
# is missing; 3 — at least one is missing and the project declares design
# fonts out of scope; 2 — usage error (missing or unreadable file, malformed
# record, a declaration file with other content).

import glob
import json
import os
import re
import sys

GENERIC = {
    "serif", "sans serif", "monospace", "cursive", "fantasy", "system ui", "math", "emoji",
    "fangsong", "ui serif", "ui sans serif", "ui monospace", "ui rounded",
    "inherit", "initial", "unset", "revert", "revert layer",
}

FONT_VALUE = re.compile(r'Font\(family:\s*"([^"]+)"')
FONT_CLASS = re.compile(r"(?<![\w-])font-\[([^\[\]]+)\]")
FAMILY_PROPERTY = re.compile(r"\[font-family:([^\[\]]+)\]")
INTEGER = re.compile(r"^\d+$")
COMMENT = re.compile(r"/\*.*?\*/", re.S)
FONT_FACE = re.compile(r"@font-face\s*\{([^}]*)\}", re.I)
FACE_FAMILY = re.compile(r"font-family\s*:\s*([^;}]+)", re.I)


def usage_error(msg):
    print(f"usage: design-fonts.py <design-reference.json> [project-root]\n{msg}", file=sys.stderr)
    sys.exit(2)


def key(name):
    return re.sub(r"[\s_-]+", " ", name.strip().strip("'\"").strip()).casefold()


def decode(value):
    return value.replace("\\_", "\0").replace("_", " ").replace("\0", "_")


def code_families(code):
    for m in FONT_CLASS.finditer(code):
        raw = m.group(1).strip("'\"")
        if raw.startswith("family-name:"):
            raw = raw[len("family-name:"):]
        if INTEGER.match(raw) or raw.startswith(("length:", "number:", "var(", "--")):
            continue
        yield decode(raw.split(":", 1)[0])
    for m in FAMILY_PROPERTY.finditer(code):
        for part in decode(m.group(1)).split(","):
            yield part.strip().strip("'\"")


def read_code(path):
    if not os.path.isfile(path):
        usage_error(f"'{path}' not found — the design reference names it as reference code")
    with open(path, encoding="utf-8") as f:
        return f.read()


def design_families(ref):
    variables = ref.get("variables")
    if isinstance(variables, dict):
        for value in variables.values():
            if isinstance(value, str):
                yield from FONT_VALUE.findall(value)
    context = ref.get("design_context")
    if context is not None and not isinstance(context, dict):
        usage_error("design_context must be null or an object")
    if context:
        if isinstance(context.get("styles"), str):
            yield from FONT_VALUE.findall(context["styles"])
        if isinstance(context.get("code_file"), str):
            yield from code_families(read_code(context["code_file"]))
    for variant in ref.get("viewports") or []:
        if isinstance(variant, dict) and isinstance(variant.get("context"), str):
            yield from code_families(read_code(variant["context"]))


DECLARATION = os.path.join(".ai", "design", "fonts.yaml")
KEY_VALUE = re.compile(r"^([A-Za-z_][\w-]*):\s*(.*)$")


def fonts_out_of_scope(root):
    """True when the project declares design fonts out of scope; False when it
    declares nothing; a usage error for a declaration saying anything else."""
    path = os.path.join(root, DECLARATION)
    if not os.path.isfile(path):
        return False
    values = {}
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            m = KEY_VALUE.match(line)
            if not m:
                usage_error(f"'{path}': unreadable line: {raw.rstrip()}")
            values[m.group(1)] = m.group(2).strip().strip("'\"")
    if values.get("version") != "1":
        usage_error(f"'{path}': version must be 1")
    scope = values.get("design_fonts")
    if scope is None:
        usage_error(f"'{path}': design_fonts is missing; the only defined value is out-of-scope")
    if scope != "out-of-scope":
        usage_error(f"'{path}': design_fonts must be out-of-scope, got '{scope}'")
    return True


def declared_families(root):
    declared = set()
    for area in ("styles", "blocks"):
        for path in sorted(glob.glob(os.path.join(root, area, "**", "*.css"), recursive=True)):
            with open(path, encoding="utf-8", errors="replace") as f:
                css = COMMENT.sub("", f.read())
            for face in FONT_FACE.finditer(css):
                for family in FACE_FAMILY.findall(face.group(1)):
                    declared.add(key(family))
    return declared


def main():
    if len(sys.argv) not in (2, 3):
        usage_error("expected a design reference and an optional project root")
    ref_path = sys.argv[1]
    root = sys.argv[2] if len(sys.argv) == 3 else "."
    if not os.path.isfile(ref_path):
        usage_error(f"'{ref_path}' not found")
    try:
        with open(ref_path, encoding="utf-8") as f:
            ref = json.load(f)
    except (OSError, ValueError) as e:
        usage_error(f"'{ref_path}' is not readable JSON: {e}")
    if not isinstance(ref, dict):
        usage_error(f"'{ref_path}' is not a design reference object")

    out_of_scope = fonts_out_of_scope(root)
    declared = declared_families(root)
    seen = set()
    missing = []
    for name in design_families(ref):
        k = key(name)
        if not k or k in GENERIC or k in declared or k in seen:
            continue
        seen.add(k)
        missing.append(name.strip())
    for name in missing:
        print(name)
    if not missing:
        sys.exit(0)
    sys.exit(3 if out_of_scope else 1)


if __name__ == "__main__":
    main()
