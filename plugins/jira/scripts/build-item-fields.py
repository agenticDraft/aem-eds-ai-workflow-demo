#!/usr/bin/env python3
# Run: python3 plugins/jira/scripts/build-item-fields.py <draft-file> --out <json-file>
"""build-item-fields.py <draft-file> [--project <key>] [--out <json-file>]

Turn an authored draft — front matter plus a markdown body — into the fields
payload a work item write sends.

The split matters and is easy to get backwards: the front matter carries what
the tracker holds in its own fields, and the body is the description. Sending
the front matter inside the description puts it in the item as literal text,
which is what happens whenever someone pastes a whole draft by hand.

Only keys the draft actually carries are sent. A tracker configured without a
given field rejects the whole write when it is named, so naming a field nobody
filled in is a way to fail a write over something the author never asked for.

With --project, the payload is the one a *create* sends: it additionally names
the project and the item type, both required at creation and neither settable
afterwards by the same call. Without it, the payload is an update's, which
carries neither — a tracker refuses an attempt to move an item between
projects this way, and an item's type is a separate transition rather than a
field an update may overwrite.

Exit codes: 0 and the payload on stdout (or at --out); 1 if the description
cannot be converted without loss; 2 for a usage error.
"""

import json
import os
import re
import subprocess
import sys

CONVERTER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "md-to-adf.py")


def usage(msg):
    print(f"usage error: {msg}", file=sys.stderr)
    sys.exit(2)


def split_front_matter(raw):
    """Returns (front matter dict, body). A draft without front matter is a
    body on its own — valid, and it simply sets no structured field."""
    if not raw.startswith("---\n"):
        return {}, raw
    end = raw.find("\n---\n", 3)
    if end == -1:
        usage("front matter opens with '---' but never closes")
    return parse_front_matter(raw[4:end]), raw[end + 5:]


def parse_front_matter(text):
    """One 'key: value' per line, the same flat shape every manifest in this
    system uses. A bracketed value is a list."""
    fields = {}
    for line in text.split("\n"):
        m = re.match(r"^([A-Za-z0-9_]+):\s*(.*)$", line)
        if not m:
            continue
        key, value = m.group(1), m.group(2).strip()
        if value.startswith("[") and value.endswith("]"):
            fields[key] = [v.strip() for v in value[1:-1].split(",") if v.strip()]
        else:
            fields[key] = value
    return fields


def description_adf(body):
    result = subprocess.run([sys.executable, CONVERTER, "-"], input=body,
                            capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        sys.exit(1)
    return json.loads(result.stdout)


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        usage("a draft file is required")
    source, out_path, project = argv[0], None, None
    rest = argv[1:]
    while rest:
        if rest[0] == "--out" and len(rest) >= 2:
            out_path, rest = rest[1], rest[2:]
        elif rest[0] == "--project" and len(rest) >= 2:
            project, rest = rest[1], rest[2:]
        else:
            usage("options are '--out <json-file>' and '--project <key>'")

    try:
        with open(source, encoding="utf-8") as f:
            raw = f.read()
    except OSError as exc:
        usage(f"cannot read '{source}': {exc}")

    front, body = split_front_matter(raw)
    if not body.strip():
        usage(f"'{source}' carries no description body")

    fields = {"description": description_adf(body)}

    if project:
        if not front.get("item_type"):
            usage("a create needs 'item_type' in the draft's front matter, "
                  "spelled the way the tracker spells it")
        if not front.get("summary"):
            usage("a create needs 'summary' in the draft's front matter")
        fields["project"] = {"key": project}
        fields["issuetype"] = {"name": front["item_type"]}

    if front.get("summary"):
        fields["summary"] = front["summary"]
    if front.get("labels"):
        fields["labels"] = front["labels"]
    if front.get("components"):
        fields["components"] = [{"name": c} for c in front["components"]]

    payload = {"fields": fields}
    rendered = json.dumps(payload)
    if out_path:
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(rendered)
    else:
        print(rendered)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
