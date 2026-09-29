#!/usr/bin/env python3
# Run: python3 plugins/eds/shared/scripts/check-size-origin.py check \
#        blocks/<name>/<name>.css .ai/run-context/prototype-report.md \
#        .ai/run-context/design-context-values.tsv [<measure.json>]
#
# check-size-origin.py selectors <block.css>
# check-size-origin.py check <block.css> <prototype-report.md> <values.tsv> [<measure.json>]
#
# Deterministic. A fixed `width` or `height` on an element that holds text
# comes only from that element's own node in the design.
#
# A fixed size is a `width` or `height` declaration whose value is not a
# percentage and not a keyword (auto, fit-content, min-content, max-content,
# stretch, a CSS-wide keyword). `min-*` and `max-*` are never read. A length
# reached by calc() or var() is a fixed size. Rules inside @media, @supports,
# @container and @layer blocks are read; every other at-rule is skipped. A
# selector list is split, and each selector is checked on its own.
#
# `selectors` prints, once each and in order, every selector carrying a fixed
# size. Those are the selectors to measure.
#
# `check` reports each fixed size that no `## Design values` line of the
# prototype report ties to its node: a line with the same selector (one of its
# list, whitespace collapsed) and the same property, whose node has a value
# table row with that property and the same value. px lengths are compared as
# numbers; any other value as its text.
# A table path of `-` means no value table: nothing is tied.
#
# With a measurement file (the browser role's `measure` output), only a
# selector whose elements hold text (`holds_text: true`) can be reported. A
# selector the page does not match holds no text. A selector the file does not
# carry counts as holding text, and its line says `(not measured)`. A tied px
# size whose measured box is larger than the design value is listed as grown.
# Without a measurement file every untied fixed size is reported.
#
#   hit    TAB <selector> TAB <property> TAB <value> TAB <reason>
#   grown  TAB <selector> TAB <property> TAB design <value>, measured <n>px
#
# Exit codes: 0 — no hit; 1 — at least one hit; 2 — usage error (missing
# argument, unreadable file, malformed CSS, table row or measurement, or a
# found measurement without `holds_text`).

import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "compare_design_values",
    os.path.join(HERE, "..", "..", "skills", "eds-verify-design", "scripts", "compare-design-values.py"),
)
cdv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cdv)

SIZE_PROPERTIES = ("width", "height")
NOT_FIXED = {
    "auto", "fit-content", "min-content", "max-content", "stretch", "-webkit-fill-available",
    "-moz-available", "inherit", "initial", "unset", "revert", "revert-layer", "none",
}
GROUPING_AT_RULES = {"media", "supports", "container", "layer"}


