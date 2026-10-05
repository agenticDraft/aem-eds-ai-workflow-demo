#!/usr/bin/env python3
# Run: python3 plugins/eds/shared/scripts/evidence-manifest.py gaps \
#        --check .ai/run-context/verify-design-check-2.txt \
#        --variables .ai/run-context/verify-design-variables-2.txt \
#        --compare .ai/run-context/verify-design-compare-2.txt
#
# evidence-manifest.py gaps [--check <check file>] [--variables <variables output>]
#                           [--compare <compare output>]
# evidence-manifest.py merge <manifest.json> --item-id <id> --target <url>
#                           --target-reachable true|false --reason <text>
#                           --gaps <file, one gap per line> --attachments <file, a JSON array>
#
# Deterministic. The two things a verification stage used to do in prose and
# inline shell when it wrote the evidence manifest, done once here so both
# writers agree:
#
# `gaps` turns a check's outputs into coverage-gap strings, one per line on
# stdout, in this order: the check file's tagged entries, then the value
# comparison's `variables` output, then its `compare` output. Lines that say
# the same thing are written once:
#
#   [content-asset gap] <text>        → content-asset gap: <text>
#   [content-dependent] <text>        → content-dependent, not graded: <text>
#   [fixable] …, untagged lines         not a gap; skipped
#   variables: unmeasured <var> <sel> <prop> <detail>
#       → design variable '<var>' (<prop> on <sel>) was judged visually only,
#         not confirmed numerically: <detail>
#       <var> is `-` → design value for <prop> on <sel> matches no design
#         variable, so it was judged visually only: <detail>
#       <sel> is `-` → design variable '<var>' was judged visually only, not
#         confirmed numerically: <detail>
#   compare: unmeasured <node> <sel> <prop> <value>: <reason>
#       → design value '<prop> <value>' on node(s) <nodes> was judged
#         visually only: <reason>
#   compare: approx <node> <sel> <prop> <detail>
#       → content-dependent, not graded: <sel> <prop>: <detail> (node(s) <nodes>)
#       <sel> is `-` → content-dependent, not graded: <prop> <value> on
#         node(s) <nodes>: <reason>
#   match, mismatch                     not a gap; skipped
#
# Lines that differ only in their node are one gap naming every node, in
# first-seen order; lines that are identical and carry no node are one gap
# with a count, `(×<n>)`, when there is more than one. A gap is never dropped
# and never reworded beyond these templates.
#
# `merge` writes the manifest: when the file is absent, from the given fields;
# when present, the union — existing entries first, then the new ones, each
# `coverage_gaps` string once and each `attachments` path once (first
# occurrence kept, order kept), with the given `item_id`, `target`,
# `target_reachable` and `target_reachable_reason` replacing the file's (the
# later writer is the more recent measurement). `version` is always "1.0".
# Written through a temporary file, so a refused call leaves the file as it
# was. Prints one line:
#
#   written: <path> gaps=<n> (+<new> new, <d> duplicate dropped) attachments=<m> (+<new> new, <d> duplicate dropped)
#
# Exit codes: 0 — done; 2 — usage error (missing argument, unreadable or
# malformed file, a malformed output line, an attachment without path, width
# or label, --target-reachable not `true`/`false`). Nothing is written on 2.

import json
import os
import sys

TAGS = {
    "[content-asset gap]": "content-asset gap: {}",
    "[content-dependent]": "content-dependent, not graded: {}",
}
KNOWN_STATUSES = {"match", "mismatch", "unmeasured", "approx"}


def usage_error(msg):
    print(
        "usage: evidence-manifest.py gaps [--check <file>] [--variables <file>] [--compare <file>]\n"
        "       evidence-manifest.py merge <manifest.json> --item-id <id> --target <url>\n"
        "                                 --target-reachable true|false --reason <text>\n"
        "                                 --gaps <file> --attachments <file.json>\n"
        f"{msg}",
        file=sys.stderr,
    )
    sys.exit(2)


