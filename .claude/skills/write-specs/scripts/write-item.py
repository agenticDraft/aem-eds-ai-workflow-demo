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
      no such operation at all, or the update would move an existing item
      onto another component. The draft is unwritten and the reason is on
      stdout as an envelope, so a caller reports one shape either way.
  2 — usage error, or a config, pack or script that cannot be read.
"""

import json
import os
import re
import subprocess
import sys
import tempfile

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


def read_target(item, extractor, tracker_pack):
    """The components and block names an item targets, as the run's own
    extractor reads them — never a second reading of the text that could
    disagree with what a route would see."""
    tmp = tempfile.mkdtemp(prefix="write-item-")
    item_json = os.path.join(tmp, "item.json")
    fact_record = os.path.join(tmp, "fact-record.yaml")
    with open(item_json, "w", encoding="utf-8") as f:
        json.dump(item, f)
    result = subprocess.run(
        ["python3", extractor, item_json, tracker_pack, fact_record,
         os.path.join(tmp, "sanitized-spec.md")],
        capture_output=True, text=True)
    if result.returncode != 0:
        check_spec.unreadable("intake extractor: " + (result.stderr or "").strip())
    lists = {}
    with open(fact_record, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^(components|files_named):\s*\[(.*)\]\s*$", line)
            if m:
                lists[m.group(1)] = [v.strip().strip('"') for v in m.group(2).split(",")
                                     if v.strip()]
    components = set(lists.get("components", []))
    blocks = {m.group(1) for p in lists.get("files_named", [])
              for m in [re.match(r"^blocks/([^/]+)/", p)] if m}
    return components, blocks


def retarget_reason(item_key, live, draft):
    """Why this update would move the item onto another component, or None.

    A different target is a different item: rewriting one in place leaves the
    old target in the structured fields, where a route reads it and a person
    may not see it."""
    (live_components, live_blocks), (draft_components, draft_blocks) = live, draft
    if live_components and live_components != draft_components:
        return (f"{item_key} carries components {sorted(live_components)}; the draft "
                f"carries {sorted(draft_components)}")
    if live_blocks and draft_blocks and not live_blocks & draft_blocks:
        return (f"{item_key} names blocks {sorted(live_blocks)}; the draft names "
                f"{sorted(draft_blocks)}, none of them the same")
    return None


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
    pack_root = check_spec.plugin_root(packs["tracker"], os.getcwd())
    pack_yaml = os.path.join(pack_root, "pack.yaml")
    if not os.path.isfile(pack_yaml):
        check_spec.unreadable(f"'{pack_yaml}' not found")

    fetch_skill, _ = declared_operation(pack_yaml, "fetch_item")
    exists = bool(item_key) and fetch_skill and item_exists(
        pack_root, fetch_skill, item_key)

    if exists:
        platform_root = check_spec.plugin_root(packs["platform"], os.getcwd())
        intake_skill = check_spec.read_stage_skill(
            os.path.join(platform_root, "pack.yaml"), "intake")
        extractor = os.path.join(platform_root, "skills", intake_skill,
                                 "scripts", "extract-fact-record.py")
        if not os.path.isfile(extractor):
            check_spec.unreadable(f"'{extractor}' not found")
        fetch_script = os.path.join(pack_root, "skills", fetch_skill, "scripts",
                                    f"{fetch_skill}.sh")
        live = read_target(check_spec.fetch_item(fetch_script, item_key),
                           extractor, pack_yaml)
        body = check_spec.parse_draft(draft)[1]
        reason = retarget_reason(item_key, live, read_target(
            check_spec.synthesize_item(fields, body), extractor, pack_yaml))
        if reason:
            envelope("fail", f"{reason} — an item is not rewritten onto another "
                     f"component; create a new item instead (--project <key>, no "
                     f"item_id). The draft is unwritten.")
            return 1
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
