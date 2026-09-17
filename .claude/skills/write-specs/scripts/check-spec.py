#!/usr/bin/env python3
"""check-spec.py — Deterministic conformance check for a work-item draft, or for
a work item already in the tracker. No model involved.

Two passes.

  route  A dry run. The platform pack's own intake extractor, the readiness
         checker and the stage-condition evaluator are executed against the
         text, so the report shows the fact record the route would compute and
         the stages that would fire. Nothing in this file re-implements those
         detectors; a second implementation would drift from the first.

  form   House rules no contract covers: criterion ids numbered from 1, one
         assertion per criterion, the sections an item of this type must carry,
         a summary that is a phrase rather than a sentence, and every component
         directory written with its trailing slash. Which heading carries the
         acceptance criteria and which carries the reproduction steps is read
         from the tracker pack's own text_conventions, never hardcoded here.

Usage:
  check-spec.py <path-to-draft.md>   — check a local draft
  check-spec.py <ITEM-KEY>           — fetch the item through the tracker pack
                                       and check what is really in it

Draft format: a front-matter block (item_type, summary, and optionally item_id,
labels and components) followed by the item's description as markdown.

Exit codes:
  0 — every form rule holds and readiness would pass; "valid: write-specs (...)"
      on stdout, with any review notes listed above it
  1 — at least one form violation, or readiness would fail; one
      "invalid: <reason>" line per violation on stderr, then a count
  2 — usage error, or a pack, script or config file that cannot be read
"""

import json
import os
import re
import subprocess
import sys
import tempfile

VAGUE = [
    "properly", "correctly", "nicely", "appropriately", "as expected",
    "user-friendly", "looks good", "look good", "seamless", "intuitive",
    "works well", "reasonable", "sensible",
]

AC_LINE_RE = re.compile(r"^AC-(\d+)\b[.)\s]*(.*)$")
LIST_LINE_RE = re.compile(r"^\s*(?:[-*+•]|\d+[.)])\s+\S")
HEADING_RE = re.compile(r"^##\s+(.+?)\s*$")
SENTENCE_END_RE = re.compile(r"\.(?:\s|$)")
BLOCK_NO_SLASH_RE = re.compile(r"\bblocks/[\w-]+(?![\w/-])")
ITEM_KEY_RE = re.compile(r"^[A-Z][A-Z0-9_]*-\d+$")

violations = []
notes = []
checks = 0


def usage_error(msg):
    print(f"usage error: {msg}", file=sys.stderr)
    sys.exit(2)


def unreadable(msg):
    print(f"usage error: {msg}", file=sys.stderr)
    sys.exit(2)


def violation(msg):
    violations.append(msg)


def note(msg):
    notes.append(msg)


def ok(desc):
    global checks
    checks += 1
    print(f"  ok: {desc}")


# --- configuration -----------------------------------------------------------

def read_pack_names(config_path):
    """The packs block of the project config: one 'key: value' line per role."""
    if not os.path.isfile(config_path):
        unreadable(f"'{config_path}' not found")
    names, in_packs = {}, False
    with open(config_path, encoding="utf-8") as f:
        for line in f:
            if re.match(r"^packs:\s*$", line):
                in_packs = True
                continue
            if in_packs:
                m = re.match(r"^\s\s(\w+):\s*(\S+)\s*$", line.rstrip("\n"))
                if m:
                    names[m.group(1)] = m.group(2)
                elif line.strip() and not line.startswith(" "):
                    break
    for role in ("platform", "tracker"):
        if role not in names:
            unreadable(f"'{config_path}' declares no {role} pack")
    return names


