// route-agent.mjs — the unattended entry point. Starts one SDK session for
// one literal prompt and turns how that session ended into an exit code.
//
// It names no pack, no tracker, no CI product. Everything it needs beyond
// the prompt comes from the environment, and every credential a pack reads
// stays in that same environment: the SDK inherits the process environment
// and loads no file, and this script never prints, copies or stores a value.
//
// Run with:
//   node plugins/agentic-core/shared/runner/route-agent.mjs "<prompt>"
//
// Environment:
//   ROUTE_POLICY_FILE      the route policy (default: .ai/route-policy.yaml); read
//                          through check-route-policy.sh before anything starts.
//                          Its forbidden rules, budget and caps bound the session.
//   ROUTE_ALLOWED_TOOLS    comma-separated allow rules, e.g. "Skill,Read,Bash(bash plugins/*)"
//                          (empty: only calls that never need approval run)
//   ROUTE_PLUGIN_DIR       directory whose sub-directories are plugins (default: plugins)
//   ROUTE_MAX_TURNS        may only LOWER the policy's caps.max_turns
//   ROUTE_TIMEOUT_MINUTES  may only LOWER the policy's caps.timeout_minutes
//   ROUTE_RESULT_FILE      where the session's final text is written
//                          (default: .ai/run-context/runner-result.txt)
//   ROUTE_PROJECT_CONFIG   project config to print the configured packs from
//                          (default: .ai/project-config.yaml)
//   ROUTE_MODEL            optional model override
//
// Exit codes:
//   0  the session ended with a result of subtype "success"
//   1  any other result subtype, a session with no result, or an error
//   2  the wall-clock cap was reached
//   3  the route policy is missing or invalid; nothing was started
//   4  the turn cap was reached
//   5  the budget cap was reached
//   64 usage: no prompt given
//
// Every cap that ends a run logs, and writes to the result file,
// "cap reached: <cap>=<value> (route policy)".

import { query } from "@anthropic-ai/claude-agent-sdk";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { forbiddenBy, parseRule } from "./policy-match.mjs";

const prompt = process.argv[2];
if (!prompt) {
  process.stderr.write("usage: route-agent.mjs <prompt>\n");
  process.exit(64);
}

const env = process.env;
const allowedTools = (env.ROUTE_ALLOWED_TOOLS || "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);
const pluginDir = resolve(env.ROUTE_PLUGIN_DIR || "plugins");
const resultFile = env.ROUTE_RESULT_FILE || ".ai/run-context/runner-result.txt";
const projectConfig = env.ROUTE_PROJECT_CONFIG || ".ai/project-config.yaml";
const policyFile = env.ROUTE_POLICY_FILE || ".ai/route-policy.yaml";

const log = (line) => process.stderr.write(`[runner] ${line}\n`);

function writeResult(text) {
  const dir = dirname(resultFile);
  if (dir && !existsSync(dir)) mkdirSync(dir, { recursive: true });
  writeFileSync(resultFile, `${text ?? ""}\n`);
  log(`result written: ${resultFile}`);
}

// The route policy, through the core's own checker. Anything but a clean
// read starts nothing: there are no defaults to fall back to.
const checker = join(dirname(fileURLToPath(import.meta.url)), "..", "lib", "check-route-policy.sh");
const checked = spawnSync("bash", [checker, policyFile], { encoding: "utf8" });
if (checked.status !== 0) {
  const reason = (checked.stderr || checked.error?.message || "no reason given").trim();
  log(`policy refused: ${reason}`);
  writeResult(`policy refused: ${reason}`);
  process.exit(3);
}
const policy = { forbidden: [], approvers: [] };
for (const line of checked.stdout.split("\n")) {
  const i = line.indexOf("=");
  if (i < 0) continue;
  const key = line.slice(0, i);
  const value = line.slice(i + 1);
  if (key === "forbidden") policy.forbidden.push(parseRule(value));
  else policy[key] = value;
}

// The variables may tighten a cap, never loosen it.
const lower = (fromPolicy, fromEnv) => {
  const p = Number(fromPolicy);
  const e = fromEnv === undefined || fromEnv === "" ? NaN : Number(fromEnv);
  return Number.isFinite(e) && e > 0 && e < p ? e : p;
};
const maxTurns = lower(policy["caps.max_turns"], env.ROUTE_MAX_TURNS);
const timeoutMinutes = lower(policy["caps.timeout_minutes"], env.ROUTE_TIMEOUT_MINUTES);
const maxBudgetUsd = Number(policy["budget.max_usd_per_run"]);

function capReached(cap, value, code) {
  const line = `cap reached: ${cap}=${value} (route policy)`;
  log(line);
  writeResult(line);
  process.exit(code);
}

// Every sub-directory that carries a plugin manifest is loaded, by path.
const plugins = existsSync(pluginDir)
  ? readdirSync(pluginDir)
      .filter((n) => existsSync(join(pluginDir, n, ".claude-plugin", "plugin.json")))
      .sort()
      .map((n) => ({ type: "local", path: join(pluginDir, n) }))
  : [];

// Which packs this project configured, from the `packs:` block. Read only
// to say it out loud at startup; the values are the project's own data.
function configuredPacks(path) {
  if (!existsSync(path)) return "(no project config)";
  const lines = readFileSync(path, "utf8").split("\n");
  const start = lines.findIndex((l) => /^packs:\s*$/.test(l));
  if (start < 0) return "(no packs block)";
  const out = [];
  for (const l of lines.slice(start + 1)) {
    const m = /^\s+([a-z]+):\s*(\S+)\s*$/.exec(l);
    if (!m) break;
    out.push(`${m[1]}=${m[2]}`);
  }
  return out.join(" ");
}

log(`prompt: ${prompt}`);
log(`packs: ${configuredPacks(projectConfig)}`);
log(`plugins: ${plugins.map((p) => p.path.split("/").pop()).join(", ") || "none"}`);
log(`allowed tools (${allowedTools.length}): ${allowedTools.join(", ") || "none — only calls that never need approval"}`);
log(`policy: ${policyFile} — ${policy.forbidden.length} forbidden rule(s), budget $${maxBudgetUsd}`);
log(`caps: maxTurns=${maxTurns} timeout=${timeoutMinutes}m`);

const timer = setTimeout(() => capReached("timeout_minutes", timeoutMinutes, 2), timeoutMinutes * 60 * 1000);
timer.unref();

const options = {
  cwd: process.cwd(),
  // "project" keeps the committed settings (the network domain list and the
  // allow rules). No "user": a runner has no user settings. Never [] — that
  // would drop the committed list silently.
  settingSources: ["project"],
  plugins,
  allowedTools,
  // Never bypass. A call the allow rules do not cover is denied, not asked.
  permissionMode: "dontAsk",
  // The forbidden rules, twice: the SDK's own deny list, and a hook that
  // matches every call (subagents' included) and names the policy when it
  // refuses. Deny beats allow, whatever the allow rules say.
  disallowedTools: policy.forbidden.map((r) => r.rule),
  hooks: {
    PreToolUse: [{
      hooks: [async (input) => {
        const rule = forbiddenBy(policy.forbidden, input.tool_name, input.tool_input);
        if (!rule) return { continue: true };
        const reason = `forbidden by route policy (${policyFile}): ${rule}`;
        log(`${input.agent_id ? "  (subagent) " : ""}denied ${input.tool_name}: ${reason}`);
        return {
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: reason,
          },
        };
      }],
    }],
  },
  maxTurns,
  maxBudgetUsd,
  ...(env.ROUTE_MODEL ? { model: env.ROUTE_MODEL } : {}),
  // `env` is deliberately not set: the SDK inherits this process's environment.
};

