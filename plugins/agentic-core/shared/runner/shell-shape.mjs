// shell-shape.mjs — names a Bash command shape that dontAsk will refuse (G130).
//
// The model composes commands the skills never print: it appends
// `; echo exit=$?`, or keeps a path in a variable and reads it with `wc $E`.
// Under dontAsk those are refused with a generic message that tells the model
// not to work around the refusal, and the route stops. This module recognises
// the shapes measured as refused, so the runner's hook can refuse them first
// with a reason that says what to write instead, and the model retries.
//
// Only measured shapes are listed (G130, SDK 0.3.285). Anything else is left to
// the SDK's own decision: a shape this module names wrongly would block a call
// the allow list permits.

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

// A reason to refuse the command, or null when no measured shape matches.
export function shapeProblem(command) {
  if (typeof command !== "string") return null;
  for (const seg of segments(command)) {
    if (/\$\?/.test(seg.bare)) {
      return "unquoted `$?` is refused under dontAsk. The Bash tool already reports a non-zero exit code; drop `; echo exit=$?` and run the command alone.";
    }
    if (/>{1,2}\s*\$/.test(seg.bare)) {
      return "a redirect into a shell variable (`> $VAR`) is refused under dontAsk. Write to the literal path instead.";
    }
    const [word, ...args] = commandWord(seg.unsingle);
    if (READ_ONLY_NO_VARS.has(word) && args.some((a) => a.includes("$"))) {
      return `\`${word}\` with a shell variable argument is refused under dontAsk. Pass the literal path instead.`;
    }
  }
  return null;
}
