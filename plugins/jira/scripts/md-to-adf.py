#!/usr/bin/env python3
"""md-to-adf.py <markdown-file> [--out <json-file>]

Convert a work item's description from the markdown an author writes into the
document format the tracker stores, and prove the conversion lost nothing
before handing it back.

Why the proof is part of the conversion rather than only part of a test suite:
the text this produces is what every downstream detector reads. A criterion is
found by its id starting a line, so a conversion that reflows a wrapped
criterion leaves an item that still renders correctly and silently stops being
counted. That failure is invisible in the rendered result and invisible in the
stored document — it is only visible by flattening the output back to text and
comparing. So every conversion does exactly that, and refuses to emit anything
it cannot reproduce.

Exit codes: 0 and the document on stdout (or at --out); 1 if the round trip
does not reproduce the input; 2 for a usage error.
"""

import json
import re
import sys

HEADING_RE = re.compile(r"^(#{1,6}) +(.*)$")
BULLET_RE = re.compile(r"^- +(.+)$")


def usage(msg):
    print(f"usage error: {msg}", file=sys.stderr)
    print(__doc__.strip().splitlines()[0], file=sys.stderr)
    sys.exit(2)


def text_nodes(line_block):
    """One text node per line, hardBreak between them. Lines are preserved
    exactly — including the leading spaces of a wrapped continuation line —
    because a detector that anchors on a line start cannot be given a
    different set of line starts than the author wrote."""
    nodes = []
    for i, line in enumerate(line_block):
        if i:
            nodes.append({"type": "hardBreak"})
        if line:
            nodes.append({"type": "text", "text": line})
    return nodes


def block_to_node(block):
    lines = block.split("\n")

    m = HEADING_RE.match(lines[0]) if len(lines) == 1 else None
    if m:
        return {
            "type": "heading",
            "attrs": {"level": len(m.group(1))},
            "content": [{"type": "text", "text": m.group(2)}],
        }

    if all(BULLET_RE.match(line) for line in lines):
        return {
            "type": "bulletList",
            "content": [
                {"type": "listItem",
                 "content": [{"type": "paragraph",
                              "content": [{"type": "text",
                                           "text": BULLET_RE.match(line).group(1)}]}]}
                for line in lines
            ],
        }

    return {"type": "paragraph", "content": text_nodes(lines)}


def to_adf(markdown):
    blocks = [b for b in re.split(r"\n[ \t]*\n", markdown.strip("\n")) if b.strip()]
    return {"type": "doc", "version": 1,
            "content": [block_to_node(b) for b in blocks]}


def to_text(node):
    """The inverse, implementing the same flattening a consumer applies. Kept
    here so a conversion can check itself without reaching into whatever
    happens to consume it — the flattening rule belongs to the document
    format, not to either end of it."""
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
        return ("#" * level) + " " + "".join(to_text(c) for c in content) + "\n\n"
    if node_type == "paragraph":
        return "".join(to_text(c) for c in content) + "\n\n"
    if node_type in ("bulletList", "orderedList"):
        lines = []
        for i, item in enumerate(content):
            item_text = "".join(to_text(c) for c in item.get("content", [])).strip()
            prefix = "- " if node_type == "bulletList" else f"{i + 1}. "
            lines.append(prefix + item_text)
        return "\n".join(lines) + "\n\n"
    return "".join(to_text(c) for c in content)


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        usage("a markdown file is required")
    source, out_path = argv[0], None
    rest = argv[1:]
    if rest:
        if rest[0] != "--out" or len(rest) != 2:
            usage("the only option is '--out <json-file>'")
        out_path = rest[1]

    try:
        with open(source, encoding="utf-8") as f:
            markdown = f.read()
    except OSError as exc:
        usage(f"cannot read '{source}': {exc}")

    if not markdown.strip():
        usage(f"'{source}' is empty")

    doc = to_adf(markdown)

    before = markdown.strip("\n")
    after = to_text(doc).strip("\n")
    if before != after:
        for n, (a, b) in enumerate(zip(before.split("\n"), after.split("\n")), 1):
            if a != b:
                print(f"conversion changed line {n}:\n  in : {a!r}\n  out: {b!r}",
                      file=sys.stderr)
                break
        else:
            print(f"conversion changed the line count: "
                  f"{len(before.splitlines())} in, {len(after.splitlines())} out",
                  file=sys.stderr)
        print("refusing to emit a document that does not reproduce its input.",
              file=sys.stderr)
        return 1

    rendered = json.dumps(doc)
    if out_path:
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(rendered)
    else:
        print(rendered)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
