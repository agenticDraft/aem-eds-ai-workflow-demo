---
description: The audit taxonomy — the four classes an audit finding belongs to, the severity test that decides whether a finding blocks delivery, and the required shape of a finding record. Every audit that classifies a discrepancy between a project's own documents, code and adopted design tokens references this file rather than restating the classes or the test inline.
---

# Audit taxonomy

An audit compares what a project's own documents and code claim against what a deterministic
check can establish — a token set already adopted, a value already in a stylesheet, a value
`git` itself can report. What it produces is a **finding**: one discrepancy, classified by what
fixing it requires, never by what topic it touches. This file fixes the classes, the test that
decides a finding's severity, and the shape every finding record must have. It names no
platform, no design tool and no file extension: "what does fixing this require" and "does an
agent read this file as truth" are not platform questions, and neither is the shape a finding is
recorded in. Which files a project has, which ones an audit reads, and where the audit writes its
findings are a pack's own concern.

**Never does:** decide which files a given platform pack treats as truth (that list is the pack's
own declaration, read by the severity test below as data), or decide how many findings a real
audit produces or in what order (this fixes the classification and the record shape, not the
audit's own flow).

## The four classes

*(D23.)* Classified by what fixing the finding requires — not by topic, so a questionnaire built
from many findings scales with genuine ambiguity rather than with finding count:

- **`mechanical`** — one answer is derivable from an adopted token set or from the code itself.
  Auto-fixable: the diff can be applied with no human input at all.
- **`needs-the-human`** — one right answer exists, but nothing in the project states it. The diff
  shows where the answer goes; it cannot show the answer itself.
- **`judgment`** — several defensible answers exist. Never applied silently: asked with a
  recommendation and a default, so a human can accept the default without having to invent an
  answer from nothing.
- **`report-only`** — the fix is a real choice with a cost attached (time, risk, a decision that
  trades one thing against another). Recorded so it is visible, never auto-applied and never
  silently dropped.

A class is a statement about what the *fix* needs, never about how alarming the finding looks. A
finding that looks trivial but has no single correct answer is `judgment`, not `mechanical`; a
finding that looks serious but has one derivable answer is `mechanical`, not something scarier.

**A `mechanical` verdict is provisional on the file being untouched since it was assembled.**
`mechanical` means a fix applies with no human input at all — a file a human has since edited no
longer meets that bar, whatever the edit was. `lib/check-auto-fix-eligibility.sh` is the
deterministic test: exactly one commit in a path's `git log` history (the boilerplate import
itself) means untouched and the finding stays `mechanical`; any other count demotes it to
`judgment`, never applied silently. `lib/check-shallow-clone.sh` is a required precondition — a
shallow clone makes every path report at most one commit regardless of real history, so it must
run first and abort the audit before any eligibility check rather than let a `git log` answer it
cannot trust flip a real edit back to `mechanical`.

## The severity test

**One question decides severity, and it is checkable, not a matter of taste (G22):** *does an
agent read this file as truth?* A file an agent loads into its own context and trusts without
re-deriving it — a house-style document, a project-conventions file, anything read once and acted
on many times — is truth-bearing. A file nobody reads for guidance, however untidy, is not.

- **`poisoning`** — the finding's `file` is one an agent reads as truth. A wrong claim there is
  not cosmetic: every stage that trusts the file inherits the wrong claim, and nothing before this
  audit catches it.
- **`cosmetic`** — every other finding. Still worth fixing, never worth blocking on.

**The test is a membership check, not a judgment call.** A platform pack declares its own,
closed list of paths it treats as truth-bearing — the files it loads into every stage's own
context — because only the pack knows which files its own platform actually reads that way; the
core cannot name one without naming a platform. Severity is then exactly: is the finding's `file`
a member of that declared list? `lib/classify-severity.sh` is the whole test — no model, no
partial credit, no "how bad does this look."

