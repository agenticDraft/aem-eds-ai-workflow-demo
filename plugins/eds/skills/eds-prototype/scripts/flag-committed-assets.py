#!/usr/bin/env python3
# Run: python3 plugins/eds/skills/eds-prototype/scripts/flag-committed-assets.py scan <path>...
#
# flag-committed-assets.py scan <path>...
# flag-committed-assets.py check <report.md> <path>...
#
# Deterministic. Run from the project root, inside its git checkout. Each
# <path> is a placed asset file, relative to the root. Its MIME type comes
# from its leading bytes, never its name. Whether it will be committed comes
# from the checkout's own ignore rules: a path git ignores is never committed;
# every other path is.
#
# scan prints one tab-separated row per path, in argument order:
#
#   ignored   <path> <bytes> <mime>            ignored; never committed
#   committed <path> <bytes> <mime>            committed text (SVG)
#   flag      <path> <bytes> <mime> <line>     committed raster
#
# Committed files are not optimised automatically, so every committed raster
# is flagged, whatever its size. <line> is the exact report line for it:
#
#   [optimise] <path> — <bytes> bytes — <mime>
#
# check exits 0 when <report.md> holds, for every path scan would flag, a line
# that is that report line, optionally preceded by "- ". Otherwise it exits 1
# and names each path whose line is missing.
#
# Exit codes: 0 — rows printed, or check passed; 1 — check found a flagged
# path with no report line; 2 — refused, nothing printed: unknown mode, no
# path, an absolute path or a `..` segment, a missing or non-regular file,
# bytes that are not PNG, JPEG, GIF, WebP or SVG, or not inside a checkout.

import os
import re
import subprocess
import sys

RASTER = {
    "image/png": lambda b: b.startswith(b"\x89PNG\r\n\x1a\n"),
    "image/jpeg": lambda b: b.startswith(b"\xff\xd8\xff"),
    "image/gif": lambda b: b.startswith(b"GIF87a") or b.startswith(b"GIF89a"),
    "image/webp": lambda b: len(b) >= 12 and b[:4] == b"RIFF" and b[8:12] == b"WEBP",
}

SVG_PROLOGUE = re.compile(
    rb"\A(?:\xef\xbb\xbf)?\s*(?:<\?xml[^>]*\?>\s*)?(?:(?:<!--.*?-->|<!DOCTYPE[^>]*>)\s*)*<svg[\s>]",
    re.S,
)


class Refused(Exception):
    pass


def mime_of(data):
    for mime, test in RASTER.items():
        if test(data):
            return mime
    if SVG_PROLOGUE.match(data):
        return "image/svg+xml"
    return None


def report_line(path, size, mime):
    return f"[optimise] {path} — {size} bytes — {mime}"


def ignored(path):
    result = subprocess.run(
        ["git", "check-ignore", "-q", "--", path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if result.returncode == 0:
        return True
    if result.returncode == 1:
        return False
    raise Refused(f"not inside a git checkout, or git refused: {path}")


def classify(paths):
    if not paths:
        raise Refused("no path given")
    inside = subprocess.run(
        ["git", "rev-parse", "--is-inside-work-tree"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if inside.returncode != 0 or inside.stdout.strip() != b"true":
        raise Refused("not inside a git checkout")
    rows = []
    for path in paths:
        if os.path.isabs(path) or ".." in path.split("/"):
            raise Refused(f"path must be relative to the project root, without '..': {path}")
        if not os.path.isfile(path):
            raise Refused(f"not a file: {path}")
        with open(path, "rb") as handle:
            data = handle.read()
        mime = mime_of(data)
        if mime is None:
            raise Refused(f"not a PNG, JPEG, GIF, WebP or SVG image: {path}")
        size = len(data)
        if ignored(path):
            rows.append(("ignored", path, size, mime))
        elif mime == "image/svg+xml":
            rows.append(("committed", path, size, mime))
        else:
            rows.append(("flag", path, size, mime))
    return rows


def scan(paths):
    for kind, path, size, mime in classify(paths):
        fields = [kind, path, str(size), mime]
        if kind == "flag":
            fields.append(report_line(path, size, mime))
        print("\t".join(fields))
    return 0


def check(report, paths):
    if not os.path.isfile(report):
        raise Refused(f"no report: {report}")
    rows = classify(paths)
    with open(report, encoding="utf-8") as handle:
        lines = {line.rstrip("\n") for line in handle}
    lines |= {line[2:] for line in lines if line.startswith("- ")}
    missing = [
        path
        for kind, path, size, mime in rows
        if kind == "flag" and report_line(path, size, mime) not in lines
    ]
    for path in missing:
        print(f"no optimise line in {report} for committed binary: {path}", file=sys.stderr)
    return 1 if missing else 0


def main(argv):
    if len(argv) < 2 or argv[1] not in ("scan", "check"):
        raise Refused("usage: flag-committed-assets.py scan <path>... | check <report.md> <path>...")
    if argv[1] == "scan":
        return scan(argv[2:])
    if len(argv) < 3:
        raise Refused("check needs a report path")
    return check(argv[2], argv[3:])


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Refused as refusal:
        print(f"flag-committed-assets: {refusal}", file=sys.stderr)
        sys.exit(2)
