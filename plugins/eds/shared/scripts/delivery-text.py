#!/usr/bin/env python3
# Run: python3 plugins/eds/shared/scripts/delivery-text.py block --branch eds-18
#
# delivery-text.py <block|note|report|checks> [options]
#
# Deterministic (D535, G535). Builds the text eds-deliver publishes, so the
# pull request and the tracker note can never carry different target text:
#
#   block  — the "Verified locally" block. eds-deliver appends it to the pull
#            request body verbatim.
#   note   — the short tracker note. It carries the same block, built by the
#            same function, and an "Action needed" list.
#   report — the "## Evidence manifest" section of delivery-report.md: target,
#            reachability, and every coverage gap verbatim, one line each.
#   checks — one line deciding whether check_status's checks are green, for
#            eds-deliver's downgrade: `checks: green [expected=<names>]`,
#            `checks: not-green failing=<names> pending=<n> [expected=<names>]`,
#            or `checks: unreadable`. Not green: any failing or cancelled
#            check that is not expected, or any pending check.
#
# Options:
#   --manifest <path>    evidence manifest (default .ai/run-context/evidence-manifest.json)
#   --config <path>      project config (default .ai/project-config.yaml)
#   --package <path>     package.json (default package.json)
#   --branch <name>      the branch checked out           (block, note)
#   --item-id <id>       the work item id                 (note)
#   --pr-url <url>       the pull request URL             (note)
#   --checks <path>      check_status's JSON (a list of {bucket, name}) (note, checks)
#   --pr-type <type>     preview-url.sh's pr-type (note, checks): served,
#                        automation-only, branch-too-long, branch-unsupported
#   --block-name <name>  the target block, for the placeholder-fixture remedy (note)
#
# A missing, unparsable or incomplete manifest counts as no manifest: the block
# says no target is on record, and the note lists the unreadable manifest under
# Action needed (a missing file is not an action).
#
# Action needed lists only what needs a person, classified by entry prefix:
#   - a coverage gap starting "content-asset gap" (verbatim);
#   - the placeholder-fixture gap (a remedy line naming the block and file);
#   - each check whose bucket is "fail" or "cancel";
#   - checks that could not be read;
#   - a manifest that could not be read.
# Nothing → "Nothing to do before merge". Every other gap stays out of the
# note; the report carries all of them.
#
# A check still running is not an action — nothing is wrong yet — but the note
# must not read as if CI had finished: each pending check gets one line in a
# "Pending" section after Action needed, and no pending check means no section.
#
# Expected failure (G31): on an automation-only PR, a failing `aem-psi-check`
# is expected (no preview URL to measure). The note lists it under Expected,
# not Action needed; `checks` does not count it. Any other PR type keeps it an
# action.
#
# The Restart line: the draft server's port is paths.preview's port plus one
# (3000 when it names none), as in start-draft-server.sh. package.json declares
# "up:draft" → `npm run up:draft -- --port <port>`; otherwise commands.serve
# with `--html-folder drafts --port <port>` appended (after `--` for an
# `npm run` command that has none).
#
# Exit codes: 0 — text printed; 2 — usage error.

import argparse
import json
import os
import re
import sys

PR_TYPES = ("served", "automation-only", "branch-too-long", "branch-unsupported")
EXPECTED_FAILURES = {"automation-only": ("aem-psi-check",)}
FIXTURE_PREFIX = "the rendered target was a generated placeholder fixture ("
ASSET_PREFIX = "content-asset gap"
MANIFEST_KEYS = ("target", "target_reachable", "target_reachable_reason", "coverage_gaps")


def read_config(path):
    """Two-level `key: value` reader for the project config; returns {'commands.serve': ..., ...}."""
    values = {}
    section = None
    try:
        with open(path, encoding="utf-8") as handle:
            for raw in handle:
                line = raw.split(" #", 1)[0].rstrip()
                if not line.strip() or line.lstrip().startswith("#"):
                    continue
                top = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", line)
                if top:
                    section = top.group(1)
                    continue
                nested = re.match(r"^\s+([A-Za-z_][\w-]*):\s*(.*)$", line)
                if nested and section:
                    value = nested.group(2).strip()
                    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                        value = value[1:-1]
                    values[f"{section}.{nested.group(1)}"] = value
    except OSError:
        pass
    return values