**Consequence, stated because it surprises on first read:** a finding's *class* and its
*severity* are independent. A `mechanical` finding can be `poisoning` (a wrong breakpoint value in
a house-style document — one answer, and every stage reads it); a `judgment` finding can be
`cosmetic` (a near-miss color nobody but a human will ever weigh); dead assets are typically
`mechanical` and always `cosmetic` — deleting an unreferenced file has one correct answer, and no
agent reads a font file as truth, however large it is.

## The required shape of a finding

```yaml
- id: "<string>"
  class: mechanical | needs-the-human | judgment | report-only
  severity: poisoning | cosmetic
  file: "<relative path>"
  finding: "<one sentence: what is wrong>"
  diff: |
    <the exact change this finding's fix would apply>
  recommendation: "<string>"    # class: judgment only
  default: "<string>"           # class: judgment only
  question: "<string>"          # class: needs-the-human only
```

A bare list, one entry per finding — the same shape `artifact-registry.md` uses for its own
registry, for the same reason: a reader validates the data file directly, never a restatement of
it in prose. An audit that produced no findings is a normal result, not a contract violation —
written as the literal `[]`, the same convention `design-manifest.md` uses for an empty
`values`/`unresolvable` list, never an omitted or blank file.

### Field rules

- `id` — non-empty, unique within the list a single audit produces.
- `class` — exactly one of the four literals above.
- `severity` — exactly one of `poisoning` or `cosmetic`, decided by the test above — never chosen
  because a finding "seems" more or less important.
- `file` — the exact relative path the finding is about. One finding names exactly one file; a
  discrepancy spanning two files (a claim in one, contradicted by a value in another) is recorded
  against the file that carries the wrong claim — the one the fix changes.
- `finding` — one sentence, plain prose, no line breaks. What is wrong, not why it matters.
- `diff` — **required on every finding, regardless of class.** The exact change the finding's fix
  would apply, as a literal block: the line or lines removed, the line or lines added, in the
  shape a human or a script could apply directly. A finding's class governs whether this diff is
  applied automatically, asked about, or only reported — never whether it exists.
  - For `mechanical`, the diff carries the derived value in full.
  - For `judgment`, the diff carries the *recommended* value — the one `default` also names — so
    accepting the default is applying exactly this diff, nothing further to construct.
  - For `needs-the-human`, nothing in the project names the answer, so the diff cannot carry a
    derived value. It still names the exact line and file, with the wrong or placeholder value
    replaced by a marker naming the open question (never a guessed value standing in for an
    answer nobody gave).
  - For `report-only`, the diff shows the one corrective change that is always safe regardless of
    which real-world option is chosen — most often, correcting a false claim to state a fact
    rather than choosing between the options that claim was about.
- `recommendation`, `default` — required together, only when `class: judgment`; absent otherwise.
  `default` is what a run proceeds with if the question goes unanswered within its budget; it is
  not silently applied on its own — see the question protocol (`question-protocol.md`) for how a
  `judgment` finding becomes a question a run asks.
- `question` — required only when `class: needs-the-human`; absent otherwise. The question text
  itself, phrased so a human can answer it directly.

## Anti-patterns

- Severity assigned by how bad a finding looks, how large a diff is, or how the file "feels"
  important, rather than by the membership test above. This is the one thing keeping a later gate
  from becoming a matter of taste (G22) — the reason this rule exists at all.
- A finding recorded with no `diff`, on the theory that `report-only` or `needs-the-human`
  findings have nothing concrete to show. Every class names an exact change; only whether it is
  applied automatically differs.
- A `judgment` finding applied without asking, on the theory that its `default` makes asking
  unnecessary. The default is what happens when nobody answers, not permission to skip asking.
  (D23.)
- A `needs-the-human` diff carrying a guessed value instead of a placeholder naming the question.
  Nothing in the project knows the answer; writing one in anyway is exactly the guess `fact-
  record.md` and `design-manifest.md` already forbid for a different kind of unknown value.
