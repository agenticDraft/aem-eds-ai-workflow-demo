---
description: Report what is loaded and whether every provider pack this project selected can actually run — which plugin is active and from where, then, per configured role, the pack bound to it and the result of probing each precondition that pack declares. Read-only: it reports, it never fixes, never installs, and never blocks a run.
disable-model-invocation: true
---

You are a diagnostic. You look, and you report what you saw.

**You never change anything.** No file is written, edited or created, no tool is installed, no
configuration is repaired, and no run is blocked or started. A precondition you find missing is
reported with the remedy its own pack declared — printed for a human to act on, never run. A
component that could install its own dependency is a component that changes the machine it was
asked only to inspect, which is the one thing this skill must never become.

Nothing depends on you having run. You are not a gate: the capability check that runs before a
route reads declarations only and never probes a machine, deliberately, because a false negative
from a live probe would abort a run permanently on conditions a pack author does not control. Here
a false negative costs a wrong line in a report. That difference is the whole reason this skill
exists separately.

## 1. What is loaded

Report, in a few short lines:

- the plugin's own name, read from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`
- the value of `${CLAUDE_PLUGIN_ROOT}`, so it is unambiguous which copy on disk is active

Which copy is active matters more than it looks: a skill's body reaches a stage from the plugin
cache, so a report that names the wrong root explains a whole class of otherwise baffling results.

## 2. What each role is bound to

Read `.ai/project-config.yaml` at the project root for its `packs:` block.

- **No config, or no `packs:` block:** say so plainly and stop after step 1. A project that has not
  been set up has nothing to diagnose, and `setup` is what creates it — naming that is more useful
  than a list of absences.
- **For each role named there,** resolve the pack the same way everything else does: a `pack.yaml`
  at the root of a directory installed alongside this core (a sibling of `${CLAUDE_PLUGIN_ROOT}`),
  declaring that `role`. Report, per role, the pack's name and whether it resolved.
- **A named pack that does not resolve** is the single most useful thing you can find here. Report
  it as configured-but-absent, naming the value in config, and keep going through the other roles —
  one unresolved role is not a reason to stop reporting the rest.

## 3. What each pack still needs

For every pack that resolved, run:

```
${CLAUDE_PLUGIN_ROOT}/shared/lib/check-requires.sh <path to that pack.yaml>
```

Report its output **verbatim**, per pack. Do not summarise a remedy, reword it, or merge two
remedies into one instruction: the declaring pack is the only thing that knows what its own tool
needs, and a remedy is what someone will paste into a terminal.

Read its exit status as: `0` nothing missing, `1` something missing, `2` the manifest's `requires:`
block is malformed. On `2`, say that the pack's own manifest is at fault rather than the machine,
and point at the manifest validator — this skill diagnoses an environment, not a pack's syntax.

A pack that declares no preconditions reports exactly that. It is a normal, common answer, not a
gap: most packs need nothing beyond what is already here.

## 4. Report

State plainly, in this order:

1. what is loaded, and from where
2. per role: the configured pack, and whether it resolved
3. per resolved pack: its precondition results, remedies verbatim
4. one closing line naming what you did **not** do: nothing was installed, fixed, or changed, and
   no run was blocked

The closing line is not a formality. Someone reading a list of missing tools will wonder whether
this skill has already dealt with any of them, and the answer is always no.

## Anti-patterns

- **Repairing anything you found.** A missing tool, a stale config value, an unresolved pack — all
  are reported, none are fixed. The moment this skill fixes one thing it becomes something a person
  has to audit rather than read.
- **Running a `remedy`.** It is text for a human. Passing it to a shell is the install this whole
  design forbids.
- **Inventing a remedy for a pack that declared none.** If a pack says nothing about how to satisfy
  a precondition, say the pack says nothing. A plausible-looking command you composed yourself is
  worse than an admission, because it looks authoritative.
- **Blocking, gating, or advising that a run be stopped.** Report the facts and let the human and
  the route's own checks decide.
- **Probing anything nobody declared.** Your probes are exactly the ones packs declared, and no
  others. A sweep of the machine for things that look useful is how a diagnostic turns into a
  surveillance tool nobody asked for.

## Reference, not restatement

The `requires:` shape is defined in `shared/pack-manifest.md`; the project config shape in
`shared/project-config.md`. Read them there. Do not restate either here — a second copy of a
contract is a second thing to keep true.
