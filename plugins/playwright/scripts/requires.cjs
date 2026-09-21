#!/usr/bin/env node
// requires.cjs — Read this pack's own declared preconditions out of its
// manifest, so an operation reports a missing tool with exactly the text the
// manifest declares.
//
// Why read it rather than write the message where it is used: the same
// remedy is reported by two different things — the diagnostic that probes on
// demand, and the operation that refuses to run without its tool. Two
// hardcoded copies of a sentence agree only until one of them is edited, and
// the person who hits the second copy is the one least able to tell it is
// stale. One declaration, two readers.
//
// Used as a module by this pack's operation scripts.

const fs = require('fs');
const path = require('path');

const MANIFEST = path.join(__dirname, '..', 'pack.yaml');

// The manifest's `requires:` shape is fixed and flat — an entry is three
// lines, each at a known indent — so it is read directly rather than through
// a parser this pack would otherwise not need at all.
function declaredRequirements() {
  let text;
  try {
    text = fs.readFileSync(MANIFEST, 'utf8');
  } catch (e) {
    return [];
  }

  const lines = text.split('\n');
  const start = lines.findIndex((l) => l === 'requires:');
  if (start < 0) return [];

  const entries = [];
  let current = null;
  for (let i = start + 1; i < lines.length; i += 1) {
    const line = lines[i];
    const tool = /^ {2}- tool: (.+)$/.exec(line);
    if (tool) {
      if (current) entries.push(current);
      current = { tool: tool[1].trim(), remedy: '' };
      continue;
    }
    if (!current) break;
    const remedy = /^ {4}remedy: "(.*)"$/.exec(line);
    if (remedy) {
      current.remedy = remedy[1];
      continue;
    }
    if (/^ {4}probe: /.test(line)) continue;
    break;
  }
  if (current) entries.push(current);
  return entries;
}

// The remedy for one declared tool. A tool the manifest does not declare
// returns null rather than a plausible-looking sentence composed here: a
// caller that finds nothing declared should say so, because an invented
// remedy reads as authoritative and may simply be wrong.
function remedyFor(tool) {
  const found = declaredRequirements().find((e) => e.tool === tool);
  return found && found.remedy ? found.remedy : null;
}

// The line an operation emits when a declared tool is absent. Kept here so
// all four operations phrase it identically.
function missingToolSummary(tool) {
  const remedy = remedyFor(tool);
  return remedy
    ? `${tool} is not available on this machine. To fix it: ${remedy}`
    : `${tool} is not available on this machine, and this pack's manifest declares no remedy for it.`;
}

module.exports = { declaredRequirements, remedyFor, missingToolSummary };
