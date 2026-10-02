// stop-guard.mjs — a route session may not end before its terminal state (G130).
//
// A route ends only through the core's terminal-state formatter. The driver
// has been seen to report "blocked" or "failed" in prose and end the session
// without running it, which leaves no terminal state and no note on the work
// item. The runner's Stop hook asks this module whether to refuse that stop;
// the refusal's reason tells the driver what to run. One refusal only: a
// session that stops again is let through, and the workflow still fails a run
// with no terminal state.

export function isRoutePrompt(prompt) {
  return typeof prompt === "string" && /(^|\s)\/agentic-core:run-route(\s|$)/.test(prompt);
}

export function stopDecision({ isRoute, terminal, stopHookActive }) {
  if (!isRoute || terminal || stopHookActive) return null;
  return {
    decision: "block",
    reason: "This route has no terminal state yet. Before ending, run the core's terminal-state formatter "
      + "(shared/lib/resolve-terminal-state.sh) with delivered, blocked or failed, the stage the route stopped at "
      + "and its summary, exactly as the route's instructions say for that ending. Run it as its own Bash call, "
      + "not chained after another command: only a call that starts with the formatter is recorded.",
  };
}
