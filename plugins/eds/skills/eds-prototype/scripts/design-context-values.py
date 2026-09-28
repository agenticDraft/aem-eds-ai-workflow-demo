#!/usr/bin/env python3
# Run: python3 plugins/eds/skills/eds-prototype/scripts/design-context-values.py .ai/run-context/design-reference.json
#
# design-context-values.py <design-reference.json>
#
# Deterministic. Reads the reference code that `design-reference.json`'s
# `design_context.code_file` names and prints one row per arbitrary-value
# class on an element carrying a `data-node-id`:
#
#   <node_id> TAB <css-property> TAB <value>
#
# Rows follow document order, then class order within an element; an
# identical row is printed once. The code file is resolved against the
# working directory (the project root).
#
# A class is read only when its prefix names exactly one CSS property:
#
#   p px py pt pr pb pl ps pe      padding, padding-inline, padding-block, ...
#   m mx my mt mr mb ml ms me      margin, margin-inline, margin-block, ...
#   gap gap-x gap-y                gap, column-gap, row-gap
#   rounded rounded-tl/tr/br/bl    border-radius, border-<corner>-radius
#   w h min-w min-h max-w max-h    width, height, min-/max- width/height
#   leading tracking opacity       line-height, letter-spacing, opacity
#   text                           font-size for a length, color for a colour
#   border                         border-width for a length, border-color for a colour
#   bg                             background-color for a colour
#   font                           font-weight for an integer
#   [<property>:<value>]           the property it names
#
# A `length:` or `color:` type hint picks the form and is dropped from the
# value. An underscore in the value is a space; `\_` is a literal underscore.
# Every other class is ignored: an unlisted prefix, a value whose form does
# not decide the property, a variant (`md:`, `hover:`), a negative (`-mt-`),
# an important (`!`) or a modifier (`/[...]`) form. No property is guessed.
#
# Exit codes: 0 — the table was printed (it may be empty); 2 — usage error
# (missing or unreadable file, malformed design_context); 3 — design_context
# is null, so there is no reference code and nothing is printed.

import json
import os
import re
import sys

FIXED = {
    "p": "padding", "px": "padding-inline", "py": "padding-block",
    "pt": "padding-top", "pr": "padding-right", "pb": "padding-bottom", "pl": "padding-left",
    "ps": "padding-inline-start", "pe": "padding-inline-end",
    "m": "margin", "mx": "margin-inline", "my": "margin-block",
    "mt": "margin-top", "mr": "margin-right", "mb": "margin-bottom", "ml": "margin-left",
    "ms": "margin-inline-start", "me": "margin-inline-end",
    "gap": "gap", "gap-x": "column-gap", "gap-y": "row-gap",
    "rounded": "border-radius",
    "rounded-tl": "border-top-left-radius", "rounded-tr": "border-top-right-radius",
    "rounded-br": "border-bottom-right-radius", "rounded-bl": "border-bottom-left-radius",
    "w": "width", "h": "height",
    "min-w": "min-width", "min-h": "min-height", "max-w": "max-width", "max-h": "max-height",
    "leading": "line-height", "tracking": "letter-spacing", "opacity": "opacity",
}

# prefix -> {form: property}; a value of any other form is ignored
BY_FORM = {
    "text": {"length": "font-size", "color": "color"},
    "border": {"length": "border-width", "color": "border-color"},
    "bg": {"color": "background-color"},
    "font": {"integer": "font-weight"},
}

HINTS = {"length": "length", "color": "color"}

ARBITRARY_VALUE = re.compile(r"^([a-z]+(?:-[a-z]+)*)-\[([^\[\]]+)\]$")
ARBITRARY_PROPERTY = re.compile(r"^\[(-{0,2}[a-z][a-z0-9-]*):([^\[\]]+)\]$")
LENGTH = re.compile(
    r"^-?(\d+\.?\d*|\.\d+)(px|rem|em|%|vw|vh|vmin|vmax|svh|lvh|dvh|ch|ex|lh|rlh|pt|pc|cm|mm|in|q)$"
    r"|^0$|^(calc|clamp|min|max)\(.*\)$"
)
COLOR = re.compile(
    r"^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"
    r"|^(rgba?|hsla?|hwb|lab|lch|oklab|oklch|color)\(.*\)$"
)
INTEGER = re.compile(r"^\d+$")
TAG_OPEN = re.compile(r"<([A-Za-z][\w.:-]*)")
ATTR_NAME = re.compile(r"[A-Za-z_:@$][\w:.$-]*")


