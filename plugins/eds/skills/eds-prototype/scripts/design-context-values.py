#!/usr/bin/env python3
# Run: python3 plugins/eds/skills/eds-prototype/scripts/design-context-values.py .ai/run-context/design-reference.json
#
# design-context-values.py <design-reference.json>
#
# Deterministic. Reads the reference code that `design-reference.json`'s
# `design_context.code_file` names and prints one row per property an
# arbitrary-value class sets, on an element carrying a `data-node-id`:
#
#   <node_id> TAB <css-property> TAB <value> TAB <approx>
#
# <approx> is `true` when the value depends on the design's content, so a
# rendering with other content cannot be expected to reproduce it: the
# property is width, height, min-height or aspect-ratio, and the node is a
# text node, contains one, or carries an image fill. Every other row is
# `false`; padding, gap and margin are never approx.
#
# A node holds text when non-whitespace copy sits anywhere inside its element:
# JSX text between tags, or a string literal in braces. Nesting follows the
# opening and closing tags; a comment or any other expression is not copy.
# A node carries an image fill when the reference's `assets` list names it
# with a raster image type (any `image/` type but `image/svg+xml`, which is a
# vector export). Rendered text is never read, only whether there is any.
#
# Rows follow document order, then class order within an element, then the
# class's property order; an identical row is printed once. The code file is resolved against the
# working directory (the project root).
#
# A class is read only when its prefix names its CSS properties:
#
#   p px py pt pr pb pl ps pe      padding, padding-inline, padding-block, ...
#   m mx my mt mr mb ml ms me      margin, margin-inline, margin-block, ...
#   gap gap-x gap-y                gap, column-gap, row-gap
#   rounded rounded-tl/tr/br/bl    border-radius, border-<corner>-radius
#   w h min-w min-h max-w max-h    width, height, min-/max- width/height
#   size                           width and height, two rows, for a length only
#   aspect                         aspect-ratio
#   leading tracking opacity       line-height, letter-spacing, opacity
#   text                           font-size for a length, color for a colour
#   border                         border-width for a length, border-color for a colour
#   bg                             background-color for a colour
#   font                           font-weight for an integer
#   [<property>:<value>]           the property it names
#
# A property one element's classes set to two different values is a conflict:
# it gets no row, and one `conflict: <node_id> <property> <value> <value>…`
# line on stderr names it. The same value set twice is one row, not a conflict.
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
    "aspect": "aspect-ratio",
    "leading": "line-height", "tracking": "letter-spacing", "opacity": "opacity",
}

# prefix -> the properties one length value sets; a value of any other form is ignored
BOTH = {"size": ("width", "height")}

# the properties whose value may follow the content; never padding, gap or margin
APPROX_PROPERTIES = {"width", "height", "min-height", "aspect-ratio"}
VECTOR_MIME = "image/svg+xml"

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
TAG_ANY = re.compile(r"<(/?)([A-Za-z][\w.:-]*)")
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


def class_rows(cls):
    """The (property, value) pairs one class sets, in property order; [] when it is ignored."""
    m = ARBITRARY_PROPERTY.match(cls)
    if m:
        return [(m.group(1), decode(m.group(2)))]
    m = ARBITRARY_VALUE.match(cls)
    if not m:
        return []
    prefix, raw = m.group(1), decode(m.group(2))
    hint = None
    head, sep, rest = raw.partition(":")
    if sep and head in HINTS:
        hint, raw = HINTS[head], rest
    if prefix in FIXED:
        return [(FIXED[prefix], raw)]
    if prefix in BOTH:
        if (hint or form_of(raw)) == "length":
            return [(prop, raw) for prop in BOTH[prefix]]
        return []
    if prefix in BY_FORM:
        form = hint or form_of(raw)
        prop = BY_FORM[prefix].get(form)
        if prop:
            return [(prop, raw)]
    return []


def element_rows(classes):
    """(rows, conflicts) for one element's class list: rows in class then property order,
    without the conflicting properties; conflicts as (property, [values in class order])."""
    pairs = []
    for cls in classes.split():
        for pair in class_rows(cls):
            if pair not in pairs:
                pairs.append(pair)
    values = {}
    for prop, value in pairs:
        values.setdefault(prop, []).append(value)
    conflicts = [(prop, vals) for prop, vals in values.items() if len(vals) > 1]
    clashing = {prop for prop, _ in conflicts}
    return [pair for pair in pairs if pair[0] not in clashing], conflicts


def report_conflicts(node, conflicts):
    for prop, vals in conflicts:
        print(f"conflict: {node} {prop} {' '.join(vals)}", file=sys.stderr)


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


def read_tag(code, i):
    """Attributes of the opening tag whose name ends at i: (attrs, end, self_closing)."""
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
    return attrs, i, True


def close(stack, tag):
    """Pop the innermost open element named tag, and everything opened inside it."""
    if any(t == tag for t, _ in stack):
        while stack[-1][0] != tag:
            stack.pop()
        stack.pop()


def text_nodes(code):
    """Node ids whose element holds copy, directly or in any descendant."""
    found = set()
    stack = []  # (tag, node id or None) per open element; a fragment's tag is ""
    i = 0
    while i < len(code):
        if code.startswith("<>", i):
            stack.append(("", None))
            i += 2
            continue
        if code.startswith("</>", i):
            close(stack, "")
            i += 3
            continue
        m = TAG_ANY.match(code, i)
        if m:
            if m.group(1):
                end = code.find(">", m.end())
                i = len(code) if end < 0 else end + 1
                close(stack, m.group(2))
                continue
            attrs, i, self_closing = read_tag(code, m.end())
            if not self_closing:
                stack.append((m.group(2), attrs.get("data-node-id") or None))
            continue
        c = code[i]
        if not stack:
            i += 1
            continue
        copy = False
        if c == "{":
            end = skip_braces(code, i)
            value = literal(code[i + 1:end - 1])
            copy = bool(value and value.strip())
            i = end
        else:
            copy = not c.isspace()
            i += 1
        if copy:
            found.update(node for _, node in stack if node)
    return found


def image_nodes(ref):
    """Node ids the reference's assets list names with a raster image type."""
    found = set()
    assets = ref.get("assets")
    for asset in assets if isinstance(assets, list) else []:
        if not isinstance(asset, dict):
            continue
        node, mime = asset.get("node_id"), asset.get("mime")
        if isinstance(node, str) and isinstance(mime, str) and mime.startswith("image/") and mime != VECTOR_MIME:
            found.add(node)
    return found


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

    content = text_nodes(code) | image_nodes(ref)
    seen = set()
    for attrs in elements(code):
        node = attrs.get("data-node-id")
        classes = attrs.get("className") or attrs.get("class")
        if not node or not classes:
            continue
        rows, conflicts = element_rows(classes)
        report_conflicts(node, conflicts)
        for prop, value in rows:
            approx = "true" if prop in APPROX_PROPERTIES and node in content else "false"
            line = f"{node}\t{prop}\t{value}\t{approx}"
            if line not in seen:
                seen.add(line)
                print(line)
    sys.exit(0)


if __name__ == "__main__":
    main()
