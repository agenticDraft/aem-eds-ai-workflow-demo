#!/usr/bin/env node
// probe-tool.cjs — Answer whether one of this pack's declared preconditions
// is present, by exit status alone. Named from the manifest's `requires:`
// probes and run by whatever reads them.
//
// This exists because "is the tool present" is not a question a fixed
// argument list can ask here: the package may be installed beside the
// project or globally, and the browser binary is a separate download that a
// present package says nothing about. That resolution logic belongs to the
// pack that depends on it, so the pack ships it rather than asking the core
// to guess on its behalf.
//
// Usage:
//   probe-tool.cjs module   — is the automation package resolvable?
//   probe-tool.cjs browser  — is the browser binary actually downloaded?
//
// Exit codes: 0 present, 1 absent, 2 usage error. Nothing is printed on
// purpose: the caller reads the status, and the remedy is the manifest's to
// state, not this script's.
//
// It installs nothing. A probe that fixed what it found would make every
// later run depend on whether something had ever inspected the machine.

const path = require('path');
const fs = require('fs');
const { execSync } = require('child_process');

// The same two-step resolution the operations themselves use: beside the
// project first, then the global root. Kept identical on purpose — a probe
// that resolved the tool differently from the code that needs it would
// answer a question nobody asked.
function resolveTool() {
  try {
    return require('playwright');
  } catch (e) {
    if (e.code !== 'MODULE_NOT_FOUND') throw e;
  }
  try {
    const globalRoot = execSync('npm root -g', { encoding: 'utf8' }).trim();
    return require(path.join(globalRoot, 'playwright'));
  } catch (e) {
    return null;
  }
}

const what = process.argv[2];

if (what !== 'module' && what !== 'browser') {
  console.error('usage: probe-tool.cjs module|browser');
  process.exit(2);
}

let tool;
try {
  tool = resolveTool();
} catch (e) {
  process.exit(1);
}

if (!tool) process.exit(1);
if (what === 'module') process.exit(0);

// A resolvable package does not mean a usable browser: the binary is a
// separate download, and its absence is the failure people actually hit.
try {
  const executable = tool.chromium.executablePath();
  process.exit(executable && fs.existsSync(executable) ? 0 : 1);
} catch (e) {
  process.exit(1);
}