def usage_error(msg):
    print(f"usage: design-context-values.py <design-reference.json>\n{msg}", file=sys.stderr)
    sys.exit(2)


def decode(value):
    return value.replace("\\_", "\0").replace("_", " ").replace("\0", "_")


def form_of(value):
    if LENGTH.match(value):
        return "length"
    if COLOR.match(value):
        return "color"
    if INTEGER.match(value):
        return "integer"
    return None


def class_row(cls):
    m = ARBITRARY_PROPERTY.match(cls)
    if m:
        return m.group(1), decode(m.group(2))
    m = ARBITRARY_VALUE.match(cls)
    if not m:
        return None
    prefix, raw = m.group(1), decode(m.group(2))
    hint = None
    head, sep, rest = raw.partition(":")
    if sep and head in HINTS:
        hint, raw = HINTS[head], rest
    if prefix in FIXED:
        return FIXED[prefix], raw
    if prefix in BY_FORM:
        form = hint or form_of(raw)
        prop = BY_FORM[prefix].get(form)
        if prop:
            return prop, raw
    return None


def skip_string(code, i):
    quote = code[i]
    i += 1
    while i < len(code) and code[i] != quote:
        i += 2 if code[i] == "\\" else 1
    return i + 1


def skip_braces(code, i):
    depth = 0
    while i < len(code):
        c = code[i]
        if c in "\"'`":
            i = skip_string(code, i)
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return i


def literal(expr):
    expr = expr.strip()
    if len(expr) >= 2 and expr[0] == expr[-1] and expr[0] in "\"'`":
        inner = expr[1:-1]
        if expr[0] == "`" and "${" in inner:
            return None
        return inner
    return None


def elements(code):
    pos = 0
    while True:
        m = TAG_OPEN.search(code, pos)
        if not m:
            return
        i = m.end()
        attrs = {}
        while i < len(code):
            while i < len(code) and code[i].isspace():
                i += 1
            if i >= len(code) or code[i] == ">" or code.startswith("/>", i):
                break
            if code[i] == "{":
                i = skip_braces(code, i)
                continue
            n = ATTR_NAME.match(code, i)
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
                    end = skip_string(code, i)
                    attrs[name] = code[i + 1:end - 1]
                    i = end
                elif i < len(code) and code[i] == "{":
                    end = skip_braces(code, i)
                    attrs[name] = literal(code[i + 1:end - 1])
                    i = end
        yield attrs
        pos = i


def main():
    if len(sys.argv) != 2:
        usage_error("expected exactly one argument")
    ref_path = sys.argv[1]
    if not os.path.isfile(ref_path):
        usage_error(f"'{ref_path}' not found")
    try:
        with open(ref_path, encoding="utf-8") as f:
            ref = json.load(f)
    except (OSError, ValueError) as e:
        usage_error(f"'{ref_path}' is not readable JSON: {e}")

    context = ref.get("design_context") if isinstance(ref, dict) else None
    if context is None:
        print(f"no reference code: '{ref_path}' has design_context null", file=sys.stderr)
        sys.exit(3)
    if not isinstance(context, dict) or not isinstance(context.get("code_file"), str):
        usage_error(f"'{ref_path}': design_context must be null or an object with a code_file path")
    code_file = context["code_file"]
    if not os.path.isfile(code_file):
        usage_error(f"'{code_file}' not found — design_context names it as the code file")
    with open(code_file, encoding="utf-8") as f:
        code = f.read()

    seen = set()
    for attrs in elements(code):
        node = attrs.get("data-node-id")
        classes = attrs.get("className") or attrs.get("class")
        if not node or not classes:
            continue
        for cls in classes.split():
            row = class_row(cls)
            if row is None:
                continue
            line = f"{node}\t{row[0]}\t{row[1]}"
            if line not in seen:
                seen.add(line)
                print(line)
    sys.exit(0)


if __name__ == "__main__":
    main()