def declares_up_draft(path):
    try:
        with open(path, encoding="utf-8") as handle:
            scripts = json.load(handle).get("scripts") or {}
    except (OSError, ValueError, AttributeError):
        return False
    return isinstance(scripts, dict) and "up:draft" in scripts


def draft_port(preview):
    match = re.match(r"^[a-zA-Z]*://[^:/]*:(\d+)", preview or "")
    return int(match.group(1)) + 1 if match else 3001


def restart_command(config, package):
    port = draft_port(config.get("paths.preview", ""))
    if declares_up_draft(package):
        return f"npm run up:draft -- --port {port}"
    serve = config.get("commands.serve", "").strip()
    if not serve:
        return "no serve command is configured"
    appended = f"--html-folder drafts --port {port}"
    if serve.startswith("npm run ") and " -- " not in f"{serve} ":
        return f"{serve} -- {appended}"
    return f"{serve} {appended}"


def read_manifest(path):
    """Returns (manifest or None, reason it could not be read or None). A missing file has no reason."""
    if not os.path.exists(path):
        return None, None
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError) as error:
        return None, f"not readable JSON ({type(error).__name__})"
    if not isinstance(data, dict):
        return None, "not a JSON object"
    missing = [key for key in MANIFEST_KEYS if key not in data]
    if missing:
        return None, "missing " + ", ".join(missing)
    if not isinstance(data["target"], str) or not data["target"]:
        return None, "empty target"
    if not isinstance(data["coverage_gaps"], list):
        return None, "coverage_gaps is not a list"
    return data, None


def verified_block(manifest, branch, config, package):
    if manifest is None:
        return "## Verified locally\nNo verification target is on record for this run."
    return "\n".join([
        "## Verified locally",
        f"Target: {manifest['target']}",
        f"Local only: answers while the draft server runs and branch {branch} is checked out.",
        f"Restart: {restart_command(config, package)}",
    ])


CHECK_LABELS = {"fail": "failing", "cancel": "cancelled"}


def read_checks(path):
    """check_status's list of checks, or None when it cannot be read."""
    try:
        with open(path, encoding="utf-8") as handle:
            checks = json.load(handle)
    except (OSError, ValueError, TypeError):
        return None
    if not isinstance(checks, list):
        return None
    return [check for check in checks if isinstance(check, dict)]


def split_red(checks, pr_type):
    """(unexpected red checks, expected red checks), each a list of checks."""
    expected_names = EXPECTED_FAILURES.get(pr_type, ())
    red = [check for check in checks if check.get("bucket") in CHECK_LABELS]
    expected = [check for check in red if check.get("name") in expected_names]
    return [check for check in red if check not in expected], expected


def check_line(check):
    return f"Check {CHECK_LABELS[check.get('bucket')]}: {check.get('name', '(unnamed)')}"


def check_actions(path, pr_type):
    """(action lines, expected lines, pending lines) for the note."""
    checks = read_checks(path)
    if checks is None:
        return ["Automated checks could not be read; see delivery-report.md"], [], []
    unexpected, expected = split_red(checks, pr_type)
    reason = f"{pr_type} PR: no preview URL to measure"
    pending = [f"Check pending: {c.get('name', '(unnamed)')} (still running when this note was posted)"
               for c in checks if c.get("bucket") == "pending"]
    return ([check_line(c) for c in unexpected], [f"{check_line(c)} ({reason})" for c in expected],
            pending)


def checks_verdict(path, pr_type):
    checks = read_checks(path)
    if checks is None:
        return "checks: unreadable"
    unexpected, expected = split_red(checks, pr_type)
    pending = sum(1 for check in checks if check.get("bucket") == "pending")
    tail = f" expected={','.join(c.get('name', '(unnamed)') for c in expected)}" if expected else ""
    if unexpected or pending:
        failing = ",".join(c.get("name", "(unnamed)") for c in unexpected)
        return f"checks: not-green failing={failing} pending={pending}{tail}"
    return f"checks: green{tail}"