def usage_error(msg):
    print(
        "usage: check-size-origin.py selectors <block.css>\n"
        "       check-size-origin.py check <block.css> <prototype-report.md> <values.tsv> [<measure.json>]\n"
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


# --- the CSS --------------------------------------------------------------

def strip_comments(css):
    out, i, quote = [], 0, None
    while i < len(css):
        c = css[i]
        if quote:
            out.append(c)
            if c == "\\" and i + 1 < len(css):
                out.append(css[i + 1])
                i += 1
            elif c == quote:
                quote = None
        elif c in "\"'":
            quote = c
            out.append(c)
        elif css.startswith("/*", i):
            end = css.find("*/", i + 2)
            if end < 0:
                usage_error("unclosed comment in the CSS")
            i = end + 2
            continue
        else:
            out.append(c)
        i += 1
    return "".join(out)


def split_top(text, sep):
    """Split on `sep` outside quotes, parentheses and brackets."""
    parts, depth, quote, start = [], 0, None, 0
    for i, c in enumerate(text):
        if quote:
            if c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c in "([":
            depth += 1
        elif c in ")]":
            depth -= 1
        elif c == sep and depth == 0:
            parts.append(text[start:i])
            start = i + 1
    parts.append(text[start:])
    return parts


def block_end(css, open_at):
    """Index of the `}` closing the `{` at open_at."""
    depth, quote, i = 0, None, open_at - 1
    while i + 1 < len(css):
        i += 1
        c = css[i]
        if quote:
            if c == "\\":
                i += 1
            elif c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i
    usage_error("unclosed block in the CSS")


def next_brace_or_semicolon(css, start):
    quote, depth = None, 0
    for i in range(start, len(css)):
        c = css[i]
        if quote:
            if c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        elif depth == 0 and c in "{;}":
            return i, c
    return len(css), None


def normalise_selector(selector):
    return re.sub(r"\s+", " ", selector.strip())


def selectors_of(prelude):
    return [normalise_selector(s) for s in split_top(prelude, ",") if s.strip()]


def rules(css):
    """(selector list, declaration body) for every style rule that is read."""
    i = 0
    while i < len(css):
        at, c = next_brace_or_semicolon(css, i)
        prelude = css[i:at].strip()
        if c is None:
            if prelude:
                usage_error(f"unterminated rule in the CSS: {prelude[:60]}")
            return
        if c == "}":
            usage_error("unmatched `}` in the CSS")
        if c == ";":
            i = at + 1  # @import, @charset, ...
            continue
        end = block_end(css, at)
        body = css[at + 1:end]
        if prelude.startswith("@"):
            name = re.match(r"@([-\w]+)", prelude)
            if name and name.group(1).lower() in GROUPING_AT_RULES:
                yield from rules(body)
        else:
            if "{" in body:
                usage_error(f"nested rule in the CSS is not read: {prelude[:60]}")
            yield selectors_of(prelude), body
        i = end + 1


def is_fixed(value):
    v = value.strip().lower()
    return bool(v) and "%" not in v and v not in NOT_FIXED and not v.startswith("fit-content(")


def fixed_sizes(css):
    """[(selector, property, value)] in source order, each once."""
    seen, out = set(), []
    for sels, body in rules(strip_comments(css)):
        for decl in split_top(body, ";"):
            if ":" not in decl:
                continue
            prop, value = decl.split(":", 1)
            prop = prop.strip().lower()
            value = re.sub(r"\s*!important\s*$", "", value.strip(), flags=re.I).strip()
            if prop not in SIZE_PROPERTIES or not is_fixed(value):
                continue
            for sel in sels:
                key = (sel, prop, value)
                if key not in seen:
                    seen.add(key)
                    out.append(key)
    return out


# --- ties -----------------------------------------------------------------

def same_value(a, b):
    pa, pb = cdv.px(a.strip()), cdv.px(b.strip())
    if pa is not None and pb is not None:
        return pa == pb
    return re.sub(r"\s+", " ", a.strip().lower()) == re.sub(r"\s+", " ", b.strip().lower())


def reason_untied(selector, prop, value, lines, rows):
    """None when a report line ties the size to its node's row, else why not."""
    nodes = []
    for line_selector, line_prop, _, node in lines:
        if line_prop != prop or selector not in selectors_of(line_selector):
            continue
        if any(n == node and p == prop and same_value(v, value) for n, p, v, _ in rows):
            return None
        if node not in nodes:
            nodes.append(node)
    if not nodes:
        return "no report line ties it to a node"
    return f"node {', '.join(nodes)} has no {prop} {value} row"


# --- the measurement ------------------------------------------------------

def read_measurement(path):
    try:
        data = json.loads(read_text(path))
    except ValueError as e:
        usage_error(f"'{path}' is not readable JSON: {e}")
    if not isinstance(data, dict) or not isinstance(data.get("results"), dict):
        usage_error(f"'{path}': expected an object with a `results` object")
    results = data["results"]
    for selector, result in results.items():
        if isinstance(result, dict) and result.get("found") and not isinstance(result.get("holds_text"), bool):
            usage_error(f"'{path}': found selector '{selector}' has no boolean holds_text")
    return results


def grown(result, prop, value):
    """The measured box side as text when it is larger than a px design value."""
    want = cdv.px(value.strip())
    geometry = result.get("geometry") if isinstance(result, dict) else None
    side = geometry.get(prop) if isinstance(geometry, dict) else None
    if want is None or isinstance(side, bool) or not isinstance(side, (int, float)):
        return None
    if side <= float(want[:-2]) + 0.5:
        return None
    return f"{round(float(side), 2):f}".rstrip("0").rstrip(".") + "px"


# --- main -----------------------------------------------------------------

def check(css_path, report_path, table_path, measure_path):
    sizes = fixed_sizes(read_text(css_path))
    lines = list(cdv.design_value_lines(read_text(report_path)))
    rows = [] if table_path == "-" else cdv.read_table(table_path)
    results = read_measurement(measure_path) if measure_path else None

    out, listed = [], []
    for selector, prop, value in sizes:
        note = ""
        if results is not None:
            result = results.get(selector)
            if result is None:
                note = " (not measured)"
            elif not isinstance(result, dict) or not result.get("found") or not result["holds_text"]:
                continue
        why = reason_untied(selector, prop, value, lines, rows)
        if why:
            out.append(("hit", selector, prop, value, why + note))
        elif results is not None and not note:
            side = grown(results[selector], prop, value)
            if side:
                listed.append(("grown", selector, prop, f"design {value}, measured {side}"))

    for line in out + listed:
        print("\t".join(line))
    sys.exit(1 if out else 0)


def main():
    args = sys.argv[1:]
    if args[:1] == ["selectors"] and len(args) == 2:
        seen = []
        for selector, _, _ in fixed_sizes(read_text(args[1])):
            if selector not in seen:
                seen.append(selector)
                print(selector)
        sys.exit(0)
    if args[:1] == ["check"] and len(args) in (4, 5):
        check(args[1], args[2], args[3], args[4] if len(args) == 5 else None)
    usage_error("expected `selectors <css>` or `check <css> <report> <table> [<measurement>]`")


if __name__ == "__main__":
    main()
