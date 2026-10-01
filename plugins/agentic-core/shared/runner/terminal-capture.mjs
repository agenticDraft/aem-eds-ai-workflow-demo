// terminal-capture.mjs — finds how a route actually ended (G121).
//
// A route ends only by running the core's terminal-state formatter
// (shared/lib/resolve-terminal-state.sh, terminal-states.md), whose output
// opens with "terminal: delivered|blocked|failed". The session's last message
// is not that ending: a session can stop after any stage and still end with a
// text that looks like a result. So the runner watches the driver's own tool
// calls and keeps the formatter's output, and the workflow judges the run by it.
//
// Only the driver's thread counts (a subagent never ends a route), only a
// command that starts with the formatter itself, and only a call that did not
// error. The formatter stays side-effect free; recording is the runner's job.

const FORMATTER = /^\s*(?:bash\s+)?\S*\/shared\/lib\/resolve-terminal-state\.sh\s+(?:delivered|blocked|failed)(?:\s|$)/;
const TERMINAL_LINE = /^terminal: (?:delivered|blocked|failed)$/;

export function isTerminalCall(command) {
  return typeof command === "string" && FORMATTER.test(command);
}

// The formatter's output, trimmed, when its first line is a terminal state;
// null for anything else.
export function terminalOutput(text) {
  const trimmed = String(text ?? "").trim();
  return TERMINAL_LINE.test(trimmed.split("\n")[0]) ? trimmed : null;
}

// A tool result's content is a string or a list of content blocks.
export function resultText(content) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content.map((c) => c?.text ?? "").join("\n");
}

export class TerminalCapture {
  #pending = new Set();
  terminal = null;

  // Feed every SDK message, in order.
  observe(m) {
    if (m?.parent_tool_use_id) return;
    const blocks = Array.isArray(m?.message?.content) ? m.message.content : [];
    if (m.type === "assistant") {
      for (const b of blocks) {
        if (b.type === "tool_use" && b.name === "Bash" && isTerminalCall(b.input?.command)) {
          this.#pending.add(b.id);
        }
      }
    } else if (m.type === "user") {
      for (const b of blocks) {
        if (b.type !== "tool_result" || !this.#pending.delete(b.tool_use_id) || b.is_error) continue;
        const out = terminalOutput(resultText(b.content));
        if (out) this.terminal = out;
      }
    }
  }
}
