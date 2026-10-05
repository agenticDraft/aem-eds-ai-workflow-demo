#!/usr/bin/env python3
# Run: python3 plugins/eds/shared/scripts/check-breakpoint-regressions.py check \
#        <measure.json> [<measure.json>...]
#
# check-breakpoint-regressions.py selectors <block.css>
# check-breakpoint-regressions.py check <measure.json> [<measure.json>...]
#
# Deterministic. Whether a block regressed at a width its design reference
# does not show (D123), read from the browser role's `measure` output, one
# file per width.
#
# `selectors` prints, once each and in source order, every selector whose rule
# declares a `min-width` other than a keyword or zero. Those are the selectors
# to measure, so that signal B below can be read. Rules inside @media,
# @supports, @container and @layer blocks are read; a selector list is split.
#
# `check` reads each measurement's `width` and every found selector, in the
# order given, and prints one line per selector and signal:
#
#   A  a word broken across lines — the selector's `broken_words` is not empty
#      [fixable] at <w>px, <selector>: <n> word(s) broken across lines (<words>)
#      <words> is the first five distinct words, then `…` when there are more.
#   B  a box narrower than its own min-width — the first match's geometry width
#      is more than half a pixel below its computed `min-width` in px
#      [fixable] at <w>px, <selector>: <n>px wide, narrower than its own min-width <m>px
#
# A `min-width` that is not a px length (auto, none, a percentage) is not read.
# A selector the page did not match, or reported `hidden: true` at this width
# (no visible match), is skipped: neither signal is read on a hidden element.
# Nothing is printed for a width where neither signal fires.
#
# Exit codes: 0 — nothing fired; 1 — at least one line; 2 — usage error
# (missing argument, unreadable or malformed file, a measurement without a
# width, or a found selector without geometry, `min-width` or `broken_words`).

import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("check_size_origin", os.path.join(HERE, "check-size-origin.py"))
cso = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cso)

PX = re.compile(r"^(\d+(?:\.\d+)?)px$")
NOT_A_MINIMUM = {"auto", "none", "0", "0px", "inherit", "initial", "unset", "revert", "revert-layer"}
WORDS_NAMED = 5
TOLERANCE = 0.5


def usage_error(msg):
    print(
        "usage: check-breakpoint-regressions.py selectors <block.css>\n"
        "       check-breakpoint-regressions.py check <measure.json> [<measure.json>...]\n"
        f"{msg}",
        file=sys.stderr,
    )
    sys.exit(2)


def read_text(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as error:
        usage_error(f"cannot read '{path}': {error.strerror}")


def number(value):
    return not isinstance(value, bool) and isinstance(value, (int, float))


def px_text(value):
    rounded = round(value, 1)
    return f"{int(rounded)}px" if float(rounded).is_integer() else f"{rounded}px"


def selectors(css_path):
    seen = []
    for sels, body in cso.rules(cso.strip_comments(read_text(css_path))):
        for decl in cso.split_top(body, ";"):
            if ":" not in decl:
                continue
            prop, value = decl.split(":", 1)
            value = re.sub(r"\s*!important\s*$", "", value.strip(), flags=re.I).strip().lower()
            if prop.strip().lower() != "min-width" or not value or value in NOT_A_MINIMUM:
                continue
            for sel in sels:
                if sel not in seen:
                    seen.append(sel)
    for sel in seen:
        print(sel)
    return 0


def read_measurement(path):
    try:
        data = json.loads(read_text(path))
    except ValueError as error:
        usage_error(f"'{path}' is not JSON: {error}")
    if not isinstance(data, dict) or not isinstance(data.get("results"), dict):
        usage_error(f"'{path}' has no results")
    width = data.get("width")
    if not number(width) or width <= 0:
        usage_error(f"'{path}' has no viewport width; measure it with a width")
    for sel, result in data["results"].items():
        if not isinstance(result, dict) or result.get("found") is not True or result.get("hidden") is True:
            continue
        geometry = result.get("geometry")
        computed = result.get("computed")
        if not isinstance(geometry, dict) or not number(geometry.get("width")):
            usage_error(f"'{path}': {sel} has no geometry width")
        if not isinstance(computed, dict) or not isinstance(computed.get("min-width"), str):
            usage_error(f"'{path}': {sel} has no computed min-width")
        if not isinstance(result.get("broken_words"), list):
            usage_error(f"'{path}': {sel} has no broken_words")
    return width, data["results"]


def findings(width, results):
    at = f"at {px_text(width)}"
    for sel, result in results.items():
        if not isinstance(result, dict) or result.get("found") is not True or result.get("hidden") is True:
            continue
        words = result["broken_words"]
        if words:
            distinct = list(dict.fromkeys(str(w) for w in words))
            named = ", ".join(distinct[:WORDS_NAMED]) + (", …" if len(distinct) > WORDS_NAMED else "")
            noun = "word" if len(words) == 1 else "words"
            yield f"[fixable] {at}, {sel}: {len(words)} {noun} broken across lines ({named})"
        minimum = PX.match(result["computed"]["min-width"].strip())
        box = result["geometry"]["width"]
        if minimum and box < float(minimum.group(1)) - TOLERANCE:
            yield (f"[fixable] {at}, {sel}: {px_text(box)} wide, narrower than its own "
                   f"min-width {px_text(float(minimum.group(1)))}")


def check(paths):
    lines = []
    for path in paths:
        lines.extend(findings(*read_measurement(path)))
    for line in lines:
        print(line)
    return 1 if lines else 0


def main(argv):
    if len(argv) == 3 and argv[1] == "selectors":
        return selectors(argv[2])
    if len(argv) >= 3 and argv[1] == "check":
        return check(argv[2:])
    usage_error("expected a mode and its arguments")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