function summarize(name, input) {
  if (!input) return "";
  if (name === "Skill") return [input.skill, input.args].filter(Boolean).join(" ");
  if (name === "Bash") return String(input.command || "").slice(0, 140);
  if (name === "Read" || name === "Write" || name === "Edit") return String(input.file_path || "");
  if (name === "Agent") return String(input.description || input.prompt || "").slice(0, 100);
  const json = JSON.stringify(input);
  return json.length > 140 ? `${json.slice(0, 140)}…` : json;
}

let sawResult = false;
try {
  for await (const m of query({ prompt, options })) {
    if (m.type === "system" && m.subtype === "init") {
      log(`session: version=${m.claude_code_version ?? "?"} model=${m.model ?? "?"} mode=${m.permissionMode ?? "?"}`);
      log(`loaded plugins: ${(m.plugins || []).map((p) => p.name).join(", ") || "none"}`);
      if (m.plugin_errors && m.plugin_errors.length) log(`plugin errors: ${JSON.stringify(m.plugin_errors)}`);
      log(`skills (${(m.skills || []).length}): ${(m.skills || []).join(", ")}`);
      log(`commands (${(m.slash_commands || []).length}): ${(m.slash_commands || []).join(", ")}`);
    } else if (m.type === "assistant") {
      for (const block of m.message?.content || []) {
        if (block.type === "tool_use") {
          const who = m.parent_tool_use_id ? "  (subagent) " : "";
          log(`${who}-> ${block.name}: ${summarize(block.name, block.input)}`);
        }
      }
    } else if (m.type === "user") {
      for (const block of Array.isArray(m.message?.content) ? m.message.content : []) {
        if (block.type === "tool_result" && block.is_error) {
          const text = typeof block.content === "string"
            ? block.content
            : (block.content || []).map((c) => c.text || "").join(" ");
          log(`!! tool error: ${text.slice(0, 300)}`);
        }
      }
    } else if (m.type === "result") {
      sawResult = true;
      clearTimeout(timer);
      const cost = m.total_cost_usd != null ? `$${m.total_cost_usd.toFixed(4)}` : "n/a";
      log(`ended: subtype=${m.subtype} turns=${m.num_turns ?? "?"} cost=${cost}`);
      if (m.subtype === "error_max_turns") capReached("max_turns", maxTurns, 4);
      if (m.subtype === "error_max_budget_usd") capReached("max_usd_per_run", maxBudgetUsd, 5);
      writeResult(m.subtype === "success" ? m.result : (m.errors || []).join("\n"));
      process.exit(m.subtype === "success" ? 0 : 1);
    }
  }
} catch (err) {
  clearTimeout(timer);
  log(`error: ${err?.message || err}`);
  process.exit(1);
}

if (!sawResult) {
  log("error: the session ended without a result");
  process.exit(1);
}
