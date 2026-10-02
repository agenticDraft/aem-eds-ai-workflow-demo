// network-allowlist.mjs — reads the project's committed sandbox domain list
// and builds the locked sandbox block every runner session carries.
//
// The committed settings file is the only list on disk. The runner copies it
// into the session's policy tier at launch; the copy lives only in the
// running process. Every failure to read a usable list is refused: there is
// no default list to fall back to.

import { existsSync, readFileSync } from "node:fs";

export class AllowlistRefused extends Error {}

// Pure: the settings file's text in, the domain list out, or a refusal.
export function parseAllowedDomains(text) {
  let settings;
  try {
    settings = JSON.parse(text);
  } catch (err) {
    throw new AllowlistRefused(`settings file is not valid JSON (${err.message})`);
  }
  const list = settings?.sandbox?.network?.allowedDomains;
  if (list === undefined) throw new AllowlistRefused("sandbox.network.allowedDomains is absent");
  if (!Array.isArray(list)) throw new AllowlistRefused("sandbox.network.allowedDomains is not a list");
  if (list.length === 0) throw new AllowlistRefused("sandbox.network.allowedDomains is empty");
  const bad = list.filter((d) => typeof d !== "string" || d.trim() === "" || d !== d.trim());
  if (bad.length) {
    throw new AllowlistRefused(`sandbox.network.allowedDomains has ${bad.length} entry(ies) that are not a plain host`);
  }
  return [...list];
}

export function readAllowedDomains(path) {
  if (!existsSync(path)) throw new AllowlistRefused(`settings file not found: ${path}`);
  return parseAllowedDomains(readFileSync(path, "utf8"));
}

// The sandbox block for the policy tier. The lock alone would leave an empty
// allowlist (the policy tier drops the project tier's domains), so the copied
// list travels with it. No unsandboxed retry; a sandbox that cannot start
// stops the session; and a sandboxed command is approved because it is
// sandboxed (D116): the sandbox's filesystem and network limits, and the
// policy tier's write denials, are the boundary, not the command's shape.
export function lockedSandbox(allowedDomains) {
  return {
    enabled: true,
    failIfUnavailable: true,
    autoAllowBashIfSandboxed: true,
    allowUnsandboxedCommands: false,
    network: { strictAllowlist: true, allowedDomains: [...allowedDomains] },
  };
}

// Pure: the project config's text in, the host of `paths.preview` out, or
// null when there is no usable preview. The preview servers run outside the
// session; a sandboxed command reaches them only through the sandbox's proxy,
// and the proxy only lets through a listed host.
export function parsePreviewHost(text) {
  const lines = text.split("\n");
  const start = lines.findIndex((l) => /^paths:\s*$/.test(l));
  if (start < 0) return null;
  for (const l of lines.slice(start + 1)) {
    if (!/^\s+\S/.test(l)) break;
    const m = /^\s+preview:\s*(.*?)\s*$/.exec(l);
    if (!m) continue;
    const value = m[1].replace(/^(["'])(.*)\1$/, "$2");
    try {
      return new URL(value).hostname || null;
    } catch {
      return null;
    }
  }
  return null;
}

export function readPreviewHost(path) {
  return existsSync(path) ? parsePreviewHost(readFileSync(path, "utf8")) : null;
}

// A new list with `host` appended unless it is already there or absent.
export function withHost(domains, host) {
  return !host || domains.includes(host) ? [...domains] : [...domains, host];
}
