// denials.mjs — prints every call the session refused, whole.
//
// The live tool log cuts a Bash command at 140 characters and an error at 300,
// which hid what dontAsk refused in run 37043853933. The SDK's result carries
// the authoritative list (`permission_denials`, each with the full tool input);
// these lines print it uncut, one denial per line, so a run's log alone says
// which allow rule a refused call missed.

function inputText(name, input) {
  // A command is printed as typed, so it can be pasted back; only line breaks are escaped.
  if (name === "Bash" && typeof input?.command === "string") return input.command.replace(/\n/g, "\\n");
  return JSON.stringify(input ?? {});
}

export function denialLines(denials) {
  if (!Array.isArray(denials) || denials.length === 0) return [];
  return [
    `permission denials (${denials.length}):`,
    ...denials.map((d) => `  ${d.tool_name} [${d.tool_use_id}]: ${inputText(d.tool_name, d.tool_input)}`),
  ];
}
