#!/usr/bin/env python3
# Run: python3 plugins/eds/skills/eds-prototype/scripts/resolve-target.py .ai/run-context/fact-record.yaml .ai/run-context/question-answer.yaml
#
# resolve-target.py <fact-record.yaml> <question-answer.yaml>
#
# Deterministic (D526). Decides the block the prototype stage targets from
# exactly one candidate, never from the order of a list. Three sources, in
# rank order; the first that yields any candidate decides alone:
#
#   answer       the answer stored under (prototype, target-block), read only
#                through the core's read-question-answer.sh. Its candidates
#                are every distinct <name> in a `blocks/<name>/` path in it;
#                with none, the whole answer when it is one block name.
#   components   the fact record's `components`, distinct.
#   files_named  the distinct <name> of every `blocks/<name>/…` path in the
#                fact record's `files_named`.
#
# Exactly one candidate resolves:
#
#   target=<name>
#   source=<answer|components|files_named>
#
# Zero, or two or more, is a question — every candidate listed, sorted:
#
#   source=<answer|components|files_named|none>
#   candidate=<name>        one line per candidate; none when source=none
#
# Exit codes: 0 — resolved; 4 — question; 1 — the answer file is malformed
# (the reader's "invalid: <reason>" on stderr), never acted on; 2 — bad
# arguments or an unreadable fact record.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
READER = os.path.join(HERE, "..", "..", "..", "core", "lib", "read-question-answer.sh")

BLOCK_PATH_RE = re.compile(r"blocks/([a-z0-9][a-z0-9-]*)/")
BLOCK_NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


def refuse(msg):
    print(f"resolve-target: {msg}", file=sys.stderr)
    sys.exit(2)


def fact_list(text, field):
    m = re.search(rf"^{field}:[ \t]*\[(.*)\][ \t]*$", text, re.MULTILINE)
    if not m:
        return []
    return [e.strip().strip('"') for e in m.group(1).split(",") if e.strip().strip('"')]


def answer_candidates(qa_path):
    r = subprocess.run(["bash", READER, qa_path, "prototype", "target-block"],
                       capture_output=True, text=True)
    if r.returncode == 3:
        return []
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        sys.exit(1)
    answer = r.stdout.strip()
    names = set(BLOCK_PATH_RE.findall(answer))
    if not names and BLOCK_NAME_RE.match(answer):
        names = {answer}
    return sorted(names)


def main(argv):
    if len(argv) != 3:
        refuse("usage: resolve-target.py <fact-record.yaml> <question-answer.yaml>")
    fact_path, qa_path = argv[1], argv[2]
    try:
        with open(fact_path, encoding="utf-8") as f:
            fact = f.read()
    except OSError as e:
        refuse(f"cannot read fact record: {e}")

    sources = [
        ("answer", lambda: answer_candidates(qa_path)),
        ("components", lambda: sorted(set(fact_list(fact, "components")))),
        ("files_named", lambda: sorted({m.group(1) for p in fact_list(fact, "files_named")
                                        if (m := BLOCK_PATH_RE.match(p))})),
    ]
    for source, candidates_of in sources:
        candidates = candidates_of()
        if len(candidates) == 1:
            print(f"target={candidates[0]}\nsource={source}")
            return 0
        if candidates:
            print(f"source={source}")
            for c in candidates:
                print(f"candidate={c}")
            return 4
    print("source=none")
    return 4


if __name__ == "__main__":
    sys.exit(main(sys.argv))
