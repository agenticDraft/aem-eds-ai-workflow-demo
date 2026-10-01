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
// stops the session.
export function lockedSandbox(allowedDomains) {
  return {
    enabled: true,
    failIfUnavailable: true,
    allowUnsandboxedCommands: false,
    network: { strictAllowlist: true, allowedDomains: [...allowedDomains] },
  };
}
