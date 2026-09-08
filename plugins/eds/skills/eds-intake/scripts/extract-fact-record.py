#!/usr/bin/env python3
# extract-fact-record.py <fetched-item.json> <tracker-pack.yaml> <out-fact-record.yaml> <out-sanitized-spec.md>
#
# Deterministic. No model involved: this is the literal-match half of the
# intake stage. It reads the raw work-item JSON a tracker's fetch_item
# operation wrote to disk, applies the tracker pack's own text_conventions
# word lists, and writes the two artifacts intake's own contract requires
# (fact-record.md, and the sanitized specification core contract SS4
# names). It has no knowledge of any tracker beyond the shape it is handed:
# item id/type/labels/components/description/attachments, and the three
# text_conventions lists it is passed a path to.
#
# Exit codes: 0 on success (both artifacts written, one summary line on
# stdout naming which literal-match fields matched, for the calling skill's
# own report); 1 for input that cannot be turned into a fact record
# (missing item id/type); 2 for a usage error.

import json
import os
import re
import sys


def usage_error(msg):
    print(f"usage: extract-fact-record.py <item.json> <tracker-pack.yaml> <out-fact-record.yaml> <out-sanitized-spec.md>\n{msg}", file=sys.stderr)
    sys.exit(2)


def fail(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def adf_to_text(node):
    """Recursively flatten an Atlassian Document Format node into plain text.
    No ADF library is used — this project's only ADF producer/consumer pair
    is this script and jira's own post-note skill, and the node shapes that
    actually appear in a work item's description are a small, stable set."""
    if node is None:
        return ""
    node_type = node.get("type")
    content = node.get("content", [])

    if node_type == "text":
        return node.get("text", "")
    if node_type == "hardBreak":
        return "\n"
    if node_type == "heading":
        level = min(int(node.get("attrs", {}).get("level", 1)), 6)
        inner = "".join(adf_to_text(c) for c in content)
        return ("#" * level) + " " + inner + "\n\n"
    if node_type == "paragraph":
        inner = "".join(adf_to_text(c) for c in content)
        return inner + "\n\n"
    if node_type in ("bulletList", "orderedList"):
        lines = []
        for i, item in enumerate(content):
            item_text = "".join(adf_to_text(c) for c in item.get("content", [])).strip()
            prefix = "- " if node_type == "bulletList" else f"{i + 1}. "
            lines.append(prefix + item_text)
        return "\n".join(lines) + "\n\n"
    if node_type == "codeBlock":
        inner = "".join(adf_to_text(c) for c in content)
        return "```\n" + inner + "\n```\n\n"
    # doc, blockquote, panel, table and anything else: recurse into content.
    return "".join(adf_to_text(c) for c in content)


def parse_text_conventions(pack_yaml_path):
    """Reads the three optional word lists from a tracker pack's
    text_conventions block. Same single-line-per-key shape
    validate-pack-manifest.sh's parser requires (shared/pack-manifest.md)."""
    lists = {"design_keywords": [], "reproduction_headings": [], "acceptance_criteria_headings": []}
    if not os.path.isfile(pack_yaml_path):
        return lists
    pattern = re.compile(r"^\s\s(design_keywords|reproduction_headings|acceptance_criteria_headings):\s\[(.*)\]$")
    with open(pack_yaml_path, encoding="utf-8") as f:
        for line in f:
            m = pattern.match(line.rstrip("\n"))
            if m:
                key, raw = m.group(1), m.group(2)
                values = [v.strip() for v in raw.split(",") if v.strip()]
                lists[key] = values
    return lists


def find_matches(text, words):
    """Case-insensitive, word-boundary-anchored match — not a bare substring
    search, so a short abbreviation ("AC") does not fire inside an unrelated
    word ("accordion"). Returns the list of words that matched, so the
    caller can report which literal token fired (fact-record.md's audit
    requirement)."""
    matches = []
    for w in words:
        pattern = re.compile(r"\b" + re.escape(w) + r"\b", re.IGNORECASE)
        if pattern.search(text):
            matches.append(w)
    return matches


URL_RE = re.compile(r"https?://\S+")
FILE_RE = re.compile(r"\b[\w./-]+\.(?:js|css|html|json|md)\b")
FIGMA_HOSTS = ("figma.com", "www.figma.com")


def any_design_url(text):
    """A design-tool URL, recognised the same way plugins/figma's own
    fetch-reference skill recognises one (host is figma.com or
    www.figma.com) — the only design provider pack this project ships.
    See phase-4-task-2-done.md for why this is not yet pack-configurable."""
    for url in URL_RE.findall(text):
        host_match = re.match(r"https?://([^/]+)", url)
        if host_match and host_match.group(1).lower() in FIGMA_HOSTS:
            return True
    return False


def yaml_list(values):
    if not values:
        return "[]"
    return "[" + ", ".join(values) + "]"


def yaml_bool(value):
    return "true" if value else "false"


def main():
    if len(sys.argv) != 5:
        usage_error("expected exactly 4 arguments")
    item_json_path, pack_yaml_path, out_fact_record, out_sanitized_spec = sys.argv[1:5]

    if not os.path.isfile(item_json_path):
        fail(f"'{item_json_path}' not found")

    with open(item_json_path, encoding="utf-8") as f:
        try:
            item = json.load(f)
        except json.JSONDecodeError as e:
            fail(f"'{item_json_path}' is not valid JSON: {e}")

    item_id = item.get("key")
    fields = item.get("fields", {}) or {}
    item_type = (fields.get("issuetype") or {}).get("name")

    if not item_id:
        fail("fetched item has no 'key' — cannot set item_id")
    if not item_type:
        fail("fetched item has no 'fields.issuetype.name' — cannot set item_type")

    labels = fields.get("labels") or []
    components = [c.get("name") for c in (fields.get("components") or []) if c.get("name")]
    attachments = fields.get("attachment") or []
    summary = fields.get("summary") or ""
    description_adf = fields.get("description")
    description_text = adf_to_text(description_adf).strip() if description_adf else ""

    plain_text = (summary + "\n\n" + description_text).strip()

    conventions = parse_text_conventions(pack_yaml_path)
    design_matches = find_matches(plain_text, conventions["design_keywords"])
    reproduction_matches = find_matches(plain_text, conventions["reproduction_headings"])
    acceptance_matches = find_matches(plain_text, conventions["acceptance_criteria_headings"])

    has_image_attachment = any(
        (a.get("mimeType") or "").startswith("image/") for a in attachments
    )
    design_source = has_image_attachment or any_design_url(plain_text)
    design_mentioned = bool(design_matches)
    has_description = bool(description_text)
    has_acceptance_criteria = bool(acceptance_matches)
    has_reproduction_steps = bool(reproduction_matches)
    has_reproduction_url = bool(URL_RE.search(plain_text))

    files_named = sorted(set(FILE_RE.findall(plain_text)))

    os.makedirs(os.path.dirname(out_fact_record) or ".", exist_ok=True)
    with open(out_fact_record, "w", encoding="utf-8") as f:
        f.write(f"item_id: \"{item_id}\"\n")
        f.write(f"item_type: {item_type}\n")
        f.write(f"labels: {yaml_list(labels)}\n")
        f.write(f"components: {yaml_list(components)}\n")
        f.write(f"files_named: {yaml_list(files_named)}\n")
        f.write("\n")
        f.write(f"design_source: {yaml_bool(design_source)}\n")
        f.write(f"design_mentioned: {yaml_bool(design_mentioned)}\n")
        f.write("\n")
        f.write(f"has_description: {yaml_bool(has_description)}\n")
        f.write(f"has_acceptance_criteria: {yaml_bool(has_acceptance_criteria)}\n")
        f.write(f"has_reproduction_url: {yaml_bool(has_reproduction_url)}\n")
        f.write(f"has_reproduction_steps: {yaml_bool(has_reproduction_steps)}\n")

    os.makedirs(os.path.dirname(out_sanitized_spec) or ".", exist_ok=True)
    with open(out_sanitized_spec, "w", encoding="utf-8") as f:
        f.write(f"# {summary}\n\n")
        f.write(f"item: {item_id} ({item_type})\n\n")
        if description_text:
            f.write(description_text)
            if not description_text.endswith("\n"):
                f.write("\n")
        else:
            f.write("(no description)\n")

    print(f"item_id={item_id} item_type={item_type}")
    print(
        "matched: design_keywords="
        + (",".join(design_matches) or "none")
        + " reproduction_headings="
        + (",".join(reproduction_matches) or "none")
        + " acceptance_criteria_headings="
        + (",".join(acceptance_matches) or "none")
        + " image_attachment="
        + yaml_bool(has_image_attachment)
    )
    sys.exit(0)


if __name__ == "__main__":
    main()