- Treating a finding's own existence as resolution. A record with no path from `report-only` or
  `judgment` to an applied fix is a graveyard, not a queue (D13); an audit that only ever produces
  `audit.md` and never feeds a change a human can merge has stopped short of what an audit is for.
- Re-deriving severity per finding by re-reading prose, instead of checking `file` against the
  pack's own declared truth-bearing list. The list is declared once; every finding's severity is a
  lookup against it, not a fresh judgment.

## Fixtures

`fixtures/audit-taxonomy/valid.yaml` is a well-formed findings list exercising all four
classes and both severities. `fixtures/audit-taxonomy/empty.yaml` is the literal `[]` — a
conformant audit that found nothing. `fixtures/audit-taxonomy/invalid/` holds one fixture per
rejection case: `no-diff.yaml`, `unknown-class.yaml`, `unknown-severity.yaml`,
`judgment-missing-default.yaml`, `needs-the-human-missing-question.yaml`,
`mechanical-with-question.yaml` (a field present that its class forbids), `duplicate-id.yaml`.

## Verification

`lib/validate-findings.sh <path-to-findings-file>` is the deterministic checker — no model
involved. It exits `0` and prints `valid: findings (<n> entries)` for a conformant list, `1` with
`invalid: <reason>` on stderr for a contract violation, `2` for a usage error.

`lib/classify-severity.sh <file> <path-to-trusted-files-list>` is the deterministic severity
test — a membership check against a pack-declared list of truth-bearing paths, one per line. It
exits `0` and prints `severity: poisoning` or `severity: cosmetic`; `2` for a usage error.

`lib/classify-hex-token.sh <hex> <path-to-design-manifest>` is the deterministic check behind the
worked example above: whether a raw color value exactly matches, nearly matches, or matches
nothing in an adopted token set (`design-manifest.md`). It exits `0` and prints
`mechanical: exact match — <token name> (<value>)`, `judgment: close match — <token name>
(<value>), max channel difference <n>`, or `no-match`; `1` if the manifest file does not conform
to `design-manifest.md`; `2` for a usage error.

`lib/check-reference.sh <needle> <root-dir> [<exclude-file>]` is the generic, deterministic check
behind "is this file referenced anywhere" — a literal-string search under a directory, with one
file excludable so a declaration is not counted as its own use. It exits `0` and prints one
`referenced: <path>:<line>` per hit when at least one is found, `1` and prints `not-referenced`
when none is, `2` for a usage error.

`lib/check-shallow-clone.sh <project-root>` is the required precondition for the two checks below:
is `<project-root>`'s clone deep enough to make `git log` a trustworthy oracle. It exits `0` and
prints `ok: full clone ...`, `1` (a PERMANENT abort) and prints `permanent-abort: ...` on stderr
naming `git fetch --unshallow` as the remedy when the clone is shallow, `2` for a usage error. Must
run, and exit `0`, before the first call described next.

`lib/check-auto-fix-eligibility.sh <project-root> <path> [<path> ...]` is the deterministic
auto-fix eligibility oracle: exactly one commit in a path's history means untouched since import
(`eligible`), any other count means edited since and no longer safe to auto-fix (`demoted`). It
exits `0` when every path is eligible, `1` when at least one is demoted (every path's verdict is
still printed), `2` for a usage error. Trusts the caller to have already run
`check-shallow-clone.sh` — see that script's own header for why the two stay separate.

```bash
bash plugins/agentic-core/shared/lib/validate-findings.test.sh
bash plugins/agentic-core/shared/lib/classify-severity.test.sh
bash plugins/agentic-core/shared/lib/classify-hex-token.test.sh
bash plugins/agentic-core/shared/lib/check-reference.test.sh
bash plugins/agentic-core/shared/lib/check-shallow-clone.test.sh
bash plugins/agentic-core/shared/lib/check-auto-fix-eligibility.test.sh
```
