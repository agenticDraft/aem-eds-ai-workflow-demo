// policy-match.mjs — does a tool call match a forbidden rule of the route
// policy? Pure functions, no I/O; route-agent.mjs calls them from its
// PreToolUse hook. The grammar is the allow-rule grammar (see
// shared/route-policy.md):
//
//   Tool            every call of that tool
//   Tool(pattern)   a call whose primary argument matches pattern, where
//                   "*" is any run of characters and the match is anchored
//
// A shell command is matched after collapsing runs of whitespace, and each
// part of a compound command (split on && || ; | and newlines) is matched on
// its own, as is the whole.

const RULE = /^([A-Za-z][A-Za-z0-9_]*)(?:\((.+)\))?$/;

export function parseRule(rule) {
  const m = RULE.exec(String(rule).trim());
  if (!m) throw new Error(`not a tool rule: ${rule}`);
  return { tool: m[1], pattern: m[2] ?? null, rule: String(rule).trim() };
}

export function primaryArgument(tool, input) {
  const i = input && typeof input === "object" ? input : {};
  switch (tool) {
    case "Bash": return String(i.command ?? "");
    case "Read":
    case "Write":
    case "Edit":
    case "NotebookEdit": return String(i.file_path ?? i.notebook_path ?? "");
    case "WebFetch": return String(i.url ?? "");
    case "Glob":
    case "Grep": return String(i.pattern ?? "");
    case "Skill": return [i.skill, i.args].filter(Boolean).join(" ");
    default: return JSON.stringify(i);
  }
}

const collapse = (s) => s.replace(/\s+/g, " ").trim();

function globToRegExp(pattern) {
  const body = collapse(pattern)
    .split("*")
    .map((part) => part.replace(/[.+?^${}()|[\]\\]/g, "\\$&"))
    .join(".*");
  return new RegExp(`^${body}$`, "s");
}

function candidates(tool, arg) {
  const whole = collapse(arg);
  if (tool !== "Bash") return [whole];
  const parts = arg
    .split(/&&|\|\||;|\||\n/)
    .map(collapse)
    .filter(Boolean);
  return [whole, ...parts];
}

// Returns the first rule (as written) that forbids this call, or null.
export function forbiddenBy(rules, tool, input) {
  for (const raw of rules) {
    const r = typeof raw === "string" ? parseRule(raw) : raw;
    if (r.tool !== tool) continue;
    if (r.pattern === null) return r.rule;
    const re = globToRegExp(r.pattern);
    if (candidates(tool, primaryArgument(tool, input)).some((c) => re.test(c))) return r.rule;
  }
  return null;
}
