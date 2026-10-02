// shell-shape.mjs — names a Bash command shape that dontAsk will refuse (G130).
//
// The model composes commands the skills never print. With the runner's
// sandbox auto-allowing sandboxed commands (D116), most of them run; a few
// shapes are still refused, with a generic message that tells the model not to
// work around the refusal, and the route stops. This module recognises those
// shapes, so the runner's hook refuses them first with a reason that says what
// to write instead, and the model retries.
//
// Only measured shapes are listed (G130, D116, SDK 0.3.285). Anything else is
// left to the SDK's own decision: a shape this module names wrongly would block
// a call the sandbox permits.

// Commands not in the route's allow list that dontAsk passes only as read-only
// calls, and refuses once an argument is a variable.
const READ_ONLY_NO_VARS = new Set(["head", "ls", "grep", "wc"]);

// Two same-length copies of the command: in `bare` every quoted character is
// blanked; in `unsingle` only single-quoted ones are. Indices stay aligned.
function masks(command) {
  let bare = "";
  let unsingle = "";
  let quote = null;
  for (const ch of command) {
    if (quote) {
      if (ch === quote) quote = null;
      bare += " ";
      unsingle += quote === "'" || ch === "'" ? " " : ch;
    } else if (ch === "'" || ch === '"') {
      quote = ch;
      bare += " ";
      unsingle += ch === "'" ? " " : ch;
    } else {
      bare += ch;
      unsingle += ch;
    }
  }
  return { bare, unsingle };
}

// Splits at unquoted ; & | and line breaks.
function segments(command) {
  const { bare, unsingle } = masks(command);
  const out = [];
  let start = 0;
  for (let i = 0; i <= bare.length; i++) {
    if (i === bare.length || /[;&|\n]/.test(bare[i])) {
      out.push({ bare: bare.slice(start, i), unsingle: unsingle.slice(start, i) });
      start = i + 1;
    }
  }
  return out;
}

function commandWord(text) {
  const words = text.trim().split(/\s+/);
  while (words.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[0])) words.shift();
  return words;
}

const SUBSTITUTION_REASON = "a command substitution `$(…)` in a variable assignment or an echo is refused under dontAsk. "
  + "Run the inner command on its own first, then pass its output as a literal value.";

// A reason to refuse the command, or null when no measured shape matches.
export function shapeProblem(command) {
  if (typeof command !== "string") return null;
  for (const seg of segments(command)) {
    if (/(^|\s)[A-Za-z_][A-Za-z0-9_]*=\$\(/.test(seg.bare)) return SUBSTITUTION_REASON;
    const [word, ...args] = commandWord(seg.unsingle);
    if (word === "echo" && args.some((a) => a.includes("$("))) return SUBSTITUTION_REASON;
    if (READ_ONLY_NO_VARS.has(word) && args.some((a) => a.includes("$"))) {
      return `\`${word}\` with a shell variable argument is refused under dontAsk. Pass the literal path instead.`;
    }
  }
  return null;
}
