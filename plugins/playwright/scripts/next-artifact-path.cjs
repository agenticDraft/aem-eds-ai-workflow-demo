#!/usr/bin/env node
// next-artifact-path.cjs <directory> <base> <extension>
//
// The name every operation in this pack writes an artifact to: the first
// `<base>-<n>.<extension>` in the directory that does not exist, `n` from 1.
// An operation never replaces a file an earlier call returned in its
// envelope's `artifacts:`, so a later call can never change what an earlier
// one reported.
//
// The path is reserved before it is returned — created empty, exclusively —
// so two calls never receive the same name. The operation then writes its
// content over the empty file.
//
// Used as a module by this pack's operation scripts; run directly it prints
// the path. Exit codes: 0 with the path on stdout; 2 for a usage error.

const fs = require('fs');
const path = require('path');

function nextArtifactPath(dir, base, ext) {
  if (!base || !/^[a-zA-Z0-9]+$/.test(ext || '')) {
    throw new Error(`base must be non-empty and extension alphanumeric without a dot: '${base}' '${ext}'`);
  }
  fs.mkdirSync(dir, { recursive: true });
  for (let n = 1; ; n += 1) {
    const candidate = path.join(dir, `${base}-${n}.${ext}`);
    try {
      fs.closeSync(fs.openSync(candidate, 'wx'));
      return candidate;
    } catch (e) {
      if (e.code !== 'EEXIST') throw e;
    }
  }
}

module.exports = { nextArtifactPath };

if (require.main === module) {
  const [dir, base, ext] = process.argv.slice(2);
  if (process.argv.length !== 5) {
    console.error('usage: next-artifact-path.cjs <directory> <base> <extension>');
    process.exit(2);
  }
  try {
    console.log(nextArtifactPath(dir, base, ext));
  } catch (e) {
    console.error(`usage: ${e.message}`);
    process.exit(2);
  }
}
