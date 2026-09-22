#!/usr/bin/env python3
# Run: python3 .claude/skills/write-specs/scripts/write-item.py <draft-file> [--project <key>]
"""write-item.py <draft-file> [--project <key>]

Write a checked draft to the tracker through the tracker role's contracted
operations, and say which write happened.

Everything here is a decision a script can make and prose cannot make
reliably. Which operation applies is not a judgement — it is whether the item
exists — and asking a model to decide it invites an update to a key nobody
issued, or a second copy of an item that was already there. So the work is:
resolve the configured tracker pack, ask it whether the item exists, pick the
operation from the answer, and run it.

Nothing here decides pass or fail. The operation's own result envelope does,
and this script passes it through as it came.

Exit codes:
  0 — an operation ran; its envelope is on stdout. `verdict:` says how it went.
  1 — no operation could run: the pack declares it unsupported, or declares
      no such operation at all. The draft is unwritten and the reason is on
      stdout as an envelope, so a caller reports one shape either way.
  2 — usage error, or a config, pack or script that cannot be read.
"""

import json
import os
import re
import subprocess
import sys

SKILL_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SKILL_DIR)

# check-spec.py already resolves the configured packs and an operation's skill
# from a pack manifest. Importing it keeps one resolver rather than a second
# copy that drifts the first time a manifest's shape changes.
import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location(
    "check_spec", os.path.join(SKILL_DIR, "check-spec.py"))
check_spec = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_spec)

CONFIG = os.path.join(".ai", "project-config.yaml")


def usage(msg):
    print(f"usage error: {msg}", file=sys.stderr)
    sys.exit(2)


def envelope(verdict, summary, artifacts=(), next_action="none"):
    lines = ["## Result", f"verdict: {verdict}", f"summary: {summary}"]
    if artifacts:
        lines.append("artifacts:")
        lines += [f"  - {a}" for a in artifacts]
    else:
        lines.append("artifacts: []")
    lines.append(f"next_action: {next_action}")
    print("\n".join(lines))


def read_unsupported(pack_yaml):
    with open(pack_yaml, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^unsupported:\s*\[(.*)\]\s*$", line)
            if m:
                return [v.strip() for v in m.group(1).split(",") if v.strip()]
    return []


def declared_operation(pack_yaml, operation):
    """The skill name for an operation, or None when the pack declines it.

    Declining and never declaring are different states and both mean 'this
    write cannot happen here', so they are reported separately rather than
    collapsed — a pack that says 'unsupported' has answered the question, and
    a pack that says nothing has a manifest someone should look at."""
    if operation in read_unsupported(pack_yaml):
        return None, f"the configured tracker declares {operation} unsupported"
    with open(pack_yaml, encoding="utf-8") as f:
        for line in f:
            m = re.match(rf"^\s\s{operation}:\s*(\S+)\s*$", line)
            if m:
                return m.group(1), None
    return None, f"the configured tracker declares no {operation} operation"


def item_exists(pack_root, fetch_skill, item_key):
    """Whether the tracker already has this key.

    A key in a draft's front matter is what someone expects, not what the
    tracker has issued. The difference decides which operation runs, so it is
    established by asking rather than by trusting the draft."""
    script = os.path.join(pack_root, "skills", fetch_skill, "scripts",
                          f"{fetch_skill}.sh")
    if not os.path.isfile(script):
        check_spec.unreadable(f"'{script}' not found")
    result = subprocess.run(["bash", script, item_key],
                            capture_output=True, text=True)
    return "verdict: pass" in (result.stdout or "")


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        usage("a draft file is required")
    draft, project = argv[0], None
    rest = argv[1:]
    while rest:
        if rest[0] == "--project" and len(rest) >= 2:
            project, rest = rest[1], rest[2:]
        else:
            usage("the only option is '--project <key>'")

    if not os.path.isfile(draft):
        usage(f"draft not found: {draft}")

    fields, _ = check_spec.parse_draft(draft)
    item_key = (fields.get("item_id") or "").strip()

    packs = check_spec.read_pack_names(CONFIG)
    pack_root = os.path.join("plugins", packs["tracker"])
    pack_yaml = os.path.join(pack_root, "pack.yaml")
    if not os.path.isfile(pack_yaml):
        check_spec.unreadable(f"'{pack_yaml}' not found")

    fetch_skill, _ = declared_operation(pack_yaml, "fetch_item")
    exists = bool(item_key) and fetch_skill and item_exists(
        pack_root, fetch_skill, item_key)

    if exists:
        operation, args = "update_item", [item_key, draft]
    else:
        if not project:
            usage("no item to update, so this is a create — pass --project <key>")
        operation, args = "create_item", [project, draft]

    skill, refusal = declared_operation(pack_yaml, operation)
    if skill is None:
        envelope("fail", f"{refusal}; the draft is unwritten.")
        return 1

    script = os.path.join(pack_root, "skills", skill, "scripts", f"{skill}.sh")
    if not os.path.isfile(script):
        check_spec.unreadable(f"'{script}' not found")

    result = subprocess.run(["bash", script] + args,
                            capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    print(f"operation: {operation}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