def read_lines(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read().splitlines()
    except OSError as error:
        usage_error(f"'{path}': {error.strerror}")


def read_json(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except OSError as error:
        usage_error(f"'{path}': {error.strerror}")
    except ValueError as error:
        usage_error(f"'{path}' is not JSON: {error}")


# --- gaps -----------------------------------------------------------------

class Gaps:
    """Gap strings in first-seen order; a key is the text without its node or
    count, and carries the nodes seen (or the number of repeats)."""

    def __init__(self):
        self.order = []
        self.nodes = {}
        self.count = {}

    def add(self, key, node=None):
        if key not in self.count:
            self.order.append(key)
            self.count[key] = 0
            self.nodes[key] = []
        self.count[key] += 1
        if node is not None and node not in self.nodes[key]:
            self.nodes[key].append(node)

    def lines(self):
        out = []
        for key in self.order:
            nodes = self.nodes[key]
            if "{nodes}" in key:
                word = "node" if len(nodes) == 1 else "nodes"
                out.append(key.replace("{nodes}", f"{word} {', '.join(nodes)}"))
            elif self.count[key] > 1:
                out.append(f"{key} (×{self.count[key]})")
            else:
                out.append(key)
        return out


def split_detail(detail):
    """`<value>: <reason>` → (value, reason); a detail with no `: ` is all reason."""
    if ": " in detail:
        value, reason = detail.split(": ", 1)
        return value, reason
    return None, detail


def tsv_rows(path, want):
    rows = []
    for number, raw in enumerate(read_lines(path), 1):
        if not raw.strip():
            continue
        parts = raw.split("\t")
        if len(parts) != 5 or parts[0] not in KNOWN_STATUSES:
            usage_error(f"'{path}' line {number}: expected `<status> TAB <a> TAB <selector> TAB <property> TAB <detail>`")
        if parts[0] in want:
            rows.append(parts)
    return rows


def gaps_from_check(path, gaps):
    for raw in read_lines(path):
        line = raw.strip()
        for tag, template in TAGS.items():
            if line.startswith(tag):
                gaps.add(template.format(line[len(tag):].strip()))
                break


def gaps_from_variables(path, gaps):
    for _, name, selector, prop, detail in tsv_rows(path, {"unmeasured"}):
        if name == "-":
            gaps.add(f"design value for {prop} on {selector} matches no design variable, "
                     f"so it was judged visually only: {detail}")
        elif selector == "-":
            gaps.add(f"design variable '{name}' was judged visually only, not confirmed numerically: {detail}")
        else:
            gaps.add(f"design variable '{name}' ({prop} on {selector}) was judged visually only, "
                     f"not confirmed numerically: {detail}")


def gaps_from_compare(path, gaps):
    for status, node, selector, prop, detail in tsv_rows(path, {"unmeasured", "approx"}):
        value, reason = split_detail(detail)
        if status == "unmeasured":
            named = f"{prop} {value}" if value is not None else prop
            gaps.add(f"design value '{named}' on {{nodes}} was judged visually only: {reason}", node)
        elif selector == "-":
            named = f"{prop} {value}" if value is not None else prop
            gaps.add(f"content-dependent, not graded: {named} on {{nodes}}: {reason}", node)
        else:
            gaps.add(f"content-dependent, not graded: {selector} {prop}: {detail} ({{nodes}})", node)


def gaps_mode(args):
    files = {"--check": None, "--variables": None, "--compare": None}
    rest = list(args)
    while rest:
        flag = rest.pop(0)
        if flag not in files or not rest:
            usage_error(f"gaps: unexpected or incomplete argument '{flag}'")
        files[flag] = rest.pop(0)
    if all(path is None for path in files.values()):
        usage_error("gaps: name at least one of --check, --variables, --compare")
    gaps = Gaps()
    if files["--check"]:
        gaps_from_check(files["--check"], gaps)
    if files["--variables"]:
        gaps_from_variables(files["--variables"], gaps)
    if files["--compare"]:
        gaps_from_compare(files["--compare"], gaps)
    for line in gaps.lines():
        print(line)
    return 0


# --- merge ----------------------------------------------------------------

def read_attachments(path):
    data = read_json(path)
    if not isinstance(data, list):
        usage_error(f"'{path}': expected a JSON array of attachments")
    for index, entry in enumerate(data):
        if not isinstance(entry, dict) or set(entry) != {"path", "width", "label"}:
            usage_error(f"'{path}' entry {index}: expected exactly path, width and label")
        if not isinstance(entry["path"], str) or not entry["path"]:
            usage_error(f"'{path}' entry {index}: path must be a non-empty string")
        if isinstance(entry["width"], bool) or not isinstance(entry["width"], (int, float)) or entry["width"] <= 0:
            usage_error(f"'{path}' entry {index}: width must be a positive number")
        if not isinstance(entry["label"], str) or not entry["label"]:
            usage_error(f"'{path}' entry {index}: label must be a non-empty string")
    return data


def read_gaps_file(path):
    return [line.strip() for line in read_lines(path) if line.strip()]


def read_existing(path):
    if not os.path.exists(path):
        return [], []
    data = read_json(path)
    if not isinstance(data, dict):
        usage_error(f"'{path}': expected an object")
    gaps = data.get("coverage_gaps", [])
    attachments = data.get("attachments", [])
    if not isinstance(gaps, list) or not all(isinstance(g, str) for g in gaps):
        usage_error(f"'{path}': coverage_gaps must be an array of strings")
    if not isinstance(attachments, list) or not all(isinstance(a, dict) and isinstance(a.get("path"), str) for a in attachments):
        usage_error(f"'{path}': attachments must be an array of objects with a path")
    return gaps, attachments


def union(existing, new, key):
    """existing then new, each key once, first occurrence kept; returns (merged, added, dropped)."""
    merged, seen, added, dropped = [], set(), 0, 0
    for source, items in (("existing", existing), ("new", new)):
        for item in items:
            k = key(item)
            if k in seen:
                dropped += 1
                continue
            seen.add(k)
            merged.append(item)
            if source == "new":
                added += 1
    return merged, added, dropped


def merge_mode(args):
    if not args:
        usage_error("merge: the manifest path is missing")
    path = args[0]
    opts = {"--item-id": None, "--target": None, "--target-reachable": None,
            "--reason": None, "--gaps": None, "--attachments": None}
    rest = list(args[1:])
    while rest:
        flag = rest.pop(0)
        if flag not in opts or not rest:
            usage_error(f"merge: unexpected or incomplete argument '{flag}'")
        opts[flag] = rest.pop(0)
    missing = [flag for flag, value in opts.items() if value is None]
    if missing:
        usage_error(f"merge: missing {', '.join(missing)}")
    for flag in ("--item-id", "--target", "--reason"):
        if not opts[flag].strip():
            usage_error(f"merge: {flag} must not be empty")
    if opts["--target-reachable"] not in ("true", "false"):
        usage_error(f"merge: --target-reachable must be true or false, got '{opts['--target-reachable']}'")

    new_gaps = read_gaps_file(opts["--gaps"])
    new_attachments = read_attachments(opts["--attachments"])
    old_gaps, old_attachments = read_existing(path)

    gaps, gaps_added, gaps_dropped = union(old_gaps, new_gaps, lambda g: g)
    attachments, att_added, att_dropped = union(old_attachments, new_attachments, lambda a: a["path"])

    manifest = {
        "version": "1.0",
        "item_id": opts["--item-id"],
        "target": opts["--target"],
        "target_reachable": opts["--target-reachable"] == "true",
        "target_reachable_reason": opts["--reason"],
        "coverage_gaps": gaps,
        "attachments": attachments,
    }
    tmp = f"{path}.tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as handle:
            json.dump(manifest, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
        os.replace(tmp, path)
    except OSError as error:
        usage_error(f"'{path}': {error.strerror}")
    print(f"written: {path} gaps={len(gaps)} (+{gaps_added} new, {gaps_dropped} duplicate dropped) "
          f"attachments={len(attachments)} (+{att_added} new, {att_dropped} duplicate dropped)")
    return 0


def main(argv):
    if len(argv) >= 2 and argv[1] == "gaps":
        return gaps_mode(argv[2:])
    if len(argv) >= 2 and argv[1] == "merge":
        return merge_mode(argv[2:])
    usage_error("the mode must be gaps or merge")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