def gap_actions(manifest, block_name):
    actions = []
    for gap in manifest["coverage_gaps"] if manifest else []:
        if not isinstance(gap, str):
            continue
        if gap.startswith(ASSET_PREFIX):
            actions.append(gap)
        elif gap.startswith(FIXTURE_PREFIX):
            fixture = gap[len(FIXTURE_PREFIX):].split(")", 1)[0]
            what = f"real `{block_name}` content" if block_name else "real content for the target block"
            actions.append(
                f"To make this openable, author and publish {what} — the only content behind this "
                f"target right now is the generated placeholder fixture at `{fixture}`."
            )
    return actions


def note(args, manifest, reason, config):
    actions = gap_actions(manifest, args.block_name)
    if reason:
        actions.append(f"The evidence manifest could not be read ({reason}); see delivery-report.md")
    check_lines, expected, pending = check_actions(args.checks, args.pr_type)
    actions += check_lines
    if not actions:
        actions = ["Nothing to do before merge"]
    lines = [
        f"{args.item_id} — ready for review",
        f"- PR: {args.pr_url}",
        "",
        verified_block(manifest, args.branch, config, args.package),
        "",
        "Action needed",
        *[f"- {action}" for action in actions],
        "",
        *(["Pending", *[f"- {line}" for line in pending], ""] if pending else []),
        *(["Expected", *[f"- {line}" for line in expected], ""] if expected else []),
        "Details: delivery-report.md (attached)",
    ]
    return "\n".join(lines)


def report(manifest, reason):
    if manifest is None:
        if reason:
            return f"The evidence manifest could not be read: {reason}."
        return "No evidence manifest is on record for this run."
    reachable = "true" if manifest["target_reachable"] is True else "false"
    gaps = [g for g in manifest["coverage_gaps"] if isinstance(g, str)]
    lines = [
        "## Evidence manifest",
        "",
        f"- target: {manifest['target']}",
        f"- target_reachable: {reachable} ({manifest['target_reachable_reason']})",
        "",
        "### coverage_gaps",
        *([f"- {gap}" for gap in gaps] or ["- none recorded"]),
    ]
    return "\n".join(lines)


class Parser(argparse.ArgumentParser):
    def error(self, message):
        print(f"usage: delivery-text.py <block|note|report|checks> [options] — {message}", file=sys.stderr)
        sys.exit(2)


def main():
    parser = Parser(add_help=False)
    parser.add_argument("mode", choices=["block", "note", "report", "checks"])
    parser.add_argument("--manifest", default=".ai/run-context/evidence-manifest.json")
    parser.add_argument("--config", default=".ai/project-config.yaml")
    parser.add_argument("--package", default="package.json")
    parser.add_argument("--branch", default="")
    parser.add_argument("--item-id", default="")
    parser.add_argument("--pr-url", default="")
    parser.add_argument("--checks", default="")
    parser.add_argument("--block-name", default="")
    parser.add_argument("--pr-type", default="")
    args = parser.parse_args()

    if args.pr_type and args.pr_type not in PR_TYPES:
        parser.error(f"--pr-type must be one of {', '.join(PR_TYPES)}")
    if args.mode == "checks":
        if not args.checks:
            parser.error("--checks is required")
        print(checks_verdict(args.checks, args.pr_type))
        return 0

    if args.mode in ("block", "note") and not args.branch:
        parser.error("--branch is required")
    if args.mode == "note" and not (args.item_id and args.pr_url):
        parser.error("--item-id and --pr-url are required")

    manifest, reason = read_manifest(args.manifest)
    config = read_config(args.config)
    if args.mode == "block":
        print(verified_block(manifest, args.branch, config, args.package))
    elif args.mode == "note":
        print(note(args, manifest, reason, config))
    else:
        print(report(manifest, reason))
    return 0


if __name__ == "__main__":
    sys.exit(main())
