#!/usr/bin/env python3
# Run: python3 plugins/eds/shared/scripts/find-baseline-target.py <block> <paths.preview> .
#
# find-baseline-target.py <block> <preview-url> [project-root]
#
# Deterministic (D532). Finds the first existing page in this checkout that
# holds <block>, and prints `<page path>\t<target URL>` on one line.
#
# The pages searched are the `.html` files git lists for the checkout —
# tracked, plus untracked files .gitignore does not exclude — in path order.
# Anything under `drafts/` is never searched, ignored or not: it holds a run's
# own fixtures, not existing content.
#
# A page holds <block> when an element's `class` attribute has <block> as its
# first token — the authored block (`class="table striped"`) and the rendered
# one (`class="table block"`) both.
#
# The target URL is the preview URL's origin plus the page path with
# `.plain.html` or `.html` removed; a page named `index` maps to its folder.
#
# Exit codes: 0 — a page was found; 1 — none was (nothing printed);
# 2 — usage error (missing argument, a block name that is not a folder name,
# a preview URL without scheme and host, a root that is not a git checkout).

import re
import subprocess
import sys
from urllib.parse import urlsplit

BLOCK_NAME = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
CLASS_ATTR = re.compile(r"""\bclass\s*=\s*(?:"([^"]*)"|'([^']*)')""", re.IGNORECASE)
EXCLUDED = ("drafts/",)


def usage(message):
    print(f"find-baseline-target: {message}", file=sys.stderr)
    sys.exit(2)


def listed_pages(root):
    result = subprocess.run(
        ["git", "-C", root, "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        usage(f"{root} is not a git checkout")
    paths = {p for p in result.stdout.split("\0") if p.endswith(".html")}
    return sorted(p for p in paths if not p.startswith(EXCLUDED))


def holds_block(text, block):
    for match in CLASS_ATTR.finditer(text):
        tokens = (match.group(1) if match.group(1) is not None else match.group(2)).split()
        if tokens and tokens[0] == block:
            return True
    return False


def target_url(origin, path):
    for suffix in (".plain.html", ".html"):
        if path.endswith(suffix):
            path = path[: -len(suffix)]
            break
    if path == "index" or path.endswith("/index"):
        path = path[: -len("index")]
    return f"{origin}/{path}"


def main(argv):
    if len(argv) not in (3, 4):
        usage("usage: find-baseline-target.py <block> <preview-url> [project-root]")
    block, preview = argv[1], argv[2]
    root = argv[3] if len(argv) == 4 else "."
    if not BLOCK_NAME.match(block):
        usage(f"not a block folder name: {block!r}")
    parts = urlsplit(preview)
    if not parts.scheme or not parts.netloc:
        usage(f"preview URL has no scheme and host: {preview!r}")
    origin = f"{parts.scheme}://{parts.netloc}"

    for path in listed_pages(root):
        try:
            with open(f"{root}/{path}", encoding="utf-8", errors="replace") as handle:
                text = handle.read()
        except OSError:
            continue
        if holds_block(text, block):
            print(f"{path}\t{target_url(origin, path)}")
            return 0
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
