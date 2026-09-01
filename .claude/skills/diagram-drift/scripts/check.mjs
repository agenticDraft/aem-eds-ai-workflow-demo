#!/usr/bin/env node
// diagram-drift — mechanical half of the drift check. No dependencies.
//
// Each diagram declares, in a comment near the top, which files it documents:
//
//   // @documents: .claude/commands/implement-ticket.md, src/pipeline/**/*.js
//   // @rendered:  implement_ticket.dot.svg
//
// This script decides only what a machine can decide with certainty:
//   - is the rendered image missing or older than its source?
//   - have the documented files changed since the diagram was last verified?
//   - does the diagram point at files that no longer exist?
//
// It never guesses whether the *content* still matches. That judgement is the
// agent's job, and it only runs when this script says something moved.

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const ROOT = process.cwd();
const LOCK = path.join(ROOT, ".diagram-lock.json");
const EXT = new Set([".dot", ".d2", ".mmd", ".puml"]);
const SKIP = new Set(["node_modules", ".git", "dist", "build", ".next", "coverage", "vendor"]);

const args = new Set(process.argv.slice(2));
const MODE = args.has("--update") ? "update" : args.has("--json") ? "json" : "report";

// ---------- fs helpers -------------------------------------------------

function walk(dir, out = []) {
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  for (const e of entries) {
    if (e.name.startsWith(".") && e.name !== ".claude") continue;
    if (SKIP.has(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

// Minimal glob: supports **, * and ? within a path. No braces.
function globToRe(g) {
  let re = "";
  for (let i = 0; i < g.length; i++) {
    const c = g[i];
    if (c === "*") {
      if (g[i + 1] === "*") { re += ".*"; i++; if (g[i + 1] === "/") i++; }
      else re += "[^/]*";
    } else if (c === "?") re += "[^/]";
    else re += c.replace(/[.+^${}()|[\]\\]/g, "\\$&");
  }
  return new RegExp("^" + re + "$");
}

function resolveGlobs(globs, allFiles) {
  const hits = new Set();
  const missing = [];
  for (const g of globs) {
    const abs = path.join(ROOT, g);
    if (!/[*?]/.test(g)) {
      if (fs.existsSync(abs)) hits.add(g);
      else missing.push(g);
      continue;
    }
    const re = globToRe(g);
    let matched = 0;
    for (const f of allFiles) {
      const rel = path.relative(ROOT, f);
      if (re.test(rel)) { hits.add(rel); matched++; }
    }
    if (!matched) missing.push(g);
  }
  return { files: [...hits].sort(), missing };
}

const sha = (buf) => crypto.createHash("sha256").update(buf).digest("hex").slice(0, 16);

function hashFiles(rels) {
  const h = crypto.createHash("sha256");
  for (const rel of rels) {
    h.update(rel);
    h.update("\0");
    try { h.update(fs.readFileSync(path.join(ROOT, rel))); } catch { h.update("<missing>"); }
    h.update("\0");
  }
  return h.digest("hex").slice(0, 16);
}

// ---------- directives -------------------------------------------------

function directives(text) {
  const head = text.split("\n").slice(0, 40).join("\n");
  const grab = (key) => {
    const m = head.match(new RegExp(`@${key}\\s*:\\s*(.+)`, "i"));
    return m ? m[1].trim().replace(/\s*(\*\/|-->|;)\s*$/, "") : null;
  };
  const docs = grab("documents");
  return {
    documents: docs ? docs.split(",").map((s) => s.trim()).filter(Boolean) : [],
    rendered: grab("rendered"),
  };
}

// ---------- main -------------------------------------------------------

const allFiles = walk(ROOT);
const diagrams = allFiles.filter((f) => EXT.has(path.extname(f))).sort();

let lock = {};
try { lock = JSON.parse(fs.readFileSync(LOCK, "utf8")); } catch {}

const findings = [];
const nextLock = {};

for (const abs of diagrams) {
  const rel = path.relative(ROOT, abs);
  const text = fs.readFileSync(abs, "utf8");
  const d = directives(text);
  const srcHash = sha(text);

  if (!d.documents.length) {
    findings.push({ diagram: rel, level: "info", kind: "unclaimed",
      msg: "No @documents: header — drift cannot be detected for this diagram." });
    nextLock[rel] = { srcHash, documents: [], docsHash: null };
    continue;
  }

  const { files, missing } = resolveGlobs(d.documents, allFiles);
  for (const m of missing) {
    findings.push({ diagram: rel, level: "error", kind: "dangling",
      msg: `@documents points at "${m}", which matches no file.` });
  }

  // rendered image staleness
  if (d.rendered) {
    const rAbs = path.resolve(path.dirname(abs), d.rendered);
    if (!fs.existsSync(rAbs)) {
      findings.push({ diagram: rel, level: "error", kind: "unrendered",
        msg: `Rendered output "${d.rendered}" is missing.` });
    } else if (fs.statSync(rAbs).mtimeMs < fs.statSync(abs).mtimeMs) {
      findings.push({ diagram: rel, level: "error", kind: "stale-render",
        msg: `"${d.rendered}" is older than the diagram source.` });
    }
  }

  const docsHash = hashFiles(files);
  const prev = lock[rel];
  nextLock[rel] = { srcHash, documents: files, docsHash };

  if (!prev) {
    findings.push({ diagram: rel, level: "info", kind: "unverified",
      msg: `Not in .diagram-lock.json yet — verify once, then run with --update.`,
      documents: files });
  } else if (prev.docsHash !== docsHash && prev.srcHash === srcHash) {
    // The documented code moved; the diagram did not. This is the drift signal.
    findings.push({ diagram: rel, level: "drift", kind: "code-moved",
      msg: `Documented files changed but the diagram did not. Re-read both and decide.`,
      documents: files });
  } else if (prev.docsHash !== docsHash && prev.srcHash !== srcHash) {
    findings.push({ diagram: rel, level: "info", kind: "both-moved",
      msg: `Both the diagram and the documented files changed — confirm they agree, then --update.`,
      documents: files });
  }
}

if (MODE === "update") {
  fs.writeFileSync(LOCK, JSON.stringify(nextLock, null, 2) + "\n");
  console.log(`.diagram-lock.json updated — ${Object.keys(nextLock).length} diagram(s) pinned.`);
  process.exit(0);
}

if (MODE === "json") {
  console.log(JSON.stringify({ diagrams: diagrams.length, findings }, null, 2));
} else {
  if (!diagrams.length) { console.log("No diagram sources found."); process.exit(0); }
  const order = { drift: 0, error: 1, info: 2 };
  const sorted = [...findings].sort((a, b) => order[a.level] - order[b.level]);
  console.log(`Scanned ${diagrams.length} diagram source(s).\n`);
  if (!sorted.length) console.log("In sync — nothing to review.");
  for (const f of sorted) {
    console.log(`[${f.level.toUpperCase()}] ${f.diagram}`);
    console.log(`  ${f.msg}`);
    if (f.documents?.length) console.log(`  documents: ${f.documents.join(", ")}`);
    console.log();
  }
}

const blocking = findings.filter((f) => f.level === "drift" || f.level === "error");
process.exit(blocking.length ? 1 : 0);