def read_stage_skill(pack_yaml, stage_id):
    """The skill a platform pack's stage list names for one stage id."""
    if not os.path.isfile(pack_yaml):
        unreadable(f"'{pack_yaml}' not found")
    current = None
    with open(pack_yaml, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^\s*-\s+id:\s*(\S+)\s*$", line)
            if m:
                current = m.group(1)
                continue
            m = re.match(r"^\s*skill:\s*(\S+)\s*$", line)
            if m and current == stage_id:
                return m.group(1)
    unreadable(f"'{pack_yaml}' declares no '{stage_id}' stage")


def read_operation_skill(pack_yaml, operation):
    """The skill a provider pack's operations block names for one operation."""
    if not os.path.isfile(pack_yaml):
        unreadable(f"'{pack_yaml}' not found")
    with open(pack_yaml, encoding="utf-8") as f:
        for line in f:
            m = re.match(rf"^\s\s{operation}:\s*(\S+)\s*$", line)
            if m:
                return m.group(1)
    unreadable(f"'{pack_yaml}' declares no '{operation}' operation")


def read_text_conventions(pack_yaml):
    """The tracker pack's heading tokens. Same one-line-per-key shape the
    pack-manifest validator requires."""
    lists = {"acceptance_criteria_headings": [], "reproduction_headings": []}
    pattern = re.compile(
        r"^\s\s(acceptance_criteria_headings|reproduction_headings):\s\[(.*)\]$")
    with open(pack_yaml, encoding="utf-8") as f:
        for line in f:
            m = pattern.match(line.rstrip("\n"))
            if m:
                lists[m.group(1)] = [v.strip() for v in m.group(2).split(",") if v.strip()]
    return lists


# --- input -------------------------------------------------------------------

def parse_draft(path):
    """Front matter plus body. Returns (fields, body)."""
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n?(.*)$", raw, re.DOTALL)
    if not m:
        unreadable(f"'{path}' has no front-matter block")
    fields, body = {}, m.group(2)
    for line in m.group(1).split("\n"):
        km = re.match(r"^(\w+):\s*(.*)$", line.strip())
        if not km:
            continue
        key, value = km.group(1), km.group(2).strip()
        if value.startswith("[") and value.endswith("]"):
            fields[key] = [v.strip() for v in value[1:-1].split(",") if v.strip()]
        else:
            fields[key] = value
    for key in ("item_type", "summary"):
        if not fields.get(key):
            unreadable(f"'{path}' front matter declares no {key}")
    return fields, body


def synthesize_item(fields, body):
    """A tracker-shaped item built from the draft, so the real extractor can
    read it. No attachment can exist yet, so a draft's only design source is a
    design-tool URL in its own text."""
    return {
        "key": fields.get("item_id") or "DRAFT-0",
        "fields": {
            "issuetype": {"name": fields["item_type"]},
            "summary": fields["summary"],
            "labels": fields.get("labels") or [],
            "components": [{"name": c} for c in (fields.get("components") or [])],
            "attachment": [],
            "description": {
                "type": "doc",
                "content": [{"type": "paragraph",
                             "content": [{"type": "text", "text": body}]}],
            },
        },
    }


def fetch_item(fetch_script, item_key):
    if not os.path.isfile(fetch_script):
        unreadable(f"'{fetch_script}' not found")
    result = subprocess.run(["bash", fetch_script, item_key],
                            capture_output=True, text=True)
    out_file = os.path.join(".ai", "tracker", f"fetch-item-{item_key}.json")
    if result.returncode != 0 or not os.path.isfile(out_file):
        # A fetch that cannot run reports itself in a result envelope and exits 0,
        # so the envelope's own summary line is the reason, not the exit code.
        combined = ((result.stdout or "") + "\n" + (result.stderr or "")).strip()
        reason = next((line.partition(":")[2].strip()
                       for line in combined.splitlines()
                       if line.startswith("summary:")), None)
        unreadable(f"fetching {item_key} failed: {reason or combined.splitlines()[-1] if combined else 'no output'}")
    with open(out_file, encoding="utf-8") as f:
        return json.load(f)


# --- form pass ---------------------------------------------------------------

def find_heading(headings, candidates):
    """First heading whose text matches one of candidates, case-insensitively."""
    wanted = [c.lower() for c in candidates]
    for index, text in headings:
        if text.lower() in wanted:
            return index, text
    return None


def check_summary(summary):
    if summary.endswith("."):
        violation(f"summary ends in a full stop — a phrase, not a sentence: '{summary}'")
    elif len(summary.split()) > 8:
        violation(f"summary is {len(summary.split())} words, more than 8: '{summary}'")
    else:
        ok(f"summary is a phrase ({len(summary.split())} words)")


def check_sections(headings, item_type, conventions):
    """Returns the acceptance-criteria heading, so the criteria check can read
    that section without looking for it a second time."""
    ac_headings = conventions["acceptance_criteria_headings"]
    repro_headings = conventions["reproduction_headings"]
    if item_type.lower() == "bug":
        required = [("a description", ["Description"]),
                    ("reproduction steps", repro_headings),
                    ("acceptance criteria", ac_headings)]
    else:
        required = [("a description", ["Description"]),
                    ("acceptance criteria", ac_headings),
                    ("an out-of-scope section", ["Out of scope"])]
        if item_type.lower() != "story":
            note(f"item_type '{item_type}' has no section rules of its own; "
                 "checked against the story rules")
    found, last_index, ordered = [], -1, True
    for label, candidates in required:
        hit = find_heading(headings, candidates)
        if hit is None:
            violation(f"no section carries {label} "
                      f"(expected a '## {candidates[0]}' heading)")
            continue
        index, text = hit
        found.append((label, text))
        if index < last_index:
            ordered = False
        last_index = index
    if len(found) == len(required):
        ok(f"every section an item of type '{item_type}' must carry is present")
        if ordered:
            ok("sections are in order")
        else:
            violation("sections are present but out of order: expected "
                      + " then ".join(f"'{f[1]}'" for f in found))
    return find_heading(headings, ac_headings)


def section_lines(lines, start_index):
    """The lines under one heading, up to the next one."""
    body = []
    for line in lines[start_index + 1:]:
        if HEADING_RE.match(line):
            break
        body.append(line)
    return body


def check_criteria(lines, ac_hit):
    if ac_hit is None:
        return
    body = section_lines(lines, ac_hit[0])
    ids, seen_any = [], False
    for line in body:
        stripped = line.strip()
        if not stripped:
            continue
        m = AC_LINE_RE.match(stripped)
        if m:
            seen_any = True
            ids.append(int(m.group(1)))
            check_one_criterion(f"AC-{m.group(1)}", m.group(2).strip())
            continue
        if LIST_LINE_RE.match(line):
            violation(f"criterion carries no AC-<n> id: '{stripped[:60]}'")
            seen_any = True
    if not seen_any:
        violation("the acceptance-criteria section holds no criteria")
        return
    if ids:
        expected = list(range(1, len(ids) + 1))
        if ids != expected:
            violation("criterion ids are not sequential from 1: got "
                      + ", ".join(f"AC-{i}" for i in ids))
        else:
            ok(f"{len(ids)} criteria, ids sequential from AC-1")


def check_one_criterion(label, text):
    if not text:
        violation(f"{label} has no text")
        return
    if ";" in text:
        violation(f"{label} joins clauses with a semicolon — split it into two criteria")
    if len(SENTENCE_END_RE.findall(text)) > 1:
        violation(f"{label} is more than one sentence — split it into two criteria")
    for word in VAGUE:
        if re.search(r"\b" + re.escape(word) + r"\b", text, re.IGNORECASE):
            violation(f"{label} is not checkable — '{word}' has no pass/fail threshold")
    if re.search(r"\band\b", text, re.IGNORECASE):
        note(f"{label} contains 'and' — confirm it is one assertion, not two")
    if len(text.split()) > 30:
        note(f"{label} is {len(text.split())} words — confirm it is one assertion")


def check_paths(text):
    misses = sorted(set(BLOCK_NO_SLASH_RE.findall(text)))
    for miss in misses:
        violation(f"'{miss}' has no trailing slash, so intake records no component "
                  f"for it — write '{miss}/'")
    if not misses:
        ok("every component directory carries its trailing slash")


# --- route pass --------------------------------------------------------------

def run(argv, label):
    result = subprocess.run(argv, capture_output=True, text=True)
    if result.returncode == 2:
        unreadable(f"{label}: {(result.stderr or '').strip()}")
    return result


def main():
    if len(sys.argv) != 2:
        usage_error("expected exactly one argument — a draft path or an item key")
    target = sys.argv[1]

    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.abspath(os.path.join(script_dir, "..", "..", "..", ".."))
    target_path = target if os.path.isabs(target) else os.path.abspath(target)
    os.chdir(repo_root)

    packs = read_pack_names(os.path.join(".ai", "project-config.yaml"))
    platform_pack = os.path.join("plugins", packs["platform"], "pack.yaml")
    tracker_pack = os.path.join("plugins", packs["tracker"], "pack.yaml")
    intake_skill = read_stage_skill(platform_pack, "intake")
    extractor = os.path.join("plugins", packs["platform"], "skills", intake_skill,
                             "scripts", "extract-fact-record.py")
    if not os.path.isfile(extractor):
        unreadable(f"'{extractor}' not found")
    lib = os.path.join("plugins", "agentic-core", "shared", "lib")
    conventions = read_text_conventions(tracker_pack)

    if os.path.isfile(target_path):
        fields, body = parse_draft(target_path)
        item = synthesize_item(fields, body)
        source = f"draft {target}"
    elif ITEM_KEY_RE.match(target):
        fetch_skill = read_operation_skill(tracker_pack, "fetch_item")
        fetch_script = os.path.join("plugins", packs["tracker"], "skills", fetch_skill,
                                    "scripts", "fetch-item.sh")
        item = fetch_item(fetch_script, target)
        source = f"item {target}"
    else:
        usage_error(f"'{target}' is neither an existing file nor an item key")

    tmp = tempfile.mkdtemp(prefix="check-spec-")
    item_json = os.path.join(tmp, "item.json")
    fact_record = os.path.join(tmp, "fact-record.yaml")
    sanitized = os.path.join(tmp, "sanitized-spec.md")
    with open(item_json, "w", encoding="utf-8") as f:
        json.dump(item, f)

    print(f"--- route ({source})")
    extracted = run(["python3", extractor, item_json, tracker_pack, fact_record, sanitized],
                    "intake extractor")
    if extracted.returncode != 0:
        unreadable("intake extractor: " + (extracted.stderr or "").strip())
    for line in extracted.stdout.strip().split("\n"):
        print(f"  {line}")
    with open(fact_record, encoding="utf-8") as f:
        facts = f.read()
    for line in facts.strip().split("\n"):
        if line.strip():
            print(f"  {line}")

    readiness = run(["bash", os.path.join(lib, "check-readiness-criteria.sh"),
                     platform_pack, fact_record], "readiness checker")
    readiness_line = (readiness.stdout or readiness.stderr or "").strip()
    print(f"  {readiness_line}")
    if readiness.returncode != 0:
        violation(f"readiness would fail — {readiness_line}")

    stages = run(["bash", os.path.join(lib, "evaluate-stage-conditions.sh"),
                  platform_pack, fact_record], "stage-condition evaluator")
    for line in (stages.stdout or "").strip().split("\n"):
        if line.strip():
            print(f"  {line}")

    print("--- form")
    with open(sanitized, encoding="utf-8") as f:
        text = f.read()
    lines = text.split("\n")
    headings = [(i, HEADING_RE.match(line).group(1))
                for i, line in enumerate(lines) if HEADING_RE.match(line)]
    check_summary(item["fields"]["summary"].strip())
    ac_hit = check_sections(headings, item["fields"]["issuetype"]["name"], conventions)
    check_criteria(lines, ac_hit)
    check_paths(text)

    for n in notes:
        print(f"  review: {n}")
    if violations:
        # The report above is stdout and the violations below are stderr; without
        # this the two streams interleave and the violations print first.
        sys.stdout.flush()
        for v in violations:
            print(f"invalid: {v}", file=sys.stderr)
        print(f"invalid: write-specs ({len(violations)} violations)", file=sys.stderr)
        sys.exit(1)
    print(f"valid: write-specs ({checks} checks passed, {len(notes)} review notes)")
    sys.exit(0)


if __name__ == "__main__":
    main()
